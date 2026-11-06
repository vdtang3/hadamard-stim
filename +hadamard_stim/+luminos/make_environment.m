function env = make_environment(app, cfg, options)
%MAKE_ENVIRONMENT What the protocol runs on at the rig, built from Luminos.
%
%   env = hadamard_stim.luminos.make_environment(app, cfg, ...
%       blue_threshold=..., calibration_movies={...}, hardware_validation=...)
%   c = hadamard_stim.HadamardStimController(env)
%
%   The rig counterpart of tests/support/parity_environment: the same env
%   fields (see hadamard_stim.protocol.run_protocol), from the active
%   Luminos state.
%     env.hw                   hadamard_stim.luminos.LuminosRig
%     env.geometry             the active DMD calibration (active_geometry)
%     env.blue_calibration     the active blue calibration (active_blue_calibration)
%     env.reconstruct_scan     \  from the Hadamard calibration scans
%     env.reconstruct_z_stack  /  (scan_reconstruction)
%     env.context              hardware facts, both git commits, calibration
%                              identities, the Firefly checks and the
%                              standing deviations, for the run recipe
%
%   Options:
%     blue_threshold       required; see active_blue_calibration (P2)
%     calibration_movies   cell of uint8 or uint16 movies, as recorded: his
%                          "had_cal" scans, from the imaging camera at the
%                          acquisition ROI
%     calibration_folders  instead, Luminos acquisition folders to read
%                          them from (Extract_Mov); each then gets the
%                          calibration's QC (write_calibration_qc)
%     hardware_validation  the Firefly checks as recorded (hardware_gate);
%                          without the ones the session mode needs, runs
%                          refuse to start
%     wheel_encoder_lines  the encoder's A and B lines (default: the
%                          profile's, his wiring)
%     acquisition_function, profile   for tests
%
%   A spontaneous session uses no blue light: the blue calibration is
%   resolved if it can be (so the session can switch to connectivity
%   without preparing again) and recorded as unavailable if not.
%
%   Errors, listing every blocker, if the rig cannot run cfg (preflight).
%   Warnings do not stop it: preparing the rig is not a run, and the
%   operator confirms them, all at once, when the run starts.
arguments
    app
    cfg struct
    options.blue_threshold = []
    options.calibration_movies cell = {}
    options.calibration_folders string = strings(0, 1)
    options.hardware_validation = []
    options.acquisition_function = @Waveform_Camera_Sync_Acquisition
    options.profile struct = hadamard_stim.luminos.firefly_profile()
    options.wheel_encoder_lines string = strings(1, 0)
end
profile = options.profile;
lines = options.wheel_encoder_lines;
if isempty(lines)
    lines = profile.wheel_encoder.lines;
end
report = hadamard_stim.luminos.preflight(app, cfg, ...
    blue_threshold=options.blue_threshold, profile=profile, wheel_encoder_lines=lines);
if ~report.can_run
    error("hadamard_stim:RigNotReady", "%s cannot run this configuration:\n  %s", ...
        profile.rig_name, strjoin(report.failures, newline + "  "));
end
devices = report.devices;

movies = options.calibration_movies;
from_folders = isempty(movies);
if from_folders
    movies = read_calibration_movies(options.calibration_folders, devices, profile);
end
if isempty(movies) && needs_scans(cfg)
    error("hadamard_stim:NoScanCalibration", ...
        ['Drift correction and the reference z-stack reconstruct Hadamard scans, which ' ...
         'needs his calibration scans: pass calibration_folders (or calibration_movies).']);
end

env.hw = hadamard_stim.luminos.LuminosRig(app, blue_threshold=options.blue_threshold, ...
    profile=profile, acquisition_function=options.acquisition_function, ...
    wheel_encoder_lines=lines);
[env.geometry, ~] = hadamard_stim.luminos.active_geometry(devices.dmd, devices.camera);
if hadamard_stim.metadata.session_mode(cfg) == "spontaneous"
    try
        env.blue_calibration = hadamard_stim.luminos.active_blue_calibration( ...
            devices.blue_modulator, options.blue_threshold);
        blue = struct("identity", env.blue_calibration.identity, "source", env.blue_calibration.source);
    catch err
        env.blue_calibration = [];
        blue = struct("identity", "unavailable: " + string(err.message), ...
            "source", "not used (spontaneous session)");
    end
else
    env.blue_calibration = hadamard_stim.luminos.active_blue_calibration( ...
        devices.blue_modulator, options.blue_threshold);
    blue = struct("identity", env.blue_calibration.identity, "source", env.blue_calibration.source);
