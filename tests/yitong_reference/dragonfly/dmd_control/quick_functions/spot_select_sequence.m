function spot_select_sequence(app,cIdx,idxAppend)
spot_rois = app.mask_sequence_rois{1};
spot_rois_idx = find(ismissing(spot_rois(:,1)));
nROI = length(spot_rois_idx);
% mask_new = logical(app.mask_sequence(:,:,idx(1)));
% spot_list = regionprops(mask_new,'pixelIdxList');
% spot_list = arrayfun(@(x) x.PixelIdxList,spot_list,'uniformoutput',false);

spot_rois_new = {};
for ii = 1:length(spot_rois_idx)
    if ii == 1
        spot_rois_new{ii} = spot_rois(1:spot_rois_idx(1)-1,:);
    else
        spot_rois_new{ii} = spot_rois(spot_rois_idx(ii-1)+1:spot_rois_idx(ii)-1,:);
    end
end

spot_rois_new(~cIdx) = [];
% spot_rois_new = cell2mat(spot_rois_new');
roi_out = cell2mat(cellfun(@(x) [x;nan nan],spot_rois_new','uniformoutput',false));
app.mask_sequence_rois{idxAppend} = roi_out;
app.mask_sequence(:,:,idxAppend)  = dmd_draw_hidden(app,spot_rois_new',false);
