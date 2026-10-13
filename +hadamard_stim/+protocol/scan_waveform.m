function waveform = scan_waveform(cfg, period_ms, orange_v, n_pat)
%SCAN_WAVEFORM DAQ samples for a Hadamard scan (z-stack plane or drift scan).
%
%   waveform = hadamard_stim.protocol.scan_waveform(cfg, period_ms, orange_v, n_pat)
%
%   His dragonflyStaticHadamardWaveform_yq with blue off: one camera frame
%   per DMD pattern, n_pat patterns repeated cfg.scan.repeats times, the
%   illumination held off for the rolling-shutter time of cfg.camera.rows.
p.daq_rate = cfg.daq.rate;
p.channels = cfg.daq.channels;
p.exposure_ms = period_ms;
p.n_pat = n_pat;
p.repeat = cfg.scan.repeats;
p.n_rows = cfg.camera.rows;
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
waveform.n_camera_frames = n_frames;
end
