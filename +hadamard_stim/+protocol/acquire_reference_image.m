function [image, acq] = acquire_reference_image(cfg, env)
%ACQUIRE_REFERENCE_IMAGE One Hadamard scan at the current focus: the image cells are found on.
%
%   [image, acq] = hadamard_stim.protocol.acquire_reference_image(cfg, env)
%
%   Before his script, Yitong took a Hadamard scan by hand and segmented
%   its reconstruction (hadamard_ref). This is that step: the drift scan's
%   patterns (static_hadamard_patterns over the scan area) at the scan
%   settings (cfg.scan: 2.5 ms exposure, 2.52 ms period, orange 0.47 V,
%   blue off), which are also what every later drift scan is compared
%   with. The stage does not move.
hadamard_stim.protocol.report_phase(env, "reference_scan");
scan_area = true(cfg.dmd.size);
if isfield(env.geometry, "scan_area")
    scan_area = env.geometry.scan_area;
end
masks = hadamard_stim.yitong.static_hadamard_patterns(scan_area);
env.hw.dmd_load_stack(permute(masks, [2 1 3]));
waveform = hadamard_stim.protocol.scan_waveform(cfg, cfg.scan.waveform_period_ms, ...
    cfg.scan.orange_v, size(masks, 3));
spec = hadamard_stim.protocol.acquisition_spec("reference_scan", ...
    cfg.naming.prefix + "_had_ref", waveform, camera_exposure_ms=cfg.scan.camera_exposure_ms);
acq = env.hw.acquire(spec);
image = env.reconstruct_scan(acq);
acq = rmfield(acq, intersect(fieldnames(acq), ["waveform" "image"]));
end
