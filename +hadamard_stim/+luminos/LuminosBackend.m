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
    %     wheel_encoder_lines       the encoder's A and B digital lines;
    %                               empty means his wiring (firefly_profile)
    %
    %   Options for tests: calibration_movies, acquisition_function,
    %   blue_calibration_function, profile.

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
            % Read only. Every requirement of a real run, as checks.
            report = hadamard_stim.luminos.preflight(obj.App, cfg, ...
                blue_threshold=obj.Settings.blue_threshold, profile=obj.Options.profile, ...
                wheel_encoder_lines=obj.Settings.wheel_encoder_lines);
            report = rmfield(report, "devices");
            checks = report.checks;
            mode = hadamard_stim.metadata.session_mode(cfg);

            if mode == "spontaneous"
                needs_scans = isequal(cfg.spontaneous.drift_correction, true);
                why_not = "Not needed: drift correction between blocks is off.";
            else
                needs_scans = cfg.z_reference.enabled || cfg.drift.enabled;
                why_not = "Not needed: z-reference and drift correction are off.";
            end
            [ok, message] = obj.scanCalibrationReady(needs_scans);
            checks(end+1) = check("scan_calibration", "His Hadamard calibration scans are named", ok, message);
            if ~needs_scans
                checks(end).status = "not_needed";
                checks(end).message = why_not;
            end

            folder = obj.dataRoot();
            [ok, message] = writable(folder);
            checks(end+1) = check("data_folder", "Acquisition folder is writable", ok, message);

            [validation, message] = obj.hardwareValidation();
            gate = hadamard_stim.metadata.hardware_gate(struct("hardware_validation", validation));
            needed = hadamard_stim.metadata.hardware_checks(mode);
            for name = ["driver" "trigger_edge" "queue_support" "slide_queue"]
                if ~ismember(name, needed)
                    checks(end+1) = struct("id", "firefly_" + name, ...
                        "label", "Firefly check recorded: " + name, "status", "not_needed", ...
                        "message", "Not needed: spontaneous blocks use no sequence queue or DMD triggers."); %#ok<AGROW>
                    continue
                end
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
            if ~report.ok
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
                writelines(hadamard_stim.metadata.canonical_json(record), ...
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
                return
            end
            % Scans taken by acquire_calibration_scans say at which camera
            % area; reconstruction centre-crops the calibration to each
            % scan, so another area or binning would reconstruct wrongly.
            [devices, ~] = hadamard_stim.luminos.resolve_hardware(obj.App, obj.Options.profile);
            camera = devices.camera;
            if isempty(camera)
                return
            end
            roi = camera.getROIForAcquisition();
            for folder = folders(:)'
                file = fullfile(folder, "hadamard_calibration_scan.json");
                if ~isfile(file)
                    continue
                end
                taken = jsondecode(fileread(file));
                if ~isequal(reshape(taken.camera.roi, 1, []), reshape(double(roi), 1, [])) ...
                        || taken.camera.bin ~= double(camera.bin)
                    ok = false;
                    message = sprintf(['The calibration scans in %s were taken at camera area %s, bin %g; ' ...
                        'the camera is now at %s, bin %g. Take the calibration scans again at this area.'], ...
                        folder, mat2str(reshape(taken.camera.roi, 1, [])), taken.camera.bin, ...
                        mat2str(reshape(double(roi), 1, [])), double(camera.bin));
                    return
                end
            end
            message = sprintf("%d folder(s).", numel(folders));
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
