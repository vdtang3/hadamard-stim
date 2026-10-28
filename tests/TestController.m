classdef TestController < matlab.unittest.TestCase
    %TESTCONTROLLER The session's lifecycle and its one write path.

    properties
        Root
        Folder
    end

    methods (TestClassSetup)
        function setUp(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
            incoming = rng;
            testCase.addTeardown(@() rng(incoming));
        end
    end

    methods (TestMethodSetup)
        function makeFolder(testCase)
            testCase.Folder = string(tempname);
            testCase.addTeardown(@() rmdir_if(testCase.Folder));
        end
    end

    methods (Test)
        function aSessionRunsInHisOrder(testCase)
            [c, cfg, ref] = testCase.session();
            act = @(a, p) hadamard_stim.apply_controller_action(c, a, p, c.Revision);

            testCase.verifyEqual(act("approve_cells", struct()).status, "not_legal");
            testCase.verifyTrue(act("set_config", struct("config", cfg)).ok);
            testCase.verifyTrue(act("set_reference_image", struct("image", ref)).ok);
            r = act("propose_cells", struct());
            testCase.verifyTrue(r.ok);
            testCase.verifyEqual(r.state.proposal.n_cells, 320);
            testCase.verifyEqual(act("start_run", struct("run_folder", testCase.Folder)).status, "not_legal");
            testCase.verifyTrue(act("approve_cells", struct()).ok);
            testCase.verifyTrue(act("acquire_z_reference", struct()).ok);
            r = act("start_run", struct("run_folder", testCase.Folder));
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(r.state.lifecycle, "COMPLETED");
            testCase.verifyEqual(numel(dir(fullfile(testCase.Folder, "trials", "*.json"))), 4);
            testCase.verifyTrue(isfile(fullfile(testCase.Folder, "run_recipe.json")));
            % The state a frontend gets is JSON-safe.
            testCase.verifyNotEmpty(jsonencode(r.state));
            % Nothing a run keeps holds DAQ samples or images: a full run
            % keeps 640 records, and samples are ~50 MB per trial.
            testCase.verifyEmpty(intersect(fieldnames(c.LastRecord.acquisition), ["waveform" "image"]));
            testCase.verifyEmpty(intersect(fieldnames(c.Reference.acquisitions), ["waveform" "image"]));
        end

        function realHardwareWithoutTheFireflyChecksNeedsAnOverride(testCase)
            [c, cfg, ref] = testCase.session();
            c.Env.context.simulated = false;
            c.setConfig(cfg);
            c.setReferenceImage(ref);
            c.proposeCells();
            c.approveCells();
            c.acquireZReference();
            r = hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("run_folder", testCase.Folder), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:WarningsNotAcknowledged");
            testCase.verifySubstring(r.message, "firefly_slide_queue");
            testCase.verifyFalse(contains(r.message, "firefly_queue_support"), ...
                "queue support is history: the live driver is asked");
            testCase.verifyFalse(isfolder(testCase.Folder));

            passed = struct("passed", true, "evidence", "test", ...
                "date", string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
                "provenance", struct("luminos_commit", "unknown"));
            c.Env.context.hardware_validation = struct("queue_support", passed, "slide_queue", passed);
            r = hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("run_folder", testCase.Folder), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            recipe = jsondecode(fileread(fullfile(testCase.Folder, "run_recipe.json")));
            testCase.verifyTrue(recipe.hardware_validation.slide_queue.passed);
            testCase.verifyFalse(recipe.simulated);
        end

        function staleAndUnknownRequestsChangeNothing(testCase)
            [c, cfg] = testCase.session();
            before = c.Revision;
            r = hadamard_stim.apply_controller_action(c, "set_config", struct("config", cfg), before - 1);
            testCase.verifyEqual(r.status, "stale_revision");
            testCase.verifyEqual(c.Revision, before);
            r = hadamard_stim.apply_controller_action(c, "delete", struct(), before);
            testCase.verifyEqual(r.status, "unknown_action");
            testCase.verifyEqual(c.Revision, before);
        end

        function stoppingBetweenTrialsThenResuming(testCase)
            [c, cfg, ref] = testCase.session();
            cfg.trials.last = 6;
            c.setConfig(cfg);
            c.setReferenceImage(ref);
            c.proposeCells();
            c.approveCells();
            c.acquireZReference();
            % Ask for a stop from inside the run, as the tab would.
            c.ProgressChangedFcn = @(ctrl) stop_at(ctrl, 3);
            c.startRun(testCase.Folder);
            testCase.verifyEqual(c.LifecycleState, "STOPPED");
            testCase.verifyEqual(c.RunState.next_trial, 4);

            c.ProgressChangedFcn = [];
            r = hadamard_stim.apply_controller_action(c, "resume_run", ...
                struct("run_folder", testCase.Folder), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(c.LifecycleState, "COMPLETED");
            testCase.verifyEqual(numel(dir(fullfile(testCase.Folder, "trials", "*.json"))), 6);
        end

        function aFailedTrialLeavesAResumableRun(testCase)
            [c, cfg, ref] = testCase.session();
            cfg.trials.last = 5;
            c.setConfig(cfg);
            c.setReferenceImage(ref);
            c.proposeCells();
            c.approveCells();
            c.acquireZReference();
            calls = 0;
            c.Env.hw.before_operation = @(op) fail_on_third_acquire(op);
            r = hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("run_folder", testCase.Folder), c.Revision);
            testCase.verifyEqual(r.status, "failed");
            testCase.verifyEqual(c.LifecycleState, "FAILED");
            testCase.verifySubstring(c.LastError, "simulated camera failure");

            c.Env.hw.before_operation = [];
            r = hadamard_stim.apply_controller_action(c, "resume_run", ...
                struct("run_folder", testCase.Folder), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(numel(dir(fullfile(testCase.Folder, "trials", "*.json"))), 5);

            function fail_on_third_acquire(op)
                if op == "acquire"
                    calls = calls + 1;
                    if calls == 3
                        error("test:camera", "simulated camera failure");
                    end
                end
            end
        end
    end

    methods
        function [c, cfg, ref] = session(testCase)
            fixtures = fullfile(testCase.Root, "tests", "fixtures");
            [cfg, env, ~, inputs] = parity_environment(fixtures);
            cfg.trials.last = 4;
            env.context = struct("luminos", struct("commit", "not_applicable", ...
                "branch", "", "dirty", false, "remote", "", "reason", "simulated rig"), ...
                "geometry_identity", env.geometry.identity, ...
                "blue_calibration", struct("identity", "blueCal.mat", "source", "testing"), ...
                "standing_deviations", "simulation: no hardware", "simulated", true);
            c = hadamard_stim.HadamardStimController(env);
            ref = inputs.ref_im;
        end
    end
end

function stop_at(ctrl, trial)
if ctrl.LastRecord.trial == trial
    ctrl.requestStop();
end
end

function rmdir_if(folder)
if isfolder(folder)
    rmdir(folder, "s");
end
end
