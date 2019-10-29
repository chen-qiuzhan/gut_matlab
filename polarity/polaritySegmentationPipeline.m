% Simple version of computing local tensor from segmentation of pullbacks
% NPM 2019 
% Run from meshDir, NOT soiDir directory where the pullbacks reside
% This code is different from polarity_from_images_simple.m in that it
% assumes the pullbacks are output as individual files, not as a single
% tiff stack.
% Requires all pullbacks to be the same size.
%
% Prerequisites
% ----------------------
% adjust_canvas_size.m (to make all images same size, if necessary)
% iLastik training on membrane 
%    output in same folder, with 1-1 correspondence between images & h5's
% 

clear; close all; clc;
seriestype = 're_adjusted' ;
stepstr = '' ;

%% Run ilastik on images and save as H5 files in soiDir (pwd)

%% Define dirs for finding images in stack
% Old definitions
% datadir = '/mnt/crunch/48Ygal4UASCAAXmCherry/201902072000_excellent/' ;
% datadir = [datadir 'Time6views_60sec_1.4um_25x_obis1.5_2/data/deconvolved_16bit/' ] ;
% soiDir = [datadir 'gut_apical_cylinder_msls_prnun5_prs1_nu0p00_s0p10_pn2_ps4_l1_l1_3layer/' ] ;
% filenameFormat = [soiDir 'fields/data_MIP/cylinder1_index/cylinder1/cmp_1_1_T%04d.tif' ] ;
% soiDir = [datadir 'msls_output_prnun5_prs1_nu0p00_s0p10_pn2_ps4_l1_l1/PullbackImages_010step_extended_shifted/'] ;

meshDir = cd ;

if strcmp(seriestype, 're_adjusted')
    soiDir = fullfile(meshDir, ['PullbackImages' stepstr '_relaxed_extended_adjusted' filesep]) ;
elseif strcmp(seriestype, 'es')
    soiDir = fullfile(meshDir, ['PullbackImages' stepstr '_extended_shifted' filesep]) ;
end
filenameFormat = fullfile(soiDir, 'Time_*_c1_stab_adjust.tif' ) ;
ilastiksegFolder = soiDir ;
polDir = fullfile(meshDir, ['polarity' filesep 'segmentation' filesep]) ;
polDir_spec = fullfile(polDir, ['membrane' stepstr '_' seriestype filesep]) ;
polOutDir = fullfile(polDir_spec, 'membrane_polarity') ;
if ~exist(polOutDir, 'dir')
    mkdir(polOutDir)
end

%% Options
step = 50 ;  % how far apart boxes for local averaging
eps = 1e-5 ;  % small number
% cutoff in bond length in units of median bond length
length_cutoff = 100 ; 
colorwheel_position = [.8 .01 .15 .15] ;
preview = false ;

% Prepare output directory
outdir = fullfile(polDir_spec, [ 'membrane_anisotropy_step' sprintf('%03d', step) filesep ]);
if ~exist(outdir, 'dir')
    mkdir(outdir)
end

%% First compute order parameter cos(2*theta)
% add paths for segmentation
addpath('/mnt/data/code/gut_matlab/tissueAnalysisSuite/')
addpath('/mnt/data/code/gut_matlab/plotting/')
% todo match opacity to magnitude, change cmap
% cmap = diverging_cmap(0:0.01:1, 1, 2) ;  
[colors, names] = define_colors(3) ;
yellow = colors(3, :) ;
cmap = interpolate_3color_cmap(0:0.01:1, 5, yellow, 4, false) ;
% check the colormap
% h2 = scatter(1:10, 1:10, 40, 1:10, 'filled') ;
% colormap(gcf, cmap);

%% Create a label matrix
segmentation_fn = fullfile(soiDir, 'segmentation.mat') ;
if exist(segmentation_fn, 'file')
    disp('Loading segmentation...')
    load(segmentation_fn)
else
    very_far = 450 ;  % distance between points that can't be a cell, in pixels
    mode = 0;  % Toggle for ilastik version control
    disp('loading h5 data in ilastik segmentation folder...')
    mem = load.ilastikh5( ilastiksegFolder, mode ) ; 
    if length(mem) < 1
        error(['Found no h5 files in ' ilastiksegFolder])
    end
    disp('segmenting the data...')
    L = seg.memWS(mem, 50, 0, 1, 3.5) ;
    % Set bond=0, clear_border=1, and threefold=0 in generate_structs()
    [L, Struct] = seg.generate_structs(L, 0, 1, 0, very_far);
    disp('done with initial segmentation')

    % Collate bond data
    % put a parameter in the cdat of Struct, a boolean of whether every 
    % vertex is 3-fold.
    disp('Record three-fold <- todo: get around this')
    Struct = seg.threefold_cell(Struct);
    % generate the Bdat structure in Struct
    disp('recording bonds...')
    Struct = seg.recordBonds(Struct, L);

    % save it
    disp(['saving the segmentation to ' segmentation_fn])
    save(segmentation_fn, 'Struct', 'L', 'mem', '-v7.3', '-nocompression')
