function reduce_spot_size_sequence(app,newR,idxAppend)

spot_rois = app.mask_sequence_rois{1};
spot_rois_idx = find(ismissing(spot_rois(:,1)));
nROI = length(spot_rois_idx);
% mask_new = logical(app.mask_sequence(:,:,idx(1)));
% spot_list = regionprops(mask_new,'pixelIdxList');
% spot_list = arrayfun(@(x) x.PixelIdxList,spot_list,'uniformoutput',false);

% reduce spot size by a multiplicative factor
spot_rois_new = cell(1,nROI);
for ii = 1:length(spot_rois_idx)
    if ii == 1
        spot_rois_new{ii} = spot_rois(1:spot_rois_idx(1)-1,:);
    else
        spot_rois_new{ii} = spot_rois(spot_rois_idx(ii-1)+1:spot_rois_idx(ii)-1,:);
    end
    
    % calculate original spot size
    ptCtr = nanmean(spot_rois_new{ii},1);
    oldR = sqrt(sum((spot_rois_new{ii}(1,:) - ptCtr).^2))*2;
    spot_rois_new{ii} = (spot_rois_new{ii} - ptCtr)*newR/oldR + ptCtr;
end

roi_out = cell2mat(cellfun(@(x) [x;nan nan],spot_rois_new','uniformoutput',false));
app.mask_sequence_rois{idxAppend} = roi_out;
app.mask_sequence(:,:,idxAppend)  = dmd_draw_hidden(app,spot_rois_new',false);
