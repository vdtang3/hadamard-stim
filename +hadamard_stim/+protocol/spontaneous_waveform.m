function waveform = spontaneous_waveform(cfg, period_ms, orange_v, n_frames)
%SPONTANEOUS_WAVEFORM DAQ waveform for one spontaneous block, described compactly.
%
%   waveform = hadamard_stim.protocol.spontaneous_waveform(cfg, period_ms, orange_v, n_frames)
%
%   The frames of his stimulation waveform with no stimulation: the camera,
%   orange, Grasshopper and IR rows of dragonflyMultiPatWaveform_2color_
%   periodicPulse_v2_yq (yitong.multipat_periodic_pulse_v2_waveform) for
%   the same settings, sample for sample, and nothing else. Blue is not
%   driven at all and the DMD gets no triggers: the illumination mask is a
%   static picture (dmd_show_mask), as his behaviour blocks used.
%   cfg.stimulation.wait_frames frames of orange come first, without
%   camera triggers, as in his trials.
%
%   A block is long (his were ~288,000 frames, 36 M samples per row), so
%   the samples are never built here. Each row is a constant head
%   (head_value for head_samples samples), then a unit repeated n_repeat
%   times, then zeros to the end:
%
%     waveform.form       "repeated"
%     waveform.channels   the driven rows, by name
%     waveform.rows(k)    channel, head_value, head_samples, unit, n_repeat
%     waveform.n_samples  samples in the whole block
%     waveform.sha256     of this description (not of samples)
%
%   hadamard_stim.waveform.row expands a row, for tests; on the rig
%   Luminos expands each row once, into its own DAQ buffer
%   (hadamard_stim.luminos.repeated_waveform).
rate = cfg.daq.rate;
F = round(period_ms * 1e-3 * rate);                      % samples per camera frame
G = round(cfg.stimulation.grasshopper_period_ms * 1e-3 * rate);   % per Grasshopper frame
W = cfg.stimulation.wait_frames * F;                     % orange settles, no camera
n_gs = floor(n_frames * (period_ms * 1e-3) / (cfg.stimulation.grasshopper_period_ms * 1e-3));

% One camera frame of orange, as his w_stim_frame_orange inside his frame:
% one dead sample, then [0, on for t_dmd_frame_orange - 2 dt, 0], then off.
n_orange = floor(F * 0.8) - 1;                           % t_dmd_frame_orange in samples
frame_orange = [0, 0, ones(1, n_orange - 2), 0, zeros(1, F - n_orange - 1)];
% His orange pattern starts one sample after the wait, so each frame's
% orange is the pattern above shifted by one sample.
unit_orange = [0, frame_orange(1:F - 1)];

v_ir = cfg.stimulation.ir_v;
rows = [
    row("cameraTrigger", 0, W, [1, zeros(1, F - 1)], n_frames)
    row("orangeIntensity", orange_v, W, orange_v * unit_orange, n_frames)
    row("grashopperTrigger", 0, W, [1, zeros(1, G - 1)], n_gs)
    row("IRVoltage", 0, 0, v_ir, W + n_frames * F)
    ];

settings = struct("exposure_ms", period_ms, "gs_ms", cfg.stimulation.grasshopper_period_ms, ...
    "n_frames", n_frames, "wait_frames", cfg.stimulation.wait_frames, ...
    "orange_v", orange_v, "blue_v", 0, "ir_v", v_ir);

waveform.function_name = "spontaneous_block";
waveform.settings = settings;
waveform.form = "repeated";
waveform.channels = [rows.channel]';
waveform.rows = rows;
waveform.n_samples = W + n_frames * F;
waveform.sha256 = hadamard_stim.metadata.sha256(unicode2native(char( ...
    hadamard_stim.metadata.canonical_json(rmfield(waveform, "function_name"))), "UTF-8"));
waveform.n_camera_frames = n_frames;
end

function r = row(channel, head_value, head_samples, unit, n_repeat)
r = struct("channel", string(channel), "head_value", head_value, ...
    "head_samples", head_samples, "unit", unit, "n_repeat", n_repeat);
end
