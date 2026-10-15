function d = diagnostics(app, profile)
%DIAGNOSTICS What the rig's devices report right now, for bring-up. Read only.
%
%   d = hadamard_stim.luminos.diagnostics(app, profile)
%
%   For the Firefly checks: the DMD's identity, queue support and queue
%   state, each camera's identity and mode, the blue modulator, the stage
%   position and the waveforms currently scheduled on the DAQ (port, name,
%   owner). Nothing is written to any device; a value that cannot be read
%   is reported as "unavailable" with the reason.
arguments
    app
    profile struct = hadamard_stim.luminos.firefly_profile()
end
[devices, missing] = hadamard_stim.luminos.resolve_hardware(app, profile);
d.read_utc = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
d.rig = struct("name", value(app, "rigName"), "acquisition_active", value(app, "acquisition_active"), ...
    "data_folder", value(app, "datafolder"));
d.missing_devices = reshape(string({missing.message}), [], 1);

dmd = devices.dmd;
d.dmd = struct("name", value(dmd, "name"), "class", class_of(dmd), ...
    "model", value(dmd, "model"), "serial", value(dmd, "serial"), ...
    "api_version", value(dmd, "api_version"), "dimensions", value(dmd, "Dimensions"), ...
    "trigger_channel", value(dmd, "trigger_channel"), "invert_output", value(dmd, "invert_output"), ...
    "pattern_owner", value(dmd, "pattern_owner"), ...
    "sequence_queue_supported", value(dmd, @(x) x.Supports_Sequence_Queue()), ...
    "queue_state", value(dmd, @(x) x.Get_Queue_State()));

d.cameras = struct("name", {}, "type", {}, "cam_id", {}, "role", {}, "trigger", {}, ...
    "frametrigger_source", {}, "frames_requested", {}, "exposure_s", {}, "bin", {}, ...
    "roi", {}, "compression_method", {});
for cam = reshape(devices.cameras, 1, [])
    role = "other";
    if string(cam.name) == profile.devices.camera.name
        role = "imaging";
    elseif string(cam.name) == profile.devices.behavior_camera.name
        role = "behavior";
    end
    d.cameras(end+1) = struct("name", value(cam, "name"), "type", value(cam, "type"), ...
        "cam_id", value(cam, "cam_id"), "role", role, "trigger", value(cam, "trigger"), ...
        "frametrigger_source", value(cam, "frametrigger_source"), ...
        "frames_requested", value(cam, "frames_requested"), ...
        "exposure_s", value(cam, "acquisition_exposuretime"), "bin", value(cam, "bin"), ...
        "roi", value(cam, @(c) c.getROIForAcquisition()), ...
        "compression_method", value(cam, "compression_method"));
end

blue = devices.blue_modulator;
d.blue_modulator = struct("name", value(blue, "name"), "port", value(blue, "port"), ...
    "iscalibrated", value(blue, "iscalibrated"), ...
    "curve_points", value(blue, @(m) size(m.calibration_curve, 2)));

stage = devices.stage;
d.stage = struct("name", value(stage, "name"), "class", class_of(stage), ...
    "units", value(stage, "position_units"), ...
    "position", value(stage, @(s) s.Get_Current_Position()));

daq = devices.daq;
d.daq = struct("name", value(daq, "name"), "rate", value(daq, @(x) x.global_props.rate), ...
    "clock_source", value(daq, @(x) x.global_props.clock_source), ...
    "scheduled", scheduled(daq), "protocol_ports", profile.channels);
end

function rows = scheduled(daq)
% The ao/do records on the DAQ now: which ports something will drive.
rows = struct("kind", {}, "port", {}, "name", {}, "owner", {});
if isempty(daq)
    return
end
try
    wf = daq.wfm_data;
catch
    return
end
for kind = ["ao" "do"]
    if ~isstruct(wf) || ~isfield(wf, kind)
        continue
    end
    for r = reshape(wf.(kind), 1, [])
        owner = "";
        if isfield(r, "script_owner")
            owner = string(r.script_owner);
        end
        rows(end+1) = struct("kind", kind, "port", string(field(r, "port")), ...
            "name", string(field(r, "name")), "owner", owner); %#ok<AGROW>
    end
end
end

function v = field(s, name)
v = "";
if isfield(s, name)
    v = s.(name);
end
end

function c = class_of(object)
c = "";
if ~isempty(object)
    c = string(class(object));
end
end

function v = value(object, what)
% A property or computed value, or "unavailable: <reason>"; JSON-safe.
v = "unavailable";
if isempty(object)
    v = "unavailable: device not found";
    return
end
try
    if isa(what, "function_handle")
        v = what(object);
    elseif isprop(object, what) || (isstruct(object) && isfield(object, what))
        v = object.(what);
    end
catch err
    v = "unavailable: " + string(err.message);
    return
end
if ischar(v)
    v = string(v);
end
end
