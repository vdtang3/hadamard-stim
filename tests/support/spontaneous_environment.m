function [cfg, env, inputs] = spontaneous_environment(fixtures, options)
%SPONTANEOUS_ENVIRONMENT The parity rig and sample, set up for spontaneous blocks.
%
%   [cfg, env, inputs] = spontaneous_environment(fixtures_folder, n_blocks=3, block_frames=1200)
%
%   parity_environment's simulated rig, sample and synthetic drift, with a
%   short spontaneous configuration (session.mode "spontaneous") and a
%   movie mean that bleaches with each block (block k as if 40*(k-1)
%   stimulation trials had come before), so the bleaching update has
%   something to correct. env.context is the simulated one the controller
%   tests use.
arguments
    fixtures (1, 1) string
    options.n_blocks (1, 1) double = 3
    options.block_frames (1, 1) double = 1200
end
[cfg, env, ~, inputs] = parity_environment(fixtures);
cfg.session.mode = "spontaneous";
cfg.spontaneous.n_blocks = options.n_blocks;
cfg.spontaneous.block_frames = options.block_frames;
ref = inputs.ref_im;
env.hw.world.movie_mean = @(rig, acq, frames) synthetic_movie_mean(ref, acq.orange_v, 40 * (acq.trial - 1));
env.context = struct("luminos", struct("commit", "not_applicable", ...
    "branch", "", "dirty", false, "remote", "", "reason", "simulated rig"), ...
    "geometry_identity", env.geometry.identity, ...
    "blue_calibration", struct("identity", "blueCal.mat", "source", "testing"), ...
    "standing_deviations", "simulation: no hardware", "simulated", true);
end
