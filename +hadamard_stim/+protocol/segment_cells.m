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
%   cells.excluded_coord  [n_exclude x 2] the skipped top-contrast candidates
%   cells.segmentation    what segmentation found and used (static_image_seg_v5's
%                         info: regions, candidates, requested and selected
%                         counts, and the settings)
%
%   Settings (cfg.segmentation; defaults are his): threshold (cells to
%   keep) or select_all (every candidate), n_exclude, candidate_pool
%   (regions ranked as candidates; the sensitivity), min_area_px,
%   filter_size_px. Fewer candidates than threshold keeps them all and
%   says so (segmentation.limited). A configuration from before these
%   settings existed gets his values.
s = cfg.segmentation;
if isempty(s.n_exclude)
    error("hadamard_stim:NExcludeMissing", ...
        ['segmentation.n_exclude is not set. Look at min_val from a ' ...
         'preview and choose how many top-contrast candidates to skip ' ...
         '(Yitong''s FOV needed 5).']);
end
problems = hadamard_stim.protocol.segmentation_problems(s);
if ~isempty(problems)
    error("hadamard_stim:SegmentationSettings", "Segmentation settings: %s", strjoin(problems, " "));
end
his = hadamard_stim.default_config().segmentation;
[x, y, min_val, excluded, info] = hadamard_stim.yitong.static_image_seg_v5(ref_image, ...
    s.threshold, s.n_exclude, ...
    candidate_pool=field_or(s, "candidate_pool", his.candidate_pool), ...
    min_area_px=field_or(s, "min_area_px", his.min_area_px), ...
    filter_size_px=field_or(s, "filter_size_px", his.filter_size_px), ...
    select_all=isequal(field_or(s, "select_all", his.select_all), true));
cells.cell_coord = [x y];
cells.excluded_coord = excluded;
cells.min_val = min_val;
cells.threshold = s.threshold;
cells.n_exclude = s.n_exclude;
cells.segmentation = info;
cells = hadamard_stim.protocol.draw_cells(cells, s, geometry);
end

function v = field_or(s, name, default)
v = default;
if isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
end
end
