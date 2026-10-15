function summary = run_summary(controller)
%RUN_SUMMARY What the package is about to run, or ran, in a few lines.
%
%   summary = hadamard_stim.ui.run_summary(controller)
%
%   Read from the controller's own state (getState) and the environment's
%   context, never recomputed: the configuration's mode and deviations,
%   the session mode, the cells, the trial range (connectivity) or blocks
%   (spontaneous) and the switches, which optional streams are on, the
%   calibrations a run records and the standing deviations of this rig.
state = controller.getState();
cfg = controller.Config;
summary.mode = state.mode;
summary.session_mode = state.session_mode;
summary.warnings = state.warnings;
summary.streams = struct("face_camera", isequal(cfg.behavior.face_camera_enabled, true), ...
    "wheel_encoder", isequal(cfg.behavior.wheel_encoder_enabled, true));
summary.blocks = struct("n_blocks", cfg.spontaneous.n_blocks, ...
    "block_frames", cfg.spontaneous.block_frames, ...
    "block_s", cfg.spontaneous.block_frames * cfg.stimulation.waveform_period_ms / 1000, ...
    "drift_correction", isequal(cfg.spontaneous.drift_correction, true));
summary.config_ok = isempty(state.config_errors);
summary.config_errors = state.config_errors;
summary.deviations = state.deviations;
summary.n_cells = state.n_approved_cells;
if summary.n_cells == 0 && ~isempty(state.proposal)
    summary.n_cells = state.proposal.n_cells;
end
summary.cells_approved = state.n_approved_cells > 0;
summary.trials = struct("first", cfg.trials.first, "last", cfg.trials.last, ...
    "n_trial", cfg.trials.n_trial, "n_sparse", cfg.trials.n_sparse);
summary.switches = struct("run_sparse", cfg.trials.run_sparse, ...
    "z_reference", cfg.z_reference.enabled, "drift_correction", cfg.drift.enabled, ...
    "bleaching_correction", cfg.bleaching.enabled);
summary.blue_calibration = state.calibration;
summary.geometry = state.environment.geometry;
summary.hardware_gate = state.environment.hardware_gate;
summary.simulated = state.environment.simulated;
summary.standing_deviations = strings(0, 1);
if isfield(controller.Env, "context") && isfield(controller.Env.context, "standing_deviations")
    summary.standing_deviations = reshape(string(controller.Env.context.standing_deviations), [], 1);
end
summary.run_folder = state.run_folder;
summary.recipe_hash = state.recipe_hash;
end
