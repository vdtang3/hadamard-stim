classdef LuminosRig < handle
    %LUMINOSRIG Firefly through Luminos, behind the protocol's hardware interface.
    %
    %   rig = hadamard_stim.luminos.LuminosRig(app, blue_threshold=..., ...)
    %
    %   The rig counterpart of hadamard_stim.testing.SimulatedRig: the same
    %   methods (hadamard_stim.protocol.hardware_interface), carrying out the
    %   same requested actions on Luminos devices. Nothing here decides what
    %   the experiment does; every sample, mask, repeat count, stage target
    %   and frame count comes from +protocol.
    %
    %   begin(cfg)            preflight (read only); refuses with every failure
    %   motor_position()      stage.Get_Current_Position(), in mm
    %   motor_move_to(z)      stage.Move_To_Position(z), blocking
    %   dmd_load_stack(m)     pattern_stack + Write_Stack('slave'), owned
    %   dmd_load_queue(s, r)  Load_Sequence_Queue(owner, s, r, picture time, edge)
    %   dmd_show_mask(m)      Target + Write_Static, owned (a static picture)
    %   acquire(spec)         install the waveform, set the cameras, run
    %                         Waveform_Camera_Sync_Acquisition, wait for it.
    %                         spec.streams decides the companions: with the
    %                         face camera off its trigger and IR rows are not
    %                         driven and it is not triggered; with the wheel
    %                         encoder on, its A/B lines (wheel_encoder_lines)
    %                         are recorded as buffered digital inputs on the
    %                         acquisition clock
    %   movie_mean(acq, f)    mean of frames f of the imaging camera's file
    %   release()             undo everything this object changed, DMD
    %                         ownership last; safe to call any number of times
    %   abort()               only sets a flag, so it is safe from a JS_Server
    %                         interrupt: the acquisition being waited for is
    %                         aborted in Luminos, and this and every later
    %                         operation raise hadamard_stim:Aborted until the
    %                         next begin
    %
    %   Every change is journaled just before it is made, so release()
    %   restores exactly what was changed, however far setup got.

    properties (SetAccess = private)
        App
        Profile struct
        Options struct
        Devices struct = struct()
        DmdSettings = []              % picture_time_us, trigger_edge (from begin)
        DaqRate = []
        moves = zeros(0, 3)           % [from, to, reached], every stage move
        acquisitions = struct([])     % what each acquisition did (no samples)
        LastRelease = []              % report of the last release()
        AbortRequested (1, 1) logical = false
    end

    properties (Access = private)
        Journal struct
    end

    methods
        function obj = LuminosRig(app, options)
            arguments
                app
                % Calibration points at or below this power are dropped
                % (active_blue_calibration, parity issue P2). Required.
                options.blue_threshold = []
                options.profile struct = hadamard_stim.luminos.firefly_profile()
                % Luminos's acquisition script; tests substitute a fake.
                options.acquisition_function = @Waveform_Camera_Sync_Acquisition
                options.timeout_margin_s (1, 1) double = 60
                options.poll_s (1, 1) double = 0.05
                % The encoder's A and B lines; empty means the profile's.
                options.wheel_encoder_lines string = strings(1, 0)
            end
            if isempty(options.wheel_encoder_lines)
                options.wheel_encoder_lines = options.profile.wheel_encoder.lines;
            end
            obj.App = app;
            obj.Profile = options.profile;
            obj.Options = options;
            obj.Journal = empty_journal();
        end

        % ---- Session ----------------------------------------------------

        function report = begin(obj, cfg)
            obj.AbortRequested = false;
            report = hadamard_stim.luminos.preflight(obj.App, cfg, ...
                blue_threshold=obj.Options.blue_threshold, profile=obj.Profile, ...
                wheel_encoder_lines=obj.Options.wheel_encoder_lines);
            if ~report.ok
                return
            end
            obj.Devices = report.devices;
            obj.DmdSettings = struct("picture_time_us", cfg.dmd.picture_time_us, ...
                "trigger_edge", cfg.dmd.trigger_edge);
            obj.DaqRate = cfg.daq.rate;
            report = rmfield(report, "devices");
        end

        function report = release(obj)
            % Reverse order of setup; each step on its own, so one failure
            % does not stop the rest. DMD ownership is released last:
            % releasing restores auto_write_stack, which must not reload
            % the operator's stack over the blank.
            j = obj.Journal;
            steps = strings(0, 1);
            errors = strings(0, 1);
                function attempt(name, fn)
                    try
                        fn();
                        steps(end+1, 1) = name;
                    catch err
                        errors(end+1, 1) = name + ": " + string(err.message);
                    end
                end

            if j.acquiring
                attempt("abort_acquisition", @() obj.abortIfActive());
            end
            for k = numel(j.cameras):-1:1
                c = j.cameras(k);
                attempt("restore_camera:" + string(c.device.name), @() restore_camera(c));
            end
            if ~isempty(j.daq)
                attempt("restore_daq", @() obj.restoreDaq(j.daq));
            end
            if j.dmd_claimed
                dmd = obj.Devices.dmd;
                if j.queue_loaded
                    attempt("reset_sequence_queue", @() dmd.Reset_Sequence_Queue());
                end
                if j.dmd_written
                    attempt("blank_dmd", @() dmd.Write_Dark());
                end
                if j.pattern_stack_saved
                    attempt("restore_pattern_stack", @() set_pattern_stack(dmd, j.pattern_stack));
                end
                if j.target_saved
                    attempt("restore_target", @() set_target(dmd, j.target));
                end
                attempt("release_dmd_ownership", @() dmd.Release_Pattern_Ownership(obj.Profile.owner));
            end
            obj.Journal = empty_journal();
            report = struct("steps", steps, "errors", errors, "ok", isempty(errors));
            obj.LastRelease = report;
            if ~isempty(errors)
                warning("hadamard_stim:ReleaseIncomplete", ...
                    "Restoring the rig did not fully succeed:\n  %s", strjoin(errors, newline + "  "));
            end
        end

        function abort(obj)
            obj.AbortRequested = true;
        end

        % ---- Stage ------------------------------------------------------

        function z = motor_position(obj)
            z = double(obj.device("stage").Get_Current_Position());
        end

        function motor_move_to(obj, z)
            obj.refuseIfAborted("the stage move");
            stage = obj.device("stage");
            from = double(stage.Get_Current_Position());
            stage.Move_To_Position(z);
            reached = double(stage.Get_Current_Position());
            obj.moves(end+1, :) = [from, z, reached];
        end

        % ---- DMD --------------------------------------------------------

        function dmd_load_stack(obj, masks)
            obj.refuseIfAborted("loading the scan patterns");
            dmd = obj.ownedDmd();
            obj.requireCanvas(dmd, masks);
            obj.saveStack(dmd);
            obj.Journal.dmd_written = true;
            dmd.pattern_stack = logical(masks);
            dmd.Write_Stack('slave');
            % Write_Stack frees any queue.
            obj.Journal.queue_loaded = false;
            dmd.Record_Owned_Pattern(obj.Profile.owner);
        end

        function dmd_load_queue(obj, sequences, repeats)
            obj.refuseIfAborted("loading the stimulation queue");
            dmd = obj.ownedDmd();
            for k = 1:numel(sequences)
                obj.requireCanvas(dmd, sequences{k});
            end
            s = obj.DmdSettings;
            obj.Journal.dmd_written = true;
            obj.Journal.queue_loaded = true;
            dmd.Load_Sequence_Queue(obj.Profile.owner, sequences, repeats, ...
                s.picture_time_us, s.trigger_edge);
            dmd.Record_Owned_Pattern(obj.Profile.owner);
            obj.Journal.queue = hadamard_stim.metadata.queue_fingerprint(sequences, repeats);
        end

        function dmd_show_mask(obj, mask)
            obj.refuseIfAborted("showing the illumination mask");
            dmd = obj.ownedDmd();
            obj.requireCanvas(dmd, mask);
            if size(mask, 3) ~= 1
                error("hadamard_stim:PatternSize", "dmd_show_mask takes one picture, not %d.", size(mask, 3));
            end
            if ~obj.Journal.target_saved
                obj.Journal.target = dmd.Target;
                obj.Journal.target_saved = true;
            end
            obj.Journal.dmd_written = true;
            dmd.Target = mask;
            dmd.Write_Static();
            % A static write frees any queue.
            obj.Journal.queue_loaded = false;
            dmd.Record_Owned_Pattern(obj.Profile.owner);
        end

        % ---- Acquisition ------------------------------------------------

        function acq = acquire(obj, spec)
            obj.refuseIfAborted("the acquisition");
            app = obj.App;
            if isequal(app.acquisition_active, true)
                error("hadamard_stim:AcquisitionActive", ...
                    "Luminos is already acquiring; the protocol's acquisition was not started.");
            end
            cameras = reshape(obj.Devices.cameras, 1, []);
            plan = hadamard_stim.luminos.camera_plan(spec, string({cameras.name}), obj.Profile);
            streams = spec_streams(spec);
            skip = strings(1, 0);
            if ~streams.face_camera
                skip = obj.Profile.face_camera_rows;
            end
            encoder_lines = strings(1, 0);
            if streams.wheel_encoder
                encoder_lines = obj.Options.wheel_encoder_lines;
            end
            [records, driven] = hadamard_stim.luminos.daq_records(spec.waveform, obj.Profile, ...
                skip_rows=skip, encoder_lines=encoder_lines);
            n_samples = hadamard_stim.waveform.n_samples(spec.waveform);

            daq = obj.device("daq");
            obj.saveDaq(daq);
            gp = obj.Journal.daq.global_props;
            gp.rate = obj.DaqRate;
            gp.total_time = n_samples / obj.DaqRate;
            wf = obj.Journal.daq.wfm_data;
            wf.ao = records.ao;
            wf.do = records.do;
            if ~isempty(records.di)
                wf.di = append_inputs(field_or(wf, "di", []), records.di);
            end
            daq.global_props = gp;
            daq.wfm_data = wf;
            if isprop(daq, "waveforms_built")
                daq.waveforms_built = false;
            end

            for k = 1:numel(cameras)
                obj.saveCamera(cameras(k));
                cameras(k).frametrigger_source = plan(k).frametrigger_source;
                cameras(k).frames_requested = plan(k).frames_requested;
                if plan(k).role == "imaging"
                    cameras(k).acquisition_exposuretime = plan(k).acquisition_exposure_s;
                end
            end

            obj.Journal.acquiring = true;
            obj.Options.acquisition_function(app, arrayfun(@(c) c.bin, cameras), ...
                "tag", char("_" + spec.folder));
            obj.waitForAcquisition(n_samples / obj.DaqRate);
            obj.Journal.acquiring = false;

            folder = string(app.expfolder);
            imaging = plan([plan.role] == "imaging");
            behavior = plan([plan.role] == "behavior");
            camera = cameras([plan.role] == "imaging");
            roi = camera.getROIForAcquisition();

            acq = rmfield(spec, intersect(fieldnames(spec), ["waveform" "image"]));
            acq.index = numel(obj.acquisitions) + 1;
            acq.motor_z = NaN;
            if isfield(obj.Devices, "stage") && ~isempty(obj.Devices.stage)
                acq.motor_z = obj.motor_position();
            end
            acq.luminos_folder = folder;
            acq.imaging = struct("camera", imaging.name, "file", fullfile(folder, imaging.file), ...
                "frame_size", floor([roi(4) roi(2)] ./ double(camera.bin)), "frames", imaging.frames_requested);
            acq.behavior = struct("camera", "", "file", "", "frames", 0, ...
                "status", "disabled in the configuration");
            if streams.face_camera
                acq.behavior.status = "not on this rig";
                if ~isempty(behavior)
                    acq.behavior = struct("camera", behavior.name, ...
                        "file", fullfile(folder, behavior.file), "frames", behavior.frames_requested, ...
                        "status", "recorded");
                    if behavior.frames_requested <= 1 && behavior.frametrigger_source == "Off"
                        acq.behavior.status = "not triggered by this waveform";
                    end
                end
            end
            acq.encoder = struct("status", "disabled in the configuration", "lines", strings(1, 0), ...
                "names", strings(1, 0), "method", "", "rate_hz", NaN, "n_samples", 0, "file", "");
            if streams.wheel_encoder
                acq.encoder = struct("status", "recorded", "lines", encoder_lines, ...
                    "names", obj.Profile.wheel_encoder.names(1:numel(encoder_lines)), ...
                    "method", "Luminos buffered digital input (wfm_data.di) on the acquisition sample clock", ...
                    "rate_hz", obj.DaqRate, "n_samples", n_samples, ...
                    "file", fullfile(folder, "output_data.mat") + ...
                    " (Device_Data, the DAQ's buffered digital-input task)");
            end
            acq.cameras = plan;
            acq.driven_ports = driven;
            acq.queue = [];
            if spec.kind == "stimulation"
                acq.queue = obj.Journal.queue;
            end
            obj.writeAcquisitionRecord(folder, acq);
            if isempty(obj.acquisitions)
                obj.acquisitions = acq;
            else
                obj.acquisitions(end+1, 1) = acq;
            end
            acq.waveform = spec.waveform;
        end

        function im = movie_mean(obj, acq, frames) %#ok<INUSD>
            mov = hadamard_stim.luminos.read_frames(acq.imaging.file, acq.imaging.frame_size, frames);
            im = mean(double(mov), 3);
        end
    end

    methods (Access = private)
        function d = device(obj, role)
            if ~isfield(obj.Devices, role) || isempty(obj.Devices.(role))
                error("hadamard_stim:NotBegun", ...
                    "No %s: begin(cfg) must succeed before the rig is used.", role);
            end
            d = obj.Devices.(role);
        end

        function dmd = ownedDmd(obj)
            dmd = obj.device("dmd");
            if isempty(obj.DmdSettings)
                error("hadamard_stim:NotBegun", "begin(cfg) must succeed before the DMD is used.");
            end
            if ~obj.Journal.dmd_claimed
                dmd.Claim_Pattern_Ownership(obj.Profile.owner);
                obj.Journal.dmd_claimed = true;
            end
        end

        function requireCanvas(~, dmd, masks)
            canvas = dmd.Pattern_Canvas_Size();
            if ~islogical(masks) || ~isequal([size(masks, 1) size(masks, 2)], canvas)
                error("hadamard_stim:PatternSize", ...
                    "The protocol's patterns are %s %s; %s needs logical %d x %d.", ...
                    mat2str(size(masks)), class(masks), dmd.name, canvas(1), canvas(2));
            end
        end

        function saveStack(obj, dmd)
            if ~obj.Journal.pattern_stack_saved
                obj.Journal.pattern_stack = dmd.pattern_stack;
                obj.Journal.pattern_stack_saved = true;
            end
        end

        function saveDaq(obj, daq)
            if isempty(obj.Journal.daq)
                obj.Journal.daq = struct("global_props", daq.global_props, ...
                    "wfm_data", daq.wfm_data);
            end
        end

        function saveCamera(obj, camera)
            known = arrayfun(@(c) c.device == camera, obj.Journal.cameras);
            if ~any(known)
                obj.Journal.cameras(end+1) = struct("device", camera, ...
                    "frames_requested", camera.frames_requested, ...
                    "frametrigger_source", camera.frametrigger_source, ...
                    "acquisition_exposuretime", camera.acquisition_exposuretime);
            end
        end

        function restoreDaq(obj, saved)
            daq = obj.Devices.daq;
            daq.global_props = saved.global_props;
            daq.wfm_data = saved.wfm_data;
            if isprop(daq, "waveforms_built")
                daq.waveforms_built = false;
            end
        end

        function abortIfActive(obj)
            if isequal(obj.App.acquisition_active, true)
                obj.App.abortAcquisition();
            end
        end

        function refuseIfAborted(obj, what)
            if obj.AbortRequested
                error("hadamard_stim:Aborted", "The run was aborted before %s.", what);
            end
        end

        function abortAndWait(obj)
            % Luminos finishes an aborted acquisition on its own timer.
            app = obj.App;
            obj.abortIfActive();
            started = tic;
            while ~(isequal(app.exp_complete, true) && isequal(app.round_complete, true)) && ...
                    toc(started) < obj.Options.timeout_margin_s
                pause(obj.Options.poll_s);
            end
            obj.Journal.acquiring = isequal(app.acquisition_active, true);
        end

        function waitForAcquisition(obj, duration_s)
            % Waveform_Camera_Sync_Acquisition returns once started; Luminos
            % finishes on a timer, which pause lets run.
            app = obj.App;
            limit = duration_s + obj.Options.timeout_margin_s;
            started = tic;
            while ~(isequal(app.exp_complete, true) && isequal(app.round_complete, true))
                if obj.AbortRequested
                    obj.abortAndWait();
                    obj.refuseIfAborted("the end of the acquisition");
                end
                if toc(started) > limit
                    error("hadamard_stim:AcquisitionTimeout", ...
                        "The acquisition did not finish within %.0f s.", limit);
                end
                pause(obj.Options.poll_s);
            end
            if isequal(app.last_run_aborted, true)
                error("hadamard_stim:AcquisitionAborted", "The acquisition was aborted in Luminos.");
            end
        end

        function writeAcquisitionRecord(~, folder, acq)
            % The package's description of this acquisition, beside Luminos's
            % own Device_Data in output_data.mat.
            file = fullfile(folder, "output_data.mat");
            if ~isfile(file)
                error("hadamard_stim:NoOutputData", ...
                    "Luminos finished without writing %s.", file);
            end
            hadamard_stim_acquisition = acq; %#ok<NASGU>
            save(file, "hadamard_stim_acquisition", "-append");
        end
    end
