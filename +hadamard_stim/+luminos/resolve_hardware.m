function [devices, failures] = resolve_hardware(app, profile)
%RESOLVE_HARDWARE The Luminos devices the adapter uses, found by name. Read only.
%
%   [devices, failures] = hadamard_stim.luminos.resolve_hardware(app, profile)
%
%   devices.<role> is the device, or [] when it is missing; failures has
%   one entry (role, message) per device that is missing or ambiguous. Roles are
%   the fields of profile.devices (daq, dmd, camera, behavior_camera, stage,
%   blue_modulator). devices.cameras is every camera, in Luminos order.
failures = struct("role", {}, "message", {});
devices = struct();
for role = string(fieldnames(profile.devices))'
    spec = profile.devices.(role);
    found = [];
    try
        found = app.getDevice(spec.type, "name", spec.name, "displayWarning", false);
    catch err
        failures(end+1) = struct("role", role, "message", string(sprintf("Looking up %s ""%s"" failed: %s", spec.type, spec.name, err.message))); %#ok<AGROW>
        devices.(role) = [];
        continue
    end
    if numel(found) > 1
        failures(end+1) = struct("role", role, "message", string(sprintf("There are %d %s devices named ""%s""; rename one in the rig file.", ...
            numel(found), spec.type, spec.name))); %#ok<AGROW>
        found = [];
    elseif isempty(found)
        failures(end+1) = struct("role", role, "message", string(sprintf("No %s named ""%s"" on this rig (check %s.json).", ...
            spec.type, spec.name, profile.rig_name))); %#ok<AGROW>
        found = [];
    end
    devices.(role) = found;
end
devices.cameras = [];
try
    devices.cameras = app.getDevice("Camera", "displayWarning", false);
catch
end
end
