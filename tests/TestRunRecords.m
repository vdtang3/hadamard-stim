classdef TestRunRecords < matlab.unittest.TestCase
    %TESTRUNRECORDS Recipe, trial records and checkpoints, and resuming from them.
    %
    %   A run is stopped after trial 39 and resumed from what it wrote to
    %   disk; the resumed trials, which include the trial-40 retarget and
    %   bleaching rescale, must still be his.

    properties
        Root
        Folder
        Golden
    end

    methods (TestClassSetup)
        function setUp(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
            testCase.Golden = load(fullfile(testCase.Root, "tests", "fixtures", "yitong_trace.mat"));
            incoming = rng;
            testCase.addTeardown(@() rng(incoming));
        end
    end

    methods (TestMethodSetup)
        function makeFolder(testCase)
            testCase.Folder = string(tempname);
            mkdir(testCase.Folder);
            testCase.addTeardown(@() rmdir(testCase.Folder, "s"));
        end
    end

    methods (Test)
        function aResumedRunIsStillHis(testCase)
            [cfg, env, state] = testCase.started();
            cfg.trials.last = 44;
            [recipe, arrays] = hadamard_stim.metadata.build_recipe(cfg, state, context(env));
            hadamard_stim.metadata.write_recipe(testCase.Folder, recipe, arrays);

            folder = testCase.Folder;
            env.after_trial = @(s, r) checkpoint(folder, s, r, recipe.recipe_hash);
            env.stop_requested = @() false;
            stop_after = 39;
            env.stop_requested = @() numel(dir(fullfile(folder, "trials", "*.json"))) >= stop_after;
            hadamard_stim.protocol.run_protocol(cfg, env, state);
            testCase.verifyEqual(numel(dir(fullfile(folder, "trials", "*.json"))), stop_after);

            resumed = hadamard_stim.metadata.load_checkpoint(folder);
            testCase.verifyEqual(resumed.next_trial, stop_after + 1);
            env.stop_requested = [];
            [final, records] = hadamard_stim.protocol.run_protocol(cfg, env, resumed);
            testCase.verifyEqual([records.trial], stop_after + 1:44);

            a = env.hw.acquisitions;
            g = testCase.Golden.acquisitions(1:numel(a));
            testCase.verifyEqual([a.folder]', [g.folder]');
            testCase.verifyEqual([a.orange_v]', [g.orange_v]');
            testCase.verifyEqual([a.motor_z]', [g.motor_z]');
            stim = find([g.kind] == "stimulation");
            for k = stim
                testCase.verifyEqual(a(k).queue.combined_sha256, g(k).queue.combined_sha256, a(k).folder);
                testCase.verifyEqual(a(k).c_idx_all_it, g(k).c_idx_all_it, a(k).folder);
            end
            testCase.verifyEqual(numel(final.cells.corrections), 2);

            json = jsondecode(fileread(fullfile(folder, "trials", "trial_0040.json")));
            testCase.verifyEqual(string(json.recipe_hash), recipe.recipe_hash);
            testCase.verifyTrue(json.retarget);
            testCase.verifyEqual(json.orange_v, g(stim(40)).orange_v, "RelTol", 1e-15);
            testCase.verifyEqual(string(json.status), "completed");
            testCase.verifyNotEmpty(json.started_utc);
            % The recorded hash is of the samples the trial's settings give.
            s = records([records.trial] == 40).acquisition.waveform_settings;
            w = hadamard_stim.protocol.stimulation_waveform(cfg, rmfield(env, "waveform_cache"), ...
                s.exposure_ms, s.orange_v, s.blue_v, s.params);
            testCase.verifyEqual(string(json.acquisition.waveform_sha256), ...
                hadamard_stim.metadata.sha256(w.amplitude));
        end

        function theRecipeIsWrittenOnceAndChecked(testCase)
            [cfg, env, state] = testCase.started();
            [recipe, arrays] = hadamard_stim.metadata.build_recipe(cfg, state, context(env));
            testCase.verifyTrue(hadamard_stim.metadata.verify_recipe_hash(recipe));
            testCase.verifyEqual(recipe.mode, "yitong_compatible");
            testCase.verifyEmpty(recipe.deviations);
            testCase.verifyEqual(recipe.software.hadamard_stim.commit, ...
                hadamard_stim.metadata.git_provenance(testCase.Root).commit);
            testCase.verifyEqual(recipe.software.luminos.commit, "not_applicable");

            hadamard_stim.metadata.write_recipe(testCase.Folder, recipe, arrays);
            testCase.verifyError(@() hadamard_stim.metadata.write_recipe(testCase.Folder, recipe, arrays), ...
                "hadamard_stim:RecipeExists");
            [back, ~] = hadamard_stim.metadata.read_recipe(testCase.Folder);
            testCase.verifyEqual(back.recipe_hash, recipe.recipe_hash);

            altered = recipe;
            altered.config.sparse.blue_v = 5;
            testCase.verifyFalse(hadamard_stim.metadata.verify_recipe_hash(altered));
            loaded = load(fullfile(testCase.Folder, "run_recipe.mat"));
            loaded.recipe = altered;
            save(fullfile(testCase.Folder, "run_recipe.mat"), "-struct", "loaded", "-v7.3");
            testCase.verifyError(@() hadamard_stim.metadata.read_recipe(testCase.Folder), ...
                "hadamard_stim:RecipeAltered");
        end

        function aCheckpointOfAnotherRunIsRefused(testCase)
            [cfg, env, state] = testCase.started();
            [recipe, arrays] = hadamard_stim.metadata.build_recipe(cfg, state, context(env));
            hadamard_stim.metadata.write_recipe(testCase.Folder, recipe, arrays);
            hadamard_stim.metadata.save_checkpoint(testCase.Folder, state, "not-this-run");
            testCase.verifyError(@() hadamard_stim.metadata.load_checkpoint(testCase.Folder), ...
                "hadamard_stim:CheckpointMismatch");
        end

        function deviationsAreListed(testCase)
            [cfg, env, state] = testCase.started();
            cfg.drift.enabled = false;
            cfg.sparse.blue_v = 3;
            [recipe, ~] = hadamard_stim.metadata.build_recipe(cfg, state, context(env));
            testCase.verifyEqual(recipe.mode, "modified");
            testCase.verifyEqual(sort([recipe.deviations.path]), ["drift.enabled" "sparse.blue_v"]);
        end

        function anIncompleteConfigurationIsRefused(testCase)
            cfg = hadamard_stim.default_config();
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyFalse(report.ok);
            testCase.verifyEqual(numel(report.errors), 4);
            cfg.sparse.blue_v = [2 4];
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyTrue(any(contains(report.errors, "sparse.blue_v")));
        end
    end

    methods
        function [cfg, env, state] = started(testCase)
            fixtures = fullfile(testCase.Root, "tests", "fixtures");
            [cfg, env, ~, inputs] = parity_environment(fixtures);
            cells = hadamard_stim.protocol.segment_cells(cfg, inputs.ref_im, env.geometry);
            reference = hadamard_stim.protocol.run_z_reference(cfg, env);
            reference.had_ref = inputs.ref_im;
            state = hadamard_stim.protocol.new_run_state(cfg, cells, reference);
        end
    end
end

function c = context(env)
c.luminos = struct("commit", "not_applicable", "branch", "", "dirty", false, ...
    "remote", "", "reason", "simulated rig");
c.geometry_identity = env.geometry.identity;
c.blue_calibration = struct("identity", "blueCal.mat (Yitong, test input)", "source", "testing");
c.standing_deviations = "simulation: no hardware";
c.simulated = true;
end

function checkpoint(folder, state, record, recipe_hash)
hadamard_stim.metadata.write_trial_record(folder, record, recipe_hash);
hadamard_stim.metadata.save_checkpoint(folder, state, recipe_hash);
end