end

function j = empty_journal()
j = struct("dmd_claimed", false, "dmd_written", false, "queue_loaded", false, ...
    "pattern_stack_saved", false, "pattern_stack", [], "queue", [], ...
    "target_saved", false, "target", [], ...
    "daq", [], "acquiring", false, ...
    "cameras", struct("device", {}, "frames_requested", {}, ...
        "frametrigger_source", {}, "acquisition_exposuretime", {}));
end

function restore_camera(c)
cam = c.device;
cam.frametrigger_source = c.frametrigger_source;
cam.frames_requested = c.frames_requested;
cam.acquisition_exposuretime = c.acquisition_exposuretime;
end

function set_pattern_stack(dmd, stack)
dmd.pattern_stack = stack;
end

function set_target(dmd, target)
dmd.Target = target;
end

function streams = spec_streams(spec)
streams = struct("face_camera", true, "wheel_encoder", false);
if isfield(spec, "streams") && isstruct(spec.streams)
    streams = spec.streams;
end
end

function v = field_or(s, name, default)
v = default;
if isstruct(s) && isfield(s, name)
    v = s.(name);
end
end

function inputs = append_inputs(existing, ours)
% The operator's own inputs stay; ours are added. Records may carry
% different fields, so both are reduced to the ones Luminos reads.
inputs = struct("name", {}, "port", {}, "script_owner", {});
for r = reshape(existing, 1, [])
    owner = "";
    if isfield(r, "script_owner")
        owner = string(r.script_owner);
    end
    inputs(end+1, 1) = struct("name", r.name, "port", r.port, "script_owner", char(owner)); %#ok<AGROW>
end
inputs = [inputs; ours(:)];
end
