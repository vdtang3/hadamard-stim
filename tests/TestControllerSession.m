classdef TestControllerSession < matlab.unittest.TestCase
    %TESTCONTROLLERSESSION What a frontend sees and can do, on the simulated rig.
    %
    %   The tab drives the controller only through apply_controller_action
    %   and reads it only through getState (and controller_view). These
    %   tests hold that surface to: config edits validated by the package,
    %   refusals that change nothing, the status of a run as it goes,
    %   abort releasing the rig before ABORTED is reported and resuming
    %   from the checkpoint, errors reaching the state, and a state small
    %   enough to poll.

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
        function configEditsGoThroughThePackage(testCase)
            [c, cfg] = testCase.session();
            c.setConfig(cfg);
            act = @(a, p) hadamard_stim.apply_controller_action(c, a, p, c.Revision);
            r = act("update_config", struct("changes", {{ ...
                struct("path", "trials.last", "value", 40), ...
                struct("path", "z_reference.enabled", "value", false), ...
                struct("path", "dmd.trigger_edge", "value", "falling")}}));
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(c.Config.trials.last, 40);
            testCase.verifyEqual(c.Config.z_reference.enabled, false);
            testCase.verifyEqual(c.Config.dmd.trigger_edge, "falling");
            % The package says what changing a protocol setting means.
            testCase.verifyEqual(r.state.mode, "modified");
            testCase.verifyEqual(string({r.state.deviations.path}), "z_reference.enabled");

            % A required setting cleared from the tab is reported, not invented.
            r = act("update_config", struct("changes", struct("path", "segmentation.n_exclude", "value", [])));
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(r.state.config_errors, "segmentation.n_exclude is not set.");

            % Refused, and nothing changes: an unlisted path, a bad value.
            before = c.Config;
            r = act("update_config", struct("changes", struct("path", "daq.rate", "value", 1)));
            testCase.verifyEqual(r.status, "failed");
            testCase.verifyEqual(r.identifier, "hadamard_stim:NotEditable");
            r = act("update_config", struct("changes", [struct("path", "trials.last", "value", 3), ...
                struct("path", "trials.first", "value", 1.5)]));
            testCase.verifyEqual(r.identifier, "hadamard_stim:InvalidValue");
            r = act("update_config", struct("changes", struct("path", "dmd.trigger_edge", "value", "both")));
            testCase.verifyEqual(r.identifier, "hadamard_stim:InvalidValue");
            testCase.verifyEqual(c.Config, before);
        end

        function everyLegalActionIsAnAction(testCase)
            c = testCase.session();
            legal = string(fieldnames(c.legalActions()))';
            for action = legal
                r = hadamard_stim.apply_controller_action(c, action, struct(), c.Revision);
                testCase.verifyNotEqual(r.status, "unknown_action", action);
            end
        end

        function aSessionWithoutABackendRefusesRigActions(testCase)
            c = testCase.session();
            for action = ["run_preflight" "prepare_rig" "set_rig_settings"]
                r = hadamard_stim.apply_controller_action(c, action, struct(), c.Revision);
                testCase.verifyEqual(r.status, "not_legal", action);
            end
            v = hadamard_stim.controller_view(c, "diagnostics");
            testCase.verifyFalse(v.ok);
            testCase.verifySubstring(v.message, "no rig backend");
        end

        function theStatusFollowsTheProtocol(testCase)
            [c, cfg, ref] = testCase.session();
            cfg.trials.last = 4;
            seen = strings(0, 1);
            c.StatusChangedFcn = @(ctrl) record(ctrl);
            testCase.ready(c, cfg, ref);
            hadamard_stim.apply_controller_action(c, "start_run", struct("run_folder", testCase.Folder), c.Revision);
            testCase.verifyEqual(c.getState().status, "complete");
            % Trial 1 retargets, trials 1-3 are sparse and trial 4 is Hadamard.
            testCase.verifyEqual(unique(seen(startsWith(seen, "running:")), "stable"), ...
                ["running:running"; "running:drift_correction"; "running:sparse_pulse"; "running:hadamard_trial"]);
            testCase.verifyTrue(any(seen == "z_reference:z_reference"));
            testCase.verifyTrue(any(seen == "segmenting:segmenting"));

            function record(ctrl)
                s = ctrl.getState();
                seen(end+1, 1) = ctrl.Activity + ":" + s.status;
            end
        end

        function abortReleasesTheRigThenResumes(testCase)
            [c, cfg, ref] = testCase.session();
            cfg.trials.last = 4;
            testCase.ready(c, cfg, ref);
            hw = c.Env.hw;
            observed = struct("status", {}, "releases", {});
            % The tab's Abort arrives as an interrupt while trial 2 runs.
            c.StatusChangedFcn = @(ctrl) on_status(ctrl);
            r = hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("run_folder", testCase.Folder), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(c.LifecycleState, "ABORTED");
            testCase.verifyEqual(r.state.status, "aborted");
            testCase.verifyEqual(r.state.last_error_identifier, "hadamard_stim:Aborted");
            testCase.verifyTrue(r.state.cleanup.ok);
            % Released before ABORTED was first reported.
            first = find([observed.status] == "aborted", 1);
            testCase.verifyEqual(observed(first).releases, hw.releases);
            testCase.verifyGreaterThan(observed(first).releases, observed(first - 1).releases);
            % Trial 2 was abandoned: the checkpoint is after trial 1.
            testCase.verifyEqual(c.RunState.next_trial, 2);
            testCase.verifyEqual(numel(dir(fullfile(testCase.Folder, "trials", "*.json"))), 1);
            v = hadamard_stim.controller_view(c, "checkpoint");
            testCase.verifyEqual(v.data.next_trial, 2);

            c.StatusChangedFcn = [];
            r = hadamard_stim.apply_controller_action(c, "resume_run", struct(), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(c.LifecycleState, "COMPLETED");
            testCase.verifyEqual(numel(dir(fullfile(testCase.Folder, "trials", "*.json"))), 4);

            function on_status(ctrl)
                observed(end+1) = struct("status", ctrl.getState().status, "releases", hw.releases);
                if ~isempty(ctrl.Phase) && isfield(ctrl.Phase, "trial") && ctrl.Phase.trial == 2 ...
                        && ctrl.legalActions().abort
                    hadamard_stim.apply_controller_action(ctrl, "abort", struct(), []);
                end
            end
        end

        function anAbortedRunMatchesAnUninterruptedOne(testCase)
            % Resuming after an abort continues exactly: same records as a
            % run that was never interrupted.
            [c1, cfg, ref] = testCase.session();
            cfg.trials.last = 5;
            testCase.ready(c1, cfg, ref);
            c1.startRun(testCase.Folder);
            straight = trial_records(testCase.Folder);
            testCase.assertNumElements(straight, 5);

            other = string(tempname);
            testCase.addTeardown(@() rmdir_if(other));
            [c2, ~, ~] = testCase.session();
            testCase.ready(c2, cfg, ref);
            c2.StatusChangedFcn = @(ctrl) abort_in(ctrl, 3);
            c2.startRun(other);
            testCase.verifyEqual(c2.LifecycleState, "ABORTED");
            c2.StatusChangedFcn = [];
            c2.resumeRun(other);
            testCase.verifyEqual(trial_records(other), straight);
        end

        function errorsReachTheState(testCase)
            [c, cfg, ref] = testCase.session();
            cfg.trials.last = 3;
            testCase.ready(c, cfg, ref);
            c.Env.hw.before_operation = @(op) fail_on(op, "dmd_load_queue");
            r = hadamard_stim.apply_controller_action(c, "start_run", ...
                struct("run_folder", testCase.Folder), c.Revision);
            testCase.verifyEqual(r.status, "failed");
            testCase.verifyEqual(r.state.status, "error");
            testCase.verifyEqual(r.state.last_error, "simulated DMD failure");
            testCase.verifyEqual(r.state.last_error_identifier, "test:dmd");
            testCase.verifyTrue(r.state.cleanup.ok);
            testCase.verifyTrue(r.state.legal_actions.resume_run);
            % A failure outside a run is reported the same way.
            c2 = testCase.session();
            c2.setConfig(cfg);
            r = hadamard_stim.apply_controller_action(c2, "propose_cells", struct(), c2.Revision);
            testCase.verifyEqual(r.status, "not_legal");
        end

        function theStateIsSmallAndCarriesNoBulkData(testCase)
            [c, cfg, ref] = testCase.session();
            cfg.trials.last = 4;
            testCase.ready(c, cfg, ref);
            c.startRun(testCase.Folder);
            state = c.getState();
            text = jsonencode(state);
            testCase.verifyLessThan(strlength(text), 64e3);
            % Nothing per pixel, per sample or per trial: the largest
            % array is the proposal's cell coordinates.
            testCase.verifyLessThanOrEqual(largest_array(state), 2 * cfg.matrix.order);
            for name = ["waveform" "image" "illum_mask" "stim_mask" "pictures" "had_mat" "picked" "acquisitions"]
                testCase.verifyFalse(contains(text, """" + name + """:"), name);
            end
        end

        function aReferenceScanSetsTheReferenceImage(testCase)
            [c, cfg, ref] = testCase.session();
            c.Env.hw.world.scan_image = @(rig, acq) reference_or_drift(acq, ref);
            c.setConfig(cfg);
            r = hadamard_stim.apply_controller_action(c, "acquire_reference_image", struct(), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(c.ReferenceImage, ref);
            testCase.verifyEqual(r.state.reference.source, "scan");
            acq = c.Env.hw.acquisitions(end);
            testCase.verifyEqual(acq.kind, "reference_scan");
            testCase.verifyEqual([acq.camera_exposure_ms acq.waveform_period_ms acq.orange_v acq.blue_v], ...
                [cfg.scan.camera_exposure_ms cfg.scan.waveform_period_ms cfg.scan.orange_v 0]);
            testCase.verifyEqual(c.Env.hw.moves, zeros(0, 2));
            testCase.verifyEqual(c.Env.hw.releases, 1);
            r = hadamard_stim.apply_controller_action(c, "propose_cells", struct(), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
        end

        function aNewSessionStartsAgainButKeepsTheConfiguration(testCase)
            [c, cfg, ref] = testCase.session();
            cfg.trials.last = 1;
            testCase.ready(c, cfg, ref);
            c.startRun(testCase.Folder);
            r = hadamard_stim.apply_controller_action(c, "new_session", struct(), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(r.state.lifecycle, "CONFIGURING");
            testCase.verifyFalse(r.state.has_reference_image);
            testCase.verifyEqual(r.state.run_folder, "");
            testCase.verifyEqual(c.Config, cfg);
        end
    end

    methods
        function [c, cfg, ref] = session(testCase)
            fixtures = fullfile(testCase.Root, "tests", "fixtures");
            [cfg, env, ~, inputs] = parity_environment(fixtures);
            env.context = struct("luminos", struct("commit", "not_applicable", ...
                "branch", "", "dirty", false, "remote", "", "reason", "simulated rig"), ...
                "geometry_identity", env.geometry.identity, ...
                "blue_calibration", struct("identity", "blueCal.mat", "source", "testing"), ...
                "standing_deviations", "simulation: no hardware", "simulated", true);
            c = hadamard_stim.HadamardStimController(env);
            ref = inputs.ref_im;
        end

        function ready(~, c, cfg, ref)
            for step = {{"set_config", struct("config", cfg)}, {"set_reference_image", struct("image", ref)}, ...
                    {"propose_cells", struct()}, {"approve_cells", struct()}, {"acquire_z_reference", struct()}}
                r = hadamard_stim.apply_controller_action(c, step{1}{1}, step{1}{2}, c.Revision);
                assert(r.ok, r.message);
            end
        end
    end
end

function abort_in(ctrl, trial)
if ~isempty(ctrl.Phase) && isfield(ctrl.Phase, "trial") && ctrl.Phase.trial == trial ...
        && ctrl.legalActions().abort
    ctrl.requestAbort();
end
end

function fail_on(op, which)
if op == which
    error("test:dmd", "simulated DMD failure");
end
end

function im = reference_or_drift(acq, ref)
im = [];
if acq.kind == "reference_scan"
    im = ref;
end
end

function records = trial_records(folder)
% The trial records, without what legitimately differs between runs.
records = {};
for f = dir(fullfile(folder, "trials", "trial_*.json"))'
    r = jsondecode(fileread(fullfile(f.folder, f.name)));
    r = rmfield(r, intersect(fieldnames(r), ["started_utc" "written_utc" "recipe_hash"]));
    if isfield(r, "acquisition") && isstruct(r.acquisition)
        r.acquisition = rmfield(r.acquisition, intersect(fieldnames(r.acquisition), ...
            ["index" "luminos_folder"]));
    end
    records{end+1} = r; %#ok<AGROW>
end
end

function n = largest_array(value)
n = 0;
if isstruct(value)
    for k = 1:numel(value)
        for name = string(fieldnames(value))'
            n = max(n, largest_array(value(k).(name)));
        end
    end
elseif iscell(value)
    for k = 1:numel(value)
        n = max(n, largest_array(value{k}));
    end
elseif isnumeric(value) || islogical(value) || isstring(value)
    n = numel(value);
end
end

function rmdir_if(folder)
if isfolder(folder)
    rmdir(folder, "s");
end
end
