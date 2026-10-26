classdef TestCalibrationScans < matlab.unittest.TestCase
    %TESTCALIBRATIONSCANS His Hadamard calibration scans, taken on a slide from the tab.
    %
    %   The scans are his had_cal recordings: the 64 full-DMD patterns of
    %   the 63 x 14 scan, his static Hadamard waveform at his calibration
    %   settings, three recordings, nothing moved, no stream recorded. They
    %   are taken before the rig is prepared (preparing needs them), with
    %   only the DAQ, DMD and camera required; they become the rig's scan
    %   calibration, each folder saying how it was taken, and scans taken
    %   at another camera area are refused. Abort reaches them, and the rig
    %   is released however they end.

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
            mkdir(testCase.Folder);
            testCase.addTeardown(@() rmdir(testCase.Folder, "s"));
        end
    end

    methods (Test)
        function theScansAreHisCalibrationRecordings(testCase)
            [cfg, env] = parity_environment(fullfile(testCase.Root, "tests", "fixtures"));
            rng(7, "twister");
            before = rng;
            acqs = hadamard_stim.protocol.acquire_calibration_scans(cfg, env);
            testCase.verifyEqual(rng, before, "The global random stream was left changed");
            testCase.verifyEqual([acqs.folder], "had_cal_1x_arch_" + (1:3));
            testCase.verifyEqual(unique([acqs.kind]), "calibration_scan");
            testCase.verifyEqual([acqs.n_frames], [64 64 64]);
            testCase.verifyEqual([acqs.camera_exposure_ms], [10 10 10]);
            testCase.verifyEqual([acqs.waveform_period_ms], [11 11 11]);
            testCase.verifyEqual([acqs.orange_v], [0.1 0.1 0.1]);
            testCase.verifyEqual([acqs.blue_v], [0 0 0]);
            testCase.verifyEqual(acqs(1).waveform_function, "dragonflyStaticHadamardWaveform_yq");
            testCase.verifyEqual(acqs(1).waveform_settings.repeat, 1);
            streams = [acqs.streams];
            testCase.verifyFalse(any([streams.face_camera] | [streams.wheel_encoder]));
            % The whole DMD, his 64 scan patterns.
            his = hadamard_stim.yitong.static_hadamard_patterns(true(cfg.dmd.size));
            testCase.verifyEqual(acqs(1).dmd_stack.sha256, hadamard_stim.metadata.sha256(his));
            testCase.verifyEmpty(env.hw.moves);
            % His settings are not a deviation of any run.
            cfg.calibration_scan.orange_v = 0.2;
            testCase.verifyEmpty(hadamard_stim.validate_config(cfg).deviations);
        end

        function theTabTakesThemBeforeTheRigIsPrepared(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            c.setConfig(cfg);
            % Nothing the scans do not use is needed: no stage, no blue
            % calibration, no DMD calibration.
            app.Devices(cellfun(@(d) d.name == "NewportTRB25CC", app.Devices)) = [];
            app.getDevice("ALP_DMD").CalibratedCamera = "none";
            blue = app.Devices{cellfun(@(d) d.name == "Blue LED 488", app.Devices)};
            blue.iscalibrated = false;
            testCase.verifyTrue(c.legalActions().acquire_calibration_scans);
            n = numel(app.Acquisitions);
            r = hadamard_stim.apply_controller_action(c, "acquire_calibration_scans", struct(), c.Revision);
            testCase.assertTrue(r.ok, r.message);
            testCase.verifyEqual(r.state.lifecycle, "CONFIGURING");
            scans = app.Acquisitions(n + 1:end);
            testCase.verifyNumElements(scans, 3);
            testCase.verifyEqual([scans.tag], "_had_cal_1x_arch_" + (1:3));
            for s = scans
                testCase.verifyEqual(s.dmd_showing, "stack");
                testCase.verifyEqual(s.stack.size, [1024 768 64]);
                ports = [s.ports.port];
                testCase.verifyFalse(any(ports == "Dev1/ao2"), "blue driven");
                testCase.verifyFalse(any(ports == "Dev1/port0/line0"), "Grasshopper triggered");
                testCase.verifyFalse(any([s.ports.kind] == "di"), "encoder recorded");
                kinetix = s.cameras([s.cameras.name] == "Teledyne Kinetix");
                testCase.verifyEqual([kinetix.frames kinetix.exposure_s], [64 0.01]);
            end
            % They are now the rig's scan calibration, and each says how it
            % was taken.
            folders = string(r.state.backend.settings.calibration_folders)';
            testCase.verifyEqual(folders, [scans.folder]);
            testCase.verifyEqual(reshape(string(r.state.calibration_scans.folders), 1, []), folders);
            record = jsondecode(fileread(fullfile(folders(2), "hadamard_calibration_scan.json")));
            testCase.verifyEqual(record.kind, 'hadamard_stim_calibration_scan');
            testCase.verifyEqual(record.camera.roi', [0 448 0 328]);
            testCase.verifyEqual(record.settings.camera_exposure_ms, 10);
            testCase.verifyEqual(string(record.folders)', folders);
            % Released: the DMD handed back and dark.
            dmd = app.getDevice("ALP_DMD");
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyEqual(dmd.Displaying, "dark");
        end

        function newScansDropAPreparedRig(testCase)
            [c, ~, cfg] = tab_session(testCase.Folder);
            c.setConfig(cfg);
            c.prepareRig();
            testCase.assertTrue(c.hasEnvironment());
            c.acquireCalibrationScans();
            testCase.verifyFalse(c.hasEnvironment());
            testCase.verifyEmpty(c.Prepared);
            testCase.verifyTrue(c.legalActions().prepare_rig);
            % Not once the cells are approved: the masks would outlive them.
            c.prepareRig();
            use_parity_scans(c, testCase.Root);
            c.acquireReferenceImage();
            c.proposeCells();
            c.approveCells();
            testCase.verifyFalse(c.legalActions().acquire_calibration_scans);
            r = hadamard_stim.apply_controller_action(c, "acquire_calibration_scans", struct(), c.Revision);
            testCase.verifyEqual(r.status, "not_legal");
        end

        function scansFromAnotherCameraAreaAreRefused(testCase)
            % A backend that reads its scan calibration from folders, as on
            % the rig.
            [~, app] = tab_session(testCase.Folder);
            backend = hadamard_stim.luminos.LuminosBackend(app, blue_threshold=15, ...
                hardware_validation_file=fullfile(testCase.Folder, "firefly_checks.json"), ...
                acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition);
            c = hadamard_stim.HadamardStimController(backend);
            cfg = c.Config;
            cfg.naming.prefix = "M1";
            c.setConfig(cfg);
            c.runPreflight();
            check = @() c.Preflight.checks(string({c.Preflight.checks.id}) == "scan_calibration");
            testCase.verifyEqual(check().status, "fail");
            c.acquireCalibrationScans();
            c.runPreflight();
            testCase.verifyEqual(check().status, "pass");
            camera = app.getDevice("Camera");
            camera(1).ROI = [0 512 0 512];
            c.runPreflight();
            testCase.verifyEqual(check().status, "fail");
            testCase.verifySubstring(check().message, "Take the calibration scans again");
        end

        function theBlueLedIsCalibratedOnTheSlideByLuminos(testCase)
            % An uncalibrated LED: preflight and Prepare say so. The tab's
            % Calibrate blue LED runs Luminos's slide routine on the LED
            % and the imaging camera; Luminos keeps the result, the run
            % reads it from there, and iscalibrated stays as it was.
            [~, app] = tab_session(testCase.Folder);
            blue = app.getDevice("Modulator_Device", "name", "Blue LED 488");
            blue.iscalibrated = [];
            blue.calibration_curve = [];
            backend = hadamard_stim.luminos.LuminosBackend(app, blue_threshold=15, ...
                hardware_validation_file=fullfile(testCase.Folder, "firefly_checks.json"), ...
                calibration_movies={uint16(100 + randi(500, 16, 600, 64))}, ...
                acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition, ...
                blue_calibration_function=@fake_slide_calibration);
            c = hadamard_stim.HadamardStimController(backend);
            r = hadamard_stim.apply_controller_action(c, "run_preflight", struct(), c.Revision);
            testCase.verifyEqual(r.state.calibration.status, "missing");
            testCase.verifySubstring(r.state.calibration.message, "Calibrate blue LED (slide)");
            r = hadamard_stim.apply_controller_action(c, "calibrate_blue_led", struct(), c.Revision);
            testCase.assertTrue(r.ok, r.message);
            testCase.verifyTrue(any(app.Log == "Blue LED 488:Set_Calibration"));
            testCase.verifyEmpty(blue.iscalibrated);
            testCase.verifyEqual(blue.calibration_info.camera, "Teledyne Kinetix");
            r = hadamard_stim.apply_controller_action(c, "run_preflight", struct(), c.Revision);
            testCase.verifyEqual(r.state.calibration.status, "valid");
            identity = r.state.calibration.identity;
            testCase.verifyEqual(identity.recorded.method, "camera_on_slide");
            testCase.verifyEqual(identity.recorded.camera, "Teledyne Kinetix");
            % Only before the cells are fixed: the calibration would change
            % under a prepared run.
            testCase.verifyTrue(c.legalActions().calibrate_blue_led);
        end

        function abortStopsTheScansAndReleasesTheRig(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            c.setConfig(cfg);
            % The second recording never finishes on its own; Abort arrives
            % while the adapter waits for it.
            c.StatusChangedFcn = @(ctrl) hang_in_recording(ctrl, app, 2);
            r = hadamard_stim.apply_controller_action(c, "acquire_calibration_scans", struct(), c.Revision);
            c.StatusChangedFcn = [];
            testCase.verifyEqual(r.status, "failed");
            testCase.verifyEqual(r.identifier, "hadamard_stim:Aborted");
            testCase.verifyEqual(r.state.status, "idle");
            testCase.verifyTrue(any(app.Log == "app:abortAcquisition"));
            testCase.verifyEqual(app.getDevice("ALP_DMD").pattern_owner, "");
            % The old calibration stands: nothing was half-replaced.
            testCase.verifyEmpty(r.state.calibration_scans);
            testCase.verifyEqual(c.Backend.settings().calibration_folders, strings(0, 1));
        end
    end
end

function hang_in_recording(ctrl, app, recording)
if ~isempty(ctrl.Phase) && ctrl.Phase.name == "calibration_scan" ...
        && ctrl.Phase.recording == recording && ~app.LeaveRunning
    app.LeaveRunning = true;
    app.WhileRunning = @(a) abort_once(a, ctrl);
end
end

function abort_once(app, ctrl)
app.WhileRunning = [];
r = hadamard_stim.apply_controller_action(ctrl, "abort", struct(), []);
assert(r.ok, r.message);
end
