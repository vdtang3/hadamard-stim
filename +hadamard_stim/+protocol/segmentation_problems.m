function problems = segmentation_problems(s)
%SEGMENTATION_PROBLEMS What is wrong with cfg.segmentation, one sentence each.
%
%   problems = hadamard_stim.protocol.segmentation_problems(cfg.segmentation)
%
%   Empty when segment_cells can run with these settings. Missing optional
%   settings (from a configuration older than them) are not problems:
%   segment_cells uses his values. n_exclude unset is reported by
%   validate_config as a required setting, not here.
problems = strings(1, 0);
if ~is_count(s.threshold, 1)
    problems(end+1) = "segmentation.threshold (cells to keep) must be a whole number of at least 1.";
end
if isfield(s, "select_all") && ~(islogical(s.select_all) || isnumeric(s.select_all)) ...
        || isfield(s, "select_all") && ~isscalar(s.select_all)
    problems(end+1) = "segmentation.select_all must be true or false.";
end
if isfield(s, "candidate_pool") && ~is_count(s.candidate_pool, 2)
    problems(end+1) = "segmentation.candidate_pool (regions ranked as candidates) must be a whole number of at least 2.";
end
if isfield(s, "min_area_px") && ~(isnumeric(s.min_area_px) && isscalar(s.min_area_px) ...
        && isfinite(s.min_area_px) && s.min_area_px >= 0)
    problems(end+1) = "segmentation.min_area_px must be 0 or more pixels.";
end
if isfield(s, "filter_size_px") && ~is_count(s.filter_size_px, 1)
    problems(end+1) = "segmentation.filter_size_px must be a whole number of pixels, at least 1.";
end
end

function tf = is_count(v, least)
tf = isnumeric(v) && isscalar(v) && isfinite(v) && v >= least && v == round(v);
end
