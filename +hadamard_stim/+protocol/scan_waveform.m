function waveform = scan_waveform(cfg, period_ms, orange_v, n_pat, repeats, options)
%SCAN_WAVEFORM DAQ samples for a Hadamard scan (z-stack plane or drift scan).
%
%   waveform = hadamard_stim.protocol.scan_waveform(cfg, period_ms, orange_v, n_pat, camera_rows=n)
%   waveform = scan_waveform(..., repeats, camera_rows=n)   default cfg.scan.repeats
%
%   His dragonflyStaticHadamardWaveform_yq with blue off: one camera frame
%   per DMD pattern, n_pat patterns repeated cfg.scan.repeats times, the
%   illumination held off for the rolling-shutter time of camera_rows rows
%   (3.75 us each). camera_rows is the acquisition area's sensor rows, read
%   from the rig (hw.camera_rows()) as his code read camApp.liveArea(1);
%   it is recorded in waveform.settings.n_rows.
arguments
    cfg struct
    period_ms (1, 1) double
    orange_v (1, 1) double
    n_pat (1, 1) double
    repeats (1, 1) double = cfg.scan.repeats
    options.camera_rows (1, 1) double {mustBeInteger, mustBePositive}
end
if ~isfield(options, "camera_rows")
    error("hadamard_stim:NoCameraRows", ...
        "The scan's rolling-shutter blanking needs the camera's rows (camera_rows=hw.camera_rows()).");
end
p.daq_rate = cfg.daq.rate;
p.channels = cfg.daq.channels;
p.exposure_ms = period_ms;
p.n_pat = n_pat;
p.repeat = repeats;
p.n_rows = options.camera_rows;
p.orange_v = orange_v;
p.blue_v = 0;
waves = hadamard_stim.yitong.static_hadamard_waveform(p);
waveform = describe(waves, "dragonflyStaticHadamardWaveform_yq", ...
    rmfield(p, ["channels" "daq_rate"]), n_pat * p.repeat);
end

function waveform = describe(waves, name, settings, n_frames)
waveform.function_name = name;
waveform.settings = settings;
waveform.channels = waves.channels;
waveform.amplitude = waves.amplitude;
waveform.sha256 = hadamard_stim.metadata.sha256(waves.amplitude);
waveform.n_camera_frames = n_frames;
end
