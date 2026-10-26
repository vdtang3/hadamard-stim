function acquisitions = acquire_calibration_scans(cfg, env)
%ACQUIRE_CALIBRATION_SCANS His Hadamard calibration scans ("had_cal"), on a uniform slide.
%
%   acquisitions = hadamard_stim.protocol.acquire_calibration_scans(cfg, env)
%
%   What the scans are reconstructed against: the 64 patterns of his 63 x 14
%   scan over the whole DMD (static_hadamard_patterns), recorded
%   cfg.calibration_scan.n_recordings times with his static Hadamard
%   waveform at the calibration settings (cfg.calibration_scan). He made
%   them by hand in his app before each session, on a Sharpie-coloured
%   slide; the operator puts the slide in place before this runs. Nothing
%   moves, and no behaviour stream is recorded.
%
%   Folders are his names: had_cal_1x_<label>_1, _2, ... Only env.hw (and
%   env.phase_changed, if any) is used, so this runs before the rig is
%   prepared: preparing needs these scans.
c = cfg.calibration_scan;
hw = env.hw;
% Generating the patterns reseeds the global stream (a kept quirk); this
% runs outside any run, so it leaves the stream as it found it.
incoming = rng;
masks = hadamard_stim.yitong.static_hadamard_patterns(true(cfg.dmd.size));
rng(incoming);
hw.dmd_load_stack(permute(masks, [2 1 3]));
waveform = hadamard_stim.protocol.scan_waveform(cfg, c.waveform_period_ms, c.orange_v, ...
    size(masks, 3), c.repeats);
acquisitions = cell(1, c.n_recordings);
for k = 1:c.n_recordings
    hadamard_stim.protocol.report_phase(env, "calibration_scan", ...
        struct("recording", k, "n_recordings", c.n_recordings));
    folder = string(sprintf('had_cal_1x_%s_%d', c.label, k));
    spec = hadamard_stim.protocol.acquisition_spec("calibration_scan", folder, waveform, ...
        camera_exposure_ms=c.camera_exposure_ms);
    acq = hw.acquire(spec);
    acquisitions{k} = rmfield(acq, intersect(fieldnames(acq), ["waveform" "image"]));
end
acquisitions = [acquisitions{:}];
end
