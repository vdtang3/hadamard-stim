function [cfg, env, canonical, reference_inputs] = parity_environment(fixtures)
%PARITY_ENVIRONMENT The protocol set up exactly as the trace golden ran his.
%
%   [cfg, env, canonical, inputs] = parity_environment(fixtures_folder)
%
%   Same sample (his 2025-03-08 reference image), same registration and
%   camera offset, same synthetic drift at each scan, same synthetic
%   bleaching, same operator choices (tests/golden/golden_trace.m). Scan
%   reconstruction is replaced by the synthetic image, as the golden's
%   shims replaced it; reconstruction parity is TestParityReconstruction.
inputs = load(fullfile(fixtures, "yitong_session_inputs.mat"), "session_2025");
masks = load(fullfile(fixtures, "yitong_masks.mat"), "canonical");
reference_inputs = inputs.session_2025;
ref = reference_inputs.ref_im;
z_center = reference_inputs.z_position;

cfg = hadamard_stim.default_config();
cfg.naming.prefix = "M-YQ0201-29_FOV1";
cfg.segmentation.n_exclude = 5;
cfg.stimulation.orange_start_v = 1.0;
cfg.dmd.trigger_edge = "rising";

% The drift the golden injected at its k-th drift scan.
k = (1:17)';
drift_xy = [1.5 * sin(0.7 * k), -1.0 * cos(0.5 * k)];
drift_z = 0.004 * sin(0.9 * k);
world.scan_image = @(rig, acq) scan_image(acq, ref, z_center, drift_xy, drift_z);
world.movie_mean = @(rig, acq, frames) synthetic_movie_mean(ref, acq.orange_v, acq.stim_index);

env.hw = hadamard_stim.testing.SimulatedRig(world, z_center);
env.geometry = hadamard_stim.testing.yitong_affine_geometry( ...
    masks.canonical.registration_data, masks.canonical.camera_offset);
blue = load(fullfile(fileparts(fixtures), "yitong_reference", "dragonfly", "Utilities", "blueCal.mat"));
env.blue_calibration = struct("v_blue", blue.vBlue, "blue_intens_c", blue.blueIntensC);
env.reconstruct_scan = @(acq) acq.image;
env.reconstruct_z_stack = @(acqs) synthetic_z_stack(ref, [acqs.motor_z] - z_center);
env.waveform_cache = containers.Map();
canonical = masks.canonical;
end

function im = scan_image(acq, ref, z_center, drift_xy, drift_z)
if acq.kind ~= "drift_scan"
    im = [];
    return
end
k = acq.drift_scan_number;
d = drift_xy(min(k, size(drift_xy, 1)), :);
dz = drift_z(min(k, numel(drift_z))) + (acq.motor_z - z_center);
im = synthetic_drift_scan(ref, d(1), d(2), dz);
end
