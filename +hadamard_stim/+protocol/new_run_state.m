function state = new_run_state(cfg, canonical, reference)
%NEW_RUN_STATE Protocol state before the first trial.
%
%   state = hadamard_stim.protocol.new_run_state(cfg, canonical_cells, reference)
%
%   canonical  approved cells (segment_cells or draw_cells): cell_coord,
%              illum_rois, stim_rois, illum_mask, stim_mask
%   reference  had_ref (the image the cells were found on), z_all and
%              had_z_stack (run_z_reference)
%
%   Everything his script kept in workspace variables between trials is
%   here, so a checkpoint of this struct resumes a run exactly:
%     next_trial, cnt, cnt_had, picked, sparse_pictures (illumPatAll),
%     orange_v, exposure_waveform_ms, b0, b1, and the current geometry.
n_cells = size(canonical.cell_coord, 1);
if n_cells ~= cfg.matrix.order
    % His script printed "nCell ~= hadOrder!" and carried on; matrix rows
    % then do not match cells. Refuse instead: this cannot be a parity run.
    error("hadamard_stim:CellCount", ...
        "%d cells were approved but the stimulation matrix has %d rows.", ...
        n_cells, cfg.matrix.order);
end
if isempty(cfg.stimulation.orange_start_v)
    error("hadamard_stim:OrangeStartMissing", ...
        "stimulation.orange_start_v is not set (Yitong set it by hand; it was not saved).");
end

state.next_trial = cfg.trials.first;
state.cnt = 0;
state.cnt_had = 0;
state.picked = false(n_cells, cfg.trials.n_trial * numel(cfg.sparse.blue_v));
state.sparse_pictures = cell(cfg.sparse.n_pulses, 1);
state.orange_v = cfg.stimulation.orange_start_v;
state.exposure_waveform_ms = cfg.stimulation.waveform_period_ms;
state.b0 = [];
state.b1 = [];
state.had_mat = hadamard_stim.yitong.stim_matrix(cfg.matrix.order);

state.cells.canonical = canonical;
current = struct("illum_rois", canonical.illum_rois, "stim_rois", canonical.stim_rois, ...
    "illum_mask", canonical.illum_mask, "stim_mask", canonical.stim_mask);
state.cells.current = current;
state.cells.corrections = struct("trial", {}, "cell_shift", {}, "flow_at_cells", {}, ...
    "z_drift", {}, "z_fallback", {}, "motor_before", {}, "motor_after", {}, ...
    "illum_mask_sha256", {}, "stim_mask_sha256", {});

state.reference = reference;
end
