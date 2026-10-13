function [mask,varargout] = dmd_draw(app,opt,prj_yes)

if ~exist('prj_yes','var')
    prj_yes = true;
end

if isvalid(app.fig_mask_draw)
    figure(app.fig_mask_draw)
else
    app.fig_mask_draw = load_reference_img();
end

L = app.dmd.device.height;
W = app.dmd.device.width;
pat = false(L,W);

cam_offset = [app.HorizontalOffsetEditField.Value app.VerticalOffsetEditField.Value];
mask_mask = true(L,W);
switch opt
    case 'Arb Shape'
        
        % start cliky loop
        figure(app.fig_mask_draw)
        hold on
        title('Please clicky ROIs')
        npts = 1;
        nroi = 1;
        while(npts > 0)

            [xv, yv] = (getline(gca, 'closed'));
            if size(xv,1) < 3  % exit loop if only a line is drawn
            break
            end

            %draw the bounding polygons and label them
%             plot(xv, yv, 'Linewidth', 1);
            roi_points{nroi,1} = [xv, yv];

%             roi_points{nroi} = [xv, yv]+cam_offset;
            nroi = nroi + 1;
        end

        
        
    case 'Rectangle'
        
        try %#okay uncaught
            myrect = getrect;   
            roi_points = {myrect(1:2)+myrect(3:4).*[0 0 1 1 0; 0 1 1 0 0]'};
%             roi_points = {myrect(1:2)+myrect(3:4).*[0 0 1 1 0; 0 1 1 0 0]'+cam_offset};
%             figure(app.fig_mask_draw)
%             hold on
%             plot(roi_points{1}(:,1),roi_points{1}(:,2))
%             hold off
        end

        
    case 'Square' % circular spot instead, better aliasing
        sq_size = app.SquareSizeEditField.Value;
        
        [xv, yv] = (getpts_counter(gca, 'closed'));
        roi_center = [xv yv];
        hTxt = title(gca,num2str(length(roi_center)),'visible','on');
        hL = line(gca,xv,yv,'linestyle','none','marker','x','markersize',9,'color','r');
        while ~isempty(xv)
            [xv, yv] = (getpts_counter(gca, 'closed'));
            roi_center = [roi_center; [xv yv]];
            hL.XData = roi_center(:,1);
            hL.YData = roi_center(:,2);
            hTxt.String = num2str(length(roi_center));
        end
        delete(hTxt)
        delete(hL)
        clear hTxt hL
        app.function_data.cell_coord = roi_center;
        
        phi = linspace(0,2*pi,12);
        xC = cos(phi) * sq_size/2;
        yC = sin(phi) * sq_size/2;
                        
        roi_points = arrayfun(@(x,y) [xC' + x, yC' + y],...
                                roi_center(:,1),roi_center(:,2),'uniformoutput',false);        
%         roi_points = arrayfun(@(x,y) [[0 sq_size sq_size 0 0]'-sq_size/2 + x,...
%                                 [0 0 sq_size sq_size 0]'-sq_size/2 + y],...
%                                 roi_center(:,1),roi_center(:,2),'uniformoutput',false);      
%         figure(app.fig_mask_draw)
%         hold on
%         cellfun(@(x) plot(x(:,1),x(:,2)),roi_points)
%         hold off
        

    case 'Auto Square' % circular spot instead, better aliasing
        ref_im = app.ref_im;
        sq_size = app.SquareSizeEditField.Value;
        [xv, yv] = static_image_seg_v5(ref_im,app.ThresholdEditField.Value);
        app.function_data.cell_coord = [xv yv];
        
        phi = linspace(0,2*pi,12);
        xC = cos(phi) * sq_size/2;
        yC = sin(phi) * sq_size/2;

        roi_center = [xv yv];
        roi_points = arrayfun(@(x,y) [xC' + x, yC' + y],...
                                roi_center(:,1),roi_center(:,2),'uniformoutput',false);   
%                             
%         roi_points = arrayfun(@(x,y) [[0 sq_size sq_size 0 0]'-sq_size/2 + x,...
%                                         [0 0 sq_size sq_size 0]'-sq_size/2 + y],...
%                                         roi_center(:,1),roi_center(:,2),'uniformoutput',false);        

        if ~isempty(app.saved_mask)
            mask_mask = app.saved_mask;
        end
%         figure(app.fig_mask_draw)
%         hold on
%         cellfun(@(x) plot(x(:,1),x(:,2)),roi_points)
%         hold off
end


roi_points_out = {cell2mat(cellfun(@(x) [x;nan nan],roi_points,'uniformoutput',false))};


varargout{1} = roi_points_out;

app.current_rois = roi_points_out;

if ~isempty(app.correction_tform)
    roi_points = dmd_apply_correction_tform(app,roi_points);
end
roi_points = cellfun(@(xy) xy+cam_offset,roi_points,'uniformoutput',false);

try
% convert camera coordinate to dmd coordinate
dmd_cam_trans = app.registration_data(1,:)';
dmd_rot_dil_mat = app.registration_data(2:3,:)';
[x, y] = meshgrid(1:W, 1:L);
dmd_pixel_pos = cellfun(@(xy) round(dmd_rot_dil_mat\(xy'-repmat(dmd_cam_trans,[1 length(xy)]))),...
                        roi_points,'uniformoutput',false);

% draw dmd patterns
in = cellfun(@(pixel_pos) inpolygon(x,y,pixel_pos(1,:),pixel_pos(2,:)),dmd_pixel_pos,'uniformoutput',false);
for i=1:length(in), pat = pat|in{i}; end
pat = pat&mask_mask;
if prj_yes, app.dmd.project(double(pat)); end
mask = pat;
catch
    disp('Pattern calculation error')
    mask = [];
end