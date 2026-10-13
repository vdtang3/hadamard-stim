function data = golden_segmentation(ctx)
%GOLDEN_SEGMENTATION static_image_seg_v5: detection, ordering, exclusion.
%
%   Real image: Yitong's 2025-03-08 Hadamard reference. His answer to the
%   interactive "cells to exclude" prompt was not saved, so every answer
%   0..99 is tried and the one that reproduces his saved, ordered
%   cell_coord exactly is recorded.
golden_use_path(ctx, "segmentation");
inputs = load(fullfile(ctx.fixtures, "yitong_session_inputs.mat"), "session_2025");
s = inputs.session_2025;
threshold = 320;

data.real.threshold = threshold;
data.real.n_exclude = NaN;
for n_exclude = 0:99
    [cells, min_val] = run_segmentation(s.ref_im, threshold, n_exclude);
    if n_exclude == 0
        data.real.min_val = min_val;
        data.real.cells_n_exclude_0 = cells;
    end
    if isequal(cells, s.cell_coord)
        data.real.n_exclude = n_exclude;
        data.real.cells = cells;
        break
    end
end
data.real.reproduces_saved_cell_coord = ~isnan(data.real.n_exclude);
fprintf("real image: n_exclude = %g\n", data.real.n_exclude);

im = synthetic_reference_image();
data.synthetic.image_sha256 = string(golden_sha256(im));
for n_exclude = [0 5]
    [cells, min_val] = run_segmentation(im, threshold, n_exclude);
    data.synthetic.("n_exclude_" + n_exclude) = struct( ...
        "threshold", threshold, "n_exclude", n_exclude, "cells", cells, "min_val", min_val);
end

% Quirk kept for parity: a tie between two pixels that are each some
% region's maximum makes ind2sub return two positions for one cell and the
% function errors. Rounding the synthetic image to integers triggers it.
try
    run_segmentation(round(im), threshold, 0);
    data.integer_image_error = "";
catch err
    data.integer_image_error = string(err.message);
end
end

function [cells, min_val] = run_segmentation(im, threshold, n_exclude)
setappdata(0, "hadamard_stim_golden_n_exclude", n_exclude);
[x, y] = static_image_seg_v5(im, threshold);
cells = [x y];
% The curve Yitong looked at before answering the prompt (figure 51).
line = findobj(figure(51), "Type", "line", "XData", 0:99);
min_val = line.YData(:);
end