end
env.reconstruct_scan = @(acq) error("hadamard_stim:NoScanCalibration", "No scan calibration.");
env.reconstruct_z_stack = env.reconstruct_scan;
if ~isempty(movies)
    format = scans_format(movies, options.calibration_folders, devices.camera);
    offset = 100;
    if isstruct(format)
        offset = format.offset;
    end
    [env.reconstruct_scan, env.reconstruct_z_stack, scorr] = ...
        hadamard_stim.luminos.scan_reconstruction(cfg.scan.m_q, movies, offset=offset);
    scan_calibration = struct("folders", options.calibration_folders, ...
        "n_movies", numel(movies), "scorr_sha256", hadamard_stim.metadata.sha256(scorr), ...
        "format", format, "offset", offset);
    if from_folders
        scan_calibration.qc = calibration_qc(cfg.scan.m_q, movies, scorr, ...
            options.calibration_folders, scan_calibration.scorr_sha256, format);
    end
else
    scan_calibration = struct("folders", strings(0, 1), "n_movies", 0, "scorr_sha256", "", ...
        "format", [], "offset", []);
end
env.waveform_cache = containers.Map();

[facts, luminos] = hadamard_stim.luminos.hardware_facts(app, devices, profile);
facts.scan_calibration = scan_calibration;
env.context = struct("luminos", luminos, ...
    "geometry_identity", env.geometry.identity, ...
    "blue_calibration", blue, ...
    "standing_deviations", standing_deviations(profile, facts, scan_calibration), ...
    "simulated", false, ...
    "hardware_validation", options.hardware_validation, ...
    "hardware", facts, ...
    "streams", hadamard_stim.luminos.stream_facts(devices, profile, lines, cfg.daq.rate));
end

function d = standing_deviations(profile, facts, scan_calibration)
% The profile's, and the 8-bit offset when the imaging camera or the
% calibration scans are not in his arithmetic (uint16 at 100).
d = profile.standing_deviations;
formats = {};
if isfield(facts, "imaging_format") && isstruct(facts.imaging_format)
    formats{end+1} = facts.imaging_format;
end
if isstruct(scan_calibration.format)
    formats{end+1} = scan_calibration.format;
end
theirs = @(f) isfield(f, "offset") && f.storage_bits == 16 && f.offset == 100;
if isfield(profile, "eight_bit_deviation") && ~all(cellfun(theirs, formats))
    d = [d; profile.eight_bit_deviation];
end
end

function tf = needs_scans(cfg)
if hadamard_stim.metadata.session_mode(cfg) == "spontaneous"
    tf = isequal(cfg.spontaneous.drift_correction, true);
else
    tf = cfg.drift.enabled || cfg.z_reference.enabled;
end
end

function movies = read_calibration_movies(folders, devices, profile)
movies = {};
if isempty(folders)
    return
end
names = string({devices.cameras.name});
k = find(names == string(devices.camera.name), 1);
for folder = folders(:)'
    movies{end+1} = Extract_Mov(char(folder), cam_indices=k); %#ok<AGROW>
end
end

function format = scans_format(movies, folders, camera)
% The calibration scans' camera format: as recorded with them
% (hadamard_calibration_scan.json), else the camera's now when the movies
% are in its class, else their class alone; [] for movies that are not
% integer frames (tests). One calibration is one format.
classes = unique(cellfun(@class, movies, "UniformOutput", false));
if numel(classes) > 1
    error("hadamard_stim:MixedCalibrationFormats", ...
        ['The Hadamard calibration scans were recorded at different bit depths (%s); ' ...
         'one calibration is computed from scans in one camera mode. Retake them.'], ...
        strjoin(classes, ", "));
end
format = [];
switch classes{1}
    case "uint8"
        bits = 8;
    case "uint16"
        bits = 16;
    otherwise
        return
end
for folder = reshape(folders, 1, [])
    file = fullfile(folder, "hadamard_calibration_scan.json");
    if isfile(file)
        try
            record = jsondecode(fileread(file));
            format = hadamard_stim.luminos.camera_format(record.camera.format);
        catch
        end
        break
    end
end
if isempty(format) && ~isempty(camera)
    format = hadamard_stim.luminos.camera_format(camera);
end
if isempty(format) || format.storage_bits ~= bits
    format = hadamard_stim.luminos.camera_format(bits);
end
end

function report = calibration_qc(m_q, movies, scorr, folders, scorr_sha256, format)
% The calibration's QC beside its recordings (write_calibration_qc). It is
% for the operator to look at: if it cannot be made, Prepare rig still
% succeeds and says why.
report = struct("written", strings(0, 1), "error", "");
try
    saturation = [];
    offset = 100;
    if isstruct(format)
        saturation = format.saturation;
        offset = format.offset;
    end
    qc = hadamard_stim.luminos.calibration_qc(m_q, movies, scorr, saturation=saturation, ...
        offset=offset);
    report.written = hadamard_stim.luminos.write_calibration_qc(qc, folders, scorr_sha256, ...
        format=format);
catch err
    report.error = string(err.message);
    warning("hadamard_stim:CalibrationQcFailed", ...
        "The Hadamard calibration QC could not be saved: %s", err.message);
end
end
