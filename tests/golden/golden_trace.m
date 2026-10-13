function data = golden_trace(ctx, trials)
%GOLDEN_TRACE Run Yitong's protocol script and record every acquisition.
%
%   RunSynchronizedAQMulti_sparse_pulse_hadamard_behavior_v1.m is executed
%   from the frozen copy, cell by cell, with one textual change: the trial
%   loop "for iTrial = 5:n_trial" becomes "for iTrial = golden_trials". As
%   written it resumes at trial 5 and relies on variables (b0, the current
%   masks) left in the workspace by an earlier run; the parity default is
%   to start at trial 1.
%
%   He ran the script one %% cell at a time and changed the apps by hand in
%   between. Those operator steps are written out below and recorded in
%   data.operator_steps; they become explicit configuration in the port.
%
%   Everything his code does runs for real: matrix, schedule, sparse
%   selection, spot_select_sequence, bit packing, load_sequence_multi
%   (against a recording ALP device), drift correction (on synthetic scans
%   with known drift) and the bleaching adjustment (on synthetic movies).
%   Mocked: acquisition, z-stack reconstruction, SpinView mouse clicks.
arguments
    ctx
    trials (1,:) double
end
golden_use_path(ctx, "trace");
inputs = load(fullfile(ctx.fixtures, "yitong_session_inputs.mat"), "session_2025");
masks = load(fullfile(ctx.fixtures, "yitong_masks.mat"), "canonical");
canonical = masks.canonical;
z_center = inputs.session_2025.z_position;

% Sample drift seen at the k-th drift-correction scan (trials 1, 40, 80, ...).
k = (1:17)';
rig = MockRig();
rig.ref = inputs.session_2025.ref_im;
rig.z_center = z_center;
rig.drift_xy = [1.5 * sin(0.7 * k), -1.0 * cos(0.5 * k)];
rig.drift_z = 0.004 * sin(0.9 * k);
rig.full_log_acquisitions = 1:30;      % z-stack, first drift scan, first trials
setappdata(0, "hadamard_stim_golden_rig", rig);

device = MockAlpDevice();
hDMDApp = MockDmdApp(MockVialuxDMD(device));
hDMDApp.registration_data = canonical.registration_data;
hDMDApp.HorizontalOffsetEditField.Value = canonical.camera_offset(1);
hDMDApp.VerticalOffsetEditField.Value = canonical.camera_offset(2);
hDMDApp.function_data.cell_coord = canonical.cell_coord;
hDMDApp.function_data.hadamard_ref = rig.ref;
hMotorZ = MockMotor(z_center);
hDragonflyApp = MockDragonflyApp(rig, hDMDApp, hMotorZ);
hDragonflyApp.ni6343 = struct("rateConfigData", 1e5);
stim_function = 'dragonflyMultiPatWaveform_2color_periodicPulse_v2_yq';
scan_function = 'dragonflyStaticHadamardWaveform_yq';
hDragonflyApp.WaveformFunctionDropDown.Items = {stim_function, scan_function};

% --- state when the z-stack cell was run (his 2025-03-08 z01 settings) ---
rig.note("before z-stack: Hadamard scan waveform, camera 2.5 ms / waveform 2.52 ms, " + ...
    "orange 0.47 V, blue 0 V, 10 repeats, IR 0.5 V, Grasshopper 25 ms, camFramesIn 8000, " + ...
    "DMD loaded with the 63x14 Hadamard patterns");
hDragonflyApp.WaveformFunctionDropDown.Value = scan_function;
hDragonflyApp.camApp = struct("ExposureTimeMsEditField", struct("Value", 2.5), ...
    "liveExposureTimeSeconds", 2.5e-3, "liveArea", [328 448]);
hDragonflyApp.ExposureTimeMsEditField_waveform.Value = 2.52;
hDragonflyApp.OrangeAmpVEditField.Value = 0.47;
hDragonflyApp.BlueAmpVEditField.Value = 0;
hDragonflyApp.RepeatEditField.Value = 10;
hDragonflyApp.IRAmpVEditField.Value = 0.5;
hDragonflyApp.GSExposureTimemsEditField.Value = 25;
hDragonflyApp.camFramesInEditField.Value = 8000;
static_Hadamard_patterns(hDMDApp);

