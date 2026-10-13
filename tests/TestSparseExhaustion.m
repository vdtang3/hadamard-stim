classdef TestSparseExhaustion < matlab.unittest.TestCase
    %TESTSPARSEEXHAUSTION When a sparse trial runs out of cells.
    %
    %   His loop skips the remaining pulses with "continue", so their DMD
    %   pictures are whatever the previous trial left in illumPatAll. His
    %   real geometry never gets there (206-226 of 320 cells per trial), but
    %   a smaller or denser one would, and the port must behave as his did.

    methods (TestClassSetup)
        function addPackage(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)
        function skippedPulsesReplayThePreviousTrial(testCase)
            [cfg, env, state] = tiny();
            % Four cells closer together than the cutoff: one cell per pulse,
            % so pulses 5 and 6 find nothing left.
            [c_idx, ~, skipped] = hadamard_stim.yitong.sparse_trial_selection( ...
                state.cells.canonical.cell_coord, cfg.sparse.dist_cutoff_px, ...
                cfg.sparse.n_pulses, state.picked);
            testCase.verifyEqual(skipped, [false false false false true true]);
            testCase.verifyEqual(sum(c_idx, 1), [1 1 1 1 0 0]);

            % A first trial has nothing to replay, where his queue load failed.
            testCase.verifyError(@() hadamard_stim.protocol.run_trial(cfg, env, state, 1), ...
                "hadamard_stim:NoPreviousPicture");

            previous = repmat({cat(3, state.cells.current.illum_mask, ...
                true(size(state.cells.current.illum_mask)))}, cfg.sparse.n_pulses, 1);
            state.sparse_pictures = previous;
            [state, record] = hadamard_stim.protocol.run_trial(cfg, env, state, 1);
            testCase.verifyEqual(state.sparse_pictures(5:6), previous(5:6));
            testCase.verifyNotEqual(state.sparse_pictures(1:4), previous(1:4));
            testCase.verifyEqual(record.picnum, 2 * ones(1, 6));
        end
    end
end

function [cfg, env, state] = tiny()
cfg = hadamard_stim.default_config();
cfg.naming.prefix = "tiny";
cfg.matrix.order = 4;
cfg.segmentation.threshold = 4;
cfg.sparse.n_pulses = 6;
cfg.sparse.dist_cutoff_px = 1000;
cfg.stimulation.orange_start_v = 1;
cfg.stimulation.n_frames = 12;
cfg.sparse.pulse_frames = 2;
cfg.sparse.period_frames = 2;
cfg.hadamard.frames_per_code = 3;
cfg.trials.n_trial = 8;
cfg.trials.n_sparse = 6;
cfg.drift.enabled = false;
cfg.bleaching.enabled = false;

registration = [940 1688; 0.8 0.7; 0.7 -0.8];
env.geometry = hadamard_stim.testing.yitong_affine_geometry(registration, [1387 1475]);
world.scan_image = @(rig, acq) [];
world.movie_mean = @(rig, acq, frames) zeros(10);
env.hw = hadamard_stim.testing.SimulatedRig(world, 0);
env.blue_calibration = struct("v_blue", linspace(0, 5, 50), "blue_intens_c", linspace(0, 100, 50)');

cells.cell_coord = [200 150; 203 150; 200 153; 203 153];
cells = hadamard_stim.protocol.draw_cells(cells, cfg.segmentation, env.geometry);
reference = struct("had_ref", zeros(328, 448), "z_all", 0, "had_z_stack", zeros(328, 448));
state = hadamard_stim.protocol.new_run_state(cfg, cells, reference);
end
