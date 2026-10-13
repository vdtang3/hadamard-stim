function data = golden_drift(ctx)
%GOLDEN_DRIFT square_target_drift_correction_v4 on the canonical geometry.
%
%   The sample image is Yitong's 2025-03-08 Hadamard reference. The "current"
%   scan is that image translated by a known XY drift and defocused by a
%   known Z drift (tests/support/synthetic_drift_scan.m); the reference
%   z-stack is built the same way (synthetic_z_stack.m). His function then
%   runs unmodified; only the acquisition and the reconstruction of the new
%   scan are mocked.
%
%   Cases:
%     in_range      Z drift inside the stack range: quadratic-fit vertex
%     out_of_range  Z drift beyond the stack: falls back to the argmax plane
%     saved_mask    as in_range, with a DMD saved_mask set, which his scan
%                   patterns are ANDed with (and his redrawn spots are not)
golden_use_path(ctx, "trace");
inputs = load(fullfile(ctx.fixtures, "yitong_session_inputs.mat"), "session_2025");
masks = load(fullfile(ctx.fixtures, "yitong_masks.mat"), "canonical");
ref = inputs.session_2025.ref_im;
z_center = inputs.session_2025.z_position;
z_all = linspace(z_center - .030, z_center + .030, 21);
had_z_stack = synthetic_z_stack(ref, z_all - z_center);

saved_mask = false(1024, 768);
saved_mask(201:900, 101:700) = true;
cases = {
    "in_range",     [1.3 -0.8], 0.005, []
    "out_of_range", [1.3 -0.8], 0.050, []
    "saved_mask",   [1.3 -0.8], 0.005, saved_mask
    };
data.z_all = z_all;
data.z_stack_offsets = z_all - z_center;
for k = 1:size(cases, 1)
    [name, drift_xy, drift_z, mask] = cases{k, :};
    data.(name) = run_case(masks.canonical, ref, z_center, z_all, had_z_stack, drift_xy, drift_z, mask);
    fprintf("%s: z move %.5f, mean shift [%.3f %.3f]\n", name, ...
        data.(name).z_correction, mean(data.(name).cell_shift, 1));
end
close all force
end

function out = run_case(canonical, ref, z_center, z_all, had_z_stack, drift_xy, drift_z, saved_mask)
rig = MockRig();
rig.ref = ref;
rig.z_center = z_center;
rig.drift_xy = drift_xy;
rig.drift_z = drift_z;
rig.full_log_acquisitions = 1;
setappdata(0, "hadamard_stim_golden_rig", rig);

device = MockAlpDevice();
dmd_app = MockDmdApp(MockVialuxDMD(device));
dmd_app.registration_data = canonical.registration_data;
dmd_app.HorizontalOffsetEditField.Value = canonical.camera_offset(1);
dmd_app.VerticalOffsetEditField.Value = canonical.camera_offset(2);
dmd_app.mask_sequence = canonical.mask_sequence;
dmd_app.mask_sequence_rois = canonical.mask_sequence_rois;
dmd_app.function_data.cell_coord = canonical.cell_coord;
dmd_app.saved_mask = saved_mask;

app = MockDragonflyApp(rig, dmd_app, MockMotor(z_center));
stim_function = 'dragonflyMultiPatWaveform_2color_periodicPulse_v2_yq';
app.WaveformFunctionDropDown.Value = stim_function;
app.WaveformFunctionDropDown.Items = {stim_function, 'dragonflyStaticHadamardWaveform_yq'};
app.camApp = struct("ExposureTimeMsEditField", struct("Value", 1.25), ...
    "liveExposureTimeSeconds", 1.25e-3, "liveArea", [328 448]);
app.ExposureTimeMsEditField_waveform.Value = 1.27;
app.OrangeAmpVEditField.Value = 1.0;
app.BlueAmpVEditField.Value = 4;
app.appendedfoldernameEditField.Value = 'previous_trial';

rng_before = rng;
square_target_drift_correction_v4(app, dmd_app, 'M-YQ0201-29_FOV1_had_trial1', ...
    had_z_stack, ref, canonical.mask_sequence_rois, z_all, 0.47);

out.sample_drift = [drift_xy drift_z];
out.saved_mask_set = ~isempty(saved_mask);
out.scan_acquisition = rig.acquisitions(1);
out.scan_image_sha256 = string(golden_sha256(rig.current_scan));
out.mask_sequence_rois = dmd_app.mask_sequence_rois;
out.mask_sequence = dmd_app.mask_sequence;
out.cell_shift = spot_shift(dmd_app.mask_sequence_rois{1}, canonical.mask_sequence_rois{1});
out.stim_cell_shift = spot_shift(dmd_app.mask_sequence_rois{2}, canonical.mask_sequence_rois{2});
out.cell_coord_after = dmd_app.function_data.cell_coord;
out.hadamard_ref_overwritten_with_scan = isequal(dmd_app.function_data.hadamard_ref, rig.current_scan);
out.motor_moves = app.motorZ.moves;
out.z_correction = app.motorZ.position - z_center;
out.restored = struct( ...
    "waveform_function", string(app.WaveformFunctionDropDown.Value), ...
    "folder", string(app.appendedfoldernameEditField.Value), ...
    "orange_v", app.OrangeAmpVEditField.Value, ...
    "blue_v", app.BlueAmpVEditField.Value, ...
    "camera_exposure_ms", app.camApp.ExposureTimeMsEditField.Value, ...
    "live_exposure_s", app.camApp.liveExposureTimeSeconds, ...
    "exposure_waveform_ms", app.ExposureTimeMsEditField_waveform.Value);
out.dmd_calls = device.calls;
% static_Hadamard_patterns seeds the global generator (rng(142857)) and
% never restores it.
out.global_rng_changed = ~isequal(rng, rng_before);
delete(dmd_app);
end

function shift = spot_shift(new_rois, ref_rois)
% Each spot moves rigidly by its smoothed (Vx, Vy); read it off the first
% vertex of every spot.
first = [1; find(isnan(ref_rois(1:end-1, 1))) + 1];
shift = new_rois(first, :) - ref_rois(first, :);
end