[z_stack_cells, protocol_cells, substitution] = protocol_chunks(ctx);
cd(ctx.dragonfly);     % the script's addpath('Auto Scripts') is relative
run_chunk(ctx, "yitong_protocol_z_stack", z_stack_cells);

% --- operator steps between the z-stack and the trial loop --------------
rig.note("after z-stack: load the two cell patterns (orange illumination, " + ...
    "blue stimulation) into the DMD app");
hDMDApp.mask_sequence = canonical.mask_sequence;
hDMDApp.mask_sequence_rois = canonical.mask_sequence_rois;
hDMDApp.MaskNoTotalEditField.Value = 2;
rig.note("after z-stack: select the stimulation waveform; camera exposure 1.25 ms, " + ...
    "waveform exposure 1.27 ms; orange set to its starting value (not saved; 1.0 V here)");
hDragonflyApp.WaveformFunctionDropDown.Value = stim_function;
hDragonflyApp.camApp.ExposureTimeMsEditField.Value = 1.25;
hDragonflyApp.camApp.liveExposureTimeSeconds = 1.25e-3;
hDragonflyApp.ExposureTimeMsEditField_waveform.Value = 1.27;
hDragonflyApp.OrangeAmpVEditField.Value = 1.0;

golden_trials = trials; %#ok<NASGU> read by the substituted loop line
run_chunk(ctx, "yitong_protocol_trials", protocol_cells);

data.trials = trials;
data.loop_substitution = substitution;
data.operator_steps = rig.operator_steps;
data.sample_drift_xy = rig.drift_xy;
data.sample_drift_z = rig.drift_z;
data.z_center = z_center;
data.acquisitions = rig.acquisitions;
data.motor_moves = hMotorZ.moves;
% Variables the script created; read with eval because they were not
% assigned in this function's own code.
final = struct();
for name = ["cntHad" "cnt" "picked" "b0" "b1" "hadMat" "cell_coord" ...
        "mask_sequence_rois_cur" "mask_sequence_cur"]
    final.(name) = eval(name);
end
data.final = struct( ...
    "cntHad", final.cntHad, "cnt", final.cnt, "picked", logical(final.picked), ...
    "b0", final.b0, "b1", final.b1, ...
    "orange_v", hDragonflyApp.OrangeAmpVEditField.Value, ...
    "had_mat_sha256", string(golden_sha256(final.hadMat)), ...
    "cell_coord", final.cell_coord, ...
    "mask_sequence_rois_cur", {final.mask_sequence_rois_cur}, ...
    "mask_sequence_cur_sha256", string(golden_sha256(final.mask_sequence_cur)));
cd(ctx.original_dir);
delete(hDMDApp);
close all force
end

function [z_stack, trials, substitution] = protocol_chunks(ctx)
% Split the script at its %% cells: everything before the "%%" that opens
% the trial-parameter cell (n_trial = 640) is the z-stack part; the trial
% part ends where the closing GFP z-stack cell begins.
script = readlines(fullfile(ctx.dragonfly, "Auto Scripts", ...
    "RunSynchronizedAQMulti_sparse_pulse_hadamard_behavior_v1.m"));
trimmed = strtrim(script);
n_trial_line = find(trimmed == "n_trial = 640;");
gfp_line = find(startsWith(trimmed, "%% get z stack for GFP"));
assert(isscalar(n_trial_line) && isscalar(gfp_line), "Script layout changed");
split = n_trial_line - 1;
assert(startsWith(trimmed(split), "%%"), "Expected a %% cell break before n_trial");
z_stack = script(1:split-1);
trials = script(split:gfp_line-1);
loop = find(strtrim(trials) == "for iTrial = 5:n_trial");
assert(isscalar(loop), "Trial loop line not found exactly once");
substitution = struct("line", split - 1 + loop, "original", trials(loop), ...
    "replacement", "for iTrial = golden_trials");
trials(loop) = substitution.replacement;
end

function run_chunk(ctx, name, lines)
% Write the lines as a script and run it in the CALLER's workspace, so the
% chunks share variables exactly as consecutive %% cells do.
file = fullfile(ctx.tmp, name + ".m");
writelines(lines, file);
evalin("caller", name + ";");
end
