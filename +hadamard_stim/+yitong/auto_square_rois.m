function spots = auto_square_rois(cell_coord, sq_size)
%AUTO_SQUARE_ROIS The illumination spots of Yitong's "Auto Square" pattern.
%
%   spots = hadamard_stim.yitong.auto_square_rois(cell_coord, sq_size)
%
%   One closed 12-vertex circle of diameter sq_size around each cell, in
%   camera coordinates; spots{k} is [12 x 2] (x, y). The first and last
%   vertices coincide, which is why reduce_spot_size, averaging all twelve,
%   centres the smaller spot slightly off the cell (notebook, finding 3).
%
%   Port of tests/yitong_reference/dragonfly/dmd_control/dmd_draw.m
%   SHA-256 21929758952b1f26e2b7113784447530f55f1ed4836619ca13fd5acf17986ae2
%   Changes: the 'Auto Square' ROI construction only. Segmentation is
%   called separately (static_image_seg_v5) and rasterising is
%   dmd_draw_rasterize.
arguments
    cell_coord (:, 2) double
    sq_size (1, 1) double
end
phi = linspace(0,2*pi,12);
xC = cos(phi) * sq_size/2;
yC = sin(phi) * sq_size/2;

roi_center = cell_coord;
spots = arrayfun(@(x,y) [xC' + x, yC' + y],...
                        roi_center(:,1),roi_center(:,2),'uniformoutput',false);
end
