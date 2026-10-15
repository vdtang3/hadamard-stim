function report = preflight(app, cfg, options)
%PREFLIGHT Whether this rig can run cfg, checked without changing anything.
%
%   report = hadamard_stim.luminos.preflight(app, cfg, blue_threshold=..., ...
%       profile=..., wheel_encoder_lines=...)
%
%   report.ok        no failures
%   report.failures  one sentence per problem, saying what to do about it
%   report.checks    every requirement, failed or not: id, label, status
%                    ("pass", "fail", "not_needed" or "disabled") and
%                    message (the failures that belong to it, joined)
%   report.devices   the resolved devices (resolve_hardware)
%
%   Only what the configuration asks for is required. Always: the imaging
%   camera, the DAQ, the DMD and its calibration. A connectivity session
%   also needs the DMD's sequence queue, the blue LED and its calibration.
%   The stage, when the session takes a z-stack or drift-corrects. The face
%   camera and the wheel encoder only when enabled; when not, their checks
%   say "disabled" and nothing about them is read.
%
%   Nothing is written to any device, and the protocol state is not
%   touched: every check reads a property or calls an inquiry method.
%   LuminosRig.begin runs it before any hardware is used.
arguments
    app
    cfg struct
    options.blue_threshold = []
    options.profile struct = hadamard_stim.luminos.firefly_profile()
    options.wheel_encoder_lines string = strings(1, 0)
end
profile = options.profile;
lines = options.wheel_encoder_lines;
if isempty(lines)
    lines = profile.wheel_encoder.lines;
end
spontaneous = hadamard_stim.metadata.session_mode(cfg) == "spontaneous";
face_camera = ~isfield(cfg, "behavior") || isequal(cfg.behavior.face_camera_enabled, true);
encoder = isfield(cfg, "behavior") && isequal(cfg.behavior.wheel_encoder_enabled, true);
failures = strings(0, 1);
checks = struct("id", {}, "label", {}, "status", {}, "message", {});
current = 0;
    function requirement(id, label)
        checks(end+1) = struct("id", id, "label", label, "status", "pass", "message", "");
        current = numel(checks);
    end
    function fail(varargin)
        failures(end+1, 1) = string(sprintf(varargin{:}));
        checks(current).status = "fail";
        checks(current).message = strjoin([checks(current).message failures(end)], " ");
        checks(current).message = strip(checks(current).message);
    end

% The rig and the app.
requirement("rig", "Luminos is running the " + profile.rig_name + " rig");
if string(read(app, "rigName", "")) ~= profile.rig_name
    fail("This Luminos session is the %s rig, not %s.", string(read(app, "rigName", "unknown")), profile.rig_name);
end
requirement("luminos_idle", "Luminos is not acquiring");
if isequal(read(app, "acquisition_active", false), true)
    fail("Luminos is in the middle of an acquisition; wait for it to finish or abort it.");
end

% The devices this configuration needs.
[devices, missing] = hadamard_stim.luminos.resolve_hardware(app, profile);
if spontaneous
    needs_stage = isequal(cfg.spontaneous.drift_correction, true);
    stage_reason = "Not needed: drift correction between blocks is off.";
else
    needs_stage = cfg.z_reference.enabled || cfg.drift.enabled;
    stage_reason = "Not needed: z-reference and drift correction are off.";
end
for role = string(fieldnames(profile.devices))'
    requirement("device_" + role, profile.devices.(role).name + " is available");
    if role == "behavior_camera" && ~face_camera
        checks(current).status = "disabled";
        checks(current).message = "The face camera is off in the configuration.";
        continue
    end
    if role == "blue_modulator" && spontaneous
        checks(current).status = "not_needed";
        checks(current).message = "Not needed: a spontaneous session uses no blue light.";
        continue
    end
    for m = missing(string([missing.role]) == role)
        if role == "stage" && ~needs_stage
            checks(current).status = "not_needed";
            checks(current).message = stage_reason;
            continue
        end
        fail("%s", m.message);
    end
end

