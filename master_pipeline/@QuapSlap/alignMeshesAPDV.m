function [rot, trans, xyzlim_raw, xyzlim, xyzlim_um, xyzlim_um_buff] = ...
    alignMeshesAPDV(QS, acom_sm, pcom_sm, opts)
% ALIGNMESHESAPDV(opts) 
% Uses anterior, posterior, and dorsal training in ilastik h5 output to
% align meshes along APDV coordinate system. Extracted COMs from the 
% segmented training is loaded/saved in h5 file opts.rawapdvname (usually
% "apdv_coms_from_training.h5").
% Smoothed COMs from the segmented training --> opts.rawapdvname
% Smoothed rotated scaled COMs              --> opts.outapdvname
% 
% 
% This is a function similar to the align_meshes_APDV.m script
%
% Parameters
% ----------
% opts : struct with fields
%   overwrite     : bool
%   overwrite_ims : bool
%   smwindow      : float or int
%       number of timepoints over which we smooth
%
% Returns
% -------
% xyzlim_raw : 
%   xyzlimits of raw meshes in units of full resolution pixels (ie not
%   downsampled)
% xyzlim : 
%   xyzlimits of rotated and translated meshes in units of full resolution 
%   pixels (ie not downsampled)
% xyzlim_um : 
%   xyz limits of rotated and translated meshes in microns
% xyzlim_um_buff : 
%   xyz limits of rotated and translated meshes in microns, with padding of
%   QS.normalShift * resolution in every dimension
%
% OUTPUTS
% -------
% xyzlim.txt 
%   xyzlimits of raw meshes in units of full resolution pixels (ie not
%   downsampled)
% xyzlim_APDV.txt 
%   xyzlimits of rotated and translated meshes in units of full resolution 
%   pixels (ie not downsampled)
% xyzlim_APDV_um.txt 
%   xyz limits of rotated and translated meshes in microns
% rotation_APDV.txt
%   rotation matrix to align mesh to APDV frame, saved to 
%   fullfile(meshDir, 'rotation_APDV.txt') ;
% translation_APDV.txt
%   translation vector to align mesh to APDV frame, saved to 
%   fullfile(meshDir, 'translation_APDV.txt') 
% xyzlim.txt 
%   raw bounding box in original frame (not rotated), in full res pixels.
%   Saved to fullfile(meshDir, 'xyzlim.txt')
% xyzlim_APDV.txt
%   bounding box in rotated frame, in full resolution pixels. Saved to 
%   fullfile(meshDir, 'xyzlim_APDV.txt')
% xyzlim_APDV_um.txt
%   bounding box in rotated frame, in microns. Saved to 
%   fullfile(meshDir, 'xyzlim_APDV_um.txt')
% apdv_coms_rs.h5 (outapdvname)
%   Centers of mass for A, P, and D in microns in rotated, scaled APDV
%   coord system. Note that this coord system is mirrored if flipy==true.
%   Also contains raw acom,pcom,dcom in subsampled pixels.
%   Saved to fullfile(meshDir, 'centerline/apdv_coms_rs.h5')
% apdv_coms_from_training.h5 (rawapdvname)
%   Raw centers of mass for A, P, and D in subsampled pixels, in 
%   probability data space coordinate system
%   Saved to fullfile(meshDir, 'centerline/apdv_coms_from_training.h5')
% startendpt.h5
%   Starting and ending points
%   Saved to fullfile(meshDir, 'centerline/startendpt_rs.h5') ;
% 
% NPMitchell 2020

% Booleans & floats
overwrite = opts.overwrite ;  % overwrite everything 
overwrite_ims = opts.overwrite_ims ;  % overwrite images, whether or not we overwrite everything else
timePoints = opts.timePoints ;
meshDir = opts.meshDir ;
preview = opts.preview ; 
resolution = opts.resolution ;
plot_buffer = opts.plot_buffer ;
ssfactor = opts.ssfactor ;
normal_step = opts.normal_step ;
flipy = opts.flipy ;
dcomname = fullfile(meshDir, 'dcom_for_rot.txt') ;

% Default valued options
timeinterval = 1 ;
timeunits = 'min' ;
if isfield(opts, 'timeinterval')
    timeinterval = opts.timeinterval ;
end
if isfield(opts, 'timeunits')
    timeunits = opts.timeunits ;
end

% Data file names
rotname = fullfile(meshDir, 'rotation_APDV.txt') ;
transname = fullfile(meshDir, 'translation_APDV.txt') ;
xyzlimname_raw = QS.fileName.xyzlim_raw ;
xyzlimname_pix = QS.fileName.xyzlim_pix ;
xyzlimname_um = QS.fileName.xyzlim_um ;
xyzlimname_um_buff = QS.fileName.xyzlim_um_buff ;
% Name output directory for apdv info
apdvoutdir = opts.apdvoutdir ;
outapdvname = fullfile(apdvoutdir, 'apdv_coms_rs.h5') ;
outstartendptname = fullfile(apdvoutdir, 'startendpt.h5') ;
% Name the directory for outputting aligned_meshes
alignedMeshDir = opts.alignedMeshDir ;
meshFileName = opts.meshFileName ;
alignedMeshBase = opts.alignedMeshBase ;
alignedMeshXYFigBaseName = [alignedMeshBase '_xy.png'] ;
alignedMeshXZFigBaseName = [alignedMeshBase '_xz.png'] ;
alignedMeshYZFigBaseName = [alignedMeshBase '_yz.png'] ;
fn = opts.fn ;

