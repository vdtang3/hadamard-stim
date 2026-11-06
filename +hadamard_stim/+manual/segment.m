function cells = segment(image, settings)
%SEGMENT The tab's segmentation of one image, without a DMD: cells and their camera-space spots.
%
%   cells = hadamard_stim.manual.segment(image, settings)
%
%   protocol.segment_cells - his static_image_seg_v5, Auto Square
%   illumination spots, the smaller stimulation spots - with settings
%   (segmentation_settings), exactly as the tab calls it, except that
%   nothing is drawn on a DMD: the cells, their order (cell k is row k of
%   cell_coord, as the tab numbers them) and the spots do not depend on
%   the DMD; the masks are drawn from them afterwards
%   (protocol.draw_cells), for the cells kept. image is not modified.
%   cells: cell_coord, excluded_coord, min_val, threshold, n_exclude,
%   segmentation, illum_rois, stim_rois.
cfg = hadamard_stim.default_config();
cfg.segmentation = hadamard_stim.manual.segmentation_settings(settings);
undrawn = struct("rasterize", @(spots, kind) [], "identity", struct("source", "none"));
cells = hadamard_stim.protocol.segment_cells(cfg, image, undrawn);
cells = rmfield(cells, ["illum_mask" "stim_mask"]);
end
