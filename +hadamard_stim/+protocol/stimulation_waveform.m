function waveform = stimulation_waveform(cfg, env, period_ms, orange_v, blue_v, params)
%STIMULATION_WAVEFORM DAQ samples for one stimulation trial.
%
%   waveform = hadamard_stim.protocol.stimulation_waveform(cfg, env, period_ms, orange_v, blue_v, params)
%
%   His dragonflyMultiPatWaveform_2color_periodicPulse_v2_yq. params is
%   [wait pulse period n_pulses] in camera frames, the four values his
%   script typed into WaveformparamsTextArea. Blue is linearised through
%   env.blue_calibration, which on the rig is the active Luminos blue
%   calibration (never a choice).
%
%   A trial's samples depend only on these settings, and runs repeat the
%   same few settings hundreds of times, so they are cached in
%   env.waveform_cache (a containers.Map) when one is given.
p.daq_rate = cfg.daq.rate;
p.channels = cfg.daq.channels;
p.exposure_ms = period_ms;
p.gs_ms = cfg.stimulation.grasshopper_period_ms;
p.n_frames = cfg.stimulation.n_frames;
p.n_pat = cfg.stimulation.n_patterns;
p.params = params;
p.blue_v = blue_v;
p.ir_v = cfg.stimulation.ir_v;
p.orange_v = orange_v;
p.blue_calibration = env.blue_calibration;

settings = rmfield(p, ["channels" "daq_rate" "blue_calibration"]);
key = "";
if isfield(env, "waveform_cache") && ~isempty(env.waveform_cache)
    % Full precision: orange drifts by bleaching ratios.
    key = string(mat2str([p.exposure_ms p.gs_ms p.n_frames p.n_pat p.params ...
        p.blue_v p.ir_v p.orange_v], 17));
    if isKey(env.waveform_cache, key)
        waveform = env.waveform_cache(key);
        return
    end
end

waves = hadamard_stim.yitong.multipat_periodic_pulse_v2_waveform(p);
waveform.function_name = "dragonflyMultiPatWaveform_2color_periodicPulse_v2_yq";
waveform.settings = settings;
waveform.channels = waves.channels;
waveform.amplitude = waves.amplitude;
waveform.n_camera_frames = p.n_frames;
if strlength(key) > 0
    env.waveform_cache(key) = waveform;
end
end