% rotname
if isfield(opts, 'rotname')
    rotname = opts.rotname ;
end
if ~strcmp(rotname(end-3:end), '.txt') 
    rotname = [rotname '.txt'] ;
end

% transname
if isfield(opts, 'transname')
    transname = opts.transname ;
end
if ~strcmp(transname(end-3:end), '.txt') 
    transname = [transname '.txt'] ;
end

% xyzlimname_raw
if isfield(opts, 'xyzlimname_raw')
    xyzlimname_raw = opts.xyzlimname_raw ;
end
if ~strcmp(xyzlimname_raw(end-3:end), '.txt') 
    xyzlimname_raw = [xyzlimname_raw '.txt'] ;
end

% xyzlimname_um
if isfield(opts, 'xyzlimname_um')
    xyzlimname_um = opts.xyzlimname_um ;
end
if ~strcmp(xyzlimname_um(end-3:end), '.txt') 
    xyzlimname_um = [xyzlimname_um '.txt'] ;
end

if isfield(opts, 'outapdvname')
    outapdvname = opts.outapdvname ;
end

% dcomname
if isfield(opts, 'dcomname')
    dcomname = opts.dcomname ;
end
if ~strcmp(dcomname(end-3:end), '.txt') 
    dcomname = [dcomname '.txt'] ;
end

if isfield(opts, 'rawapdvname')
    rawapdvname = opts.rawapdvname ;
end
if isfield(opts, 'rawapdvname')
    apdvoutdir = opts.apdvOutDir ;
end

% figure parameters
xwidth = 16 ; % cm
ywidth = 10 ; % cm
colors = define_colors ;
blue = colors(1, :) ;
red = colors(2, :) ;
green = colors(5, :) ;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Checks, directories, and assertions
% Ensure that PLY files exist
for tt = timePoints 
    if ~exist(sprintf(meshFileName, tt), 'file')
        error('Found no matching PLY files in ' + meshDir)
    end
end

% Name the directory for outputting figures
figoutdir = fullfile(alignedMeshDir, 'images');
fig1outdir = fullfile(figoutdir, 'aligned_mesh_xy') ;
fig2outdir = fullfile(figoutdir, 'aligned_mesh_xz') ;
fig3outdir = fullfile(figoutdir, 'aligned_mesh_yz') ;

% Create the directories 
dirs2make = {apdvoutdir, alignedMeshDir, figoutdir, ...
    fig1outdir, fig2outdir, fig3outdir} ;
for kk = 1:length(dirs2make)
    thisdir = dirs2make{kk} ;
    if ~exist(thisdir, 'dir')
        mkdir(thisdir) ;
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Get axis limits from looking at all meshes =============================
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
close all
if exist(xyzlimname_raw, 'file')
    disp('loading xyzlimits from disk')
    xyzlim_raw = dlmread(xyzlimname_raw, ',', 1, 0);
    xmin = xyzlim_raw(1);
    ymin = xyzlim_raw(2);
    zmin = xyzlim_raw(3);
    xmax = xyzlim_raw(4);
    ymax = xyzlim_raw(5);
    zmax = xyzlim_raw(6);
else
    disp('Extracting xyzlimits for raw meshes...')
    disp([' ... since ' xyzlimname_raw ' does not exist'])
    for tt = timePoints
        % Get the timestamp string from the name of the mesh
        mesh = read_ply_mod(sprintf(meshFileName, tt)) ;

        minx = min(mesh.v) ;
        maxx = max(mesh.v) ;
        if tt == timePoints(1)
            xmin = minx(1) ;
            ymin = minx(2) ;
            zmin = minx(3) ;
            xmax = maxx(1) ;
            ymax = maxx(2) ;
            zmax = maxx(3) ;
        else
            xmin= min(xmin, minx(1)) ;
            ymin = min(ymin, minx(2)) ;
            zmin = min(zmin, minx(3)) ;
            xmax = max(xmax, maxx(1)) ;
            ymax = max(ymax, maxx(2)) ;
            zmax = max(zmax, maxx(3)) ;
        end 
    end

    % Save xyzlimits 
    disp('Saving raw mesh xyzlimits for plotting')
    header = 'xyzlimits for original meshes in units of full resolution pixels' ; 
    write_txt_with_header(xyzlimname_raw, [xmin, xmax; ymin, ymax; zmin, zmax], header) ;
    % Now read it back in
    xyzlim_raw = dlmread(xyzlimname_raw, ',', 1, 0) ;
end
disp('done')

