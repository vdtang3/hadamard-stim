classdef TestReadinessPolicy < matlab.unittest.TestCase
    %TESTREADINESSPOLICY Scientific uncertainty warns and is recorded; hardware conflicts block.
    %
    %   The policy (Vincent, 2026-10-27 and 10-28): an experimenter may go
    %   ahead after a clear warning about a scientific or data-quality risk;
    %   only what is impossible, undefined, or a conflict over the hardware
    %   refuses. "Not proven" (the slide test never run, failed, or run on
    %   another DMD path) is a warning, while "proven impossible right now"
    %   (the board not open, the live driver without queue support) is a
    %   blocker. Age is shown and never judged.

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
        % ---- DMD commissioning ------------------------------------------

        function onlyTheTwoDmdChecksAreReadiness(testCase)
            % No driver probe and no power-on edge: neither is required,
            % recorded or shown. A missing slide test is a warning; a
            % missing queue-support record is history (the live driver is
            % asked at every preflight).
            gate = hadamard_stim.metadata.hardware_gate(struct("hardware_validation", struct()));
            testCase.verifyEqual(string({gate.items.id}), "firefly_" + ["queue_support" "slide_queue"]);
            testCase.verifyEqual(string({gate.items.status}), ["info" "warning"]);
            testCase.verifyEqual(gate.missing, "slide_queue");
            testCase.verifyEqual(hadamard_stim.metadata.hardware_checks("connectivity"), "slide_queue");
            testCase.verifyEmpty(hadamard_stim.metadata.hardware_checks("spontaneous"));
            report = hadamard_stim.metadata.readiness_report(gate.items);
            testCase.verifyTrue(report.can_run);
            item = gate.items(2);
            testCase.verifySubstring(item.consequence, "not been verified on a slide");
            % Old driver and edge records in the file change nothing.
            old = struct("passed", false, "evidence", "x", "date", "2020-01-01");
            gate = hadamard_stim.metadata.hardware_gate(struct("hardware_validation", ...
                struct("driver", old, "trigger_edge", old)));
            testCase.verifyEqual(string({gate.items.id}), "firefly_" + ["queue_support" "slide_queue"]);
        end

        function theQueueEdgeIsTheProtocolsNotAnOperatorSetting(testCase)
            cfg = hadamard_stim.default_config();
            testCase.verifyEqual(cfg.dmd.trigger_edge, "rising");
            fields = hadamard_stim.ui.config_fields();
            testCase.verifyFalse(ismember("dmd.trigger_edge", [fields.path]));
            testCase.verifyFalse(ismember("dmd.trigger_edge", [fields([fields.required]).path]));
            testCase.verifyTrue(any(contains(hadamard_stim.luminos.firefly_profile().standing_deviations, ...
                "explicitly set to rising")));
            % And every queue of a run is loaded on it.
            [c, app, cfg] = tab_session(testCase.Folder);
            app.getDevice("ALP_DMD").PowerOnEdge = 2008;    % whatever the board started on
            cfg.trials.last = 1;
            run_on_tab(c, cfg);
            queues = app.Acquisitions(arrayfun(@(a) ~isempty(a.queue_settings), app.Acquisitions));
            testCase.assertNotEmpty(queues);
            testCase.verifyEqual(unique(arrayfun(@(a) string(a.queue_settings.trigger_edge), queues)), "rising");
        end

        function aFailedSlideTestIsAProminentWarning(testCase)
            failed = struct("passed", false, "evidence", "9 of 12 triggers.", "date", today_utc());
            gate = hadamard_stim.metadata.hardware_gate(struct("hardware_validation", ...
                struct("slide_queue", failed)));
            item = gate.items(string({gate.items.id}) == "firefly_slide_queue");
            testCase.verifyEqual(item.status, "warning");
            testCase.verifySubstring(item.message, "FAILED");
            testCase.verifySubstring(item.consequence, "NOT playing as the protocol models");
            testCase.verifySubstring(item.consequence, "diagnostic data");
        end

        function aSlideTestIsEvidenceUntilTheDmdPathChanges(testCase)
            % Age is shown only. Another board, another edge, or Luminos's
            % DMD code changed since: a warning. Another Luminos commit with
            % the same DMD code, or one that cannot be compared, and another
            % hadamard-stim commit: a note.
            p = struct("luminos_commit", "aaaaaaaa11", "hadamard_stim_commit", "cccccccc33", "dmd_serial", 7);
            record = struct("passed", true, "evidence", "12 of 12 triggers.", "provenance", p, ...
                "details", struct("trigger_edge", "rising"), "date", ...
                string(datetime("now", "TimeZone", "UTC") - days(400), "yyyy-MM-dd'T'HH:mm:ss'Z'"));
            v = struct("queue_support", record, "slide_queue", record);
            current = struct("luminos_commit", "aaaaaaaa11", "hadamard_commit", "cccccccc33", ...
                "dmd_serial", "7", "trigger_edge", "rising");
            slide = @(current) pick_item(hadamard_stim.metadata.hardware_gate( ...
                struct("hardware_validation", v), "connectivity", current), "firefly_slide_queue");
            item = slide(current);
            testCase.verifyEqual(item.status, "pass");
            testCase.verifySubstring(item.message, "Verified 13 months ago");

            changed = current;
            changed.luminos_commit = "bbbbbbbb22";
            changed.dmd_code_changed = false;
            testCase.verifyEqual(slide(changed).status, "info");
            testCase.verifySubstring(slide(changed).message, "DMD code is the same");
            changed.dmd_code_changed = [];
            testCase.verifyEqual(slide(changed).status, "info");
            changed.dmd_code_changed = true;
            changed.dmd_code_changes = "src/Devices/Patterning/DMD/ALP/ALP_DMD.m";
            item = slide(changed);
            testCase.verifyEqual(item.status, "warning");
            testCase.verifySubstring(item.consequence, "DMD code changed since it was run");
            testCase.verifySubstring(item.consequence, "ALP_DMD.m");

            changed = current;
            changed.hadamard_commit = "dddddddd44";
            testCase.verifyEqual(slide(changed).status, "info");
            changed = current;
            changed.dmd_serial = "8";
            testCase.verifyEqual(slide(changed).status, "warning");
            changed = current;
            changed.trigger_edge = "falling";
            testCase.verifyEqual(slide(changed).status, "warning");
            testCase.verifySubstring(slide(changed).consequence, "run on the rising edge");
            % Queue support is history whatever it says.
            changed.dmd_serial = "8";
            item = pick_item(hadamard_stim.metadata.hardware_gate( ...
                struct("hardware_validation", v), "connectivity", changed), "firefly_queue_support");
            testCase.verifyEqual(item.status, "pass");
        end

        function theDmdCodeComparisonAsksGit(testCase)
            repo = fullfile(testCase.Folder, "luminos");
            dmd = fullfile(repo, "src", "Devices", "Patterning", "DMD", "ALP");
            mkdir(dmd);
            mkdir(fullfile(repo, "src", "Other"));
            git = @(varargin) system(sprintf('git -C "%s" %s', repo, sprintf("%s ", varargin{:})));
            git("init", "-q");
            git("config", "user.email", "t@t", ";", "git", "-C", """" + repo + """", "config", "user.name", "t");
            write_text(fullfile(dmd, "ALP_DMD.m"), "1");
            write_text(fullfile(repo, "src", "Other", "x.m"), "1");
            git("add", "-A", ";", "git", "-C", """" + repo + """", "commit", "-qm", "one");
            [~, first] = system(sprintf('git -C "%s" rev-parse HEAD', repo));
            write_text(fullfile(repo, "src", "Other", "x.m"), "2");
            git("commit", "-qam", "two");
            [~, second] = system(sprintf('git -C "%s" rev-parse HEAD', repo));
            write_text(fullfile(dmd, "ALP_DMD.m"), "2");
            git("commit", "-qam", "three");
            [~, third] = system(sprintf('git -C "%s" rev-parse HEAD', repo));
            [first, second, third] = deal(strip(string(first)), strip(string(second)), strip(string(third)));
            changed = @(a, b) hadamard_stim.luminos.dmd_code_changed(a, b, repo=repo);
            testCase.verifyEqual(changed(first, second), false);
            [tf, files] = changed(second, third);
            testCase.verifyTrue(tf);
            testCase.verifyEqual(files, "src/Devices/Patterning/DMD/ALP/ALP_DMD.m");
            testCase.verifyEmpty(changed(first, "0123456789abcdef"));
            testCase.verifyEmpty(changed("unknown", third));
        end

        function aRecordedCheckKeepsItsProvenance(testCase)
            [~, app] = tab_session(testCase.Folder);
            file = fullfile(testCase.Folder, "checks.json");
            hadamard_stim.checks.record_firefly_check(file, hadamard_stim.checks.queue_support_check(app));
            saved = jsondecode(fileread(file));
            p = saved.queue_support.provenance;
            testCase.verifyNotEmpty(p.hadamard_stim_commit);
            testCase.verifyEqual(p.dmd_serial, 1);
            testCase.verifyTrue(isfield(p, "luminos_commit"));
        end

        function aBoardLuminosCannotOpenBlocksWithoutAnyDriverRecord(testCase)
            % No commissioning record at all is no blocker; the board not
            % open now is, found live.
            [c, app, cfg] = tab_session(testCase.Folder);
            delete(c.Backend.settings().hardware_validation_file);
            c.setConfig(cfg);
            c.runPreflight();
            testCase.verifyTrue(c.Preflight.can_run);
            checks = c.Preflight.checks;
            testCase.verifyEqual(string({checks([checks.status] == "warning").id}), "firefly_slide_queue");
            app.getDevice("ALP_DMD").mexPointer = 0;
            c.runPreflight();
            testCase.verifyFalse(c.Preflight.can_run);
            testCase.verifyEqual(status_of(c, "dmd_board"), "blocker");
        end

        function liveQueueSupportDecidesWhateverTheRecordSays(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            % A failed record, a driver that says yes now: runnable.
            file = c.Backend.settings().hardware_validation_file;
            saved = jsondecode(fileread(file));
            saved.queue_support.passed = false;
            write_text(file, jsonencode(saved));
            c.setConfig(cfg);
            c.runPreflight();
            testCase.verifyTrue(c.Preflight.can_run);
            testCase.verifyEqual(status_of(c, "dmd_queue"), "pass");
            testCase.verifyEqual(status_of(c, "firefly_queue_support"), "info");
            % The driver says no now: connectivity cannot run, whatever was recorded.
            saved.queue_support.passed = true;
            write_text(file, jsonencode(saved));
            app.getDevice("ALP_DMD").SupportsQueue = false;
            c.runPreflight();
            testCase.verifyEqual(status_of(c, "dmd_queue"), "blocker");
            testCase.verifyFalse(c.Preflight.can_run);
            cfg.session.mode = "spontaneous";
            c.setConfig(cfg);
            c.runPreflight();
            testCase.verifyEqual(status_of(c, "dmd_queue"), "not_needed");
            testCase.verifyEqual(status_of(c, "firefly_queue_support"), "not_needed");
        end

        function theTabRunsTheSlideCheckOnTheProtocolsEdge(testCase)
            [c, app, cfg] = tab_session(testCase.Folder, validated=false);
            backend = hadamard_stim.luminos.LuminosBackend(app, blue_threshold=15, ...
                hardware_validation_file=c.Backend.settings().hardware_validation_file, ...
                calibration_movies={uint16(zeros(16, 600, 64))}, ...
                acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition, ...
                slide_queue_frame_means=@(acq) slide_means());
            c = hadamard_stim.HadamardStimController(backend);
            c.setConfig(cfg);
            r = hadamard_stim.apply_controller_action(c, "run_commissioning_check", ...
                struct("name", "slide_queue"), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(app.Acquisitions(end).queue_settings.trigger_edge, "rising");
            % Readiness is read again, so the tab shows the new record.
            testCase.verifyEqual(status_of(c, "firefly_slide_queue"), "pass");
            r = hadamard_stim.apply_controller_action(c, "run_commissioning_check", ...
                struct("name", "driver"), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:NotFromTheTab");
        end

        % ---- Calibrations -----------------------------------------------

        function anOldBlueCalibrationPassesAndAMissingOneBlocks(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            blue = app.getDevice("NI_DAQ_Modulator", "name", "Blue LED 488");
            blue.calibration_info = struct("method", "slide", "units", "counts", "camera", "Kinetix", ...
                "measured_utc", string(datetime("now", "TimeZone", "UTC") - days(200), "yyyy-MM-dd'T'HH:mm:ss'Z'"));
            c.setConfig(cfg);
            c.runPreflight();
            testCase.verifyEqual(status_of(c, "blue_calibration"), "pass");
            testCase.verifyTrue(c.Preflight.can_run);
            % Section 6: with no curve there is no defined blue command
            % (his values are linearised intensities, not volts).
            blue.calibration_curve = [];
            c.runPreflight();
            testCase.verifyEqual(status_of(c, "blue_calibration"), "blocker");
            r = hadamard_stim.apply_controller_action(c, "prepare_rig", struct(), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:RigNotReady");
        end

        function scansAreNeededOnlyByWhatReconstructs(testCase)
            % No scans named: a blocker when drift correction or the
            % z-reference reconstruct, nothing when neither is on.
            [~, app, cfg] = tab_session(testCase.Folder);
            backend = hadamard_stim.luminos.LuminosBackend(app, blue_threshold=15, ...
                hardware_validation_file=fullfile(testCase.Folder, "firefly_checks.json"), ...
                acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition);
            c = hadamard_stim.HadamardStimController(backend);
            c.setConfig(cfg);
            c.runPreflight();
            testCase.verifyEqual(status_of(c, "scan_calibration"), "blocker");
            cfg.z_reference.enabled = false;
            cfg.drift.enabled = false;
            c.setConfig(cfg);
            c.runPreflight();
            testCase.verifyEqual(status_of(c, "scan_calibration"), "not_needed");
            testCase.verifyTrue(c.Preflight.can_run);
        end

        function aDmdCalibrationAtAnotherAreaIsUsedWithAWarning(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            app.getDevice("ALP_DMD").ReferenceRoi = [0 0 512 512];
            c.setConfig(cfg);
            r = hadamard_stim.apply_controller_action(c, "prepare_rig", struct(), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            c.runPreflight();
            testCase.verifyEqual(status_of(c, "dmd_calibration"), "warning");
            % No transform at all blocks preparing.
            app.getDevice("ALP_DMD").CalibratedCamera = "Grasshopper3";
            r = hadamard_stim.apply_controller_action(c, "prepare_rig", struct(), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:RigNotReady");
            testCase.verifySubstring(r.message, "no calibration for Teledyne Kinetix");
        end

        function optionalHardwareOffIsOnlyNoted(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            app.Devices(cellfun(@(d) d.name == "Grasshopper3", app.Devices)) = [];
            cfg.behavior.face_camera_enabled = false;
            cfg.behavior.wheel_encoder_enabled = false;
            c.setConfig(cfg);
            c.runPreflight();
            testCase.verifyTrue(c.Preflight.can_run);
            testCase.verifyEqual(status_of(c, "device_behavior_camera"), "disabled");
            testCase.verifyEqual(status_of(c, "wheel_encoder"), "disabled");
            readiness = c.getState().readiness;
            notes = readiness.checks(string({readiness.checks.id}) == "session_streams");
            testCase.verifyEqual(notes.status, "info");
        end

        % ---- Controller --------------------------------------------------

        function warningsAloneDoNotStopRunAndTheOverrideIsRecordedOnResumeToo(testCase)
            % Commissioning never recorded: warnings. A run starts only with
            % all of them acknowledged; a resume asks again for the rig's
            % warnings (not for the configuration's) and records it.
            [c, cfg, ref] = simulated_session(testCase.Root);
            c.Env.context.simulated = false;
            c.Env.context.hardware_validation = [];
            cfg.trials.last = 2;
            ready(c, cfg, ref);
            readiness = c.getState().readiness;
            testCase.verifyTrue(readiness.can_run);
            testCase.verifyTrue(c.legalActions().start_run);
            ids = string({readiness.warnings.id});
            testCase.verifyEqual(ids, "firefly_slide_queue");
            testCase.verifyError(@() c.startRun(testCase.Folder), "hadamard_stim:WarningsNotAcknowledged");
            testCase.verifyFalse(isfile(fullfile(testCase.Folder, "run_recipe.json")));

            c.StatusChangedFcn = @(ctrl) abort_in(ctrl, 2);
            c.startRun(testCase.Folder, AcknowledgedWarnings=ids, OperatorNote="bring-up");
            c.StatusChangedFcn = [];
            testCase.assertEqual(c.LifecycleState, "ABORTED");
            recipe = hadamard_stim.metadata.read_recipe(testCase.Folder);
            testCase.verifyEqual(string({recipe.start_override.warnings.id}), ids);
            testCase.verifyEqual(recipe.start_override.operator_note, "bring-up");

            testCase.verifyError(@() c.resumeRun(testCase.Folder), "hadamard_stim:WarningsNotAcknowledged");
            r = hadamard_stim.apply_controller_action(c, "resume_run", ...
                struct("acknowledged_warnings", ids), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(c.LifecycleState, "COMPLETED");
            record = jsondecode(fileread(fullfile(testCase.Folder, "resumes", "resume_001.json")));
            testCase.verifyTrue(record.operator_override);
            testCase.verifyEqual(string({record.override.warnings.id}), ids);
            testCase.verifyFalse(record.calibration_changed);
        end

        function aRunWithoutWarningsRecordsNoOverride(testCase)
            [c, cfg, ref] = simulated_session(testCase.Root);
            cfg.trials.last = 1;
            ready(c, cfg, ref);
            testCase.verifyEmpty(c.getState().readiness.warnings);
            c.startRun(testCase.Folder);
            recipe = hadamard_stim.metadata.read_recipe(testCase.Folder);
            testCase.verifyEmpty(recipe.start_override);
        end

        function blockersStopRunWhateverIsAcknowledged(testCase)
            [c, cfg, ref] = simulated_session(testCase.Root);
            cfg.trials.last = 1;
            ready(c, cfg, ref);
            c.Env.hw.readiness = hadamard_stim.metadata.readiness_report( ...
                hadamard_stim.metadata.readiness_item("dmd_ownership", "DMD", "blocker", ...
                message="owned by ""other"""));
            r = hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("run_folder", testCase.Folder, "acknowledged_warnings", "dmd_ownership"), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:HardwareNotReady");
            testCase.verifyFalse(isfile(fullfile(testCase.Folder, "run_recipe.json")));
        end

        function setupGoesAheadWithWarnings(testCase)
            % Preparing and the reference scan are not a run: warnings are
            % shown but need no acknowledgement.
            [c, ~, cfg] = tab_session(testCase.Folder, validated=false);
            c.setConfig(cfg);
            c.runPreflight();
            testCase.verifyNotEmpty(c.getState().readiness.warnings);
            r = hadamard_stim.apply_controller_action(c, "prepare_rig", struct(), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            use_parity_scans(c, testCase.Root);
            r = hadamard_stim.apply_controller_action(c, "acquire_reference_image", struct(), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
        end
    end
end

function t = today_utc()
t = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
end

function item = pick_item(gate, id)
item = gate.items(string({gate.items.id}) == id);
end

function write_text(file, text)
fid = fopen(file, "w");
fwrite(fid, text);
fclose(fid);
end

function run_on_tab(c, cfg)
% Prepare, a reference scan, cells, z-reference and a run, as the tab does.
for step = {{"set_config", struct("config", cfg)}, {"prepare_rig", struct()}}
    r = hadamard_stim.apply_controller_action(c, step{1}{1}, step{1}{2}, c.Revision);
    assert(r.ok, r.message);
end
use_parity_scans(c, fileparts(fileparts(mfilename("fullpath"))));
for step = {{"acquire_reference_image", struct()}, {"propose_cells", struct()}, ...
        {"approve_cells", struct()}, {"acquire_z_reference", struct()}}
    r = hadamard_stim.apply_controller_action(c, step{1}{1}, step{1}{2}, c.Revision);
    assert(r.ok, r.message);
end
warnings = c.getState().readiness.warnings;
r = hadamard_stim.apply_controller_action(c, "start_run", struct("run_folder", ...
    string(tempname), "acknowledged_warnings", string({warnings.id})), c.Revision);
assert(r.ok, r.message);
end

function means = slide_means()
% A uniform slide's frame means for the slide check's queue, as modelled.
shown = hadamard_stim.protocol.alp_queue_display([3 2], [2 3], 16);
offset = [0 3];
picture = 5 * ones(1, 16);
live = shown.sequence > 0;
picture(live) = offset(shown.sequence(live)) + shown.picture(live);
rng(5);
means = 100 + 40 * picture + randn(1, 16);
end

function s = status_of(c, id)
checks = c.Preflight.checks;
s = checks(string({checks.id}) == id).status;
end

function [c, cfg, ref] = simulated_session(root)
[cfg, env, ~, inputs] = parity_environment(fullfile(root, "tests", "fixtures"));
env.context = struct("luminos", struct("commit", "not_applicable", ...
    "branch", "", "dirty", false, "remote", "", "reason", "simulated rig"), ...
    "geometry_identity", env.geometry.identity, ...
    "blue_calibration", struct("identity", "blueCal.mat", "source", "testing"), ...
    "standing_deviations", "simulation: no hardware", "simulated", true);
c = hadamard_stim.HadamardStimController(env);
ref = inputs.ref_im;
end

function ready(c, cfg, ref)
for step = {{"set_config", struct("config", cfg)}, {"set_reference_image", struct("image", ref)}, ...
        {"propose_cells", struct()}, {"approve_cells", struct()}, {"acquire_z_reference", struct()}}
    r = hadamard_stim.apply_controller_action(c, step{1}{1}, step{1}{2}, c.Revision);
    assert(r.ok, r.message);
end
end

function abort_in(ctrl, trial)
if ~isempty(ctrl.Phase) && isfield(ctrl.Phase, "trial") && ctrl.Phase.trial == trial ...
        && ctrl.legalActions().abort
    ctrl.requestAbort();
end
end
