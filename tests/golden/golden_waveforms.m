function data = golden_waveforms(ctx)
%GOLDEN_WAVEFORMS Yitong's DAQ waveforms, sample for sample.
%
%   Each case calls his waveform function with a mock dragonflyApp holding
%   the settings the protocol uses. Every DAQ row is stored run-length
%   encoded (values + run lengths), which is exact and small.
%
%   Settings evidence: 100 kHz DAQ and the channel list are in his
%   dragonflySettings.m; the 1.25/1.27 ms and 2.5/2.52 ms exposures, the
%   328-row Kinetix area, IR 0.5 V, Grasshopper 25 ms and camFramesIn 8000
%   are in the RCaMPtopatch.set saved with his 2025-03-08 session. The
%   orange voltage during stimulation trials was not saved; 1.0 V is a
%   placeholder (it only scales the orange row).
golden_use_path(ctx);
channels = dragonfly_out_channels(ctx);
data.channels = channels;

stim = struct("exposure_ms", 1.27, "n_frames", 8000, "gs_ms", 25, "ir_v", 0.5, "orange_v", 1.0);
cases = {
    "stim_sparse",         stim, struct("blue_v", 4, "params", [200 16 160 30])
    "stim_hadamard",       stim, struct("blue_v", 2, "params", [200 600 600 8])
    "stim_small_sparse",   setfield(stim, "n_frames", 12), struct("blue_v", 4, "params", [3 2 4 3])
    "stim_small_hadamard", setfield(stim, "n_frames", 12), struct("blue_v", 2, "params", [3 4 4 3])
    };
for k = 1:size(cases, 1)
    [name, base, trial] = cases{k, :};
    app = mock_app(channels);
    app.ExposureTimeMsEditField_waveform.Value = base.exposure_ms;
    app.camFramesInEditField.Value = base.n_frames;
    app.GSExposureTimemsEditField.Value = base.gs_ms;
    app.IRAmpVEditField.Value = base.ir_v;
    app.OrangeAmpVEditField.Value = base.orange_v;
    app.BlueAmpVEditField.Value = trial.blue_v;
    app.dmdApp.MaskNoTotalEditField.Value = 2;
    app.WaveformparamsTextArea.Value = cellstr(string(trial.params(:)));
    waves = dragonflyMultiPatWaveform_2color_periodicPulse_v2_yq(app);
    data.(name) = describe(waves, channels, "dragonflyMultiPatWaveform_2color_periodicPulse_v2_yq", ...
        struct("base", base, "trial", trial));
end

scans = {
    "scan_drift", struct("exposure_ms", 2.52, "n_pat", 64, "repeat", 10, "n_rows", 328, "orange_v", 0.47, "blue_v", 0)
    "scan_small", struct("exposure_ms", 2.52, "n_pat", 4,  "repeat", 2,  "n_rows", 328, "orange_v", 0.47, "blue_v", 0)
    };
for k = 1:size(scans, 1)
    [name, s] = scans{k, :};
    app = mock_app(channels);
    app.ExposureTimeMsEditField_waveform.Value = s.exposure_ms;
    app.RepeatEditField.Value = s.repeat;
    app.camApp.liveArea = [s.n_rows 448];
    app.OrangeAmpVEditField.Value = s.orange_v;
    app.BlueAmpVEditField.Value = s.blue_v;
    app.dmdApp.mask_sequence = false(1, 1, s.n_pat);    % only size(...,3) is read
    waves = dragonflyStaticHadamardWaveform_yq(app);
    data.(name) = describe(waves, channels, "dragonflyStaticHadamardWaveform_yq", s);
end
close all force
end

function app = mock_app(channels)
dmd_app = MockDmdApp(MockVialuxDMD(MockAlpDevice()));
app = MockDragonflyApp([], dmd_app, MockMotor(0));
app.ni6343 = struct("rateConfigData", 1e5, "outChannelsConfigData", {[cellstr(channels) cell(numel(channels), 1)]});
app.camApp = struct("liveArea", [328 448]);
end

function channels = dragonfly_out_channels(ctx)
% Run his settings file in an isolated workspace and keep the channel names.
outChannelSettings = {};
eval(fileread(fullfile(ctx.dragonfly, "Settings", "dragonflySettings.m")));
channels = string(outChannelSettings(:, 1));
end

function d = describe(waves, channels, function_name, settings)
amplitude = waves.amplitude;
d.function_name = string(function_name);
d.settings = settings;
d.n_samples = size(amplitude, 2);
d.rows = channels;
d.values = cell(numel(channels), 1);
d.run_lengths = cell(numel(channels), 1);
for row = 1:numel(channels)
    [d.values{row}, d.run_lengths{row}] = run_length_encode(amplitude(row, :));
end
% What Yitong's generateWaveform reported: rising edges of rows 1 and 2.
% Row 2 is the Grasshopper trigger, not the DMD, so his "dmdTrigsOut"
% display counted Grasshopper frames.
rising = @(x) nnz(diff([0 x]) > 0);
d.app_cam_pictures_out = rising(amplitude(1, :));
d.app_dmd_trigs_out = rising(amplitude(2, :));
d.rising_edges = arrayfun(@(r) rising(amplitude(r, :)), (1:numel(channels))');
d.sha256 = string(golden_sha256(amplitude));
end

function [values, lengths] = run_length_encode(x)
starts = [true, x(2:end) ~= x(1:end-1) & ~(isnan(x(2:end)) & isnan(x(1:end-1)))];
values = x(starts);
lengths = diff([find(starts), numel(x) + 1]);
end
