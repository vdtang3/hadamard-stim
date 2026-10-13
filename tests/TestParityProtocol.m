classdef TestParityProtocol < matlab.unittest.TestCase
    %TESTPARITYPROTOCOL The whole protocol, simulated, against his trace.
    %
    %   Runs segmentation, the reference z-stack and all 640 trials on the
    %   simulated rig, in the same synthetic world as tests/golden/
    %   golden_trace.m, and compares every acquisition with the one his
    %   script made: folder, stage position, voltages, exposures, waveform
    %   parameters, the cells each pulse or code stimulates, the DMD queue's
    %   bytes and repeats, the scan patterns, the current masks, every stage
    %   move, and the script's variables at the end.
    %
    %   About ten minutes. run_tests runs it unless asked for the fast tier.

    properties
        Root
        Golden
        Cfg
        Env
        State
        Records
        CurrentMasks      % sha256 of the current masks after each trial, his layout
        Acquisitions
    end

    methods (TestClassSetup)
        function runEverything(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
            fixtures = fullfile(testCase.Root, "tests", "fixtures");
            testCase.Golden = load(fullfile(fixtures, "yitong_trace.mat"));
            % His scan patterns reseed the global generator (a kept quirk).
            incoming = rng;
            testCase.addTeardown(@() rng(incoming));

            [cfg, env, ~, inputs] = parity_environment(fixtures);
            cfg.trials.last = max(testCase.Golden.trials);
            masks = strings(1, cfg.trials.last);
            env.after_trial = @(state, record) record_masks(state, record);
            cells = hadamard_stim.protocol.segment_cells(cfg, inputs.ref_im, env.geometry);
            reference = hadamard_stim.protocol.run_z_reference(cfg, env);
            reference.had_ref = inputs.ref_im;
            state = hadamard_stim.protocol.new_run_state(cfg, cells, reference);
            [testCase.State, testCase.Records] = hadamard_stim.protocol.run_protocol(cfg, env, state);
            testCase.Cfg = cfg;
            testCase.Env = env;
            testCase.Acquisitions = env.hw.acquisitions;
            testCase.CurrentMasks = masks;

            function record_masks(state, record)
                c = state.cells.current;
                masks(record.trial) = hadamard_stim.metadata.sha256( ...
                    double(permute(cat(3, c.illum_mask, c.stim_mask), [2 1 3])));
            end
        end
    end

    methods (Test)
        function sameAcquisitionsInTheSameOrder(testCase)
            a = testCase.Acquisitions;
            g = testCase.Golden.acquisitions;
            testCase.assertEqual(numel(a), numel(g));
            testCase.verifyEqual([a.kind]', [g.kind]');
            testCase.verifyEqual([a.folder]', [g.folder]');
        end

        function sameStagePositionsAndMoves(testCase)
            a = testCase.Acquisitions;
            g = testCase.Golden.acquisitions;
            testCase.verifyEqual([a.motor_z]', [g.motor_z]');
            testCase.verifyEqual(testCase.Env.hw.moves, testCase.Golden.motor_moves);
        end

        function sameLightAndCameraSettings(testCase)
            a = testCase.Acquisitions;
            g = testCase.Golden.acquisitions;
            testCase.verifyEqual([a.orange_v]', [g.orange_v]');
            testCase.verifyEqual([a.blue_v]', [g.blue_v]');
            testCase.verifyEqual([a.camera_exposure_ms]', [g.camera_exposure_ms]');
            testCase.verifyEqual([a.waveform_period_ms]', [g.exposure_waveform_ms]');
            testCase.verifyEqual([a.waveform_function]', [g.waveform_function]');
            stim = [a.kind] == "stimulation";
            params = arrayfun(@(x) string(x.waveform_settings.params), a(stim), "UniformOutput", false);
            testCase.verifyEqual(vertcat(params{:}), vertcat(g(stim).waveform_params));
        end

        function sameCellsStimulated(testCase)
            a = testCase.Acquisitions;
            g = testCase.Golden.acquisitions;
            for k = find([g.kind] == "stimulation")
                testCase.verifyEqual(a(k).c_idx_all_it, g(k).c_idx_all_it, a(k).folder);
            end
        end

        function sameDmdQueueByteForByte(testCase)
            a = testCase.Acquisitions;
            g = testCase.Golden.acquisitions;
            for k = find([g.kind] == "stimulation")
                q = a(k).queue;
                testCase.verifyEqual(q.combined_sha256, g(k).queue.combined_sha256, a(k).folder);
                testCase.verifyEqual(q.picnum, g(k).queue.picnum, a(k).folder);
                testCase.verifyEqual(q.repeat, g(k).queue.repeat, a(k).folder);
                if ~isempty(g(k).queue.sha256)
                    testCase.verifyEqual(q.sha256, g(k).queue.sha256, a(k).folder);
                end
            end
        end

        function sameScanPatterns(testCase)
            a = testCase.Acquisitions;
            g = testCase.Golden.acquisitions;
            for k = find([g.kind] ~= "stimulation")
                testCase.verifyEqual(a(k).dmd_stack.sha256, g(k).mask_sequence_sha256, a(k).folder);
            end
        end

        function sameCurrentMasksAtEveryTrial(testCase)
            g = testCase.Golden.acquisitions;
            stim = g([g.kind] == "stimulation");
            testCase.verifyEqual(testCase.CurrentMasks(:), [stim.mask_sequence_sha256]');
        end

        function sameVariablesAtTheEnd(testCase)
            f = testCase.Golden.final;
            s = testCase.State;
            testCase.verifyEqual(s.cnt_had, f.cntHad);
            testCase.verifyEqual(s.cnt, f.cnt);
            testCase.verifyEqual(s.picked, f.picked);
            testCase.verifyEqual(s.b0, f.b0);
            testCase.verifyEqual(s.b1, f.b1);
            testCase.verifyEqual(s.orange_v, f.orange_v);
            testCase.verifyEqual(hadamard_stim.metadata.sha256(s.had_mat), f.had_mat_sha256);
            testCase.verifyEqual(s.cells.canonical.cell_coord, f.cell_coord);
            testCase.verifyEqual({s.cells.current.illum_rois, s.cells.current.stim_rois}, ...
                f.mask_sequence_rois_cur);
        end

        function everyCorrectionIsKept(testCase)
            c = testCase.State.cells.corrections;
            drift_trials = testCase.Golden.trials(testCase.Golden.trials == 1 | ...
                mod(testCase.Golden.trials, testCase.Cfg.drift.retarget_every) == 0);
            testCase.verifyEqual([c.trial], drift_trials);
            moves = testCase.Env.hw.moves;
            drift_moves = moves(end - numel(c) + 1:end, :);
            testCase.verifyEqual([c.motor_after]', drift_moves(:, 2));
        end

        function firstTrialsDriveHisSamples(testCase)
            % The fixture's stim_sparse and stim_hadamard cases have the
            % settings of trials 1 and 4, so their samples must be equal.
            w = load(fullfile(testCase.Root, "tests", "fixtures", "yitong_waveforms.mat"));
            for pair = {["stim_sparse" 1], ["stim_hadamard" 4]}
                [name, trial] = pair{1}{:};
                rec = testCase.Records([testCase.Records.trial] == str2double(trial));
                s = rec.acquisition.waveform_settings;
                waveform = hadamard_stim.protocol.stimulation_waveform(testCase.Cfg, ...
                    testCase.Env, s.exposure_ms, s.orange_v, s.blue_v, s.params);
                d = w.(name);
                for row = 1:numel(d.rows)
                    [values, lengths] = run_length(waveform.amplitude(row, :));
                    testCase.verifyEqual(values, d.values{row}, name + "/" + d.rows(row));
                    testCase.verifyEqual(lengths, d.run_lengths{row}, name + "/" + d.rows(row));
                end
            end
        end
    end
end

function [values, lengths] = run_length(x)
starts = [true, x(2:end) ~= x(1:end-1) & ~(isnan(x(2:end)) & isnan(x(1:end-1)))];
values = x(starts);
lengths = diff([find(starts), numel(x) + 1]);
end
