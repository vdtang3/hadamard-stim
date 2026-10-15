classdef TestOptionalStreams < matlab.unittest.TestCase
    %TESTOPTIONALSTREAMS Face video and the wheel encoder are companions, not prerequisites.
    %
    %   On the fake Firefly: preflight asks only for what the configuration
    %   turns on, in both session modes; a stream that is off drives and
    %   triggers nothing and is recorded as deliberately off; a stream that
    %   is on is recorded with its hardware; and turning the face camera off
    %   leaves the protocol's own samples exactly as they were.

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
        function preflightAsksOnlyForWhatIsOn(testCase)
            % Every combination of mode and streams, on a rig with no
            % Grasshopper: only a session that wants face video fails for it.
            [c, app, cfg] = tab_session(testCase.Folder);
            app.Devices(cellfun(@(d) d.name == "Grasshopper3", app.Devices)) = [];
            for mode = ["connectivity" "spontaneous"]
                for face = [false true]
                    for encoder = [false true]
                        cfg.session.mode = mode;
                        cfg.behavior.face_camera_enabled = face;
                        cfg.behavior.wheel_encoder_enabled = encoder;
                        c.setConfig(cfg);
                        c.runPreflight();
                        checks = c.Preflight.checks;
                        status = @(id) checks(string({checks.id}) == id).status;
                        name = sprintf("%s face=%d encoder=%d", mode, face, encoder);
                        testCase.verifyEqual(status("device_behavior_camera"), ...
                            pick(face, "fail", "disabled"), name);
                        testCase.verifyEqual(status("wheel_encoder"), ...
                            pick(encoder, "pass", "disabled"), name);
                        testCase.verifyEqual(c.Preflight.ok, ~face, name);
                        spontaneous = mode == "spontaneous";
                        testCase.verifyEqual(status("device_blue_modulator"), ...
                            pick(spontaneous, "not_needed", "pass"), name);
                        testCase.verifyEqual(status("dmd_queue"), pick(spontaneous, "not_needed", "pass"), name);
                        testCase.verifyEqual(any(string({checks.id}) == "block_memory"), spontaneous, name);
                        for check = ["firefly_trigger_edge" "firefly_queue_support" "firefly_slide_queue"]
                            testCase.verifyEqual(status(check), pick(spontaneous, "not_needed", "pass"), name);
                        end
                    end
                end
            end
        end

        function aSpontaneousSessionNeedsNoStageWithoutDriftCorrection(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            app.Devices(cellfun(@(d) d.name == "NewportTRB25CC", app.Devices)) = [];
            cfg.session.mode = "spontaneous";
            cfg.spontaneous.drift_correction = false;
            c.setConfig(cfg);
            c.runPreflight();
            checks = c.Preflight.checks;
            status = @(id) checks(string({checks.id}) == id).status;
            testCase.verifyEqual(status("device_stage"), "not_needed");
            testCase.verifyEqual(status("scan_calibration"), "not_needed");
            testCase.verifyTrue(c.Preflight.ok);
            % With drift correction the stage is needed again.
            cfg.spontaneous.drift_correction = true;
            c.setConfig(cfg);
            c.runPreflight();
            checks = c.Preflight.checks;
            testCase.verifyEqual(checks(string({checks.id}) == "device_stage").status, "fail");
        end

        function encoderLinesThatCannotBeRecordedAreRefused(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            cfg.behavior.wheel_encoder_enabled = true;
            c.setConfig(cfg);
            % The camera trigger's line, and a line the Waveforms tab records.
            c.setRigSettings(struct("wheel_encoder_lines", ["Dev1/port0/line26" "Dev1/port0/line10"]));
            daq = app.getDevice("DAQ");
            daq.wfm_data.di = struct("name", "photodiode", "port", "Dev1/port0/line10");
            c.runPreflight();
            check = c.Preflight.checks(string({c.Preflight.checks.id}) == "wheel_encoder");
            testCase.verifyEqual(check.status, "fail");
            testCase.verifySubstring(check.message, "cameraTrigger");
            testCase.verifySubstring(check.message, """photodiode""");
            % The setting itself is checked when it is set.
            r = hadamard_stim.apply_controller_action(c, "set_rig_settings", ...
                struct("settings", struct("wheel_encoder_lines", "Dev1/port0/line9")), c.Revision);
            testCase.verifyEqual(r.status, "failed");
            testCase.verifySubstring(r.message, "two lines");
        end

        function aConnectivityRunWithNeitherStreamDrivesNeither(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            cfg.trials.last = 1;
            cfg.behavior.face_camera_enabled = false;
            c = ready(testCase, c, cfg);
            c.startRun(fullfile(testCase.Folder, "run"));
            testCase.assertEqual(c.LifecycleState, "COMPLETED");
            stim = app.Acquisitions(end);
            ports = [stim.ports.port];
            testCase.verifyFalse(any(ports == "Dev1/port0/line0"), "Grasshopper trigger driven");
            testCase.verifyFalse(any(ports == "Dev1/ao3"), "IR driven");
            testCase.verifyFalse(any([stim.ports.kind] == "di"), "encoder recorded");
            testCase.verifyTrue(any(ports == "Dev1/ao2"), "blue not driven");
            grasshopper = stim.cameras([stim.cameras.name] == "Grasshopper3");
            testCase.verifyEqual(grasshopper.frametrigger_source, "Off");
            testCase.verifyEqual(grasshopper.frames, 1);
            record = jsondecode(fileread(fullfile(testCase.Folder, "run", "run_recipe.json")));
            testCase.verifyEqual(record.streams.face_camera.status, 'disabled in the configuration');
            testCase.verifyEqual(record.streams.wheel_encoder.status, 'disabled in the configuration');
            testCase.verifyFalse(record.streams.face_camera.enabled);
            testCase.verifyNumElements(record.warnings, 2);
            testCase.verifyEqual(record.session_mode, 'connectivity');
        end

        function aConnectivityRunWithBothStreamsRecordsBoth(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            cfg.trials.last = 1;
            cfg.behavior.wheel_encoder_enabled = true;
            c = ready(testCase, c, cfg);
            c.startRun(fullfile(testCase.Folder, "run"));
            testCase.assertEqual(c.LifecycleState, "COMPLETED");
            % The encoder is sampled in every acquisition, scans included,
            % for exactly the acquisition's samples.
            for a = reshape(app.Acquisitions, 1, [])
                di = a.ports([a.ports.kind] == "di");
                testCase.verifyEqual([di.port], ["Dev1/port0/line9" "Dev1/port0/line10"], a.tag);
                testCase.verifyEqual([di.n_samples], [a.n_samples a.n_samples], a.tag);
            end
            stim = app.Acquisitions(end);
            grasshopper = stim.cameras([stim.cameras.name] == "Grasshopper3");
            testCase.verifyEqual(grasshopper.frametrigger_source, "External");
            testCase.verifyEqual(grasshopper.frames, 406);
            acq = c.Env.hw.acquisitions(end);
            testCase.verifyEqual(acq.behavior.status, "recorded");
            testCase.verifyEqual(acq.encoder.status, "recorded");
            testCase.verifyEqual(acq.encoder.n_samples, stim.n_samples);
            recipe = jsondecode(fileread(fullfile(testCase.Folder, "run", "run_recipe.json")));
            hw = recipe.streams.wheel_encoder.hardware;
            testCase.verifyEqual(string(hw.lines)', ["Dev1/port0/line9" "Dev1/port0/line10"]);
            testCase.verifyEqual(hw.rate_hz, 1e5);
            testCase.verifySubstring(hw.clock, "acquisition");
            testCase.verifyEqual(recipe.streams.face_camera.hardware.camera.name, 'Grasshopper3');
            testCase.verifyEqual(recipe.streams.face_camera.hardware.trigger.port, 'Dev1/port0/line0');
            testCase.verifyEmpty(recipe.warnings);
            % Released: the operator's waveform settings are back, inputs too.
            testCase.verifyFalse(isfield(app.getDevice("DAQ").wfm_data, "di") && ...
                ~isempty(app.getDevice("DAQ").wfm_data.di));
        end

        function theFaceCameraSwitchLeavesTheProtocolSamplesAlone(testCase)
            % The same trial with the face camera on and off: the protocol's
            % waveform is identical; only which rows the rig drives differs.
            hashes = strings(1, 2);
            ports = cell(1, 2);
            for k = 1:2
                folder = fullfile(testCase.Folder, "s" + k);
                [c, app, cfg] = tab_session(folder);
                cfg.trials.last = 1;
                cfg.behavior.face_camera_enabled = k == 1;
                c = ready(testCase, c, cfg);
                c.startRun(fullfile(folder, "run"));
                hashes(k) = c.Env.hw.acquisitions(end).waveform_sha256;
                p = app.Acquisitions(end).ports;
                ports{k} = p;
            end
            testCase.verifyEqual(hashes(1), hashes(2));
            [on, off] = ports{:};
            testCase.verifyEqual(setdiff([on.port], [off.port]), ["Dev1/ao3" "Dev1/port0/line0"]);
            % The rows both drive are sample for sample the same.
            [~, a, b] = intersect([on.port], [off.port]);
            testCase.verifyEqual({on(a).sha256}, {off(b).sha256});
        end
    end

    methods
        function c = ready(testCase, c, cfg)
            c.setConfig(cfg);
            c.prepareRig();
            use_parity_scans(c, testCase.Root);
            c.acquireReferenceImage();
            c.proposeCells();
            c.approveCells();
            c.acquireZReference();
        end
    end
end

function v = pick(condition, yes, no)
if condition
    v = yes;
else
    v = no;
end
end
