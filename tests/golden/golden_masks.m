function data = golden_masks(ctx)
%GOLDEN_MASKS Spot ROIs and DMD masks, built the way Yitong built them.
%
%   His two patterns came from the DMD app, not the protocol script:
%     pattern 1 (orange illumination): dmd_set_sequence 'Append' with
%       'Auto Square', SquareSize 5, Threshold 320;
%     pattern 2 (blue stimulation): quick function
%       reduce_spot_size_sequence(app, 3, 2).
%   Section "check_2024" proves this by reproducing his saved 2024-08-23
%   camera-space ROIs. His saved DMD masks cannot be reproduced exactly:
%   the best integer camera offset still differs from them by about one
%   pixel along spot edges, consistent with the dmd_draw_hidden
%   correction_tform step, whose transform was never saved. The best-fit
%   offset and the residual mismatch are recorded. Section "canonical" then
%   builds the 2025-03-08 geometry the same way (no correction_tform); the
%   trace and drift goldens start from it.
inputs = load(fullfile(ctx.fixtures, "yitong_session_inputs.mat"));
segmentation = load(fullfile(ctx.fixtures, "yitong_segmentation.mat"), "real");
square_size = 5;
stim_diameter = 3;

% --- 2024: same procedure must reproduce the saved session ---------------
golden_use_path(ctx, "fixed_cells");
s24 = inputs.session_2024;
setappdata(0, "hadamard_stim_golden_cells", s24.cell_coord);
[offset, mismatch] = infer_camera_offset(s24);
app = new_app(s24.registration_data, offset);
build_patterns(app, square_size, stim_diameter);
check.camera_offset = offset;
check.illum_mask_mismatch_pixels_at_best_offset = mismatch;
check.illum_mask_saved_pixels = nnz(s24.mask_sequence(:, :, 1));
check.square_size = square_size;
check.stim_diameter = stim_diameter;
check.illum_rois_max_abs_error = max(abs(app.mask_sequence_rois{1} - s24.mask_sequence_rois{1}), [], "all", "omitnan");
check.stim_rois_max_abs_error = max(abs(app.mask_sequence_rois{2} - s24.mask_sequence_rois{2}), [], "all", "omitnan");
data.check_2024 = check;
fprintf("2024 check: offset [%g %g], mask mismatch %d px, roi errors %.3g %.3g\n", offset, ...
    mismatch, check.illum_rois_max_abs_error, check.stim_rois_max_abs_error);
delete(app);

% --- 2025: canonical geometry from the real segmentation ----------------
golden_use_path(ctx, "segmentation");
s25 = inputs.session_2025;
setappdata(0, "hadamard_stim_golden_n_exclude", segmentation.real.n_exclude);
app = new_app(s25.registration_data, offset);
app.ref_im = s25.ref_im;
build_patterns(app, square_size, stim_diameter);
canonical.assumption = "camera offset is the best fit to the 2024-08-23 masks; " + ...
    "the 2025-03-08 session did not save it, and no correction_tform is applied";
canonical.camera_offset = offset;
canonical.registration_data = s25.registration_data;
canonical.n_exclude = segmentation.real.n_exclude;
canonical.cell_coord = app.function_data.cell_coord;
canonical.cell_coord_equals_saved = isequal(canonical.cell_coord, s25.cell_coord);
canonical.mask_sequence_rois = app.mask_sequence_rois;
canonical.mask_sequence = app.mask_sequence;
data.canonical = canonical;

% --- spot_select_sequence, as the protocol calls it ----------------------
matrix = load(fullfile(ctx.fixtures, "yitong_matrix.mat"), "had_mat");
n_cells = size(canonical.cell_coord, 1);
selections.hadamard_code_1 = matrix.had_mat(:, 1) > 0;
selections.sparse_first = quasi_equidist_hardsphere_v2(canonical.cell_coord, 123, [], zeros(n_cells, 640));
for name = string(fieldnames(selections)).'
    c_idx = selections.(name);
    rois_cur = canonical.mask_sequence_rois;
    app.mask_sequence_rois = rois_cur;
    app.mask_sequence = canonical.mask_sequence;
    % The protocol's exact sequence of calls (script lines 160-167).
    app.function_data.cIdx = c_idx;
    app.mask_sequence_rois(1) = rois_cur(2);
    spot_select_sequence(app, c_idx, 2)
    app.mask_sequence_rois(1) = rois_cur(1);
    data.spot_select.(name) = struct("c_idx", c_idx, ...
        "rois", {app.mask_sequence_rois}, "mask_sequence", app.mask_sequence, ...
        "btd_sha256", string(golden_sha256(alp_logical_to_btd(permute(app.mask_sequence, [2 1 3])))));
end
delete(app);
end

function app = new_app(registration, offset)
app = MockDmdApp(MockVialuxDMD(MockAlpDevice()));
app.registration_data = registration;
app.HorizontalOffsetEditField.Value = offset(1);
app.VerticalOffsetEditField.Value = offset(2);
app.ThresholdEditField.Value = 320;
end

function build_patterns(app, square_size, stim_diameter)
app.SquareSizeEditField.Value = square_size;
dmd_set_sequence(app, 'Append');
reduce_spot_size_sequence(app, stim_diameter, 2);
end

function [offset, mismatch] = infer_camera_offset(s)
%INFER_CAMERA_OFFSET Integer camera offset whose rendering best matches
%his saved illumination mask (fewest differing pixels). A least-squares
%estimate from the mask's centre of mass is refined by a +-3 px search.
A = s.registration_data(2:3, :)';
t = s.registration_data(1, :)';
rois = s.mask_sequence_rois{1};
[r, c] = find(s.mask_sequence(:, :, 1));
estimate = round(A * [mean(c); mean(r)] + t - mean(rois, 1, "omitnan")');
spots = split_rois(rois);
app = MockDmdApp(MockVialuxDMD(MockAlpDevice()));
app.registration_data = s.registration_data;
cleanup = onCleanup(@() delete(app));
mismatch = inf;
for dx = -3:3
    for dy = -3:3
        candidate = estimate' + [dx dy];
        app.HorizontalOffsetEditField.Value = candidate(1);
        app.VerticalOffsetEditField.Value = candidate(2);
        d = nnz(xor(dmd_draw_hidden(app, spots, false), s.mask_sequence(:, :, 1)));
        if d < mismatch
            mismatch = d;
            offset = candidate;
        end
    end
end
end

function spots = split_rois(rois)
ends = find(isnan(rois(:, 1)));
starts = [1; ends(1:end-1) + 1];
spots = arrayfun(@(a, b) rois(a:b-1, :), starts, ends, "UniformOutput", false);
end
