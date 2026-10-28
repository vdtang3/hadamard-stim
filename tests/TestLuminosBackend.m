classdef TestLuminosBackend < matlab.unittest.TestCase
    %TESTLUMINOSBACKEND The tab's path: a controller on LuminosBackend, fake Firefly.
    %
    %   What the Hadamard_Stim device builds: preflight one requirement at
    %   a time and read only, the active blue calibration's status, rig
    %   settings, read-only diagnostics, and a run driven only through
    %   apply_controller_action that asks the rig for exactly what the
    %   programmatic path asks for. Abort reaches the acquisition being
    %   waited for, and the rig is released before ABORTED is reported.

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
        function preflightReportsEachRequirementAndChangesNothing(testCase)
            [c, app, cfg] = tab_session(testCase.Folder, validated=false);
            c.setConfig(cfg);
            dmd = app.getDevice("ALP_DMD");
            dmd.pattern_owner = "adaptive_optopatch";
            n = numel(app.Log);
            r = hadamard_stim.apply_controller_action(c, "run_preflight", struct(), c.Revision);
            testCase.assertTrue(r.ok, r.message);
            checks = r.state.preflight.checks;
            ids = string({checks.id});
            testCase.verifyEqual(numel(unique(ids)), numel(ids));
            testCase.verifyEqual(ids(1:2), ["rig" "luminos_idle"]);
            testCase.verifyEqual(r.state.readiness.checks(1).id, "config");
            for id = ["device_dmd" "device_camera" "device_behavior_camera" "device_daq" ...
                    "device_stage" "device_blue_modulator" "dmd_board" "dmd_queue" "dmd_ownership" ...
                    "dmd_canvas" "dmd_polarity" "daq_rate" "daq_outputs" "camera_settings" ...
                    "blue_calibration" "dmd_calibration" "scan_calibration" "data_folder" ...
                    "firefly_queue_support" "firefly_slide_queue"]
                testCase.verifyTrue(ismember(id, ids), id);
            end
            testCase.verifyFalse(any(ismember(["firefly_driver" "firefly_trigger_edge"], ids)));
            % Another owner is a hardware conflict (blocker); commissioning
            % checks recorded as failed are evidence, not a refusal: a failed
            % slide test is a warning, a failed queue-support record history
            % (the live driver answers).
            blocked = checks([checks.status] == "blocker");
            testCase.verifyEqual(string({blocked.id}), "dmd_ownership");
            warned = checks([checks.status] == "warning");
            testCase.verifyEqual(string({warned.id}), "firefly_slide_queue");
            testCase.verifyEqual(checks(ids == "firefly_queue_support").status, "info");
            testCase.verifySubstring(warned(1).message, "FAILED");
            owner = checks(ids == "dmd_ownership");
            testCase.verifySubstring(owner.message, "owned by ""adaptive_optopatch""");
            testCase.verifyFalse(owner.overrideable);
            testCase.verifyFalse(r.state.preflight.can_run);
            testCase.verifyFalse(r.state.readiness.can_run);
            % Read only: no device operation, the owner untouched, and the
            % session's lifecycle and environment as they were.
            testCase.verifyEqual(numel(app.Log), n);
            testCase.verifyEqual(dmd.pattern_owner, "adaptive_optopatch");
            testCase.verifyEqual(r.state.lifecycle, "CONFIGURING");
            testCase.verifyFalse(r.state.environment.prepared);
        end

        function aStageThatIsNotNeededIsSaidToBeNotNeeded(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            app.Devices(cellfun(@(d) d.name == "NewportTRB25CC", app.Devices)) = [];
            cfg.z_reference.enabled = false;
            cfg.drift.enabled = false;
            c.setConfig(cfg);
            c.runPreflight();
            checks = c.Preflight.checks;
            stage = checks(string({checks.id}) == "device_stage");
            testCase.verifyEqual(stage.status, "not_needed");
            testCase.verifyEqual(checks(string({checks.id}) == "scan_calibration").status, "not_needed");
        end

        function theBlueCalibrationStatusIsTheOneARunWouldUse(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            c.setConfig(cfg);
            c.runPreflight();
            s = c.getState().calibration;
            testCase.verifyEqual(s.status, "valid");
            testCase.verifyEqual(s.blue_threshold, 15);
            testCase.verifyEqual(s.identity.device, "Blue LED 488");

            blue = app.getDevice("NI_DAQ_Modulator", "name", "Blue LED 488");
            blue.iscalibrated = false;
            c.runPreflight();
            s = c.getState().calibration;
            testCase.verifyEqual(s.status, "missing");
            testCase.verifySubstring(s.message, "Blue LED 488 has no active calibration");
            % ... and a run cannot be prepared without it.
            r = hadamard_stim.apply_controller_action(c, "prepare_rig", struct(), c.Revision);
            testCase.verifyEqual(r.status, "failed");
            testCase.verifyEqual(r.identifier, "hadamard_stim:RigNotReady");
            testCase.verifyFalse(r.state.environment.prepared);

            blue.iscalibrated = true;
            r = hadamard_stim.apply_controller_action(c, "set_rig_settings", ...
                struct("settings", struct("blue_threshold", [])), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            c.runPreflight();
            testCase.verifyEqual(c.getState().calibration.status, "invalid");
        end

        function rigSettingsAreCheckedAndDropThePreparedRig(testCase)
            [c, ~, cfg] = tab_session(testCase.Folder);
            c.setConfig(cfg);
            r = hadamard_stim.apply_controller_action(c, "prepare_rig", struct(), c.Revision);
            testCase.assertTrue(r.ok, r.message);
            testCase.verifyTrue(r.state.environment.prepared);
            testCase.verifyEqual(r.state.calibration.status, "valid");
            for bad = {struct("blue_threshold", -1), struct("blue_threshold", "x"), struct("colour", 1)}
                r = hadamard_stim.apply_controller_action(c, "set_rig_settings", ...
                    struct("settings", bad{1}), c.Revision);
                testCase.verifyEqual(r.identifier, "hadamard_stim:InvalidSetting");
            end
            testCase.verifyTrue(r.state.environment.prepared);
            r = hadamard_stim.apply_controller_action(c, "set_rig_settings", ...
                struct("settings", struct("blue_threshold", 20, ...
                "calibration_folders", {{'a', 'b'}})), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(r.state.backend.settings.blue_threshold, 20);
            testCase.verifyEqual(r.state.backend.settings.calibration_folders, ["a"; "b"]);
            testCase.verifyFalse(r.state.environment.prepared);
        end

        function diagnosticsOnlyRead(testCase)
            [c, app] = tab_session(testCase.Folder);
            n = numel(app.Log);
            v = hadamard_stim.controller_view(c, "diagnostics");
            testCase.assertTrue(v.ok, v.message);
            d = v.data;
            testCase.verifyEqual(numel(app.Log), n);
            testCase.verifyEqual(d.dmd.name, "DMD (shared)");
            testCase.verifyTrue(d.dmd.sequence_queue_supported);
            testCase.verifyTrue(isstruct(d.dmd.queue_state));
            testCase.verifyEqual(string({d.cameras.name}), ["Teledyne Kinetix" "Grasshopper3" "Blackfly"]);
            testCase.verifyEqual(string({d.cameras.role}), ["imaging" "behavior" "other"]);
            testCase.verifyEqual(d.stage.position, app.getDevice("Newport_Motor_Controller").Get_Current_Position());
            testCase.verifyEqual(d.blue_calibration.status, "valid");
            testCase.verifyEqual(numel(d.daq.protocol_ports), 12);
            testCase.verifyNotEmpty(jsonencode(v));
        end

        function theTabPathAsksTheRigForWhatTheProgrammaticPathAsks(testCase)
            % Programmatic: make_environment, then the controller's methods.
            [app1, cfg, inputs] = fake_firefly(fullfile(testCase.Folder, "a"));
            cfg.trials.last = 4;
            rng(3, "twister");
            calibration = uint16(100 + randi(500, 16, 600, 64));
            env = hadamard_stim.luminos.make_environment(app1, cfg, blue_threshold=15, ...
                calibration_movies={calibration}, hardware_validation=passed_checks(), ...
                acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition);
            programmatic = hadamard_stim.HadamardStimController(env);
            use_parity_scans(programmatic, testCase.Root);
            programmatic.setConfig(cfg);
            programmatic.setReferenceImage(inputs.ref_im);
            programmatic.proposeCells();
            programmatic.approveCells();
            programmatic.acquireZReference();
            programmatic.startRun(fullfile(testCase.Folder, "run_a"));

            % The tab: the device's construction, then named actions only.
            [tab, app2] = tab_session(fullfile(testCase.Folder, "b"));
            act = @(a, p) hadamard_stim.apply_controller_action(tab, a, p, tab.Revision);
            testCase.assertTrue(act("update_config", struct("changes", config_changes(cfg))).ok);
            testCase.assertEqual(tab.Config, cfg);
            testCase.assertTrue(act("run_preflight", struct()).ok);
            testCase.assertTrue(tab.Preflight.can_run, strjoin(string({tab.Preflight.checks([tab.Preflight.checks.status] == "blocker").message}), newline));
            testCase.assertTrue(act("prepare_rig", struct()).ok);
            use_parity_scans(tab, testCase.Root);
            r = act("acquire_reference_image", struct());
            testCase.assertTrue(r.ok, r.message);
            for step = ["propose_cells" "approve_cells" "acquire_z_reference"]
                r = act(step, struct());
                testCase.assertTrue(r.ok, step + ": " + r.message);
            end
            r = act("start_run", struct("run_folder", fullfile(testCase.Folder, "run_b")));
            testCase.assertTrue(r.ok, r.message);
            testCase.verifyEqual(r.state.lifecycle, "COMPLETED");

            % The same acquisitions, in the same order, playing the same
            % samples on the same ports with the same DMD contents, after
            % the tab's one extra (the reference scan).
            a = strip_paths(app1.Acquisitions);
            b = strip_paths(app2.Acquisitions);
            testCase.verifyEqual(b(1).tag, "_M-YQ0201-29_FOV1_had_ref");
            testCase.verifyEqual(b(2:end), a);
            testCase.verifyEqual(tab.Env.hw.moves, programmatic.Env.hw.moves);
            testCase.verifyEqual(tab.Cells.cell_coord, programmatic.Cells.cell_coord);
            ra = jsondecode(fileread(fullfile(testCase.Folder, "run_a", "run_recipe.json")));
            rb = jsondecode(fileread(fullfile(testCase.Folder, "run_b", "run_recipe.json")));
            testCase.verifyEqual(rb.config, ra.config);
            testCase.verifyEqual(rmfield(rb.calibrations.blue, "resolved_utc"), ...
                rmfield(ra.calibrations.blue, "resolved_utc"));
            testCase.verifyEqual(rb.calibrations.geometry, ra.calibrations.geometry);
            testCase.verifyEqual(rb.standing_deviations, ra.standing_deviations);
            testCase.verifyEqual(rb.matrix, ra.matrix);
        end

        function abortReachesTheAcquisitionBeingWaitedFor(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            cfg.trials.last = 3;
            testCase.ready(c, cfg);
            n_before = numel(app.Acquisitions);
            % Trial 2's stimulation acquisition never finishes on its own;
            % the operator's Abort arrives as a JS_Server interrupt while
            % the adapter waits for it (here, from its poll of the app).
            c.ProgressChangedFcn = @(ctrl) hang_after(ctrl, app, 1);
            r = hadamard_stim.apply_controller_action(c, "start_run", struct(), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(r.state.lifecycle, "ABORTED");
            testCase.verifyTrue(any(app.Log == "app:abortAcquisition"));
            testCase.verifyEqual(app.Log(end), "DMD (shared):Release_Pattern_Ownership");
            testCase.verifyEqual(r.state.cleanup.steps(end), "release_dmd_ownership");
            testCase.verifyEqual(app.getDevice("ALP_DMD").pattern_owner, "");
            testCase.verifyEqual(r.state.progress.next_trial, 2);
            testCase.verifyGreaterThan(numel(app.Acquisitions), n_before);

            % The default run folder is in Luminos's data folder, and the
            % tab can find it and resume it.
            runs = hadamard_stim.controller_view(c, "run_folders").data;
            testCase.verifyEqual(runs(1).folder, c.RunFolder);
            testCase.verifyTrue(startsWith(c.RunFolder, app.datafolder));
            app.LeaveRunning = false;
            app.WhileRunning = [];
            c.ProgressChangedFcn = [];
            r = hadamard_stim.apply_controller_action(c, "resume_run", ...
                struct("run_folder", runs(1).folder), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(r.state.lifecycle, "COMPLETED");
        end

        function failedFireflyChecksAreAcknowledgedOnceThenRecorded(testCase)
            % Checks recorded as failed: the tab shows them as warnings, Run
            % refuses until they are acknowledged together, touching
            % nothing, and the recipe records the override.
            [c, app, cfg] = tab_session(testCase.Folder, validated=false);
            cfg.trials.last = 1;
            testCase.ready(c, cfg);
            n = numel(app.Log);
            r = hadamard_stim.apply_controller_action(c, "start_run", struct(), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:WarningsNotAcknowledged");
            testCase.verifyEqual(numel(app.Log), n);
            testCase.verifyEqual(r.state.environment.hardware_gate.missing, "slide_queue");
            readiness = r.state.readiness;
            testCase.verifyTrue(readiness.can_run);
            ids = string({readiness.warnings.id});
            testCase.verifyEqual(ids, "firefly_slide_queue");
            r = hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("acknowledged_warnings", ids), c.Revision);
            testCase.assertTrue(r.ok, r.message);
            recipe = jsondecode(fileread(fullfile(c.RunFolder, "run_recipe.json")));
            testCase.verifyTrue(recipe.start_override.operator_override);
            testCase.verifyEqual(string({recipe.start_override.warnings.id}), ids);
            testCase.verifySubstring(recipe.start_override.warnings(1).consequence, "diagnostic data");
        end

        function aConflictingDaqOutputBlocksTheRun(testCase)
            % Another waveform on a port the protocol drives: no override.
            [c, app, cfg] = tab_session(testCase.Folder);
            cfg.trials.last = 1;
            testCase.ready(c, cfg);
            daq = app.getDevice("DAQ");
            wf = daq.wfm_data;
            wf.ao(end+1) = struct("name", 'Ambient', "port", 'Dev1/ao0', "wavefile", 'awfm_constant', ...
                "params", {{1}}, "operation", 'Addition', "concatTime", []);
            daq.wfm_data = wf;
            r = hadamard_stim.apply_controller_action(c, "run_preflight", struct(), c.Revision);
            testCase.verifyFalse(r.state.readiness.can_run);
            r = hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("acknowledged_warnings", string({r.state.readiness.checks.id})), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:HardwareNotReady");
            testCase.verifySubstring(r.message, "already drives Dev1/ao0");
            testCase.verifyEqual(c.RunFolder, "");
        end

        function anAcquisitionInProgressBlocksTheRun(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            cfg.trials.last = 1;
            testCase.ready(c, cfg);
            app.acquisition_active = true;
            r = hadamard_stim.apply_controller_action(c, "start_run", struct(), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:HardwareNotReady");
            testCase.verifySubstring(r.message, "middle of an acquisition");
        end
    end

    methods
        function ready(testCase, c, cfg)
            act = @(a, p) hadamard_stim.apply_controller_action(c, a, p, c.Revision);
            testCase.assertTrue(act("set_config", struct("config", cfg)).ok);
            r = act("prepare_rig", struct());
            testCase.assertTrue(r.ok, r.message);
            use_parity_scans(c, testCase.Root);
            for step = ["acquire_reference_image" "propose_cells" "approve_cells" "acquire_z_reference"]
                r = act(step, struct());
                testCase.assertTrue(r.ok, step + ": " + r.message);
            end
        end
    end
end

function hang_after(ctrl, app, trial)
if ctrl.LastRecord.trial == trial && ~app.LeaveRunning
    app.LeaveRunning = true;
    app.WhileRunning = @(a) abort_once(a, ctrl);
end
end

function abort_once(app, ctrl)
app.WhileRunning = [];
r = hadamard_stim.apply_controller_action(ctrl, "abort", struct(), []);
assert(r.ok, r.message);
end

function changes = config_changes(cfg)
% The tab's edits that turn the default configuration into cfg.
defaults = hadamard_stim.default_config();
changes = struct("path", {}, "value", {});
for f = hadamard_stim.ui.config_fields()'
    v = cfg;
    d = defaults;
    for p = split(f.path, ".")'
        v = v.(p);
        d = d.(p);
    end
    if ~isequal(v, d)
        changes(end+1) = struct("path", f.path, "value", v); %#ok<AGROW>
    end
end
end

function a = strip_paths(a)
a = rmfield(a, "folder");
end

function v = passed_checks()
passed = struct("passed", true, "evidence", "test", "date", "2026-10-14");
v = struct("queue_support", passed, "slide_queue", passed);
end
