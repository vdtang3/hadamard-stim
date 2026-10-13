function mask = dmd_draw_rasterize(roi_points, registration_data, cam_offset, dmd_size, saved_mask, correction_tform)
%DMD_DRAW_RASTERIZE Rasterise spots the way his "Append" pattern drawing did.
%
%   mask = hadamard_stim.yitong.dmd_draw_rasterize(roi_points, registration_data, cam_offset, dmd_size, saved_mask)
%
%   How his initial Auto Square illumination pattern reached the DMD:
%   inpolygon over the whole DMD for every spot, then ANDed with the DMD
%   app's saved_mask when one was set. The protocol's later patterns go
%   through dmd_draw_hidden instead, which never applies saved_mask
%   (notebook, P3). Without a saved_mask the two give the same mask; the
%   parity tests check that.
%
%   Port of tests/yitong_reference/dragonfly/dmd_control/dmd_draw.m
%   SHA-256 21929758952b1f26e2b7113784447530f55f1ed4836619ca13fd5acf17986ae2
%   Changes: the rasterising after the switch only, with the geometry and
%   saved_mask passed in; never projects.
arguments
    roi_points cell
    registration_data (3, 2) double
    cam_offset (1, 2) double
    dmd_size (1, 2) double = [1024 768]
    saved_mask = []
    correction_tform = []
end
L = dmd_size(1);
W = dmd_size(2);
pat = false(L,W);
mask_mask = true(L,W);
if ~isempty(saved_mask)
    mask_mask = saved_mask;
end

if ~isempty(correction_tform)
    roi_points = cellfun(@(xy) transformPointsInverse(correction_tform,xy),roi_points,'uniformoutput',false);
end
roi_points = cellfun(@(xy) xy+cam_offset,roi_points,'uniformoutput',false);

try
dmd_cam_trans = registration_data(1,:)';
dmd_rot_dil_mat = registration_data(2:3,:)';
[x, y] = meshgrid(1:W, 1:L);
dmd_pixel_pos = cellfun(@(xy) round(dmd_rot_dil_mat\(xy'-repmat(dmd_cam_trans,[1 length(xy)]))),...
                        roi_points,'uniformoutput',false);

in = cellfun(@(pixel_pos) inpolygon(x,y,pixel_pos(1,:),pixel_pos(2,:)),dmd_pixel_pos,'uniformoutput',false);
for i=1:length(in), pat = pat|in{i}; end
pat = pat&mask_mask;
mask = pat;
catch err
    warning('hadamard_stim:PatternCalculation', 'Pattern calculation error: %s', err.message);
    mask = [];
end
end
