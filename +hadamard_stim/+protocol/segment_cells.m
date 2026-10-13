function cells = segment_cells(cfg, ref_image, geometry)
%SEGMENT_CELLS Cells, spots and DMD masks from the reference image.
%
%   cells = hadamard_stim.protocol.segment_cells(cfg, ref_image, geometry)
%
%   What Yitong did in the DMD app before the script: "Append" with Auto
%   Square (segmentation, spots of cfg.segmentation.illum_spot_size), then
%   reduce_spot_size_sequence for the stimulation spots. The result is a
%   proposal: the operator looks at min_val and the cells, and approves.
%   Approved, it becomes the canonical geometry, which is never edited.
%
%   cells.cell_coord  [n x 2] x, y, in ascending contrast (matrix row order)
%   cells.illum_rois, cells.stim_rois   NaN-separated camera-space spots
%   cells.illum_mask, cells.stim_mask   canvas masks of all cells
%   cells.min_val     the curve he chose n_exclude from
s = cfg.segmentation;
if isempty(s.n_exclude)
    error("hadamard_stim:NExcludeMissing", ...
        ['segmentation.n_exclude is not set. Look at min_val from a ' ...
         'preview and choose how many top-contrast candidates to skip ' ...
         '(Yitong''s FOV needed 5).']);
end
[x, y, min_val] = hadamard_stim.yitong.static_image_seg_v5(ref_image, s.threshold, s.n_exclude);
cells.cell_coord = [x y];
cells.min_val = min_val;
cells.threshold = s.threshold;
cells.n_exclude = s.n_exclude;
cells = hadamard_stim.protocol.draw_cells(cells, s, geometry);
end