end
disp('done with segmentation')

%% Now plot each timepoint
% pre-allocate 
aniso_medians = zeros(size(L, 3), 1) ;
aniso_unc = zeros(size(L, 3), 1) ;
fns = dir(fullfile(soiDir, filenameFormat)) ;
for t=1:size(L, 3)
    fn = fns(t).name ;
    fullfn = fullfile(fns(t).folder, fns(t).name) ;
    disp(['Considering timepoint: ', num2str(t)])
    disp([' associated with fn: ', fn])
    fnsplit = split(fns(t).name, '.tif') ;
    fnout = [fnsplit{1} '_membrane_anisotropy.mat'] ;
    fullfnout = fullfile(polOutDir, fnout) ;
    disp([' to output as ' fnout])
    
    % Collate the vertices into array
    vdat = Struct(t).Vdat ;
    xv = zeros(length(vdat), 1) ;
    yv = zeros(length(vdat), 1) ;
    for i=1:length(vdat)
        xv(i) = vdat(i).vertxcoord ;
        yv(i) = vdat(i).vertycoord ;
    end

    % Collate the lines into linesegments to get orientation
    disp('collating into linesegments...')
    bdat = Struct(t).Bdat ;
    xyxy = zeros(length(bdat), 4) ;
    vectors = zeros(length(bdat), 2) ;
    bondxy = zeros(length(bdat), 2) ;
    for bondi = 1:length(bdat)
        ij = bdat(bondi).verts ;
        x1 = vdat(ij(1)).vertxcoord ;
        y1 = vdat(ij(1)).vertycoord ;
        x2 = vdat(ij(2)).vertxcoord ;
        y2 = vdat(ij(2)).vertycoord ;
        % Create the vector / linesegment
        xyxy(bondi, 1:2) = [x1, y1];
        xyxy(bondi, 3:4) = [x2, y2];
        vectors(bondi, :) = xyxy(bondi, 3:4) - xyxy(bondi, 1:2) ;
        bondxy(bondi, :) = [0.5 * (x1 + x2), 0.5 * (y1 + y2)] ;
    end
    
    % get orientation of each vector
    disp('obtaining orientation of each bond...')
    thetas = atan2(vectors(:, 2), vectors(:, 1)) ;
    lengths = sum(vectors .^ 2, 2) ;
    lengths = lengths / median(lengths) ;
    lengths(lengths > length_cutoff) = 0 ;
    xv = cos(2 * thetas) .* lengths ;
    yv = sin(2 * thetas) .* lengths ;
    
    % Check: plot the bonds by their angle
    if preview
        fig = figure ;
        p1 = imagesc(mem(:, :, t)) ;
        hold on;
        quiver(bondxy(:, 1), bondxy(:, 2), vectors(:, 1), vectors(:, 2))
        caxis([-1 1])
    end
    
    % Make a grid over the field, average in each grid bin
    disp('gridding...')
    alphaVal = 0.3 ;
    imsize = size(mem(:, :, t)) ;
    maxy = imsize(1) ; 
    maxx = imsize(2) ; 
    XX = 0:step:maxx ;
    YY = 0:step:maxy ;
    nrows = floor(maxy / step) ;
    ncols = floor(maxx / step) ;
    [~, idx] = histc(bondxy(:, 1), XX) ;
    [~, idy] = histc(bondxy(:, 2), YY) ;
    compartmentID = idy + (idx - 1) * nrows;
    
    % In case there are linesegs out of bounds, map them to 1 
    % todo: check that 1 is blank?
    compartmentID(compartmentID < 1) = 1 ;
    compartmentID(compartmentID > nrows * ncols) = 1 ;
    xvmean = accumarray( compartmentID, xv, [], @mean);
    yvmean = accumarray( compartmentID, yv, [], @mean);
    meanlengths = accumarray( compartmentID, lengths, [], @mean);
    
    % anisotropy is measured via its magnitude and cosine of its angle
    vectormeans = [xvmean, yvmean] ;
    mags = vecnorm(vectormeans')' ;
    lcos2t = xvmean ;
    lsin2t = yvmean ;
    
    % Pad with zeros if the data does not fill the whole image (this
    % finishes the last row or column of the grid with zeros)
    if length(mags) < nrows * ncols
        mags(nrows * ncols) = 0 ;
        lcos2t(nrows * ncols) = 0 ;
        lsin2t(nrows * ncols) = 0 ;
        meanlengths(nrows * ncols) = 0 ;
    end
    
    % Make a rectangular grid of the data
    meanlengths(meanlengths == 0) = Inf ;
    % normalize magnitudes by the length to get scale free measure
    mags_n = reshape(mags ./ meanlengths, [nrows, ncols]) ;
    lcos2t = reshape(lcos2t, [nrows, ncols]) ;
    lsin2t = reshape(lsin2t, [nrows, ncols]) ;
    xcenters = XX(1:end-1) + 0.5 * (XX(2) - XX(1)) ;
    ycenters = YY(1:end-1) + 0.5 * (YY(2) - YY(1)) ; 
    
    
    % Save the results
    save(fullfnout, 'xcenters', 'ycenters', 'mags_n', 'lcos2t', 'lsin2t', 'meanlengths')
    
    % Save a plot
    fn = sprintf([outdir 'memaniso_%06d.png'], t) ;
    if overwrite || ~exist(fn, 'file')
        % New figure
        hf=figure;
        set(hf, 'Visible', 'off');
        % Background image
        h1 = axes;
        p1 = imagesc(mem(:, :, t)); 
        colormap(h1,'gray');
        set(h1,'ydir','normal');
        % Foreground image
        h2=axes;
        % Could use pcolor
        % s = pcolor(xx, yy, aniso) ;   
        % s.FaceColor = 'interp' ;
        % s.EdgeColor = 'none' ;
        % set(s,'facealpha',0.3)
        % Instead use imagesc
        opacity = min(1, mags_n * alphaVal) ;
        % check it
        % imshow(opacity) 
        % error('break')
        s = imagesc(xcenters, ycenters, lcos2t, 'AlphaDataMapping','scaled',...
                'AlphaData', opacity) ;
        % alpha(h2, alphaVal)
        caxis([-1, 1]) ;
        set(h2,'color','none','visible','off');
        colormap(h2, cmap);
        set(h2,'ydir','normal');
        linkaxes([h1 h2])
        axis equal
        % Make both axes invisible
        axis off
        set(h1, 'Visible', 'off')
        % Get the current axis size in case things get disrupted
        originalPos_h1 = get(h1, 'Position') ;
        originalPos_h2 = get(h2, 'Position') ;
        title(['t=' num2str(t) ' min'],...
            'FontWeight','Normal')
        set(h2, 'Position', originalPos_h2);

        % Colorwheel as grid
        ax3 = axes('Position', colorwheel_position) ;
        [xx, yy] = meshgrid(-1:0.01:1, -1:0.01:1) ;
        color = cos(2 * atan2(yy, xx)) * 0.5  + 0.5 ;
        radius = vecnorm([xx(:), yy(:)]') ;
        alpha = reshape(radius, size(xx)) ;
        alpha(radius > 1) = 0 ;
        h = imagesc(xx(:), yy(:), color) ;
        set(h, 'AlphaData', alpha) ;
        colormap(gca, cmap)
        axis equal
        axis off
        title({'Cell membrane', 'anisotropy'}, 'Fontweight', 'normal')

        % Save the image
        disp(['Saving figure ' fn])
        saveas(hf, fn)
    end
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    % Here just take simple medians 
    cos2tbin_medians(t) = nanmedian(lcos2t(lcos2t ~= 0)) ;
    tmp = nanstd(lcos2t(lcos2t ~= 0)) ;
    cos2tbin_unc(t) = tmp / sqrt(length(lcos2t(lcos2t ~= 0))) ;
    
    sin2tbin_medians(t) = nanmedian(lsin2t(lsin2t ~= 0)) ;
    tmp = nanstd(lsin2t(lsin2t ~= 0)) ;
    sin2tbin_unc(t) = tmp / sqrt(length(lsin2t(lsin2t ~= 0))) ;
    
    % Weight the anisotropy by the scale of the mesh at that point and sum
    % todo: write this
    % cos2t_raw = cos(2 * thetas) ;
    % lodil is the length divided by the dilation from the metric
    % lodil = lengths / lineseg_dilation ;
    % aniso_medians(t) = nanmedian(xv) ;
    
    
    % % Linear colorbar
    % c = colorbar();
    % % Manually flush the event queue and force MATLAB to render the colorbar
    % % necessary on some versions
    % drawnow
    % % Get the color data of the object that correponds to the colorbar
    % cdata = c.Face.Texture.CData;
    % % Change the 4th channel (alpha channel) to 10% of it's initial value (255)
    % cdata(end,:) = uint8(alphaVal * cdata(end,:));
    % % Ensure that the display respects the alpha channel
    % c.Face.Texture.ColorType = 'truecoloralpha';
    % % Update the color data with the new transparency information
    % c.Face.Texture.CData = cdata;
    % % Put the axis back in place
    % set(h2, 'Position', originalPos_h1);
    % % Move the colorbar closer
    % c.Position = c.Position - [0.15, 0, 0, 0] ;
    
    % Tighten the margins -- this messes up the relative positions 
    % outerpos = h1.OuterPosition;
    % ti = h1.TightInset; 
    % left = outerpos(1) + ti(1);
    % bottom = outerpos(2) + ti(2);
    % ax_width = outerpos(3) - ti(1) - ti(3);
    % ax_height = outerpos(4) - ti(2) - ti(4);
    % h1.Position = [left bottom ax_width ax_height];
    % % Now do the second axis
    % outerpos = h1.OuterPosition;
    % ti = h2.TightInset; 
    % left = outerpos(1) + ti(1);
    % bottom = outerpos(2) + ti(2);
    % ax_width = outerpos(3) - ti(1) - ti(3);
    % ax_height = outerpos(4) - ti(2) - ti(4);
    % h2.Position = [left bottom ax_width ax_height];
    
    % Take into account the map itself
    % g_uv x^u y^v / sqrt(g_uv x^u x^u) sqrt(g_uv y^u y^v) = cos theta
    
    close('all')
end

%% Plot medians
% errorbar(aniso_medians, aniso_std)
close all
xx = 0:size(L, 3) - 1 ;
clower = cos2tbin_medians - cos2tbin_unc ;
cupper = cos2tbin_medians + cos2tbin_unc ;
% sin(2t) * l
slower = sin2tbin_medians - sin2tbin_unc ;
supper = sin2tbin_medians + sin2tbin_unc ;

colors = define_colors();
blue = colors(1, :)  ;
red = uint8(colors(2, :) * 255) ;
% lightblue = [149 / 255, 208 / 255, 252 / 255] ;
cf = fill([xx, fliplr(xx)], [clower, fliplr(cupper)], blue, 'LineStyle', 'none') ;
set(cf, 'facealpha', .1)
hold on;
sf = fill([xx, fliplr(xx)], [slower, fliplr(supper)], red, 'LineStyle', 'none') ;
set(sf, 'facealpha', .1)

ch = plot(xx, cos2tbin_medians, 'Color', blue) ;
sh = plot(xx, sin2tbin_medians, 'Color', red) ;
xlabel('time [min]')
ylabel('$\langle \ell \cos(2\theta) \rangle$, $\langle \ell \sin(2\theta) \rangle$', 'interpreter', 'latex')
title('membrane anisotropy')
xlim([0, size(L, 3)]) ;
legend([ch, sh], {'$\langle \ell \cos(2\theta) \rangle$', ...
    '$\langle \ell \sin(2\theta) \rangle$'}, 'location', 'best', 'Interpreter', 'Latex')
% ylim([min(aniso_medians - aniso_unc), max(aniso_medians + aniso_unc)])
zeroh = plot([0, size(L, 3)], [0, 0], 'k--') ;
set(get(get(zeroh,'Annotation'),'LegendInformation'),...
    'IconDisplayStyle','off'); % Exclude line from legend

% save it
outfn_time = [soiDir, 'membrane_anisotropy.png'] ;
disp(['saving to ', outfn_time]) 
saveas(gcf, outfn_time)

% Save data
save([soiDir 'membrane_anisotropy_timeseq.mat'], ...
    'cos2tbin_medians', 'cos2tbin_unc', 'sin2tbin_medians', 'sin2tbin_unc')

clear tmp

%% Now try radon transform approach
% for time = timePoints
%     disp(['Considering time=' num2str(time)])
%     fileName = sprintf(filenameFormat, time);
% 
%     fullFileName = fullfile(dataDir, fileName);
%     disp([ 'reading ' fullFileName]) 
%     data = readSingleTiff(fullFileName);
%     
%     theta = 0:180;
%     [R,xp] = radon(I,theta);
%     imagesc(theta,xp,R);
%     title('R_{\theta} (x\prime)');
%     xlabel('\theta (degrees)');
%     ylabel('x\prime');
%     set(gca,'XTick',0:20:180);
%     colormap(hot);
%     colorbar
% end







