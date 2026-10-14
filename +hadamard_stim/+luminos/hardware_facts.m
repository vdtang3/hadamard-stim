function [facts, luminos] = hardware_facts(app, devices, profile)
%HARDWARE_FACTS What the run recipe records about the rig, read from Luminos.
%
%   [facts, luminos] = hadamard_stim.luminos.hardware_facts(app, devices, profile)
%
%   facts    rig, DMD, cameras, stage, DAQ port map and blue modulator, as
%            Luminos reports them; JSON-safe
%   luminos  the Luminos software, {commit, branch, dirty, remote, version}
%            (luminos_session_info), for recipe.software.luminos
%
%   Only facts: the package writes the recipe (build_recipe). A fact that
%   cannot be read is recorded as "unavailable" rather than failing.
facts.rig = struct("name", fact(app, "rigName"), "user", fact(app, @(a) a.User.name), ...
    "profile", profile.rig_name);

dmd = devices.dmd;
facts.dmd = struct("name", fact(dmd, "name"), "class", string(class(dmd)), ...
    "model", fact(dmd, "model"), "serial", fact(dmd, "serial"), ...
    "dimensions", fact(dmd, "Dimensions"), "api_version", fact(dmd, "api_version"), ...
    "trigger_channel", fact(dmd, "trigger_channel"), "invert_output", fact(dmd, "invert_output"), ...
    "sequence_queue_supported", fact(dmd, @(d) d.Supports_Sequence_Queue()));

facts.cameras = struct("name", {}, "type", {}, "cam_id", {}, "roi", {}, "bin", {}, ...
    "compression_method", {}, "trigger", {});
for cam = reshape(devices.cameras, 1, [])
    facts.cameras(end+1) = struct("name", fact(cam, "name"), "type", fact(cam, "type"), ...
        "cam_id", fact(cam, "cam_id"), "roi", fact(cam, @(c) c.getROIForAcquisition()), ...
        "bin", fact(cam, "bin"), "compression_method", fact(cam, "compression_method"), ...
        "trigger", fact(cam, "trigger"));
end

stage = devices.stage;
facts.stage = struct("name", fact(stage, "name"), "class", string(class(stage)), ...
    "units", fact(stage, "position_units"));

facts.daq = struct("name", fact(devices.daq, "name"), ...
    "rate", fact(devices.daq, @(d) d.global_props.rate), ...
    "clock_source", fact(devices.daq, @(d) d.global_props.clock_source), ...
    "channels", profile.channels);

facts.blue_modulator = struct("name", fact(devices.blue_modulator, "name"), ...
    "class", string(class(devices.blue_modulator)), ...
    "port", fact(devices.blue_modulator, "port"), ...
    "range_v", fact(devices.blue_modulator, @(m) [m.min m.max]));

luminos = struct("commit", "unavailable", "branch", "", "dirty", false, ...
    "remote", "", "version", "unavailable");
try
    info = luminos_session_info(app);
    luminos.commit = string(info.git.commit);
    luminos.branch = string(info.git.branch);
    luminos.dirty = logical(info.git.dirty);
    luminos.version = string(info.luminos_version);
catch err
    luminos.reason = "luminos_session_info failed: " + string(err.message);
end
end

function v = fact(object, what)
% A property (name) or computed value (function of the object), or
% "unavailable" when it cannot be read; values are made JSON-safe.
v = "unavailable";
if isempty(object)
    return
end
try
    if isa(what, "function_handle")
        v = what(object);
    elseif isprop(object, what) || (isstruct(object) && isfield(object, what))
        v = object.(what);
    end
catch
    return
end
if ischar(v)
    v = string(v);
end
end