%% With acoms and pcoms in hand, we compute dorsal and rot/trans ==========
xminrs = 0 ; xmaxrs = 0;
yminrs = 0 ; ymaxrs = 0;
zminrs = 0 ; zmaxrs = 0;
for tidx = 1:length(timePoints)
    tic
    tt = timePoints(tidx) ;
    
    % Pick out the acom and pcom in SUBSAMPLED UNITS from smoothed sequence
    % NOTE: this is from the RAW data
    acom = acom_sm(tidx, :) ;
    pcom = pcom_sm(tidx, :) ; 
    
    %% Name the output centerline
    fig1outname = fullfile(fig1outdir, sprintf(alignedMeshXYFigBaseName, tt)) ;
    fig2outname = fullfile(fig2outdir, sprintf(alignedMeshXZFigBaseName, tt)) ;
    fig3outname = fullfile(fig3outdir, sprintf(alignedMeshYZFigBaseName, tt)) ; 
        
    %% Read the mesh  
    meshfn = sprintf(meshFileName, tt) ;
    disp(['Loading mesh ' meshfn])
    mesh = read_ply_mod(meshfn );
    vtx_sub = mesh.v / ssfactor ;
    vn = mesh.vn ;
    fvsub = struct('faces', mesh.f, 'vertices', vtx_sub, 'normals', vn) ;
    
    % Check normals
    % close all
    % plot3(vtx_sub(1:10:end, 1), vtx_sub(1:10:end, 2), vtx_sub(1:10:end, 3), '.')
    % hold on
    % plot3(vtx_sub(1:10:end, 1) + 10 * vn(1:10:end, 1),...
    %     vtx_sub(1:10:end, 2) + 10 * vn(1:10:end, 2), ...
    %     vtx_sub(1:10:end, 3) + 10 * vn(1:10:end, 3), 'o')
    
    % View the normals a different way
    % close all
    % plot3(vtx_sub(1:10:end, 1), vtx_sub(1:10:end, 2), vtx_sub(1:10:end, 3), '.')
    % for i=1:10:length(vtx_sub)
    %     hold on
    %     plot3([vtx_sub(i, 1), vtx_sub(i, 1) + 10*vn(i, 1)], ... 
    %     [vtx_sub(i, 2), vtx_sub(i, 2) + 10*vn(i, 2)], ...
    %     [vtx_sub(i, 3), vtx_sub(i, 3) + 10*vn(i, 3)], 'r-') 
    % end
    % axis equal
    
    % Must either downsample mesh, compute xyzgrid using ssfactor and
    % pass to options struct.
    % Here, downsampled mesh
    % mesh.vertex.x = xs ;
    % mesh.vertex.y = ys ;
    % mesh.vertex.z = zs ;
    try
        name = sprintf(fn, tt) ;
        spt = h5read(outstartendptname, ['/' name '/spt']) ;
        ept = h5read(outstartendptname, ['/' name '/ept']) ;
        spt_ept_exist = true ;
    catch
        spt_ept_exist = false;
    end
    if overwrite || ~spt_ept_exist 
        % Point match for aind and pind
        disp(['Point matching mesh ' meshfn])
        adist2 = sum((vtx_sub - acom) .^ 2, 2);
        %find the smallest distance and use that as an index 
        aind = find(adist2 == min(adist2)) ;
        % Next point match the posterior
        pdist2 = sum((vtx_sub - pcom) .^ 2, 2);
        % find the smallest distance and use that as an index
        pind = find(pdist2 == min(pdist2)) ;

        % Check it
        if preview
            disp('Previewing mesh in figure window')
            trimesh(mesh.f, vtx_sub(:, 1), vtx_sub(:, 2), vtx_sub(:, 3), vtx_sub(:, 1))
            hold on;
            plot3(vtx_sub(aind, 1), vtx_sub(aind, 2), vtx_sub(aind, 3), 'ko')
            plot3(vtx_sub(pind, 1), vtx_sub(pind, 2), vtx_sub(pind, 3), 'ro')
        end

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %% Define start point and endpoint 
        disp('Defining start point and endpoint for first TP')
        % Check if acom is inside mesh. If so, use that as starting point.
        ainside = inpolyhedron(fvsub, acom(1), acom(2), acom(3)) ;
        pinside = inpolyhedron(fvsub, pcom(1), pcom(2), pcom(3)) ;

        if ainside
            disp('start point for centerline is inside mesh')
            startpt = acom' ;
        else
            % move along the inward normal of the mesh from the matched vertex
            vtx = [vtx_sub(aind, 1), vtx_sub(aind, 2), vtx_sub(aind, 3)]' ;
            normal = fvsub.normals(aind, :) ;
            startpt = vtx + normal;
            if ~inpolyhedron(fvsub, startpt(1), startpt(2), startpt(3)) 
                % this didn't work, check point in reverse direction
                startpt = vtx - normal * normal_step ;
                if ~inpolyhedron(fvsub, startpt(1), startpt(2), startpt(3))
                    % Can't seem to jitter into the mesh, so use vertex
                    disp("Can't seem to jitter into the mesh, so using vertex for startpt")
                    startpt = vtx ;
                end
            end
        end 
        % Note: Keep startpt in subsampled units

        % Define end point
        if pinside
            disp('end point for centerline is inside mesh')
            endpt = pcom' ;
        else
            % move along the inward normal of the mesh from the matched vertex
            vtx = [vtx_sub(pind, 1), vtx_sub(pind, 2), vtx_sub(pind, 3)]' ;
            normal = fvsub.normals(pind, :) ;
            endpt = vtx + normal * normal_step;
            if ~inpolyhedron(fvsub, endpt(1), endpt(2), endpt(3)) 
                % this didn't work, check point in reverse direction
                endpt = vtx - normal * normal_step ;
                if ~inpolyhedron(fvsub, endpt(1), endpt(2), endpt(3))
                    % Can't seem to jitter into the mesh, so use vertex
                    disp("Can't seem to jitter into the mesh, so using vertex for endpt")
                    endpt = vtx ;
                end
            end
        end 
        % Note: Keep endpt in subsampled units

        % Check out the mesh
        if preview
            hold on
            trimesh(fvsub.faces, xs, ys, zs)
            % plot3(xs, ys, zs, 'ko')
            scatter3(startpt(1), startpt(2), startpt(3), 'ro')
            scatter3(endpt(1), endpt(2), endpt(3), 'ko')
            xlabel('x [subsampled pixels]')
            ylabel('y [subsampled pixels]')
            zlabel('z [subsampled pixels]')
            hold off
            axis equal
        end

        %% Rescale start point and end point to full resolution
        spt = [startpt(1), startpt(2), startpt(3)] * ssfactor;
        ept = [endpt(1), endpt(2), endpt(3)] * ssfactor;
        
        clearvars startpt endpt ainside pinside normal vtx
    else
        disp('loading spt and ept')
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% Grab dorsal direction if this is the first timepoint
    if tidx == 1
        disp('Obtaining dorsal direction since this is first TP')
        no_rot_on_disk = ~exist(rotname, 'file') ;
        redo_rot_calc = no_rot_on_disk || overwrite ;
        
        if exist(rotname, 'file') 
            disp('rot exists on file')
        else
            disp(['no rot txt file: ' rotname ])
        end
        
        if overwrite && ~no_rot_on_disk
            disp('Overwriting rot calculation using dorsal pt')
        elseif redo_rot_calc
            disp('Computing rot calculation using dorsal pt for the first time')
        end

        if redo_rot_calc
            % load the probabilities for anterior posterior dorsal
            % Load dcom if already on disk
            disp(['Loading dorsal COM from disk: ' dcomname])
            dcom = dlmread(dcomname) ;
            
            % compute rotation -- Note we choose to use startpt instead of
            % acom here so that the dorsal point will lie in the y=0 plane.
            % Explanation: we will subtract off startpt * ssfactor as the
            % translation, so if this differs from acom in y dim, then
            % dorsal point gets shifted in y.
            origin = spt / ssfactor ; % [startpt(1), startpt(2), startpt(3)] ;
            apaxis = pcom - origin ;
            aphat = apaxis / norm(apaxis) ;
            
            % compute rotation matrix using this procedure: 
            % https://math.stackexchange.com/questions/180418/calculate-rotation-matrix-to-align-vector-a-to-vector-b-in-3d
            xhat = [1, 0, 0] ;
            zhat = [0, 0, 1] ;
            ssc = @(v) [0 -v(3) v(2); v(3) 0 -v(1); -v(2) v(1) 0] ;
            RU = @(A,B) eye(3) + ssc(cross(A,B)) + ...
                 ssc(cross(A,B))^2*(1-dot(A,B))/(norm(cross(A,B))^2) ;
            % rotz aligns AP to xhat (x axis)
            rotx = RU(aphat, xhat) ;

            % Rotate dorsal to the z axis
            % find component of dorsal vector from acom perpendicular to AP
            dvec = rotx * (dcom - origin)' - rotx * (dot(dcom - origin, aphat) * aphat)' ;
            dhat = dvec / norm(dvec) ;
            rotz = RU(dhat, zhat) ;
            rot = rotz * rotx  ;
            
            % % test arrow
            % aphx = rotx * aphat' ;
            % aphxz = rot * aphat' ;
            % vecs = [aphat; aphx'; aphxz'] ;
            % for qq = 1:length(vecs)
            %     plot3([0, vecs(qq, 1)], [0, vecs(qq, 2)], [0, vecs(qq, 3)], '.-') 
            %     hold on;
            % end
            % axis equal
            % t2 = dcom - origin ;
            % aphx = rotx * t2' ;
            % aphxz = rot * t2' ;
            % vecs = [t2; aphx'; aphxz'] ;
            % for qq = 1:length(vecs)
            %     plot3([0, vecs(qq, 1)], [0, vecs(qq, 2)], [0, vecs(qq, 3)], '.-') 
            %     hold on;
            % end
            % legend({'original', 'rotx', 'rot', 'dorsal', 'rotxd', 'rotd'})
            % axis equal
            % error('here')
            
            % Save the rotation matrix
            disp(['Saving rotation matrix to txt: ', rotname])
            dlmwrite(rotname, rot)
        else
            disp('Loading rot from disk...')
            rot = dlmread(rotname) ;
            dcom = dlmread(dcomname) ;
        end
    end
    
    %% Compute the translation to put anterior to origin AFTER rot & scale
    if tidx == 1
        if overwrite || ~exist(transname, 'file')
            % Save translation in units of mesh coordinates
            trans = -(rot * spt')' ;
            disp(['Saving translation vector (post rotation) to txt: ', transname])
            dlmwrite(transname, trans)
        else
            trans = dlmread(transname, ',');
        end
    end
    
    %% Rotate and translate (and mirror) acom, pcom, dcom
    try 
        apdcoms_rs_exist = true ;
        name = sprintf(fn, tt) ;
        acom_rs = h5read(outapdvname, ['/' name '/acom_rs']) ;
        pcom_rs = h5read(outapdvname, ['/' name '/pcom_rs']) ;
        dcom_rs = h5read(outapdvname, ['/' name '/dcom_rs']) ;
        
        % Check that matches what is stored
        acom_rs_new = ((rot * (acom' * ssfactor))' + trans) * resolution ;
        pcom_rs_new = ((rot * (pcom' * ssfactor))' + trans) * resolution ;
        dcom_rs_new = ((rot * (dcom' * ssfactor))' + trans) * resolution ;
        if flipy
            acom_rs_new = [ acom_rs_new(1) -acom_rs_new(2) acom_rs_new(3) ] ;
            pcom_rs_new = [ pcom_rs_new(1) -pcom_rs_new(2) pcom_rs_new(3) ] ;
            dcom_rs_new = [ dcom_rs_new(1) -dcom_rs_new(2) dcom_rs_new(3) ] ;
        end
        assert(all(abs(acom_rs_new - acom_rs) < 1e-6))
        assert(all(abs(pcom_rs_new - pcom_rs) < 1e-6))
        assert(all(abs(dcom_rs_new - dcom_rs) < 1e-6))
    catch
        apdcoms_rs_exist = false ;
    end
    
    if overwrite || ~apdcoms_rs_exist
        acom_rs = ((rot * (acom' * ssfactor))' + trans) * resolution ;
        pcom_rs = ((rot * (pcom' * ssfactor))' + trans) * resolution ;
        dcom_rs = ((rot * (dcom' * ssfactor))' + trans) * resolution ;

        if flipy
            acom_rs = [ acom_rs(1) -acom_rs(2) acom_rs(3) ] ;
            pcom_rs = [ pcom_rs(1) -pcom_rs(2) pcom_rs(3) ] ;
            dcom_rs = [ dcom_rs(1) -dcom_rs(2) dcom_rs(3) ] ;
        end
    end
    
    %% Rotate and translate vertices and endpoints
    % Note: all in original mesh units (not subsampled)
    xyzrs = ((rot * (vtx_sub * ssfactor)')' + trans) * resolution;
    % vtx_rs = (rot * (vtx_sub * ssfactor)' + trans')' * resolution ;
    vn_rs = (rot * fvsub.normals')' ;
    sptr = (rot * spt')' + trans ; 
    eptr = (rot * ept')' + trans ;
    dpt = dcom' * ssfactor ;
    dptr = (rot * (dcom' * ssfactor))' + trans ; 
    
    % Scale to actual resolution
    sptrs = sptr * resolution ;
    eptrs = eptr * resolution ; 
    dptrs = dptr * resolution ;
    
    % Flip in Y if data is reflected across XZ
    if flipy
        % Note: since normals point inward along y when y is flipped, it
        % remains only to flip normals along X and Z in the second line.
        xyzrs = [xyzrs(:, 1), -xyzrs(:, 2), xyzrs(:, 3)] ;  % flip vertices
        vn_rs = [-vn_rs(:, 1), vn_rs(:, 2), -vn_rs(:, 3)] ; % flip normals > normals point inward
        sptrs = [sptrs(1), -sptrs(2), sptrs(3)] ;           % flip startpt
        eptrs = [eptrs(1), -eptrs(2), eptrs(3)] ;           % flip endpt
        dptrs = [dptrs(1), -dptrs(2), dptrs(3)] ;           % flip dorsalpt
    else
        vn_rs = -vn_rs ;    % flip normals > normals point inward 
        mesh.f = mesh.f(:, [1, 3, 2]) ;
    end
    
    %% Update our estimate for the true xyzlims
    xminrs = min(xminrs, min(xyzrs(:, 1))) ;
    yminrs = min(yminrs, min(xyzrs(:, 2))) ;
    zminrs = min(zminrs, min(xyzrs(:, 3))) ;
    xmaxrs = max(xmaxrs, max(xyzrs(:, 1))) ;
    ymaxrs = max(ymaxrs, max(xyzrs(:, 2))) ;
    zmaxrs = max(zmaxrs, max(xyzrs(:, 3))) ;
    
    %% Get a guess for the axis limits if this is first TP
    if tidx == 1 
        % Check if already saved. If so, load it. Otherwise, guess.
        fntmp = xyzlimname_um ;
        if exist(fntmp, 'file')
            xyzlims = dlmread(fntmp, ',', 1, 0) ;
            xminrs = xyzlims(1) ;
            yminrs = xyzlims(2) ;
            zminrs = xyzlims(3) ;
            xmaxrs = xyzlims(4) ;
            ymaxrs = xyzlims(5) ;
            zmaxrs = xyzlims(6) ;
            % Note that we can't simply rotate the bounding box, since it will
            % be tilted in the new frame. We must guess xyzlims for plotting
            % and update the actual xyzlims
            % this works for new box: resolution * ((rot * box')' + trans) ;
        end
        % Expand xyzlimits for plots
        xminrs_plot = xminrs - plot_buffer ;
        yminrs_plot = yminrs - plot_buffer ;
        zminrs_plot = zminrs - plot_buffer ;
        xmaxrs_plot = xmaxrs + plot_buffer ;
        ymaxrs_plot = ymaxrs + plot_buffer ;
        zmaxrs_plot = zmaxrs + plot_buffer ;    
    end
    
    %% Check the rotation
    if tidx == 1 && redo_rot_calc
        close all
        fig = figure('Visible', 'off') ;
        tmp = trisurf(mesh.f, xyzrs(:, 1), xyzrs(:,2), xyzrs(:, 3), ...
                    xyzrs(:, 1), 'edgecolor', 'none', 'FaceAlpha', 0.5) ;
        [~,~,~] = apply_ambient_occlusion(tmp, 'SoftLighting', true) ; % 'ColorMap', viridis) ;
        hold on;
        xyz = vtx_sub;
        
        % Aligned meshes have inward pointing normals, so flip them for
        % plotting ambient occlusion (irrespective of flipy, I believe)
        faces_to_plot = mesh.f(:, [2, 1, 3]) ;
        
        tmp2 = trisurf(faces_to_plot, xyz(:, 1), xyz(:,2), xyz(:, 3), ...
            xyz(:, 1), 'edgecolor', 'none', 'FaceAlpha', 0.5) ;
        clearvars faces_to_plot
        [~,~,~] = apply_ambient_occlusion(tmp2, 'SoftLighting', true) ; % 'ColorMap', viridis) ;
        boxx = [xmin, xmin, xmin, xmin, xmax, xmax, xmax, xmax, xmin] ;
        boxy = [ymin, ymax, ymax, ymin, ymin, ymax, ymax, ymin, ymin] ;
        boxz = [zmin, zmin, zmax, zmax, zmax, zmax, zmin, zmin, zmin] ;
        box = [boxx', boxy', boxz'] ;
        box_sub = box / ssfactor ; 
        boxrs = resolution * ((rot * box')' + trans) ;
        plot3(box_sub(:, 1), box_sub(:, 2), box_sub(:, 3), 'k-')
        plot3(boxrs(:, 1), boxrs(:, 2), boxrs(:, 3), 'k-')
        for i=1:3
            plot3([boxrs(i, 1), box_sub(i, 1)], ...
                [boxrs(i, 2), box_sub(i, 2)], ...
                [boxrs(i, 3), box_sub(i, 3)], '--')
        end
          
        % plot the skeleton
        % for i=1:length(skelrs)
        %     plot3(skelrs(:,1), skelrs(:,2), skelrs(:,3),'-','Color',[0,0,0], 'LineWidth', 3);
        % end
        plot3(sptrs(1), sptrs(2), sptrs(3), 'ro')
        plot3(eptrs(1), eptrs(2), eptrs(3), 'bo')
        plot3(dptrs(1), dptrs(2), dptrs(3), 'go')
        plot3(acom(1), acom(2), acom(3), 'rx')
        plot3(pcom(1), pcom(2), pcom(3), 'bx')
        plot3(dcom(1), dcom(2), dcom(3), 'gx')

        xlabel('x [$\mu$m or pix]', 'Interpreter', 'Latex'); 
        ylabel('y [$\mu$m or pix]', 'Interpreter', 'Latex');
        zlabel('z [$\mu$m or pix]', 'Interpreter', 'Latex');
        title('Checking rotation')
        axis equal
        saveas(fig, fullfile(alignedMeshDir, 'rot_check.png'))
        close all
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% Save the rotated, translated, scaled to microns mesh ===============
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    alignedmeshfn = fullfile(alignedMeshDir, sprintf([alignedMeshBase '.ply'], tt)) ;
    if overwrite || ~exist(alignedmeshfn, 'file')
        disp('Saving the aligned mesh...')
        disp([' --> ' alignedmeshfn])
        plywrite_with_normals(alignedmeshfn, mesh.f, xyzrs, vn_rs)
    else
        disp(['alignedMesh PLY exists on disk (' alignedmeshfn ')'])
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% Plot and save
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
    % Save plot of rotated and translated mesh
    figs_do_not_exist = ~exist(fig1outname, 'file') || ...
        ~exist(fig2outname, 'file') || ~exist(fig3outname, 'file');
    
    if overwrite || overwrite_ims || figs_do_not_exist
        disp('Saving rotated & translated figure (xy)...')    
        close all
        fig = figure('Visible', 'Off') ;
        if flipy
            faces_to_plot = mesh.f(:, [2, 1, 3]) ;
        else
            faces_to_plot = mesh.f ;
        end
        th = trisurf(faces_to_plot, xyzrs(:, 1), xyzrs(:, 2), xyzrs(:, 3), ...
            'edgecolor', 'none', 'facecolor', 'w', 'FaceAlpha', 0.5) ;
        % 'FaceVertexCData',bsxfun(@times,(1-AO),C)
        [~,~,~] = apply_ambient_occlusion(th, 'SoftLighting', true) ;
        
        % Figure properties
        axis equal
        set(gca, 'color', 'k', 'xcol', 'w', 'ycol', 'w', 'zcol', 'w')
        set(gcf, 'color', 'k')
        titlestr = ['Aligned mesh, $t=$' num2str(tt * timeinterval) ' ' timeunits] ;
        title(titlestr, 'interpreter', 'latex', 'color', 'w'); 
        grid off
        
        % check it 
        % set(gcf, 'visible', 'on')
        % waitfor(gcf)
        % error('here')

        hold on;
        plot3(sptrs(1), sptrs(2), sptrs(3), 'o', 'color', red)
        plot3(eptrs(1), eptrs(2), eptrs(3), 'o', 'color', blue)
        plot3(dptrs(1), dptrs(2), dptrs(3), 'o', 'color', green)
        plot3(acom_rs(1), acom_rs(2), acom_rs(3), 's', 'color', red)
        plot3(pcom_rs(1), pcom_rs(2), pcom_rs(3), '^', 'color', blue)
        xlabel('x [$\mu$m]', 'Interpreter', 'Latex'); 
        ylabel('y [$\mu$m]', 'Interpreter', 'Latex');
        zlabel('z [$\mu$m]', 'Interpreter', 'Latex');
        
        % xy
        view(2)
        xlim([xminrs_plot xmaxrs_plot]); 
        ylim([yminrs_plot ymaxrs_plot]); 
        zlim([zminrs_plot zmaxrs_plot]) ;
        set(gcf, 'PaperUnits', 'centimeters');
        set(gcf, 'PaperPosition', [0 0 xwidth ywidth]);
        disp(['Saving to ' fig1outname])
        % saveas(fig, fig1outname)
        export_fig(fig1outname, '-nocrop', '-r150')
        
        % yz
        disp('Saving rotated & translated figure (yz)...')    
        view(90, 0);
        xlim([xminrs_plot xmaxrs_plot]); 
        ylim([yminrs_plot ymaxrs_plot]); 
        zlim([zminrs_plot zmaxrs_plot]) ;
        set(gcf, 'PaperUnits', 'centimeters');
        set(gcf, 'PaperPosition', [0 0 xwidth ywidth]);  % x_width=10cm y_width=15cm
        % saveas(fig, fig2outname)
        export_fig(fig2outname, '-nocrop', '-r150')
        
        % xz
        disp('Saving rotated & translated figure (xz)...')  
        view(0, 0)    
        xlim([xminrs_plot xmaxrs_plot]); 
        ylim([yminrs_plot ymaxrs_plot]); 
        zlim([zminrs_plot zmaxrs_plot]) ;
        set(gcf, 'PaperUnits', 'centimeters');
        set(gcf, 'PaperPosition', [0 0 xwidth ywidth]);  % x_width=10cm y_width=15cm
        % saveas(fig, fig3outname)
        export_fig(fig3outname, '-nocrop', '-r150')
        close all
    end
    
    %% Preview and save coms
    % Check the normals 
    if preview 
        close all
        plot3(vtx_rs(1:10:end, 1), vtx_rs(1:10:end, 2), vtx_rs(1:10:end, 3), '.')
        for i=1:10:length(vtx_rs)
            hold on
            plot3([vtx_rs(i, 1), vtx_rs(i, 1) + 10*vn_rs(i, 1)], ... 
            [vtx_rs(i, 2), vtx_rs(i, 2) + 10*vn_rs(i, 2)], ...
            [vtx_rs(i, 3), vtx_rs(i, 3) + 10*vn_rs(i, 3)], 'r-') 
        end
        axis equal
    end    
    
    % Save acom, pcom and their aligned counterparts as attributes in an
    % hdf5 file            
    name = sprintf(fn, tt) ;
    % Save if overwrite
    if overwrite || ~apdcoms_rs_exist
        try
            h5create(outapdvname, ['/' name '/acom'], size(acom)) ;
        catch
            disp('acom already exists as h5 file. Overwriting.')
        end
        try
            h5create(outapdvname, ['/' name '/pcom'], size(pcom)) ;
        catch
            disp('pcom already exists as h5 file. Overwriting.')
        end
        try 
            h5create(outapdvname, ['/' name '/dcom'], size(dcom)) ;
        catch
            disp('dcom already exists as h5 file. Overwriting.')
        end
        try
            h5create(outapdvname, ['/' name '/acom_rs'], size(acom_rs)) ;
        catch
            disp('acom_rs already exists as h5 file. Overwriting.')
        end
        try
            h5create(outapdvname, ['/' name '/pcom_rs'], size(pcom_rs)) ;
        catch
            disp('pcom_rs already exists as h5 file. Overwriting.')
        end
        try 
            h5create(outapdvname, ['/' name '/dcom_rs'], size(dcom_rs)) ;
        catch
            disp('dcom_rs already exists as h5 file. Overwriting.')
        end
        h5write(outapdvname, ['/' name '/acom'], acom) ;
        h5write(outapdvname, ['/' name '/pcom'], pcom) ;
        h5write(outapdvname, ['/' name '/dcom'], dcom) ;
        h5write(outapdvname, ['/' name '/acom_rs'], acom_rs) ;
        h5write(outapdvname, ['/' name '/pcom_rs'], pcom_rs) ;
        h5write(outapdvname, ['/' name '/dcom_rs'], dcom_rs) ;
        % h5disp(outapdvname, ['/' name]);
        disp('Saved h5: scom pcom dcom acom_rs pcom_rs dcom_rs')
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% Save the startpt/endpt, both original and rescaled to um ===========
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Save acom, pcom and their aligned counterparts as attributes in an
    % hdf5 file
    name = sprintf(fn, tt) ;
    
    if overwrite || ~spt_ept_exist
        disp('Saving the startpt/endpt...')
        try
            h5create(outstartendptname, ['/' name '/spt'], size(spt)) ;
        catch
            disp('spt already exists as h5 file. Overwriting.')
        end
        try
            h5create(outstartendptname, ['/' name '/ept'], size(ept)) ;
        catch
            disp('ept already exists as h5 file. Overwriting.')
        end
        try 
            h5create(outstartendptname, ['/' name '/dpt'], size(dpt)) ;
        catch
            disp('dpt already exists as h5 file. Overwriting.')
        end
        try
            h5create(outstartendptname, ['/' name '/sptrs'], size(eptrs)) ;
        catch
            disp('sptrs already exists as h5 file. Overwriting.')
        end
        try
            h5create(outstartendptname, ['/' name '/eptrs'], size(eptrs)) ;
        catch
            disp('eptrs already exists as h5 file. Overwriting.')
        end
        try 
            h5create(outstartendptname, ['/' name '/dptrs'], size(dptrs)) ;
        catch
            disp('dptrs already exists as h5 file. Overwriting.')
        end

        h5write(outstartendptname, ['/' name '/spt'], spt) ;
        h5write(outstartendptname, ['/' name '/ept'], ept) ;
        h5write(outstartendptname, ['/' name '/dpt'], dpt) ;
        h5write(outstartendptname, ['/' name '/sptrs'], sptrs) ;
        h5write(outstartendptname, ['/' name '/eptrs'], eptrs) ;
        h5write(outstartendptname, ['/' name '/dptrs'], dptrs) ;
        disp('Saved h5: spt ept dpt sptrs eptrs dptrs')
    else
        disp('startpt/endpt already exist and not overwriting...')
    end
    toc
end

% Todo: save raw xyzlim in full resolution pixels but not rotated/scaled
% Save xyzlim_raw
if overwrite || ~exist(xyzlimname_raw, 'file')
    disp('Saving rot/trans mesh xyzlimits for plotting')
    header = 'xyzlimits for raw meshes in units of full resolution pixels' ;
    xyzlim = [xmin, xmax; ymin, ymax; zmin, zmax] ;
    write_txt_with_header(xyzlimname_raw, xyzlim, header) ;
else
    xyzlim_raw = [xmin, xmax; ymin, ymax; zmin, zmax] ;
end

% Save xyzlimits 
if overwrite || ~exist(xyzlimname_pix, 'file')
    disp('Saving rot/trans mesh xyzlimits for plotting')
    header = 'xyzlimits for rotated translated meshes in units of full resolution pixels' ;
    xyzlim = [xminrs, xmaxrs; yminrs, ymaxrs; zminrs, zmaxrs] / resolution;
    write_txt_with_header(xyzlimname_pix, xyzlim, header) ;
else
    xyzlim = [xminrs, xmaxrs; yminrs, ymaxrs; zminrs, zmaxrs] / resolution;
end

% Save xyzlimits in um
if overwrite || ~exist(xyzlimname_um, 'file')
    disp('Saving rot/trans mesh xyzlimits for plotting, in microns')
    header = 'xyzlimits for rotated translated meshes in microns' ;
    xyzlim_um = [xminrs, xmaxrs; yminrs, ymaxrs; zminrs, zmaxrs] ;
    write_txt_with_header(xyzlimname_um, xyzlim_um, header) ;
end

% Save buffered xyzlimits in um
if overwrite || ~exist(xyzlimname_um_buff, 'file')
    disp('Saving rot/trans mesh xyzlimits for plotting, in microns')
    header = 'xyzlimits for rotated translated meshes in microns, with padding (buffered)' ;
    xyzlim_um = [xminrs, xmaxrs; yminrs, ymaxrs; zminrs, zmaxrs] ;
    xyzlim_um_buff = xyzlim_um + QS.normalShift * resolution * [-1, 1] ;
    write_txt_with_header(xyzlimname_um_buff, xyzlim_um_buff, header) ;
end

disp('done')