% DMD: queue support, ownership, canvas, polarity.
dmd = devices.dmd;
if ~isempty(dmd)
    requirement("dmd_queue", "The DMD supports the sequence queue");
    if spontaneous
        checks(current).status = "not_needed";
        checks(current).message = "Not needed: spontaneous blocks show one static mask.";
    elseif ~call(@() dmd.Supports_Sequence_Queue(), false)
        fail("%s does not report sequence-queue support (Supports_Sequence_Queue), which his stimulation trials need.", dmd.name);
    end
    requirement("dmd_ownership", "The DMD can be claimed for hadamard_stim");
    owner = string(read(dmd, "pattern_owner", ""));
    if strlength(owner) > 0 && owner ~= profile.owner
        fail("%s is owned by ""%s""; stop that before starting.", dmd.name, owner);
    end
    requirement("dmd_canvas", "The DMD canvas matches his masks");
    canvas = call(@() dmd.Pattern_Canvas_Size(), []);
    if ~isequal(canvas, fliplr(cfg.dmd.size))
        fail("%s has a %s canvas; his masks need %d x %d (rows x columns).", dmd.name, ...
            mat2str(canvas), cfg.dmd.size(2), cfg.dmd.size(1));
    end
    requirement("dmd_polarity", "The DMD output is not inverted");
    if isequal(read(dmd, "invert_output", false), true)
        fail("%s has invert_output set; his loader sent masks uninverted.", dmd.name);
    end
end

% DAQ: his rate on the DAQ's own clock, and no other outputs scheduled.
daq = devices.daq;
if ~isempty(daq)
    requirement("daq_rate", "The DAQ runs at his 100 kHz on its own clock");
    gp = read(daq, "global_props", []);
    if ~isstruct(gp) || ~isfield(gp, "rate")
        fail("%s has no waveform settings (global_props); open the Waveforms tab once.", daq.name);
    elseif double(gp.rate) ~= cfg.daq.rate || cfg.daq.rate ~= profile.daq_rate
        fail("The DAQ rate is %g Hz; his waveforms are %g Hz samples. Set it in the Waveforms tab.", ...
            double(gp.rate), cfg.daq.rate);
    end
    if isstruct(gp) && isfield(gp, "clock_source") && ~isempty(gp.clock_source) ...
            && ~contains(string(gp.clock_source), "Internal", "IgnoreCase", true)
        fail("The DAQ is clocked from %s; his waveforms need the DAQ's own clock.", string(gp.clock_source));
    end
    if ~isempty(read(daq, "external_clock_rate", []))
        fail("The DAQ has an external clock rate override; clear the camera clock in the Waveforms tab.");
    end
    requirement("daq_outputs", "No other waveforms are scheduled on the DAQ");
    wf = read(daq, "wfm_data", struct());
    for kind = ["ao" "do"]
        if ~isstruct(wf) || ~isfield(wf, kind)
            continue
        end
        for r = reshape(wf.(kind), 1, [])
            owner = "";
            if isfield(r, "script_owner")
                owner = string(r.script_owner);
            end
            % camera_trigger records are Luminos's own, dropped by every acquisition.
            if ismember(owner, [profile.owner "camera_trigger"])
                continue
            end
            fail("The DAQ already drives %s (""%s""); clear it from the Waveforms tab, because his protocol owns every output during a run.", ...
                string(r.port), string(r.name));
        end
    end
end

% The wheel encoder: its lines are a rig setting; whether they are wired
% to the encoder can only be checked at the rig (a Firefly check).
requirement("wheel_encoder", "The wheel encoder's A/B lines can be recorded");
if ~encoder
    checks(current).status = "disabled";
    checks(current).message = "The wheel encoder is off in the configuration.";
else
    for problem = encoder_problems(lines, profile, daq)
        fail("%s", problem);
    end
    if checks(current).status == "pass"
        checks(current).message = sprintf("A = %s, B = %s, sampled on the acquisition clock. %s.", ...
            lines(1), lines(2), profile.wheel_encoder.source);
    end
end

