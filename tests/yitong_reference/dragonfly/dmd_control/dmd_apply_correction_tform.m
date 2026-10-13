function rois_corrected = dmd_apply_correction_tform(app,rois)

% im_live = app.ref_im;
% % im_test = zeros(size(im_live));
% % [X,Y] = meshgrid(1:size(im_test,2),1:size(im_test,1));
% % rois = {cell2mat(cellfun(@(x) [x;nan nan],rois,'uniformoutput',false))};
% % im_test(inpolygon(X,Y,rois{:}(:,1),rois{:}(:,2)))=1;
% % 
% tform = app.correction_tform;
% rig_mat = tform([1 2],[1 2]);
% trans_mat = tform(3,[1 2])';
% % 
% % im_corr = imwarp(im_test,tform);
% % 
% % rois_corrected = bwboundaries(im_corr);
% 
% rois_corrected = cellfun(@(xy) (rig_mat*xy'+repmat(trans_mat,[1 length(xy)]))',rois,'uniformoutput',false);
% % figure;imshow2(im_live,[])
% % hold on
% % cellfun(@(x) plot(x(:,1),x(:,2),'g'),rois)
% % cellfun(@(x) plot(x(:,1),x(:,2),'r'),rois_corrected)

tform = app.correction_tform;
rois_corrected = cellfun(@(xy) transformPointsInverse(tform,xy),rois,'uniformoutput',false);