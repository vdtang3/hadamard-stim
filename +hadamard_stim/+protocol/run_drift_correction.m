function [state, correction] = run_drift_correction(cfg, env, state, iTrial, options)
%RUN_DRIFT_CORRECTION Re-find the cells and refocus, as he did every 40 trials.
%
%   [state, correction] = hadamard_stim.protocol.run_drift_correction(cfg, env, state, iTrial)
%   [...] = run_drift_correction(..., smooth=false, stim=false)
%
%   The one drift operation both session modes use. Connectivity trials
%   call it with the defaults (square_target_drift_correction_v4).
%   Spontaneous blocks call it with smooth=false and stim=false, which is
%   his square_target_drift_correction_single_v1: each cell keeps its own
%   flow, and only the illumination spots are redrawn (the stimulation
%   spots and mask stay as they were, and the correction records an empty
%   stim_mask_sha256). iTrial names the scan folder (_had_trial<N>), as
%   both his scripts did with the trial or block number.
%
%   square_target_drift_correction_v4: a Hadamard scan at twice the
%   stimulation exposure, orange at cfg.scan.orange_v and blue off; then
%   XY drift from optical flow against the reference image, smoothed over
%   neighbouring cells, applied to the canonical spots (never cumulative);
%   then Z drift from the scan's spatial spectrum against the reference
%   z-stack, applied as a relative stage move.
%
%   He switched the app's waveform, folder, orange and exposure for the scan
%   and switched them back afterwards. Here the scan's settings live only in
%   its own acquisition spec, so there is nothing to switch back, except
%   one thing that outlived the scan: he restored the waveform period as
%   camera exposure + 0.02 ms rather than the value typed before, and the
%   trials after it use that (state.exposure_waveform_ms). He also left
%   blue at 0 V, which the next trial overwrote.
%
%   The correction is appended to state.cells.corrections; the canonical
%   cells are not touched.
arguments
    cfg
    env
    state
    iTrial
    options.smooth (1, 1) logical = true
    options.stim (1, 1) logical = true
end
hw = env.hw;
canonical = state.cells.canonical;
tExpOrig = cfg.stimulation.camera_exposure_ms;

scan_area = true(cfg.dmd.size);
if isfield(env.geometry, "scan_area")
    scan_area = env.geometry.scan_area;
end
masks = hadamard_stim.yitong.static_hadamard_patterns(scan_area);
hw.dmd_load_stack(permute(masks, [2 1 3]));

scale = cfg.drift.exposure_scale;
waveform = hadamard_stim.protocol.scan_waveform(cfg, tExpOrig*scale + .02, ...
    cfg.scan.orange_v, size(masks, 3));
folder = cfg.naming.prefix + "_had_trial" + num2str(iTrial);
spec = hadamard_stim.protocol.acquisition_spec("drift_scan", folder, waveform, ...
    trial=iTrial, camera_exposure_ms=tExpOrig*scale, ...
    streams=hadamard_stim.protocol.acquisition_streams(cfg, "drift_scan"));
acq = hw.acquire(spec);
hadCur = env.reconstruct_scan(acq);

state.exposure_waveform_ms = tExpOrig + .02;

ref = state.reference;
result = hadamard_stim.yitong.drift_correction(hadCur, ref.had_ref, ref.had_z_stack, ...
    ref.z_all, canonical.cell_coord, {canonical.illum_rois, canonical.stim_rois}, ...
    smooth=options.smooth);

current = state.cells.current;
current.illum_rois = hadamard_stim.yitong.join_rois(result.illum_spots);
current.illum_mask = env.geometry.rasterize(result.illum_spots, "hidden");
stim_mask_sha256 = "";
if options.stim
    current.stim_rois = hadamard_stim.yitong.join_rois(result.stim_spots);
    current.stim_mask = env.geometry.rasterize(result.stim_spots, "hidden");
    stim_mask_sha256 = hadamard_stim.metadata.sha256(current.stim_mask);
end
state.cells.current = current;

zOrig = hw.motor_position();
hw.motor_move_to(zOrig - result.z_drift);

correction = struct("trial", iTrial, "cell_shift", result.cell_shift, ...
    "flow_at_cells", result.flow_at_cells, "z_drift", result.z_drift, ...
    "z_fallback", result.z_fallback, "motor_before", zOrig, ...
    "motor_after", hw.motor_position(), ...
    "illum_mask_sha256", hadamard_stim.metadata.sha256(current.illum_mask), ...
    "stim_mask_sha256", stim_mask_sha256);
state.cells.corrections(end+1) = correction;
end
