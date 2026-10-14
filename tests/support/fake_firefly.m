function [app, cfg, inputs, rig] = fake_firefly(folder)
%FAKE_FIREFLY A fake Firefly session ready for the parity configuration.
%
%   [app, cfg, inputs, rig] = fake_firefly(folder)
%
%   app     hadamard_stim.testing.make_fake_luminos in folder, its blue
%           modulator calibrated with Yitong's blueCal.mat curve
%   cfg     the parity configuration (parity_environment)
%   inputs  his 2025 session inputs (reference image, z position)
%   rig     a LuminosRig on app with blue_threshold 15, not yet begun
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
[cfg, ~, ~, inputs] = parity_environment(fullfile(root, "tests", "fixtures"));
blue = load(fullfile(root, "tests", "yitong_reference", "dragonfly", "Utilities", "blueCal.mat"));
app = hadamard_stim.testing.make_fake_luminos(folder, z_start=inputs.z_position, ...
    blue_curve=[blue.vBlue(:)'; blue.blueIntensC(:)']);
rig = hadamard_stim.luminos.LuminosRig(app, blue_threshold=15, ...
    acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition);
end
