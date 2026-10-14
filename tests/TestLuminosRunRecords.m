classdef TestLuminosRunRecords < matlab.unittest.TestCase
    %TESTLUMINOSRUNRECORDS A controller session on the Luminos adapter, and what it records.
    %
    %   make_environment on fake Firefly devices, then the controller in his
    %   order of work up to one trial. The recipe must hold what Luminos
    %   reported about the rig, the calibrations actually used, both
    %   software commits and every standing deviation; refusals must leave
    %   the rig untouched and no run folder behind.

    properties
        Root
        Folder
        RunFolder
        App
        Cfg
        Inputs
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(testCase.Root, "tests", "support")));
            incoming = rng;
            testCase.addTeardown(@() rng(incoming));
        end
    end

    methods (TestMethodSetup)
        function makeFolders(testCase)
            testCase.Folder = string(tempname);
            mkdir(testCase.Folder);
            testCase.addTeardown(@() rmdir(testCase.Folder, "s"));
            testCase.RunFolder = fullfile(testCase.Folder, "run");
            [testCase.App, testCase.Cfg, testCase.Inputs] = fake_firefly(testCase.Folder);
            testCase.Cfg.trials.last = 1;
        end
    end

    methods (Test)
        function theRecipeRecordsTheRig(testCase)
            c = testCase.readySession();
            r = hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("run_folder", testCase.RunFolder), c.Revision);
            testCase.assertTrue(r.ok, r.message);
            recipe = jsondecode(fileread(fullfile(testCase.RunFolder, "run_recipe.json")));

            testCase.verifyFalse(recipe.simulated);
            testCase.verifyEqual(string(recipe.hardware.rig.name), "Firefly");
            testCase.verifyEqual(string(recipe.hardware.dmd.name), "DMD (shared)");
            testCase.verifyTrue(recipe.hardware.dmd.sequence_queue_supported);
            testCase.verifyEqual(string({recipe.hardware.cameras.name}), ...
                ["Teledyne Kinetix" "Grasshopper3" "Blackfly"]);
            testCase.verifyEqual(string({recipe.hardware.daq.channels.port})', ...
                [hadamard_stim.luminos.firefly_profile().channels.port]');
            testCase.verifyEqual(string(recipe.hardware.stage.units), "mm");

            testCase.verifyEqual(string(recipe.calibrations.blue_source), "luminos_modulator_calibration");
            testCase.verifyEqual(recipe.calibrations.blue.blue_threshold, 15);
            testCase.verifyEqual(string(recipe.calibrations.geometry.source), "luminos_dmd_calibration");
            testCase.verifyGreaterThan(recipe.hardware.scan_calibration.n_movies, 0);

            testCase.verifyEqual(string(recipe.standing_deviations), ...
                hadamard_stim.luminos.firefly_profile().standing_deviations);
            testCase.verifyTrue(recipe.hardware_validation.slide_queue.passed);
            % Off the rig Luminos's own provenance helper is absent, and the
            % recipe says so instead of inventing a commit.
            testCase.verifyEqual(string(recipe.software.luminos.commit), "unavailable");
            testCase.verifySubstring(string(recipe.software.luminos.reason), "luminos_session_info");
            testCase.verifyNotEmpty(recipe.software.hadamard_stim.commit);

            trial = jsondecode(fileread(fullfile(testCase.RunFolder, "trials", "trial_0001.json")));
            testCase.verifyEqual(string(trial.status), "completed");
            testCase.verifyNotEmpty(trial.acquisition.waveform_sha256);
            testCase.verifyEqual(trial.recipe_hash, recipe.recipe_hash);
        end

        function eachHardwareSessionIsReleased(testCase)
            c = testCase.readySession();
            hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("run_folder", testCase.RunFolder), c.Revision);
            dmd = testCase.App.getDevice("ALP_DMD");
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyEqual(c.Env.hw.LastRelease.steps(end), "release_dmd_ownership");
            testCase.verifyEmpty(testCase.App.getDevice("DAQ").wfm_data.do);
        end

        function aFailedTrialStillReleasesTheRig(testCase)
            c = testCase.readySession();
            % The z-reference took 21 acquisitions; the trial's drift scan fails.
            testCase.App.FailOnAcquisition = numel(testCase.App.Acquisitions) + 1;
            r = hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("run_folder", testCase.RunFolder), c.Revision);
            testCase.verifyEqual(r.status, "failed");
            testCase.verifyEqual(c.LifecycleState, "FAILED");
            testCase.verifyEqual(testCase.App.getDevice("ALP_DMD").pattern_owner, "");
            testCase.verifyEqual(testCase.App.Log(end), "DMD (shared):Release_Pattern_Ownership");
        end

        function aRigThatCannotRunIsRefusedBeforeAnythingHappens(testCase)
            c = testCase.readySession();
            dmd = testCase.App.getDevice("ALP_DMD");
            dmd.pattern_owner = "adaptive_optopatch";
            n = numel(testCase.App.Log);
            r = hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("run_folder", testCase.RunFolder), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:HardwareNotReady");
            testCase.verifySubstring(r.message, "owned by ""adaptive_optopatch""");
            testCase.verifyFalse(isfolder(testCase.RunFolder));
            testCase.verifyEqual(numel(testCase.App.Log), n);
            testCase.verifyEqual(dmd.pattern_owner, "adaptive_optopatch");
        end

        function withoutTheFireflyChecksNothingRuns(testCase)
            c = testCase.readySession(hardware_validation=[]);
            r = hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("run_folder", testCase.RunFolder), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:HardwareNotValidated");
            testCase.verifyFalse(isfolder(testCase.RunFolder));
        end

        function anUncalibratedBlueRefusesTheEnvironment(testCase)
            blue = testCase.App.getDevice("NI_DAQ_Modulator");
            blue.iscalibrated = false;
            testCase.verifyError(@() testCase.environment(), "hadamard_stim:RigNotReady");
            try
                testCase.environment();
            catch err
                testCase.verifySubstring(err.message, "Blue LED 488 has no active calibration");
            end
        end
    end

    methods
        function env = environment(testCase, options)
            arguments
                testCase
                options.hardware_validation = passed_checks()
            end
            rng(3, "twister");
            calibration = uint16(100 + randi(500, 16, 600, 64));
            env = hadamard_stim.luminos.make_environment(testCase.App, testCase.Cfg, ...
                blue_threshold=15, calibration_movies={calibration}, ...
                hardware_validation=options.hardware_validation, ...
                acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition);
        end

        function c = readySession(testCase, options)
            % A controller on the adapter, cells approved and the reference
            % z-stack taken. Scans reconstruct to the parity world's images,
            % since the fake camera records zeros.
            arguments
                testCase
                options.hardware_validation = passed_checks()
            end
            env = testCase.environment(hardware_validation=options.hardware_validation);
            [~, parity] = parity_environment(fullfile(testCase.Root, "tests", "fixtures"));
            world = parity.hw.world;
            env.reconstruct_scan = @(acq) world.scan_image([], struct("kind", acq.kind, ...
                "drift_scan_number", 1, "motor_z", acq.motor_z));
            env.reconstruct_z_stack = parity.reconstruct_z_stack;
            c = hadamard_stim.HadamardStimController(env);
            c.setConfig(testCase.Cfg);
            c.setReferenceImage(testCase.Inputs.ref_im);
            c.proposeCells();
            c.approveCells();
            c.acquireZReference();
        end
    end
end

function v = passed_checks()
passed = struct("passed", true, "evidence", "test", "date", "2026-10-14");
v = struct("driver", passed, "trigger_edge", passed, "queue_support", passed, "slide_queue", passed);
end
