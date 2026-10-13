classdef HadamardStimController < handle
    %HADAMARDSTIMCONTROLLER One Hadamard stimulation session: setup, then a run.
    %
    %   c = hadamard_stim.HadamardStimController(env)
    %
    %   env is what the protocol runs on (see hadamard_stim.protocol.run_protocol)
    %   plus, for the records:
    %     env.context   luminos provenance, geometry and blue calibration
    %                   identities, standing deviations (build_recipe)
    %
    %   The session follows his order of work, one step at a time:
    %     CONFIGURING      edit the configuration
    %     CELLS_PROPOSED   segmentation run on the reference image; look at
    %                      the cells and min_val, then approve or re-run
    %     CELLS_APPROVED   the canonical geometry is fixed from here on
    %     READY            reference z-stack acquired; a run can start
    %     RUNNING          trials in progress (stop takes effect between trials)
    %     STOPPED / COMPLETED / FAILED
    %   A stopped or failed run resumes from its folder's checkpoint.
    %
    %   Everything a frontend may do goes through apply_controller_action;
    %   getState is what it shows.

    properties (SetAccess = private)
        Revision (1, 1) double = 0
        LifecycleState (1, 1) string = "CONFIGURING"
        Config struct
        Proposal = []          % cells from the last segmentation, not yet approved
        Cells = []             % approved canonical cells
        ReferenceImage = []    % the Hadamard image the cells are found on
        Reference = []         % z-stack reference (run_z_reference) plus had_ref
        RunFolder (1, 1) string = ""
        RecipeHash (1, 1) string = ""
        RunState = []
        LastRecord = []
        LastError (1, 1) string = ""
        StopRequested (1, 1) logical = false
    end

    properties
        Env struct
        % Called with the controller after every trial; the Luminos device
        % pushes progress to the tab from here.
        ProgressChangedFcn = []
    end

    methods
        function obj = HadamardStimController(env)
            obj.Env = env;
            obj.Config = hadamard_stim.default_config();
        end

        % ---- Setup ------------------------------------------------------

        function setConfig(obj, cfg)
            obj.assertState(["CONFIGURING" "CELLS_PROPOSED" "CELLS_APPROVED" "READY"]);
            obj.Config = cfg;
            obj.bump();
        end

        function setReferenceImage(obj, im)
            obj.assertState(["CONFIGURING" "CELLS_PROPOSED"]);
            obj.ReferenceImage = im;
            obj.Proposal = [];
            obj.LifecycleState = "CONFIGURING";
            obj.bump();
        end

        function proposeCells(obj)
            obj.assertState(["CONFIGURING" "CELLS_PROPOSED"]);
            if isempty(obj.ReferenceImage)
                error("hadamard_stim:NoReferenceImage", "Set the reference image before segmenting.");
            end
            obj.Proposal = hadamard_stim.protocol.segment_cells(obj.Config, ...
                obj.ReferenceImage, obj.Env.geometry);
            obj.LifecycleState = "CELLS_PROPOSED";
            obj.bump();
        end

        function approveCells(obj)
            obj.assertState("CELLS_PROPOSED");
            obj.Cells = obj.Proposal;
            obj.LifecycleState = "CELLS_APPROVED";
            obj.bump();
        end

        function acquireZReference(obj)
            obj.assertState(["CELLS_APPROVED" "READY"]);
            reference = hadamard_stim.protocol.run_z_reference(obj.Config, obj.Env);
            reference.had_ref = obj.ReferenceImage;
            obj.Reference = reference;
            obj.LifecycleState = "READY";
            obj.bump();
        end

        % ---- Running ----------------------------------------------------

        function startRun(obj, run_folder)
            obj.assertState("READY");
            report = hadamard_stim.validate_config(obj.Config);
            if ~report.ok
                error("hadamard_stim:InvalidConfig", "The configuration cannot run:\n  %s", ...
                    strjoin(report.errors, newline + "  "));
            end
            obj.assertHardwareValidated();
            state = hadamard_stim.protocol.new_run_state(obj.Config, obj.Cells, obj.Reference);
            [recipe, arrays] = hadamard_stim.metadata.build_recipe(obj.Config, state, obj.Env.context);
            hadamard_stim.metadata.write_recipe(run_folder, recipe, arrays);
            obj.RunFolder = run_folder;
            obj.RecipeHash = recipe.recipe_hash;
            hadamard_stim.metadata.save_checkpoint(run_folder, state, recipe.recipe_hash);
            obj.run(state);
        end

        function resumeRun(obj, run_folder)
            obj.assertState(["CONFIGURING" "READY" "STOPPED" "FAILED"]);
            obj.assertHardwareValidated();
            [recipe, ~] = hadamard_stim.metadata.read_recipe(run_folder);
            state = hadamard_stim.metadata.load_checkpoint(run_folder);
            obj.Config = recipe.config;
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
        end

        % ---- Reporting --------------------------------------------------

        function state = getState(obj)
            % Small and JSON-safe: what a frontend shows.
            state.revision = obj.Revision;
            state.lifecycle = obj.LifecycleState;
            state.legal_actions = obj.legalActions();
            report = hadamard_stim.validate_config(obj.Config);
            state.config = obj.Config;
            state.config_errors = report.errors;
            state.mode = report.mode;
            state.deviations = report.deviations;
            state.has_reference_image = ~isempty(obj.ReferenceImage);
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
                    "last_trial", obj.Config.trials.last, "orange_v", s.orange_v, ...
                    "n_corrections", numel(s.cells.corrections), ...
                    "stop_requested", obj.StopRequested);
            end
            state.last_trial = [];
            if ~isempty(obj.LastRecord)
                r = obj.LastRecord;
                state.last_trial = struct("trial", r.trial, "kind", r.kind, ...
                    "folder", r.folder, "skipped", r.skipped, "retarget", r.retarget);
            end
            state.last_error = obj.LastError;
        end

        function legal = legalActions(obj)
            s = obj.LifecycleState;
            idle = s ~= "RUNNING";
            legal.set_config = ismember(s, ["CONFIGURING" "CELLS_PROPOSED" "CELLS_APPROVED" "READY"]);
            legal.set_reference_image = ismember(s, ["CONFIGURING" "CELLS_PROPOSED"]);
            legal.propose_cells = ismember(s, ["CONFIGURING" "CELLS_PROPOSED"]) && ~isempty(obj.ReferenceImage);
            legal.approve_cells = s == "CELLS_PROPOSED";
            legal.acquire_z_reference = ismember(s, ["CELLS_APPROVED" "READY"]);
            legal.start_run = s == "READY";
            legal.resume_run = idle && ismember(s, ["CONFIGURING" "READY" "STOPPED" "FAILED"]);
            legal.stop_after_current = s == "RUNNING" && ~obj.StopRequested;
        end
    end

    methods (Access = private)
        function run(obj, state)
            obj.LifecycleState = "RUNNING";
            obj.StopRequested = false;
            obj.LastError = "";
            obj.RunState = state;
            obj.bump();
            env = obj.Env;
            env.after_trial = @(s, r) obj.afterTrial(s, r);
            env.stop_requested = @() obj.StopRequested;
            try
                state = hadamard_stim.protocol.run_protocol(obj.Config, env, state);
                obj.RunState = state;
                if state.next_trial > obj.Config.trials.last
                    obj.LifecycleState = "COMPLETED";
                else
                    obj.LifecycleState = "STOPPED";
                end
            catch err
                obj.LastError = string(err.message);
                obj.LifecycleState = "FAILED";
                obj.bump();
                rethrow(err);
            end
            obj.bump();
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

        function assertHardwareValidated(obj)
            gate = hadamard_stim.metadata.hardware_gate(obj.Env.context);
            if ~gate.ok
                error("hadamard_stim:HardwareNotValidated", ...
                    ['Firefly has not passed the checks a real acquisition needs: %s. ' ...
                     'Run them (docs/notebook.md, Phase 2 rig checks) and record the results.'], ...
                    strjoin(gate.missing, ", "));
            end
        end

        function assertState(obj, allowed)
            if ~ismember(obj.LifecycleState, allowed)
                error("hadamard_stim:NotLegal", "Not possible while the session is %s.", ...
                    obj.LifecycleState);
            end
        end

        function bump(obj)
            obj.Revision = obj.Revision + 1;
        end
    end
end
