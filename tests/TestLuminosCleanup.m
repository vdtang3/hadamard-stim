classdef TestLuminosCleanup < matlab.unittest.TestCase
    %TESTLUMINOSCLEANUP release() restores exactly what was changed, whatever failed.
    %
    %   Each test makes one step of a session fail on fake Luminos devices,
    %   then checks that LuminosRig.release() put back what had changed,
    %   touched nothing else, released DMD ownership last, and can be called
    %   again harmlessly.

    properties
        Folder
        App
        Cfg
        Rig
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "support")));
        end
    end

    methods (TestMethodSetup)
        function begin(testCase)
            testCase.Folder = string(tempname);
            mkdir(testCase.Folder);
            testCase.addTeardown(@() rmdir(testCase.Folder, "s"));
            [testCase.App, testCase.Cfg, ~, testCase.Rig] = fake_firefly(testCase.Folder);
            report = testCase.Rig.begin(testCase.Cfg);
            testCase.assertTrue(report.can_run, strjoin(report.failures, newline));
        end
    end

    methods (Test)
        function aCompleteSessionIsUndone(testCase)
            rig = testCase.Rig;
            rig.dmd_load_stack(testCase.masks(4));
            rig.acquire(testCase.scanSpec());
            rig.dmd_load_queue({testCase.masks(2), testCase.masks(2)}, [3 6]);
            report = rig.release();
            testCase.verifyTrue(report.ok);
            testCase.verifyAsFound();
            testCase.verifyEqual(report.steps', ["restore_camera:Blackfly" "restore_camera:Grasshopper3" ...
                "restore_camera:Teledyne Kinetix" "restore_daq" "reset_sequence_queue" "blank_dmd" ...
                "restore_pattern_stack" "release_dmd_ownership"]);
        end

        function aFailedClaimLeavesNothingToUndo(testCase)
            testCase.device("DMD (shared)").FailOn = "Claim_Pattern_Ownership";
            testCase.verifyError(@() testCase.Rig.dmd_load_stack(testCase.masks(4)), "fake:Injected");
            report = testCase.Rig.release();
            testCase.verifyEqual(report.steps, strings(0, 1));
            testCase.verifyAsFound();
        end

        function aFailedStackWriteIsUndone(testCase)
            testCase.device("DMD (shared)").FailOn = "Write_Stack";
            testCase.verifyError(@() testCase.Rig.dmd_load_stack(testCase.masks(4)), "fake:Injected");
            report = testCase.Rig.release();
            testCase.verifyEqual(report.steps', ["blank_dmd" "restore_pattern_stack" "release_dmd_ownership"]);
            testCase.verifyAsFound();
        end

        function aFailedQueueLoadIsReset(testCase)
            testCase.device("DMD (shared)").FailOn = "Load_Sequence_Queue";
            testCase.verifyError(@() testCase.Rig.dmd_load_queue({testCase.masks(2)}, 4), "fake:Injected");
            report = testCase.Rig.release();
            testCase.verifyEqual(report.steps', ["reset_sequence_queue" "blank_dmd" "release_dmd_ownership"]);
            testCase.verifyAsFound();
        end

        function aFailedDaqInstallIsUndone(testCase)
            % global_props has been written when wfm_data fails.
            testCase.device("DAQ_Session").FailOn = "set_wfm_data";
            testCase.verifyError(@() testCase.Rig.acquire(testCase.scanSpec()), "fake:Injected");
            report = testCase.Rig.release();
            testCase.verifyEqual(report.steps', "restore_daq");
            testCase.verifyAsFound();
            testCase.verifyNoCameraWasTouched();
        end

        function aCameraFailingHalfwayIsUndone(testCase)
            % The Kinetix is set, the Grasshopper fails part way, the Blackfly
            % is never reached.
            testCase.device("Grasshopper3").FailOn = "set_frames_requested";
            testCase.verifyError(@() testCase.Rig.acquire(testCase.scanSpec()), "fake:Injected");
            report = testCase.Rig.release();
            testCase.verifyEqual(report.steps', ["restore_camera:Grasshopper3" ...
                "restore_camera:Teledyne Kinetix" "restore_daq"]);
            testCase.verifyAsFound();
            testCase.verifyFalse(any(startsWith(testCase.App.Log, "Blackfly:")));
        end

        function aFailedAcquisitionIsUndone(testCase)
            testCase.App.FailOnAcquisition = 1;
            testCase.verifyError(@() testCase.Rig.acquire(testCase.scanSpec()), "fake:AcquisitionFailed");
            testCase.Rig.release();
            testCase.verifyAsFound();
            testCase.verifyFalse(any(testCase.App.Log == "app:abortAcquisition"));
        end

        function anAbortInLuminosStopsTheRun(testCase)
            testCase.App.AbortOnAcquisition = 1;
            testCase.verifyError(@() testCase.Rig.acquire(testCase.scanSpec()), "hadamard_stim:AcquisitionAborted");
            testCase.Rig.release();
            testCase.verifyAsFound();
        end

        function aHungAcquisitionIsAbortedThenUndone(testCase)
            app = testCase.App;
            app.LeaveRunning = true;
            rig = hadamard_stim.luminos.LuminosRig(app, blue_threshold=15, timeout_margin_s=0.2, ...
                acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition);
            rig.begin(testCase.Cfg);
            testCase.verifyError(@() rig.acquire(testCase.scanSpec()), "hadamard_stim:AcquisitionTimeout");
            report = rig.release();
            testCase.verifyEqual(report.steps(1), "abort_acquisition");
            testCase.verifyFalse(app.acquisition_active);
            testCase.verifyAsFound();
        end

        function aFailedStageMoveIsNotRecorded(testCase)
            stage = testCase.device("NewportTRB25CC");
            stage.FailOn = "Move_To_Position";
            testCase.verifyError(@() testCase.Rig.motor_move_to(stage.pos + 0.003), "fake:Injected");
            testCase.verifyEmpty(testCase.Rig.moves);
            % His script never moved the stage back, and neither does release.
            testCase.Rig.motor_move_to(stage.pos + 0.003);
            z = stage.pos;
            testCase.Rig.release();
            testCase.verifyEqual(stage.pos, z);
        end

        function aFailingRestoreStepDoesNotStopTheRest(testCase)
            rig = testCase.Rig;
            rig.dmd_load_stack(testCase.masks(4));
            dmd = testCase.device("DMD (shared)");
            dmd.FailOn = "Write_Dark";
            testCase.verifyWarning(@() rig.release(), "hadamard_stim:ReleaseIncomplete");
            testCase.verifyFalse(rig.LastRelease.ok);
            testCase.verifySubstring(rig.LastRelease.errors, "blank_dmd");
            % Ownership is still given back, last.
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyEqual(testCase.App.Log(end), "DMD (shared):Release_Pattern_Ownership");
        end

        function releaseCanBeCalledAgain(testCase)
            rig = testCase.Rig;
            rig.dmd_load_queue({testCase.masks(2)}, 4);
            rig.release();
            n = numel(testCase.App.Log);
            report = rig.release();
            testCase.verifyEqual(report.steps, strings(0, 1));
            testCase.verifyEqual(numel(testCase.App.Log), n);
            testCase.verifyAsFound();
        end

        function nothingRunsBeforeBegin(testCase)
            rig = hadamard_stim.luminos.LuminosRig(testCase.App, blue_threshold=15);
            testCase.verifyError(@() rig.dmd_load_queue({testCase.masks(2)}, 4), "hadamard_stim:NotBegun");
            testCase.verifyError(@() rig.motor_position(), "hadamard_stim:NotBegun");
        end

        function wrongSizedPatternsAreRefusedBeforeLoading(testCase)
            testCase.verifyError(@() testCase.Rig.dmd_load_queue({false(1024, 768, 2)}, 4), ...
                "hadamard_stim:PatternSize");
            testCase.verifyFalse(any(contains(testCase.App.Log, "Load_Sequence_Queue")));
            testCase.Rig.release();
            testCase.verifyAsFound();
        end
    end

    methods
        function d = device(testCase, name)
            for k = 1:numel(testCase.App.Devices)
                if testCase.App.Devices{k}.name == name
                    d = testCase.App.Devices{k};
                    return
                end
            end
        end

        function m = masks(~, n)
            m = false(768, 1024, n);
            m(1:10, 1:10, :) = true;
        end

        function spec = scanSpec(testCase)
            cfg = testCase.Cfg;
            waveform = hadamard_stim.protocol.scan_waveform(cfg, cfg.scan.waveform_period_ms, ...
                cfg.scan.orange_v, 64, camera_rows=328);
            spec = hadamard_stim.protocol.acquisition_spec("z_stack_plane", "cleanup_test", ...
                waveform, camera_exposure_ms=cfg.scan.camera_exposure_ms);
        end

        function verifyAsFound(testCase)
            % The fake Firefly as make_fake_luminos made it, apart from the
            % DMD showing dark when anything had been loaded.
            dmd = testCase.device("DMD (shared)");
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyTrue(dmd.auto_write_stack);
            testCase.verifyEmpty(dmd.pattern_stack);
            testCase.verifyEmpty(dmd.sequence_queue);
            testCase.verifyTrue(ismember(dmd.Displaying, ["nothing" "dark"]));
            daq = testCase.device("DAQ_Session");
            testCase.verifyEmpty(daq.wfm_data.ao);
            testCase.verifyEmpty(daq.wfm_data.do);
            testCase.verifyEqual(daq.global_props.total_time, 1);
            for name = ["Teledyne Kinetix" "Grasshopper3" "Blackfly"]
                cam = testCase.device(name);
                testCase.verifyEqual(cam.frametrigger_source, "Off", name);
                testCase.verifyEqual(cam.frames_requested, 1, name);
                testCase.verifyEqual(cam.acquisition_exposuretime, 0.15, name);
            end
            % Only the owner's last act may follow the DMD's release.
            log = testCase.App.Log;
            released = find(log == "DMD (shared):Release_Pattern_Ownership", 1, "last");
            if ~isempty(released)
                testCase.verifyEqual(released, numel(log), "DMD ownership was not released last");
            end
        end

        function verifyNoCameraWasTouched(testCase)
            log = testCase.App.Log;
            touched = startsWith(log, ["Teledyne Kinetix:" "Grasshopper3:" "Blackfly:"]);
            testCase.verifyFalse(any(touched), strjoin(log(touched), ", "));
        end
    end
end