% A spontaneous block is one long acquisition; Luminos holds every driven
% row and recorded line for its whole length while it runs.
if spontaneous
    requirement("block_memory", "One spontaneous block fits in memory");
    [need, detail] = hadamard_stim.luminos.block_memory(cfg, face_camera, encoder);
    available = available_memory();
    checks(current).message = sprintf("About %.1f GB while a block runs (%s).", need / 2^30, detail);
    if isfinite(available) && need > 0.8 * available
        fail(['A block needs about %.1f GB but only %.1f GB is free; that is not safe. ' ...
            'Use shorter blocks (spontaneous.block_frames) or free memory.'], need / 2^30, available / 2^30);
    elseif isfinite(available)
        checks(current).message = checks(current).message + sprintf(" %.1f GB free.", available / 2^30);
    end
end

% Cameras.
camera = devices.camera;
if ~isempty(camera)
    requirement("camera_settings", camera.name + " records raw, unbinned frames");
    if string(read(camera, "compression_method", "None")) ~= "None"
        fail("%s records with %s compression; set it to None (the adapter reads raw frames).", ...
            camera.name, string(camera.compression_method));
    end
    if double(read(camera, "bin", 1)) ~= 1
        fail("%s is binned %g x; his scans and segmentation used 1 x 1.", camera.name, double(camera.bin));
    end
end

% Calibrations: the active ones, as a run would resolve them.
if ~isempty(devices.blue_modulator) && ~spontaneous
    requirement("blue_calibration", "The active blue calibration is valid");
    try
        hadamard_stim.luminos.active_blue_calibration(devices.blue_modulator, options.blue_threshold);
    catch err
        fail("%s", err.message);
    end
end
if ~isempty(dmd) && ~isempty(camera)
    requirement("dmd_calibration", "The DMD calibration for " + camera.name + " is valid");
    try
        hadamard_stim.luminos.active_geometry(dmd, camera);
    catch err
        fail("%s", err.message);
    end
end

report.ok = isempty(failures);
report.failures = failures;
report.checks = checks;
report.devices = devices;
end

function problems = encoder_problems(lines, profile, daq)
% What stops the configured lines from being recorded as the encoder.
problems = strings(1, 0);
if numel(lines) ~= 2
    problems(end+1) = sprintf(['The wheel encoder needs two lines (A and B); the rig setting ' ...
        'wheel_encoder_lines has %d.'], numel(lines));
    return
end
bad = lines(~matches(lines, regexpPattern("^Dev\d+/port\d+/line\d+$")));
if ~isempty(bad)
    problems(end+1) = "These encoder lines are not digital lines (DevN/portN/lineN): " + strjoin(bad, ", ") + ".";
end
if lines(1) == lines(2)
    problems(end+1) = "Encoder A and B are both " + lines(1) + ".";
end
ports = string({profile.channels.port});
taken = intersect(lines, ports);
for line = taken
    k = find(ports == line, 1);
    problems(end+1) = sprintf("Encoder line %s is the %s output.", line, profile.channels(k).name); %#ok<AGROW>
end
if ~isempty(daq)
    wf = read(daq, "wfm_data", struct());
    if isstruct(wf) && isfield(wf, "di")
        for r = reshape(wf.di, 1, [])
            if ismember(string(r.port), lines)
                problems(end+1) = sprintf(['The Waveforms tab already records %s as "%s"; remove it there ' ...
                    'so the encoder can be recorded.'], string(r.port), string(r.name)); %#ok<AGROW>
            end
        end
    end
end
end

function bytes = available_memory()
% Free physical memory, where MATLAB can say (Windows); Inf elsewhere.
bytes = Inf;
try
    [~, system] = memory();
    bytes = system.PhysicalMemory.Available;
catch
end
end

function v = read(object, name, default)
% A property, or default when the object does not have it.
v = default;
try
    if isprop(object, name) || (isstruct(object) && isfield(object, name))
        v = object.(name);
    end
catch
end
end

function v = call(fn, default)
v = default;
try
    v = fn();
catch
end
end
