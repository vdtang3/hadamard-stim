classdef TestParityDrift < matlab.unittest.TestCase
    %TESTPARITYDRIFT Drift correction equals his square_target_drift_correction_v4.
    %
    %   The three cases of yitong_drift: Z drift inside the reference stack
    %   (quadratic-fit vertex), beyond it (falls back to the best plane), and
    %   with a DMD saved_mask, which his scan patterns were ANDed with and
    %   his redrawn spots were not.

    properties (TestParameter)
        Case = {"in_range", "out_of_range", "saved_mask"}
    end

    properties
        Root
        Drift
        Masks
        Inputs
    end

    methods (TestClassSetup)
        function load_(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
            fixtures = fullfile(testCase.Root, "tests", "fixtures");
            testCase.Drift = load(fullfile(fixtures, "yitong_drift.mat"));
            testCase.Masks = load(fullfile(fixtures, "yitong_masks.mat"), "canonical").canonical;
            testCase.Inputs = load(fullfile(fixtures, "yitong_session_inputs.mat"), "session_2025").session_2025;
            incoming = rng;
            testCase.addTeardown(@() rng(incoming));
        end
    end

    methods (Test)
        function correctionIsHis(testCase, Case)
            g = testCase.Drift.(Case);
            [state, env, cfg] = testCase.setUp(g);
            rng(1, "twister");
            before = rng;
            [state, correction] = hadamard_stim.protocol.run_drift_correction(cfg, env, state, 1);

            c = state.cells.current;
            testCase.verifyEqual(double(permute(cat(3, c.illum_mask, c.stim_mask), [2 1 3])), ...
                g.mask_sequence, "masks");
            testCase.verifyEqual({c.illum_rois, c.stim_rois}, g.mask_sequence_rois, "rois");
            % The fixture reads each spot's shift off its first vertex.
            canonical = state.cells.canonical;
            testCase.verifyEqual(first_vertex_shift(c.illum_rois, canonical.illum_rois), g.cell_shift);
            testCase.verifyEqual(first_vertex_shift(c.stim_rois, canonical.stim_rois), g.stim_cell_shift);
            testCase.verifyEqual(correction.cell_shift, g.cell_shift, "AbsTol", 1e-12);
            testCase.verifyEqual(env.hw.moves, g.motor_moves);
            testCase.verifyEqual(env.hw.position - testCase.Inputs.z_position, g.z_correction);
            % "out_of_range" means the sample drifted beyond the stack; his
            % fit still put the vertex inside it, so no case reaches the
            % best-plane fallback.
            testCase.verifyFalse(correction.z_fallback);

            scan = env.hw.acquisitions(1);
            testCase.verifyEqual(scan.folder, g.scan_acquisition.folder);
            testCase.verifyEqual(scan.dmd_stack.sha256, g.scan_acquisition.mask_sequence_sha256);
            testCase.verifyEqual(scan.orange_v, g.scan_acquisition.orange_v);
            testCase.verifyEqual(scan.blue_v, g.scan_acquisition.blue_v);
            testCase.verifyEqual(scan.camera_exposure_ms, g.scan_acquisition.camera_exposure_ms);
            testCase.verifyEqual(scan.waveform_period_ms, g.scan_acquisition.exposure_waveform_ms);
            testCase.verifyEqual(state.exposure_waveform_ms, g.restored.exposure_waveform_ms);
            % His scan patterns reseed the global generator and leave it.
            testCase.verifyNotEqual(rng, before);
            % The canonical cells are untouched; the correction is history.
            testCase.verifyEqual(state.cells.canonical.illum_rois, testCase.Masks.mask_sequence_rois{1});
            testCase.verifyEqual(numel(state.cells.corrections), 1);
        end
    end

    methods
        function [state, env, cfg] = setUp(testCase, g)
            fixtures = fullfile(testCase.Root, "tests", "fixtures");
            [cfg, env, canonical] = parity_environment(fixtures);
            ref = testCase.Inputs.ref_im;
            z_center = testCase.Inputs.z_position;
            drift = g.sample_drift;
            world.scan_image = @(rig, acq) synthetic_drift_scan(ref, drift(1), drift(2), ...
                drift(3) + (acq.motor_z - z_center));
            world.movie_mean = [];
            env.hw = hadamard_stim.testing.SimulatedRig(world, z_center);
            saved = [];
            if g.saved_mask_set
                saved = false(1024, 768);
                saved(201:900, 101:700) = true;
            end
            env.geometry = hadamard_stim.testing.yitong_affine_geometry( ...
                canonical.registration_data, canonical.camera_offset, saved_mask=saved);

            cells.cell_coord = canonical.cell_coord;
            cells.illum_rois = canonical.mask_sequence_rois{1};
            cells.stim_rois = canonical.mask_sequence_rois{2};
            cells.illum_mask = logical(canonical.mask_sequence(:, :, 1)');
            cells.stim_mask = logical(canonical.mask_sequence(:, :, 2)');
            reference.had_ref = ref;
            reference.z_all = testCase.Drift.z_all;
            reference.had_z_stack = synthetic_z_stack(ref, testCase.Drift.z_stack_offsets);
            state = hadamard_stim.protocol.new_run_state(cfg, cells, reference);
        end
    end
end

function shift = first_vertex_shift(new_rois, ref_rois)
first = [1; find(isnan(ref_rois(1:end-1, 1))) + 1];
shift = new_rois(first, :) - ref_rois(first, :);
end
