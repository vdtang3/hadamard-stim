function mask = dmd_draw_hidden(roi_points, registration_data, cam_offset, dmd_size, correction_tform)
%DMD_DRAW_HIDDEN Rasterise camera-space spots onto the DMD, as his DMD app did.
%
%   mask = hadamard_stim.yitong.dmd_draw_hidden(roi_points, registration_data, cam_offset, dmd_size)
%   mask = hadamard_stim.yitong.dmd_draw_hidden(..., correction_tform)
%
%   roi_points         spots in camera coordinates (cell of [n x 2] x, y)
%   registration_data  his 3 x 2 affine DMD-to-camera registration: row 1
%                      translation, rows 2-3 the linear part
%   cam_offset         [x y] of the camera ROI on the full sensor
%   dmd_size           [L W] = [1024 768], his device.height/width
%   correction_tform   optional; empty in every case we can reproduce
%
%   The mask is in his orientation, L x W. Its transpose is the Luminos
%   canvas (rows = ALP lines), which is what the rest of this package uses.
%   Each spot is drawn by inpolygon over its own bounding box.
%
%   Port of tests/yitong_reference/dragonfly/dmd_control/dmd_draw_hidden.m
%   SHA-256 316fa4ae4113105c5f26fccc98f61c2f443f8daa6c1d0c72fb341bac74b86e52
%   Port of tests/yitong_reference/dragonfly/dmd_control/dmd_apply_correction_tform.m
%   SHA-256 74a917ad27b2df3a7b902c75b1a953d5ae5062f538fcc0ad22e2a76e659fbfa5
%   Changes: geometry passed in instead of read from the DMD app; never
%   projects (he always called it with prj_yes false here); the ROI outputs
%   are join_rois; app state (current_rois, current_mask) not written. On a
%   failure he printed "Pattern calculation error" and returned [], and so
%   does this, with the error text added.
arguments
    roi_points cell
    registration_data (3, 2) double
    cam_offset (1, 2) double
    dmd_size (1, 2) double = [1024 768]
    correction_tform = []
end
L = dmd_size(1);
W = dmd_size(2);
pat = false(L,W);

if ~isempty(correction_tform)
    roi_points = cellfun(@(xy) transformPointsInverse(correction_tform,xy),roi_points,'uniformoutput',false);
end
roi_points = cellfun(@(xy) xy+cam_offset,roi_points,'uniformoutput',false);

try
% convert camera coordinate to dmd coordinate
dmd_cam_trans = registration_data(1,:)';
dmd_rot_dil_mat = registration_data(2:3,:)';
dmd_pixel_pos = cellfun(@(xy) round(dmd_rot_dil_mat\(xy'-repmat(dmd_cam_trans,[1 length(xy)]))),...
                        roi_points,'uniformoutput',false);

% draw dmd patterns fast
for ii = 1:length(dmd_pixel_pos)
    xi = dmd_pixel_pos{ii}(1,:);
    yi = dmd_pixel_pos{ii}(2,:);
    xMin = max(min(xi),1);
    xMax = min(max(xi),W);
    yMin = max(min(yi),1);
    yMax = min(max(yi),L);
    [xInd,yInd] = meshgrid(xMin:xMax,yMin:yMax);
    onInd = inpolygon(xInd,yInd,xi,yi);
    patInd = sub2ind([L,W],yInd(onInd),xInd(onInd));
    pat(patInd) = true;
end

mask = pat;
catch err
    warning('hadamard_stim:PatternCalculation', 'Pattern calculation error: %s', err.message);
    mask = [];
end
end
