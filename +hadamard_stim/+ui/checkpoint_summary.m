function summary = checkpoint_summary(run_folder, context)
%CHECKPOINT_SUMMARY What resuming a run folder would continue from.
%
%   summary = hadamard_stim.ui.checkpoint_summary(run_folder, context)
%
%   Read from the folder's recipe and checkpoint through load_checkpoint,
%   exactly as resume_run reads them, so a checkpoint that would be
%   refused is reported here with the same error. context (the prepared
%   environment's, or []) is compared with the calibrations the run
%   recorded: a resume on a different calibration is flagged, not refused.
arguments
    run_folder (1, 1) string
    context = []
end
summary = struct("run_folder", run_folder, "ok", false, "message", "", ...
    "recipe_hash", "", "next_trial", [], "first_trial", [], "last_trial", [], ...
    "n_trial_records", 0, "cnt", [], "cnt_had", [], "n_sparse_cells_used", [], ...
    "orange_v", [], "exposure_waveform_ms", [], "b0", [], "b1", [], ...
    "n_corrections", 0, "last_correction", [], "complete", false, ...
    "calibration_matches", [], "geometry_matches", []);
try
    [recipe, ~] = hadamard_stim.metadata.read_recipe(run_folder);
    state = hadamard_stim.metadata.load_checkpoint(run_folder);
catch err
    summary.message = string(err.message);
    return
end
summary.ok = true;
summary.recipe_hash = recipe.recipe_hash;
summary.first_trial = recipe.config.trials.first;
summary.last_trial = recipe.config.trials.last;
summary.next_trial = state.next_trial;
summary.complete = state.next_trial > recipe.config.trials.last;
summary.n_trial_records = numel(dir(fullfile(run_folder, "trials", "trial_*.json")));
summary.cnt = state.cnt;
summary.cnt_had = state.cnt_had;
summary.n_sparse_cells_used = nnz(any(state.picked, 2));
summary.orange_v = state.orange_v;
summary.exposure_waveform_ms = state.exposure_waveform_ms;
summary.b0 = state.b0;
summary.b1 = state.b1;
corrections = state.cells.corrections;
summary.n_corrections = numel(corrections);
if ~isempty(corrections)
    c = corrections(end);
    summary.last_correction = struct("trial", c.trial, "z_drift", c.z_drift, ...
        "mean_cell_shift_px", mean(c.cell_shift, 1), "motor_after", c.motor_after);
end
if ~isempty(context) && isfield(context, "blue_calibration")
    summary.calibration_matches = isequal(jsonencode(recipe.calibrations.blue), ...
        jsonencode(context.blue_calibration.identity));
    summary.geometry_matches = isequal(jsonencode(recipe.calibrations.geometry), ...
        jsonencode(context.geometry_identity));
end
end
