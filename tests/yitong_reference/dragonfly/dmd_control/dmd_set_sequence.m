function mask_sequence = dmd_set_sequence(app,opt,roi_points)

L = app.dmd.device.height;
W = app.dmd.device.width;
pat = false(L,W);
% mask_roi = [];

switch opt
    case 'Append'
        [mask,mask_roi] = dmd_draw(app,app.DMDMaskGenButtonGroup.SelectedObject.Text,0);
        app.mask_sequence_rois = [app.mask_sequence_rois mask_roi'];
        try
            app.mask_sequence = cat(3,app.mask_sequence,mask);
        catch
            app.mask_sequence = mask;
        end
    case 'Delete'
        opts.Interpreter = 'tex';
        cell_input = inputdlg('\fontsize{10} Please specify the indices to delete (fmt: ind1 ind2 ... or ind1:ind2)','',1,{''},opts);
        del_ind = str2num(cell2mat(cell_input));
        try
        app.mask_sequence_rois(del_ind) = [];
        end
        app.mask_sequence(:,:,del_ind) = [];
        
    case 'Reorder'
        opts.Interpreter = 'tex';
        cell_input = inputdlg('\fontsize{10} Please specify the new indices (fmt: ind1 ind2 ... or ind1:ind2)','',1,{''},opts);
        new_ind = str2num(cell2mat(cell_input));
        app.mask_sequence_rois = app.mask_sequence_rois(new_ind);
        app.mask_sequence = app.mask_sequence(:,:,new_ind);
        
    case 'Camera ROIs'
        cam_offset = [app.HorizontalOffsetEditField.Value app.VerticalOffsetEditField.Value];
        if ~exist('roi_points','var')
            [fname,~]=uigetfile('*.mat');
            load(fname,'roi_points')
        end
        roi_points_plot = roi_points;
        roi_points = cellfun(@(xy) xy+cam_offset,roi_points,'uniformoutput',false);
        
        dmd_cam_trans = app.registration_data(1,:)';
        dmd_rot_dil_mat = app.registration_data(2:3,:)';
        [x, y] = meshgrid(1:W, 1:L);
        dmd_pixel_pos = cellfun(@(xy) round(dmd_rot_dil_mat\(xy'-repmat(dmd_cam_trans,[1 length(xy)]))),roi_points,'uniformoutput',false);

        % draw dmd patterns
        in = cellfun(@(pixel_pos) inpolygon(x,y,pixel_pos(1,:),pixel_pos(2,:)),dmd_pixel_pos,'uniformoutput',false);
        pat_temp = false(L,W,length(in));
        for i=1:length(in), pat_temp(:,:,i) = pat_temp(:,:,i)|in{i}; end
        
        app.mask_sequence_rois = roi_points_plot;
        app.mask_sequence = pat_temp;
end
line_all = findobj(get(app.fig_mask_draw,'Children'),'type','line');
delete(line_all(~(line_all==app.h_mask_sequence_rois)))
mask_sequence = pat;
app.MaskNoTotalEditField.Value = size(app.mask_sequence,3);

% figure(app.fig_mask_seq_preview);clf
% moviesc(pat);