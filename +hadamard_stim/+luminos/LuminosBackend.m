classdef LuminosBackend < handle
    %LUMINOSBACKEND Firefly through Luminos, as the controller's backend (the tab's path).
    %
    %   backend = hadamard_stim.luminos.LuminosBackend(app, blue_threshold=...,
    %       calibration_folders=..., hardware_validation_file=...)
    %   c = hadamard_stim.HadamardStimController(backend)
    %
    %   Implements hadamard_stim.backend_interface: what the controller needs
    %   from the rig before an environment exists. The environment itself is
    %   make_environment's, so a session prepared here runs on exactly the
    %   LuminosRig, calibrations and context a programmatic session gets.
    %
    %   Settings (rig facts, not part of the experiment's configuration):
    %     blue_threshold            calibration points at or below this power
    %                               are dropped (P2); required, no default
    %     calibration_folders       Luminos acquisition folders holding his
    %                               Hadamard calibration scans ("had_cal")
    %     hardware_validation_file  JSON recording the DMD commissioning
    %                               checks (hardware_gate): {"slide_queue":
    %                               {"passed": true, "evidence": "...",
    %                               "date": "...", "provenance": {...}}, ...}
    %     run_root                  where new run folders go; empty means
    %                               Luminos's data folder for the day
    %     wheel_encoder_lines       the encoder's A and B digital lines;
    %                               empty means his wiring (firefly_profile)
    %
    %   Options for tests: calibration_movies, acquisition_function,
    %   blue_calibration_function, slide_queue_frame_means, profile,
    %   dmd_code_changed_function.

    properties (SetAccess = private)
        App
        Settings struct
        Options struct
        LastCalibrationScans = []   % what the last calibration scans took
    end

    methods
        function obj = LuminosBackend(app, options)
            arguments
                app
                options.blue_threshold = []
                options.calibration_folders string = strings(0, 1)
                options.hardware_validation_file (1, 1) string = ""
                options.run_root (1, 1) string = ""
                options.wheel_encoder_lines string = strings(1, 0)
                options.calibration_movies cell = {}
                options.acquisition_function = @Waveform_Camera_Sync_Acquisition
                % Luminos's slide calibration of a modulator; tests substitute a fake.
                options.blue_calibration_function = @Calibrate_Modulator_On_Slide
                % The slide queue check's frame means; empty reads the movie.
                options.slide_queue_frame_means = []
                % (then_commit, now_commit) -> [changed, files]: whether
                % Luminos's DMD code differs; tests substitute a fake.
                options.dmd_code_changed_function = @hadamard_stim.luminos.dmd_code_changed
                options.profile struct = hadamard_stim.luminos.firefly_profile()
            end
            obj.App = app;
            obj.Options = options;
            obj.Settings = struct("blue_threshold", [], ...
                "calibration_folders", strings(0, 1), ...
                "hardware_validation_file", "", "run_root", "", ...
                "wheel_encoder_lines", strings(1, 0));
            obj.set_settings(struct("blue_threshold", options.blue_threshold, ...
                "calibration_folders", options.calibration_folders, ...
                "hardware_validation_file", options.hardware_validation_file, ...
                "run_root", options.run_root, ...
                "wheel_encoder_lines", options.wheel_encoder_lines));
        end

        function s = settings(obj)
            s = obj.Settings;
        end

        function set_settings(obj, changes)
            % Only the named fields change; each is checked before any is set.
            s = obj.Settings;
            for name = string(fieldnames(changes))'
                v = changes.(name);
                switch name
                    case "blue_threshold"
                        if ~isempty(v) && ~(isnumeric(v) && isscalar(v) && isfinite(v) && v > 0)
                            error("hadamard_stim:InvalidSetting", ...
                                "blue_threshold must be one positive number in the calibration's power units, or empty.");
                        end
                        s.blue_threshold = double(v);
                    case "calibration_folders"
                        if iscell(v)
                            v = string(v);
                        end
                        if ~(isstring(v) || ischar(v)) && ~isempty(v)
                            error("hadamard_stim:InvalidSetting", "calibration_folders must be folder names.");
                        end
                        v = string(v);
                        s.calibration_folders = reshape(v(strlength(v) > 0), [], 1);
                    case "wheel_encoder_lines"
                        if iscell(v)
                            v = string(v);
                        end
                        if ~isempty(v) && ~(isstring(v) || ischar(v))
                            error("hadamard_stim:InvalidSetting", "wheel_encoder_lines must be two line names, or empty.");
                        end
                        v = string(v);
                        v = reshape(v(strlength(v) > 0), 1, []);
                        if ~ismember(numel(v), [0 2])
                            error("hadamard_stim:InvalidSetting", ...
                                "wheel_encoder_lines must name two lines (A and B), or be empty for his wiring.");
                        end
                        s.wheel_encoder_lines = v;
                    case {"hardware_validation_file" "run_root"}
                        if isempty(v)
                            v = "";
                        end
                        if ~((isstring(v) || ischar(v)) && isscalar(string(v)))
                            error("hadamard_stim:InvalidSetting", "%s must be one path.", name);
                        end
                        s.(name) = string(v);
                    otherwise
                        error("hadamard_stim:InvalidSetting", "There is no rig setting called '%s'.", name);
                end
            end
            obj.Settings = s;
        end

        function report = preflight(obj, cfg)
            % Read only. Every requirement of a real run, as readiness
            % items (hadamard_stim.metadata.readiness_report): the rig's
            % (luminos.preflight), the Hadamard calibration scans, the
            % data folder and the recorded Firefly commissioning checks.
            profile = obj.Options.profile;
            rig = hadamard_stim.luminos.preflight(obj.App, cfg, ...
                blue_threshold=obj.Settings.blue_threshold, profile=profile, ...
                wheel_encoder_lines=obj.Settings.wheel_encoder_lines);
            checks = rig.checks;
            mode = hadamard_stim.metadata.session_mode(cfg);

            checks(end+1) = obj.scanCalibrationCheck(cfg);

            folder = obj.dataRoot();
            [ok, message] = writable(folder);
            if ok
                checks(end+1) = hadamard_stim.metadata.readiness_item("data_folder", ...
                    "Acquisition folder is writable", "pass", message=folder);
            else
                checks(end+1) = hadamard_stim.metadata.readiness_item("data_folder", ...
                    "Acquisition folder is writable", "blocker", message=message, ...
                    consequence="The run's recipe, trial records and checkpoints cannot be written.");
            end

            [validation, problem] = obj.hardwareValidation();
            current = struct("trigger_edge", string(cfg.dmd.trigger_edge), ...
                "luminos_commit", luminos_commit(obj.App), ...
                "hadamard_commit", package_commit(), ...
                "dmd_serial", dmd_serial(rig.devices), ...
                "dmd_code_changed", [], "dmd_code_changes", strings(1, 0));
            then = recorded_luminos_commit(validation, "slide_queue");
            if strlength(then) > 0 && strlength(current.luminos_commit) > 0
                try
                    [current.dmd_code_changed, current.dmd_code_changes] = ...
                        obj.Options.dmd_code_changed_function(then, current.luminos_commit);
                catch
                end
            end
            gate = hadamard_stim.metadata.hardware_gate( ...
                struct("hardware_validation", validation), mode, current);
            items = gate.items;
            if strlength(problem) > 0
                for k = find(string({items.status}) == "warning")
                    items(k).message = problem + " " + items(k).message;
                end
            end
            checks = [checks reshape(items, 1, [])];

            report = hadamard_stim.metadata.readiness_report(checks);
            report.calibration = obj.blueCalibrationStatus();
        end

        function cam = imaging_camera(obj)
            % The imaging camera's area and format, as the Camera tab left
            % them: the field of view is chosen there and inherited; the
            % acquisition timing (trigger, frames, exposure) is the
            % package's. Read only, cheap enough for every getState.
            cam = [];
            try
                spec = obj.Options.profile.devices.camera;
                c = obj.App.getDevice(spec.type, "name", spec.name, "displayWarning", false);
                if numel(c) ~= 1
                    return
                end
                roi = double(c.getROIForAcquisition());   % [x width y height], unbinned
                bin = double(c.bin);
                cam = struct("name", string(c.name), "roi", roi, "width", roi(2), ...
                    "height", roi(4), "bin", bin, "frame_size", floor([roi(4) roi(2)] ./ bin), ...
                    "bit_depth", double(read(c, "bit_depth", 16)), ...
                    "bit_mode", string(read(c, "bit_mode_label", "")));
            catch
                cam = [];
            end
        end

        function sets = calibration_scan_sets(obj)
            % Hadamard calibration scan sets taken from the tab before
            % (hadamard_calibration_scan.json, under the run root or the
            % user's dated data folders), newest first, each with whether
            % it fits the camera as it is set now: reusing one is setting
            % calibration_folders to its folders.
            sets = struct("taken_utc", {}, "folders", {}, "camera_roi", {}, "bin", {}, ...
                "label", {}, "compatible", {}, "message", {}, "in_use", {});
            root = obj.dataRoot();
            if strlength(obj.Settings.run_root) == 0 && strlength(root) > 0
                root = fileparts(root);
            end
            if strlength(root) == 0 || ~isfolder(root)
                return
            end
            found = [dir(fullfile(root, "*", "hadamard_calibration_scan.json")); ...
                dir(fullfile(root, "*", "*", "hadamard_calibration_scan.json"))];
            seen = strings(0, 1);
            records = struct("record", {}, "datenum", {});
            for f = reshape(found, 1, [])
                try
                    r = jsondecode(fileread(fullfile(f.folder, f.name)));
                catch
                    continue
                end
                key = strjoin(string(r.folders), "|");
                if ismember(key, seen)
                    continue
                end
                seen(end+1) = key; %#ok<AGROW>
                records(end+1) = struct("record", r, "datenum", f.datenum); %#ok<AGROW>
            end
            [~, order] = sort([records.datenum], "descend");
            in_use = strjoin(obj.Settings.calibration_folders, "|");
            for r = records(order)
                [compatible, message] = obj.scanSetFits(r.record);
                sets(end+1) = struct("taken_utc", string(r.record.taken_utc), ...
                    "folders", reshape(string(r.record.folders), 1, []), ...
                    "camera_roi", reshape(r.record.camera.roi, 1, []), "bin", r.record.camera.bin, ...
                    "label", string(field_or(r.record.settings, "label", "")), ...
                    "compatible", compatible, "message", message, ...
                    "in_use", strjoin(string(r.record.folders), "|") == in_use); %#ok<AGROW>
            end
        end

        function result = run_commissioning_check(obj, name, cfg)
            % Run one of the two DMD commissioning checks and record it in
            % the hardware validation file (record_firefly_check):
            % "queue_support" (Supports_Sequence_Queue) or "slide_queue"
            % (queue playback on a uniform slide, on the protocol's edge).
            % The driver probe is an installation step with Luminos closed
            % (README), not a tab check.
            file = obj.Settings.hardware_validation_file;
            if strlength(file) == 0
                error("hadamard_stim:NoValidationFile", ...
                    "Name the hardware validation file in the rig settings first; the result is recorded there.");
            end
            if isequal(read(obj.App, "acquisition_active", false), true)
                error("hadamard_stim:LuminosBusy", "Luminos is acquiring; wait for it to finish.");
            end
            switch name
                case "queue_support"
                    result = hadamard_stim.checks.queue_support_check(obj.App, obj.Options.profile);
                case "slide_queue"
                    result = hadamard_stim.checks.slide_queue_check(obj.App, ...
                        trigger_edge=string(cfg.dmd.trigger_edge), profile=obj.Options.profile, ...
                        acquisition_function=obj.Options.acquisition_function, ...
                        frame_means=obj.Options.slide_queue_frame_means);
                otherwise
                    error("hadamard_stim:NotFromTheTab", ...
                        ['There is no "%s" check in the tab: it runs "queue_support" and ' ...
                         '"slide_queue". The driver probe needs Luminos closed (README, ' ...
                         'Installation).'], name);
            end
            hadamard_stim.checks.record_firefly_check(file, result);
        end

        function result = calibrate_blue_led(obj)
            % Luminos's slide calibration of the blue LED against the
            % imaging camera (Calibrate_Modulator_On_Slide: Yitong's method,
            % camera counts above the LED-off level). Luminos records and
            % saves it on the modulator, where active_blue_calibration reads
            % it; nothing is kept here. The slide must be in place and the
            % camera set as the experiment will use it.
            profile = obj.Options.profile;
            if isequal(read(obj.App, "acquisition_active", false), true)
                error("hadamard_stim:LuminosBusy", "Luminos is acquiring; wait for it to finish.");
            end
            result = obj.Options.blue_calibration_function(obj.App, ...
                profile.devices.blue_modulator.name, camera=profile.devices.camera.name);
        end

        function hw = calibration_hardware(obj, cfg)
            % A LuminosRig ready for the Hadamard calibration scans
            % (protocol.acquire_calibration_scans): begun with only what
            % they use (DAQ, DMD, imaging camera), so nothing here needs a
            % prepared environment, because preparing needs these scans.
            % The caller releases it.
            hw = hadamard_stim.luminos.LuminosRig(obj.App, profile=obj.Options.profile, ...
                acquisition_function=obj.Options.acquisition_function);
            report = hw.begin(cfg, "calibration_scan");
            if ~report.can_run
                hw.release();
                error("hadamard_stim:HardwareNotReady", ...
                    "The rig cannot take the calibration scans:\n  %s", ...
                    strjoin(report.failures, newline + "  "));
            end
        end

        function record = record_calibration_scans(obj, cfg, acquisitions)
            % Each folder gets a hadamard_calibration_scan.json (settings,
            % camera area, DMD, time), and the folders become the
            % calibration_folders setting.
            [devices, ~] = hadamard_stim.luminos.resolve_hardware(obj.App, obj.Options.profile);
            record = struct("kind", "hadamard_stim_calibration_scan", "schema_version", "1.0.0", ...
                "taken_utc", string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
                "settings", cfg.calibration_scan, "m_q", cfg.scan.m_q, ...
                "camera", struct("name", string(devices.camera.name), ...
                    "roi", devices.camera.getROIForAcquisition(), "bin", double(devices.camera.bin)), ...
                "dmd", string(devices.dmd.name), ...
                "folders", reshape([acquisitions.luminos_folder], 1, []), ...
                "waveform_sha256", acquisitions(1).waveform_sha256);
            for folder = record.folders
                hadamard_stim.metadata.write_text(hadamard_stim.metadata.canonical_json(record), ...
                    fullfile(folder, "hadamard_calibration_scan.json"));
            end
            obj.set_settings(struct("calibration_folders", record.folders));
            obj.LastCalibrationScans = record;
        end

        function env = environment(obj, cfg)
            [validation, ~] = obj.hardwareValidation();
            env = hadamard_stim.luminos.make_environment(obj.App, cfg, ...
                blue_threshold=obj.Settings.blue_threshold, ...
                calibration_movies=obj.Options.calibration_movies, ...
                calibration_folders=obj.Settings.calibration_folders, ...
                hardware_validation=validation, ...
                acquisition_function=obj.Options.acquisition_function, ...
                profile=obj.Options.profile, ...
                wheel_encoder_lines=obj.Settings.wheel_encoder_lines);
        end

        function d = diagnostics(obj)
            d = hadamard_stim.luminos.diagnostics(obj.App, obj.Options.profile);
            d.blue_calibration = obj.blueCalibrationStatus();
        end

        function folder = default_run_folder(obj, cfg)
            stamp = string(datetime("now", "Format", "HHmmss"));
            folder = fullfile(obj.dataRoot(), stamp + "_" + cfg.naming.prefix + "_hadamard_stim");
        end

        function runs = run_folders(obj)
            % Run folders under the run root, or under the user's dated data
            % folders (this one and its siblings), newest first.
            runs = struct("folder", {}, "name", {}, "modified", {});
            root = obj.dataRoot();
            if strlength(obj.Settings.run_root) == 0 && strlength(root) > 0
                root = fileparts(root);
            end
            if strlength(root) == 0 || ~isfolder(root)
                return
            end
            found = [dir(fullfile(root, "*", "run_recipe.json")); ...
                dir(fullfile(root, "*", "*", "run_recipe.json"))];
            found = found(isfile(fullfile(string({found.folder}), "run_checkpoint.mat")));
            [~, order] = sort([found.datenum], "descend");
            for f = reshape(found(order), 1, [])
                [~, name] = fileparts(f.folder);
                runs(end+1) = struct("folder", string(f.folder), "name", string(name), ...
                    "modified", string(datetime(f.datenum, "ConvertFrom", "datenum", ...
                    "Format", "yyyy-MM-dd HH:mm"))); %#ok<AGROW>
            end
        end
    end

    methods (Access = private)
        function folder = dataRoot(obj)
            folder = obj.Settings.run_root;
            if strlength(folder) == 0
                folder = string(read(obj.App, "datafolder", ""));
            end
        end

        function item = scanCalibrationCheck(obj, cfg)
            % The Hadamard calibration scans every reconstruction uses (the
            % reference image, the z-stack, drift correction). None at all
            % blocks the actions that reconstruct; scans taken at another
            % camera area or binning, or on another day, can still be used
            % and are reported as such.
            id = "scan_calibration";
            label = "Hadamard calibration scans";
            if hadamard_stim.metadata.session_mode(cfg) == "spontaneous"
                needed = isequal(cfg.spontaneous.drift_correction, true);
                why_not = "Not needed: drift correction between blocks is off.";
            else
                needed = cfg.z_reference.enabled || cfg.drift.enabled;
                why_not = "Not needed: z-reference and drift correction are off.";
            end
            make = @(status, varargin) hadamard_stim.metadata.readiness_item(id, label, status, ...
                "group", "calibration", varargin{:});
            if ~needed
                item = make("not_needed", message=why_not);
                return
            end
            if ~isempty(obj.Options.calibration_movies)
                item = make("pass", message="Given as movies.");
                return
            end
            none = "Reconstruction needs them: the reference image, the z-stack and drift correction cannot be computed.";
            folders = obj.Settings.calibration_folders;
            if isempty(folders)
                item = make("blocker", message= ...
                    "None named. Take them on a uniform slide, or reuse an earlier set.", consequence=none);
                return
            end
            missing = folders(~isfolder(folders));
            if ~isempty(missing)
                item = make("blocker", message="These calibration folders do not exist: " + ...
                    strjoin(missing, ", ") + ".", consequence=none);
                return
            end
            record = [];
            for folder = folders(:)'
                file = fullfile(folder, "hadamard_calibration_scan.json");
                if isfile(file)
                    record = jsondecode(fileread(file));
                    break
                end
            end
            if isempty(record)
                item = make("warning", message=sprintf(['%d folder(s), not taken from the tab: the ' ...
                    'camera area they were taken at is not recorded.'], numel(folders)), ...
                    consequence="Reconstruction may be spatially wrong if they were taken at another camera area or binning.", ...
                    details=struct("folders", folders, "taken_utc", ""));
                return
            end
            [compatible, message] = obj.scanSetFits(record);
            age = hadamard_stim.metadata.calibration_age(string(record.taken_utc));
            details = struct("folders", reshape(folders, 1, []), "taken_utc", age.taken_utc, ...
                "taken", age.taken, "ago", age.ago, "age_days", age.age_days, ...
                "camera_roi", reshape(record.camera.roi, 1, []), "bin", record.camera.bin, ...
                "compatible", compatible);
            % Age is shown, never judged; only a misfit warns.
            if ~compatible
                item = make("warning", message=age.text + ". " + message, details=details, consequence= ...
                    "Reconstruction centre-crops or pads the calibration to each scan, so it still runs, " + ...
                    "but the reference image, z-stack and drift correction may be spatially wrong. Retake them at this area.");
            else
                % Age is text only: compatible scans pass whatever their age.
                reused = "";
                if ~age.today && ~isempty(age.age_days)
                    reused = " — reused";
                end
                item = make("pass", message=age.text + reused + ". At this camera area and binning.", details=details);
            end
        end

        function [compatible, message] = scanSetFits(obj, record)
            % Whether scans recorded by record were taken at the camera's
            % area and binning now (reconstruction centre-crops the
            % calibration to each scan, so another area reconstructs wrongly).
            compatible = true;
            message = "At this camera area.";
            [devices, ~] = hadamard_stim.luminos.resolve_hardware(obj.App, obj.Options.profile);
            camera = devices.camera;
            if isempty(camera)
                return
            end
            roi = camera.getROIForAcquisition();
            if ~isequal(reshape(record.camera.roi, 1, []), reshape(double(roi), 1, [])) ...
                    || record.camera.bin ~= double(camera.bin)
                compatible = false;
                message = sprintf('Taken at camera area %s, bin %g; the camera is now at %s, bin %g.', ...
                    mat2str(reshape(record.camera.roi, 1, [])), record.camera.bin, ...
                    mat2str(reshape(double(roi), 1, [])), double(camera.bin));
            end
        end

        function [validation, message] = hardwareValidation(obj)
            validation = struct();
            message = "";
            file = obj.Settings.hardware_validation_file;
            if strlength(file) == 0
                message = ['No hardware validation file is set. Name the JSON file that records ' ...
                    'the Firefly checks in the rig settings.'];
                return
            end
            if ~isfile(file)
                message = sprintf('The hardware validation file %s does not exist yet.', file);
                return
            end
            try
                validation = jsondecode(fileread(file));
            catch err
                message = sprintf('%s could not be read: %s', file, err.message);
                validation = struct();
            end
        end

        function status = blueCalibrationStatus(obj)
            % valid / missing / invalid, as a run would resolve it.
            status = struct("status", "missing", "device", "", "identity", [], ...
                "blue_threshold", obj.Settings.blue_threshold, "message", "");
            [devices, ~] = hadamard_stim.luminos.resolve_hardware(obj.App, obj.Options.profile);
            modulator = devices.blue_modulator;
            status.device = obj.Options.profile.devices.blue_modulator.name;
            if isempty(modulator)
                status.message = status.device + " is not on this rig.";
                return
            end
            try
                calibration = hadamard_stim.luminos.active_blue_calibration( ...
                    modulator, obj.Settings.blue_threshold);
                status.status = "valid";
                status.identity = calibration.identity;
            catch err
                status.message = string(err.message);
                if err.identifier ~= "hadamard_stim:NoBlueCalibration"
                    status.status = "invalid";
                end
            end
        end
    end
end

function [ok, message] = writable(folder)
ok = false;
if strlength(folder) == 0
    message = "Luminos has no data folder for this session.";
    return
end
if ~isfolder(folder)
    message = sprintf("The data folder %s does not exist.", folder);
    return
end
[~, attributes] = fileattrib(folder);
ok = isstruct(attributes) && attributes.UserWrite;
message = "";
if ~ok
    message = sprintf("The data folder %s is not writable.", folder);
end
end

function v = read(object, name, default)
v = default;
try
    if isprop(object, name) || (isstruct(object) && isfield(object, name))
        v = object.(name);
    end
catch
end
end

function t = luminos_commit(app)
t = "";
try
    info = luminos_session_info(app);
    t = string(info.git.commit);
catch
end
end

function t = package_commit()
% This package's commit, read once per MATLAB session (a git call).
persistent commit
if isempty(commit)
    repo = fileparts(fileparts(fileparts(mfilename("fullpath"))));
    commit = hadamard_stim.metadata.git_provenance(repo).commit;
end
t = commit;
end

function t = dmd_serial(devices)
t = "";
try
    if ~isempty(devices.dmd)
        t = string(devices.dmd.serial);
    end
catch
end
end

function v = field_or(s, name, default)
v = default;
if isstruct(s) && isfield(s, name)
    v = s.(name);
end
end

function t = recorded_luminos_commit(validation, name)
% The Luminos commit a recorded check ran under, "" when not recorded.
t = "";
try
    t = string(validation.(name).provenance.luminos_commit);
catch
end
if ~isscalar(t)
    t = "";
end
end
