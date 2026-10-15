classdef HadamardStimController < handle
    %HADAMARDSTIMCONTROLLER One Hadamard stimulation session: setup, then a run.
    %
    %   c = hadamard_stim.HadamardStimController(env)
    %   c = hadamard_stim.HadamardStimController(backend)
    %
    %   env is what the protocol runs on (see hadamard_stim.protocol.run_protocol)
    %   plus, for the records:
    %     env.context   luminos provenance, geometry and blue calibration
    %                   identities, standing deviations (build_recipe)
    %   backend (hadamard_stim.backend_interface; the Luminos tab's form)
    %   builds that env when the operator prepares the rig, and answers
    %   preflight and diagnostics before then.
    %
    %   The session follows his order of work, one step at a time:
    %     CONFIGURING      edit the configuration; prepare the rig; take or
    %                      set the reference image
    %     CELLS_PROPOSED   segmentation run on the reference image; look at
    %                      the cells and min_val, then approve or re-run
    %     CELLS_APPROVED   the canonical geometry is fixed from here on
    %     READY            reference z-stack acquired; a run can start
    %     RUNNING          trials in progress (stop takes effect between
    %                      trials; abort abandons the trial in progress)
    %     STOPPED / COMPLETED / FAILED / ABORTED
    %   A stopped, failed or aborted run resumes from its folder's checkpoint.
    %   The rig is released before any of those last four is reported.
    %
    %   Everything a frontend may do goes through apply_controller_action;
    %   getState is what it shows, and controller_view the larger read-only
    %   products (images, the recipe, a checkpoint).

    properties (SetAccess = private)
        Revision (1, 1) double = 0
        LifecycleState (1, 1) string = "CONFIGURING"
        Config struct
        Proposal = []          % cells from the last segmentation, not yet approved
        Cells = []             % approved canonical cells
        ReferenceImage = []    % the Hadamard image the cells are found on
        ReferenceRevision (1, 1) double = 0
        ReferenceSource struct = struct("kind", "", "folder", "")
        Reference = []         % z-stack reference (run_z_reference) plus had_ref
        RunFolder (1, 1) string = ""
        RecipeHash (1, 1) string = ""
        RunState = []
        LastRecord = []
        LastError (1, 1) string = ""
        LastErrorIdentifier (1, 1) string = ""
        StopRequested (1, 1) logical = false
        AbortRequested (1, 1) logical = false
        Backend = []           % hadamard_stim.backend_interface, or [] when given an env
        Preflight = []         % the last preflight report
        Prepared = []          % when and for what the env was built from the backend
        Activity (1, 1) string = ""   % the long operation in progress, if any
        Phase = []             % which part of the protocol is running (report_phase)
        LastCleanup = []       % the rig's report from the last release
        LastResume = []        % the last resume's record (write_resume_record)
        RunStarted = NaT
        RunEnded = NaT
    end

    properties
        Env struct
        % Called with the controller after every trial; the Luminos device
        % pushes progress to the tab from here.
        ProgressChangedFcn = []
        % Called with the controller whenever a long operation starts,
        % moves to another phase, or ends.
        StatusChangedFcn = []
    end

    properties (Access = private)
        HardwareHeld (1, 1) logical = false
    end

    methods
        function obj = HadamardStimController(source)
            if isstruct(source)
                obj.Env = source;
            else
                obj.Backend = source;
                obj.Env = struct();
            end
            obj.Config = hadamard_stim.default_config();
        end

        % ---- Setup ------------------------------------------------------

        function setConfig(obj, cfg)
            obj.assertIdle(["CONFIGURING" "CELLS_PROPOSED" "CELLS_APPROVED" "READY"]);
            obj.Config = cfg;
            obj.bump();
        end

        function updateConfig(obj, changes)
            % changes: struct array of path/value, only the fields
            % hadamard_stim.ui.config_fields lists.
            obj.setConfig(hadamard_stim.ui.apply_config_changes(obj.Config, changes));
        end

        function setRigSettings(obj, changes)
            obj.requireBackend();
            obj.assertIdle(["CONFIGURING" "CELLS_PROPOSED"]);
            obj.Backend.set_settings(changes);
            % The environment was built with the old settings.
            obj.Env = struct();
            obj.Prepared = [];
            obj.Preflight = [];
            obj.Proposal = [];
            obj.LifecycleState = "CONFIGURING";
            obj.bump();
        end

        function runPreflight(obj)
            % Read only: nothing on the rig or in the session changes except
            % the stored report.
            obj.requireBackend();
            if obj.LifecycleState == "RUNNING" || obj.Activity ~= ""
                error("hadamard_stim:NotLegal", "Not possible while %s.", lower(obj.LifecycleState));
            end
            obj.during("preflight", @() obj.preflightBody());
        end

        function prepareRig(obj)
            % Build the environment from the backend: calibrations, geometry
            % and the LuminosRig a run will use.
            obj.requireBackend();
            obj.assertIdle(["CONFIGURING" "CELLS_PROPOSED"]);
            obj.during("preparing", @() obj.prepareBody());
        end

        function acquireReferenceImage(obj)
            obj.assertIdle(["CONFIGURING" "CELLS_PROPOSED"]);
            obj.requireEnvironment();
            obj.during("scanning", @() obj.referenceBody());
        end

        function setReferenceImage(obj, im)
            obj.assertIdle(["CONFIGURING" "CELLS_PROPOSED"]);
            obj.adoptReferenceImage(im, struct("kind", "provided", "folder", ""));
        end

        function proposeCells(obj)
            obj.assertIdle(["CONFIGURING" "CELLS_PROPOSED"]);
            if isempty(obj.ReferenceImage)
                error("hadamard_stim:NoReferenceImage", "Set the reference image before segmenting.");
            end
            obj.requireEnvironment();
            obj.during("segmenting", @() obj.segmentBody());
        end

        function approveCells(obj)
            obj.assertIdle("CELLS_PROPOSED");
            obj.Cells = obj.Proposal;
            obj.LifecycleState = "CELLS_APPROVED";
            obj.bump();
        end

        function acquireZReference(obj)
            obj.assertIdle(["CELLS_APPROVED" "READY"]);
            obj.requireEnvironment();
            obj.during("z_reference", @() obj.zReferenceBody());
        end

        function newSession(obj)
            % Start again on a new field of view; the configuration and the
            % prepared rig are kept.
            if ismember(obj.LifecycleState, ["CONFIGURING" "RUNNING"]) || obj.Activity ~= ""
                error("hadamard_stim:NotLegal", "Not possible while the session is %s.", obj.LifecycleState);
            end
            obj.Proposal = [];
            obj.Cells = [];
            obj.ReferenceImage = [];
            obj.ReferenceRevision = obj.ReferenceRevision + 1;
            obj.ReferenceSource = struct("kind", "", "folder", "");
            obj.Reference = [];
            obj.RunFolder = "";
            obj.RecipeHash = "";
            obj.RunState = [];
            obj.LastRecord = [];
            obj.LastError = "";
            obj.LastErrorIdentifier = "";
            obj.LastCleanup = [];
            obj.LastResume = [];
            obj.RunStarted = NaT;
            obj.RunEnded = NaT;
            obj.LifecycleState = "CONFIGURING";
            obj.bump();
        end

        % ---- Running ----------------------------------------------------

        function startRun(obj, run_folder)
            arguments
                obj
                run_folder (1, 1) string = ""
            end
            obj.assertIdle("READY");
            report = hadamard_stim.validate_config(obj.Config);
            if ~report.ok
                error("hadamard_stim:InvalidConfig", "The configuration cannot run:\n  %s", ...
                    strjoin(report.errors, newline + "  "));
            end
            obj.assertHardwareValidated();
            if strlength(run_folder) == 0
                obj.requireBackend();
                run_folder = obj.Backend.default_run_folder(obj.Config);
            end
            state = hadamard_stim.protocol.new_run_state(obj.Config, obj.Cells, obj.Reference);
            % Checked before the run folder exists, so a refused run leaves nothing.
            session = obj.beginHardware(); %#ok<NASGU>
            [recipe, arrays] = hadamard_stim.metadata.build_recipe(obj.Config, state, obj.Env.context);
            hadamard_stim.metadata.write_recipe(run_folder, recipe, arrays);
            obj.RunFolder = run_folder;
            obj.RecipeHash = recipe.recipe_hash;
            hadamard_stim.metadata.save_checkpoint(run_folder, state, recipe.recipe_hash);
            obj.run(state);
        end

        function resumeRun(obj, run_folder, options)
            % Continue a run from its checkpoint. If the blue or DMD
            % calibration prepared now differs from the one the run
            % recorded, the resume stops with hadamard_stim:CalibrationChanged
            % (both identities and the consequence in its message) unless
            % ContinueWithChangedCalibration is true; the override is
            % recorded in the run's resumes/ folder.
            arguments
                obj
                run_folder (1, 1) string = ""
                options.ContinueWithChangedCalibration (1, 1) logical = false
            end
            obj.assertIdle(["CONFIGURING" "READY" "STOPPED" "FAILED" "ABORTED"]);
            obj.requireEnvironment();
            if strlength(run_folder) == 0
                run_folder = obj.RunFolder;
            end
            if strlength(run_folder) == 0
                error("hadamard_stim:NoRunFolder", "Name the run folder to resume.");
            end
            obj.assertHardwareValidated();
            [recipe, ~] = hadamard_stim.metadata.read_recipe(run_folder);
            state = hadamard_stim.metadata.load_checkpoint(run_folder);
            comparison = hadamard_stim.metadata.calibration_comparison(recipe, obj.Env.context);
            if comparison.changed && ~options.ContinueWithChangedCalibration
                error("hadamard_stim:CalibrationChanged", "%s", calibration_change_message(comparison));
            end
            obj.Config = recipe.config;
            session = obj.beginHardware(); %#ok<NASGU>
            file = hadamard_stim.metadata.write_resume_record(run_folder, recipe.recipe_hash, ...
                state.next_trial, comparison, options.ContinueWithChangedCalibration);
            obj.LastResume = struct("record", string(file), "next_trial", state.next_trial, ...
                "calibration_changed", comparison.changed, ...
                "continued_with_changed_calibration", comparison.changed && options.ContinueWithChangedCalibration);
            obj.Cells = state.cells.canonical;
            obj.Reference = state.reference;
            obj.RunFolder = run_folder;
            obj.RecipeHash = recipe.recipe_hash;
            obj.run(state);
        end

        function requestStop(obj)
            if obj.LifecycleState ~= "RUNNING"
                error("hadamard_stim:NotRunning", "No run is in progress.");
            end
            obj.StopRequested = true;
            obj.bump();
            obj.notifyStatus();
        end

        function requestAbort(obj)
            % Abandon what the rig is doing now. The trial in progress is not
            % recorded, so a resume repeats it from the last checkpoint.
            if ~ismember(obj.Activity, ["running" "z_reference" "scanning"])
                error("hadamard_stim:NotRunning", "Nothing is running on the rig.");
            end
            obj.AbortRequested = true;
            obj.StopRequested = true;
            obj.Env.hw.abort();
            obj.bump();
            obj.notifyStatus();
        end

        % ---- Reporting --------------------------------------------------

        function state = getState(obj)
            % Small and JSON-safe: what a frontend shows. Images, masks,
            % waveforms, queues, trial records and checkpoints are left out;
            % hadamard_stim.controller_view returns those that can be shown.
            state.revision = obj.Revision;
            state.lifecycle = obj.LifecycleState;
            state.status = obj.statusWord();
            state.activity = obj.Activity;
            state.phase = obj.Phase;
            state.legal_actions = obj.legalActions();
            report = hadamard_stim.validate_config(obj.Config);
            state.config = obj.Config;
            state.config_sha256 = hadamard_stim.metadata.sha256(unicode2native(jsonencode(obj.Config), "UTF-8"));
            state.config_errors = report.errors;
            state.mode = report.mode;
            state.deviations = report.deviations;
            state.has_reference_image = ~isempty(obj.ReferenceImage);
            state.reference = struct("revision", obj.ReferenceRevision, ...
                "size", size(obj.ReferenceImage), "source", obj.ReferenceSource.kind, ...
                "folder", obj.ReferenceSource.folder);
            state.proposal = [];
            if ~isempty(obj.Proposal)
                state.proposal = struct("n_cells", size(obj.Proposal.cell_coord, 1), ...
                    "cell_coord", obj.Proposal.cell_coord, "min_val", obj.Proposal.min_val);
            end
            state.n_approved_cells = 0;
            if ~isempty(obj.Cells)
                state.n_approved_cells = size(obj.Cells.cell_coord, 1);
            end
            state.run_folder = obj.RunFolder;
            state.recipe_hash = obj.RecipeHash;
            state.progress = [];
            if ~isempty(obj.RunState)
                s = obj.RunState;
                state.progress = struct("next_trial", s.next_trial, ...
                    "first_trial", obj.Config.trials.first, ...
                    "last_trial", obj.Config.trials.last, "orange_v", s.orange_v, ...
                    "n_corrections", numel(s.cells.corrections), ...
                    "stop_requested", obj.StopRequested, ...
                    "abort_requested", obj.AbortRequested);
            end
            state.timing = struct("run_started_utc", utc_text(obj.RunStarted), ...
                "run_ended_utc", utc_text(obj.RunEnded), "elapsed_s", obj.elapsedSeconds());
            state.last_trial = [];
            if ~isempty(obj.LastRecord)
                r = obj.LastRecord;
                state.last_trial = struct("trial", r.trial, "kind", r.kind, ...
                    "folder", r.folder, "skipped", r.skipped, "retarget", r.retarget, ...
                    "started_utc", r.started_utc);
            end
            state.last_error = obj.LastError;
            state.last_error_identifier = obj.LastErrorIdentifier;
            state.cleanup = obj.LastCleanup;
            state.last_resume = obj.LastResume;
            state.backend = struct("available", ~isempty(obj.Backend), "settings", []);
            if ~isempty(obj.Backend)
                state.backend.settings = obj.Backend.settings();
            end
            state.environment = obj.environmentSummary();
            state.preflight = obj.Preflight;
            state.calibration = obj.calibrationStatus();
        end

        function legal = legalActions(obj)
            s = obj.LifecycleState;
            idle = s ~= "RUNNING" && obj.Activity == "";
            backend = ~isempty(obj.Backend);
            env = obj.hasEnvironment();
            editable = idle && ismember(s, ["CONFIGURING" "CELLS_PROPOSED" "CELLS_APPROVED" "READY"]);
            early = idle && ismember(s, ["CONFIGURING" "CELLS_PROPOSED"]);
            legal.set_config = editable;
            legal.update_config = editable;
            legal.set_rig_settings = backend && early;
            legal.run_preflight = backend && idle;
            legal.prepare_rig = backend && early;
            legal.acquire_reference_image = env && early;
            legal.set_reference_image = early;
            legal.propose_cells = early && env && ~isempty(obj.ReferenceImage);
            legal.approve_cells = idle && s == "CELLS_PROPOSED";
            legal.acquire_z_reference = idle && env && ismember(s, ["CELLS_APPROVED" "READY"]);
            legal.start_run = idle && s == "READY";
            legal.resume_run = idle && env && ismember(s, ["CONFIGURING" "READY" "STOPPED" "FAILED" "ABORTED"]);
            legal.stop_after_current = s == "RUNNING" && ~obj.StopRequested;
            legal.abort = ismember(obj.Activity, ["running" "z_reference" "scanning"]) && ~obj.AbortRequested;
            legal.new_session = idle && ~ismember(s, ["CONFIGURING" "RUNNING"]);
        end

        function tf = hasEnvironment(obj)
            tf = isfield(obj.Env, "hw") && ~isempty(obj.Env.hw);
        end
    end

    methods (Access = private)
        function run(obj, state)
            obj.LifecycleState = "RUNNING";
            obj.Activity = "running";
            obj.StopRequested = false;
            obj.LastError = "";
            obj.LastErrorIdentifier = "";
            obj.RunState = state;
            obj.RunStarted = datetime("now", "TimeZone", "UTC");
            obj.RunEnded = NaT;
            obj.bump();
            obj.notifyStatus();
            env = obj.observedEnv();
            env.after_trial = @(s, r) obj.afterTrial(s, r);
            env.stop_requested = @() obj.StopRequested;
            failure = [];
            try
                state = hadamard_stim.protocol.run_protocol(obj.Config, env, state);
                obj.RunState = state;
            catch err
                failure = err;
            end
            % The rig is restored before the outcome is reported.
            obj.Phase = [];
            obj.releaseHardware();
            obj.RunEnded = datetime("now", "TimeZone", "UTC");
            if obj.AbortRequested
                obj.LifecycleState = "ABORTED";
                obj.LastError = sprintf(['Aborted by the operator; the rig has been released. ' ...
                    'The run resumes at trial %d from its checkpoint.'], obj.RunState.next_trial);
                obj.LastErrorIdentifier = "hadamard_stim:Aborted";
            elseif ~isempty(failure)
                obj.LifecycleState = "FAILED";
                obj.LastError = string(failure.message);
                obj.LastErrorIdentifier = string(failure.identifier);
            elseif state.next_trial > obj.Config.trials.last
                obj.LifecycleState = "COMPLETED";
            else
                obj.LifecycleState = "STOPPED";
            end
            obj.Activity = "";
            obj.bump();
            obj.notifyStatus();
            if ~isempty(failure) && ~obj.AbortRequested
                rethrow(failure);
            end
        end

        function afterTrial(obj, state, record)
            % Record first, then checkpoint: a checkpoint never points past
            % a trial whose record is missing.
            hadamard_stim.metadata.write_trial_record(obj.RunFolder, record, obj.RecipeHash);
            hadamard_stim.metadata.save_checkpoint(obj.RunFolder, state, obj.RecipeHash);
            obj.RunState = state;
            obj.LastRecord = record;
            obj.bump();
            if ~isempty(obj.ProgressChangedFcn)
                obj.ProgressChangedFcn(obj);
            end
        end

        % ---- Long operations ----------------------------------------------

        function during(obj, activity, body)
            % Run body as the named activity: shown while it lasts, any error
            % kept in the state, the activity cleared however it ends.
            obj.Activity = activity;
            obj.AbortRequested = false;
            obj.LastError = "";
            obj.LastErrorIdentifier = "";
            obj.bump();
            obj.notifyStatus();
            finish = onCleanup(@() obj.endActivity()); %#ok<NASGU>
            try
                body();
            catch err
                obj.LastError = string(err.message);
                obj.LastErrorIdentifier = string(err.identifier);
                if obj.AbortRequested
                    obj.LastError = "Aborted by the operator during " + strrep(activity, "_", " ") + ...
                        "; the rig has been released.";
                    obj.LastErrorIdentifier = "hadamard_stim:Aborted";
                end
                rethrow(err);
            end
        end

        function endActivity(obj)
            obj.Activity = "";
            obj.Phase = [];
            obj.bump();
            obj.notifyStatus();
        end

        function preflightBody(obj)
            report = obj.Backend.preflight(obj.Config);
            config = hadamard_stim.validate_config(obj.Config);
            first = struct("id", "config", "label", "The configuration is complete", ...
                "status", "pass", "message", "");
            if ~config.ok
                first.status = "fail";
                first.message = strjoin(config.errors, " ");
            end
            checks = [first, reshape(report.checks, 1, [])];
            failed = checks([checks.status] == "fail");
            obj.Preflight = struct("ok", isempty(failed), "checked_utc", utc_text(datetime("now", "TimeZone", "UTC")), ...
                "config_sha256", hadamard_stim.metadata.sha256(unicode2native(jsonencode(obj.Config), "UTF-8")), ...
                "checks", checks, "calibration", report.calibration);
        end

        function prepareBody(obj)
            env = obj.Backend.environment(obj.Config);
            obj.Env = env;
            obj.Prepared = struct("utc", utc_text(datetime("now", "TimeZone", "UTC")), ...
                "m_q", obj.Config.scan.m_q);
            % Cells proposed with the old geometry are not this rig's.
            obj.Proposal = [];
            obj.LifecycleState = "CONFIGURING";
        end

        function referenceBody(obj)
            session = obj.beginHardware(); %#ok<NASGU>
            [im, acq] = hadamard_stim.protocol.acquire_reference_image(obj.Config, obj.observedEnv());
            obj.releaseHardware();
            if isempty(im)
                error("hadamard_stim:NoReferenceImage", ...
                    "The reference scan reconstructed to no image; nothing was changed.");
            end
            folder = "";
            if isfield(acq, "luminos_folder")
                folder = string(acq.luminos_folder);
            end
            obj.adoptReferenceImage(im, struct("kind", "scan", "folder", folder));
        end

        function segmentBody(obj)
            obj.Proposal = hadamard_stim.protocol.segment_cells(obj.Config, ...
                obj.ReferenceImage, obj.Env.geometry);
            obj.LifecycleState = "CELLS_PROPOSED";
        end

        function zReferenceBody(obj)
            obj.requirePreparedScan();
            session = obj.beginHardware(); %#ok<NASGU>
            reference = hadamard_stim.protocol.run_z_reference(obj.Config, obj.observedEnv());
            obj.releaseHardware();
            reference.had_ref = obj.ReferenceImage;
            obj.Reference = reference;
            obj.LifecycleState = "READY";
        end

        function adoptReferenceImage(obj, im, source)
            obj.ReferenceImage = im;
            obj.ReferenceRevision = obj.ReferenceRevision + 1;
            obj.ReferenceSource = source;
            obj.Proposal = [];
            obj.LifecycleState = "CONFIGURING";
            obj.bump();
        end

        function env = observedEnv(obj)
            env = obj.Env;
            env.phase_changed = @(phase) obj.onPhase(phase);
        end

        function onPhase(obj, phase)
            phase.started_utc = utc_text(datetime("now", "TimeZone", "UTC"));
            obj.Phase = phase;
            obj.bump();
            obj.notifyStatus();
        end

        function notifyStatus(obj)
            if ~isempty(obj.StatusChangedFcn)
                obj.StatusChangedFcn(obj);
            end
        end

        % ---- Hardware sessions --------------------------------------------

        function assertHardwareValidated(obj)
            gate = hadamard_stim.metadata.hardware_gate(obj.Env.context);
            if ~gate.ok
                error("hadamard_stim:HardwareNotValidated", ...
                    ['Firefly has not passed the checks a real acquisition needs: %s. ' ...
                     'Run them (docs/notebook.md, Phase 2 rig checks) and record the results.'], ...
                    strjoin(gate.missing, ", "));
            end
        end

        function session = beginHardware(obj)
            % One session of hardware use: refuse if the rig cannot run this
            % configuration, otherwise return a guard that releases the rig
            % however the caller exits. Callers that report an outcome
            % release first (releaseHardware), which makes the guard a no-op.
            obj.AbortRequested = false;
            report = obj.Env.hw.begin(obj.Config);
            obj.HardwareHeld = true;
            session = onCleanup(@() obj.releaseHardware());
            if ~report.ok
                error("hadamard_stim:HardwareNotReady", ...
                    "The rig cannot run this configuration:\n  %s", ...
                    strjoin(report.failures, newline + "  "));
            end
        end

        function releaseHardware(obj)
            if ~obj.HardwareHeld
                return
            end
            obj.HardwareHeld = false;
            try
                report = obj.Env.hw.release();
            catch err
                report = struct("steps", strings(0, 1), "errors", string(err.message), "ok", false);
            end
            obj.LastCleanup = struct("ok", report.ok, "released_utc", utc_text(datetime("now", "TimeZone", "UTC")), ...
                "steps", reshape(string(report.steps), [], 1), ...
                "errors", reshape(string(report.errors), [], 1));
        end

        % ---- Checks -------------------------------------------------------

        function requireBackend(obj)
            if isempty(obj.Backend)
                error("hadamard_stim:NoBackend", ...
                    "This session was given its environment directly; there is no rig backend to ask.");
            end
        end

        function requireEnvironment(obj)
            if ~obj.hasEnvironment()
                error("hadamard_stim:NotPrepared", ...
                    "The rig has not been prepared: run the preflight, then Prepare.");
            end
        end

        function requirePreparedScan(obj)
            % The scan reconstruction was built for the m_q of its day.
            if ~isempty(obj.Prepared) && ~isequal(obj.Prepared.m_q, obj.Config.scan.m_q)
                error("hadamard_stim:PreparedForOtherScan", ...
                    "scan.m_q changed since the rig was prepared; start a new session and prepare again.");
            end
        end

        function assertIdle(obj, allowed)
            if obj.Activity ~= ""
                error("hadamard_stim:NotLegal", "Not possible while %s is in progress.", ...
                    strrep(obj.Activity, "_", " "));
            end
            obj.assertState(allowed);
        end

        function assertState(obj, allowed)
            if ~ismember(obj.LifecycleState, allowed)
                error("hadamard_stim:NotLegal", "Not possible while the session is %s.", ...
                    obj.LifecycleState);
            end
        end

        % ---- Presentation ---------------------------------------------------

        function word = statusWord(obj)
            % One word for what the session is doing, for the tab's banner.
            switch obj.Activity
                case "running"
                    word = "running";
                    if ~isempty(obj.Phase)
                        word = replace(obj.Phase.name, ["sparse" "hadamard"], ...
                            ["sparse_pulse" "hadamard_trial"]);
                    end
                case ""
                    switch obj.LifecycleState
                        case "COMPLETED", word = "complete";
                        case "ABORTED", word = "aborted";
                        case "FAILED", word = "error";
                        case "STOPPED", word = "stopped";
                        otherwise, word = "idle";
                    end
                otherwise
                    word = obj.Activity;
            end
        end

        function s = environmentSummary(obj)
            s = struct("prepared", obj.hasEnvironment(), "prepared_utc", "", ...
                "simulated", false, "geometry", [], "blue_calibration", [], "hardware_gate", []);
            if ~isempty(obj.Prepared)
                s.prepared_utc = obj.Prepared.utc;
            end
            if ~isfield(obj.Env, "context")
                return
            end
            context = obj.Env.context;
            s.simulated = isfield(context, "simulated") && isequal(context.simulated, true);
            if isfield(context, "geometry_identity")
                s.geometry = context.geometry_identity;
            end
            if isfield(context, "blue_calibration")
                s.blue_calibration = context.blue_calibration;
            end
            gate = hadamard_stim.metadata.hardware_gate(context);
            s.hardware_gate = struct("ok", gate.ok, "missing", gate.missing);
        end

        function c = calibrationStatus(obj)
            % The blue calibration a run would use: from the prepared
            % environment, else from the last preflight.
            c = struct("status", "unknown", "identity", [], "blue_threshold", [], ...
                "message", "Run the preflight to check the active blue calibration.");
            if ~isempty(obj.Backend)
                c.blue_threshold = obj.Backend.settings().blue_threshold;
            end
            if isfield(obj.Env, "context") && isfield(obj.Env.context, "blue_calibration")
                b = obj.Env.context.blue_calibration;
                c.status = "valid";
                c.identity = b.identity;
                c.message = "In use (" + string(b.source) + ").";
            elseif ~isempty(obj.Preflight)
                c = obj.Preflight.calibration;
            end
        end

        function s = elapsedSeconds(obj)
            s = 0;
            if isnat(obj.RunStarted)
                return
            end
            stop = obj.RunEnded;
            if isnat(stop)
                stop = datetime("now", "TimeZone", "UTC");
            end
            s = round(seconds(stop - obj.RunStarted));
        end

        function bump(obj)
            obj.Revision = obj.Revision + 1;
        end
    end
end

function t = utc_text(d)
t = "";
if ~isnat(d)
    t = string(datetime(d, "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
end
end

function text = calibration_change_message(comparison)
lines = "The calibrations prepared now differ from the ones this run recorded.";
for name = ["blue" "geometry"]
    side = comparison.(name);
    if isequal(side.matches, false)
        lines(end+1) = sprintf("%s recorded: %s", name, brief(side.recorded)); %#ok<AGROW>
        lines(end+1) = sprintf("%s current:  %s", name, brief(side.current)); %#ok<AGROW>
    end
end
lines = [lines, comparison.consequence, ...
    "To resume anyway, confirm it (resume_run with continue_with_changed_calibration, " + ...
    "or resumeRun(..., ContinueWithChangedCalibration=true)); the override is recorded in the run folder."];
text = strjoin(lines, newline);
end

function text = brief(identity)
% A calibration identity in one line: the fields that tell two apart.
if isstring(identity) || ischar(identity)
    text = string(identity);
    return
elseif ~isstruct(identity)
    text = string(jsonencode(identity));
    return
end
parts = strings(1, 0);
for name = ["device" "status" "measured_utc" "curve_sha256" "n_points" "blue_threshold" "bin" "roi"]
    if isfield(identity, name) && ~isempty(identity.(name))
        v = identity.(name);
        if name == "curve_sha256"
            v = extractBefore(string(v) + "            ", 13);
        end
        parts(end+1) = name + "=" + string(jsonencode(v)); %#ok<AGROW>
    end
end
if isempty(parts)
    parts = string(jsonencode(identity));
end
text = strjoin(parts, ", ");
end
