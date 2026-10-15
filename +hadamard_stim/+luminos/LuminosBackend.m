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
    %     hardware_validation_file  JSON recording the four Firefly checks
    %                               (hardware_gate): {"driver": {"passed":
    %                               true, "evidence": "...", "date": "..."}, ...}
    %     run_root                  where new run folders go; empty means
    %                               Luminos's data folder for the day
    %
    %   Options for tests: calibration_movies, acquisition_function, profile.

    properties (SetAccess = private)
        App
        Settings struct
        Options struct
    end

    methods
        function obj = LuminosBackend(app, options)
            arguments
                app
                options.blue_threshold = []
                options.calibration_folders string = strings(0, 1)
                options.hardware_validation_file (1, 1) string = ""
                options.run_root (1, 1) string = ""
                options.calibration_movies cell = {}
                options.acquisition_function = @Waveform_Camera_Sync_Acquisition
                options.profile struct = hadamard_stim.luminos.firefly_profile()
            end
            obj.App = app;
            obj.Options = options;
            obj.Settings = struct("blue_threshold", [], ...
                "calibration_folders", strings(0, 1), ...
                "hardware_validation_file", "", "run_root", "");
            obj.set_settings(struct("blue_threshold", options.blue_threshold, ...
                "calibration_folders", options.calibration_folders, ...
                "hardware_validation_file", options.hardware_validation_file, ...
                "run_root", options.run_root));
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
            % Read only. Every requirement of a real run, as checks.
            report = hadamard_stim.luminos.preflight(obj.App, cfg, ...
                blue_threshold=obj.Settings.blue_threshold, profile=obj.Options.profile);
            report = rmfield(report, "devices");
            checks = report.checks;

            needs_scans = cfg.z_reference.enabled || cfg.drift.enabled;
            [ok, message] = obj.scanCalibrationReady(needs_scans);
            checks(end+1) = check("scan_calibration", "His Hadamard calibration scans are named", ok, message);
            if ~needs_scans
                checks(end).status = "not_needed";
                checks(end).message = "Not needed: z-reference and drift correction are off.";
            end

            folder = obj.dataRoot();
            [ok, message] = writable(folder);
            checks(end+1) = check("data_folder", "Acquisition folder is writable", ok, message);

            [validation, message] = obj.hardwareValidation();
            gate = hadamard_stim.metadata.hardware_gate(struct("hardware_validation", validation));
            for name = ["driver" "trigger_edge" "queue_support" "slide_queue"]
                ok = ~ismember(name, gate.missing);
                text = message;
                if ok
                    text = sprintf("Recorded %s: %s", text_of(validation.(name), "date"), ...
                        text_of(validation.(name), "evidence"));
                elseif strlength(text) == 0
                    text = sprintf(['Not recorded as passed in %s. Carry out the check ' ...
                        '(docs/notebook.md, Phase 2 rig checks) and record it there.'], ...
                        obj.Settings.hardware_validation_file);
                end
                checks(end+1) = check("firefly_" + name, "Firefly check recorded: " + name, ok, text); %#ok<AGROW>
            end

            report.checks = checks;
            failed = checks([checks.status] == "fail");
            report.failures = reshape(string({failed.message}), [], 1);
            report.ok = isempty(failed);
            report.calibration = obj.blueCalibrationStatus();
        end

        function env = environment(obj, cfg)
            [validation, ~] = obj.hardwareValidation();
            env = hadamard_stim.luminos.make_environment(obj.App, cfg, ...
                blue_threshold=obj.Settings.blue_threshold, ...
                calibration_movies=obj.Options.calibration_movies, ...
                calibration_folders=obj.Settings.calibration_folders, ...
                hardware_validation=validation, ...
                acquisition_function=obj.Options.acquisition_function, ...
                profile=obj.Options.profile);
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

        function [ok, message] = scanCalibrationReady(obj, needed)
            ok = true;
            message = "";
            if ~needed || ~isempty(obj.Options.calibration_movies)
                return
            end
            folders = obj.Settings.calibration_folders;
            if isempty(folders)
                ok = false;
                message = ['Drift correction and the z-reference reconstruct Hadamard scans: name ' ...
                    'the Luminos folders of his calibration scans (had_cal) in the rig settings.'];
                return
            end
            missing = folders(~isfolder(folders));
            if ~isempty(missing)
                ok = false;
                message = "These calibration folders do not exist: " + strjoin(missing, ", ") + ".";
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

function c = check(id, label, ok, message)
status = "pass";
if ~ok
    status = "fail";
end
c = struct("id", id, "label", label, "status", status, "message", string(message));
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

function t = text_of(s, name)
t = "(not recorded)";
if isfield(s, name) && ~isempty(s.(name))
    t = string(s.(name));
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
