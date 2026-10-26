function cfg = default_config()
%DEFAULT_CONFIG Yitong's Firefly Hadamard protocol, as he ran it on 2025-03-08.
%
%   cfg = hadamard_stim.default_config()
%
%   One struct describes an experiment completely; the tab only edits it.
%   Values are his script's constants and the settings saved with his
%   2025-03-08 session (docs/notebook.md). Fields left empty must be set
%   before a run, because no evidence fixes them:
%
%     naming.prefix                 mouse and field of view, e.g. "M-YQ0201-29_FOV1"
%     segmentation.n_exclude        his answer at the input() prompt (5 for his FOV)
%     stimulation.orange_start_v    he set orange by hand before the trials;
%                                   the value was not saved
%     dmd.trigger_edge              the board's power-on trigger edge, which
%                                   his loader inherited (Firefly check 2)
%
%   Changing anything else leaves Yitong-compatible mode; validate_config
%   reports each difference as a deviation.
%
%   Two kinds of session share this configuration (session.mode):
%     "connectivity"  his sparse-pulse and coded stimulation trials
%                     (RunSynchronizedAQMulti_sparse_pulse_hadamard_behavior_v1)
%     "spontaneous"   voltage imaging in blocks with no blue light
%                     (RunSynchronizedAQMulti_behavior_NPY_GFP_v1)
%   Face video and the wheel encoder (behavior.*) are optional companions
%   of either; turning one off is a warning, not a deviation.
cfg.schema_version = "1.1.0";
cfg.mode = "yitong_compatible";

cfg.session.mode = "connectivity";

cfg.behavior.face_camera_enabled = true;     % he recorded face video in every paper session
cfg.behavior.wheel_encoder_enabled = false;  % he recorded it too; off until Firefly's wiring is checked

cfg.naming.prefix = "";

% DAQ output channels in his dragonflySettings.m order; the waveform rows
% follow it. The Luminos adapter maps them onto Firefly's channels.
cfg.daq.rate = 1e5;
cfg.daq.channels = ["cameraTrigger"; "grashopperTrigger"; "dmdTrigger"; ...
    "blueIntensity"; "orangeIntensity"; "redShutter"; "limeShutter"; ...
    "blueShutter"; "piezoTrigger"; "IRVoltage"; "magnetPTrigger"; "magnetNTrigger"];

cfg.camera.rows = 328;               % Kinetix active area rows (rolling-shutter wait)

cfg.dmd.size = [1024 768];           % his mask orientation [L W]; Luminos canvas is the transpose
cfg.dmd.picture_time_us = 44;
cfg.dmd.trigger_edge = "";

cfg.segmentation.threshold = 320;    % cells to keep
cfg.segmentation.n_exclude = [];
cfg.segmentation.illum_spot_size = 5;   % Auto Square SquareSize
cfg.segmentation.stim_spot_size = 3;    % reduce_spot_size_sequence(app, 3, 2)

cfg.matrix.order = 320;

cfg.stimulation.camera_exposure_ms = 1.25;
cfg.stimulation.waveform_period_ms = 1.27;
cfg.stimulation.n_frames = 8000;     % camFramesIn
cfg.stimulation.wait_frames = 200;   % nFrameWait
cfg.stimulation.grasshopper_period_ms = 25;
cfg.stimulation.ir_v = 0.5;
cfg.stimulation.orange_start_v = [];
cfg.stimulation.n_patterns = 2;      % orange illumination, blue stimulation

cfg.sparse.blue_v = 4;
cfg.sparse.pulse_frames = 16;        % nFramePulse
cfg.sparse.period_frames = 160;      % nFramePerPulse
cfg.sparse.n_pulses = 30;            % nIt
cfg.sparse.dist_cutoff_px = 123;     % 0.8 mm at 6.5 um per pixel

cfg.hadamard.blue_v = 2;             % blueVHad
cfg.hadamard.frames_per_code = 600;  % nFrameHCode

cfg.trials.n_trial = 640;
cfg.trials.n_sparse = 480;           % nTrialSP; every (n_trial / (n_trial - n_sparse))th trial is Hadamard
cfg.trials.first = 1;                % his script says 5: it resumed an earlier run
cfg.trials.last = 640;
cfg.trials.run_sparse = true;

cfg.scan.m_q = [63 14];
cfg.scan.repeats = 10;
cfg.scan.camera_exposure_ms = 2.5;   % z-stack; drift scans use 2 x the stimulation exposure
cfg.scan.waveform_period_ms = 2.52;
cfg.scan.orange_v = 0.47;            % hadOrangeV, also the z-stack's orange

% The Hadamard calibration scans ("had_cal"), on a uniform slide before the
% session: his 2025-03-08 recordings had_cal_1x_arch_1..3 (RCaMPtopatch.set):
% static Hadamard waveform, one pass of the 64 patterns, 10 ms exposure on
% an 11 ms period, orange 0.1 V, blue off. He recorded them at a centred
% 512 x 512 area; here they are taken at the experiment's own camera area,
% which his reconstruction centre-crops to anyway.
cfg.calibration_scan.n_recordings = 3;
cfg.calibration_scan.camera_exposure_ms = 10;
cfg.calibration_scan.waveform_period_ms = 11;
cfg.calibration_scan.orange_v = 0.1;
cfg.calibration_scan.repeats = 1;
cfg.calibration_scan.label = "arch";

cfg.z_reference.enabled = true;
cfg.z_reference.half_range = 0.030;  % motor units either side of the focus
cfg.z_reference.n_steps = 20;        % 21 planes
cfg.z_reference.label = "Arch";

cfg.drift.enabled = true;
cfg.drift.retarget_every = 40;       % nTrialsRetarget; also at trial 1
cfg.drift.exposure_scale = 2;

% Spontaneous sessions: his 2025 behaviour script ran 10 blocks with a
% drift correction (and the bleaching update) before each. The block
% length is from the published analysis (4 blocks = 1,152,000 frames);
% his block settings are on the external drives and not yet read.
cfg.spontaneous.n_blocks = 10;
cfg.spontaneous.block_frames = 288000;   % ~6.1 min at 1.27 ms per frame
cfg.spontaneous.drift_correction = true;

cfg.bleaching.enabled = true;
cfg.bleaching.frames = 501:1000;
cfg.bleaching.n_pix_cell = 5;
end
