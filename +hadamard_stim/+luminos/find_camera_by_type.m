function [camera, message] = find_camera_by_type(app, spec)
%FIND_CAMERA_BY_TYPE The one Luminos camera of spec.camera_type. Read only.
%
%   [camera, message] = hadamard_stim.luminos.find_camera_by_type(app, spec)
%
%   spec is firefly_profile's devices.camera: the Teledyne Kinetix, Luminos
%   camera type 3 (PVCAM). The camera is chosen by that type, not by its
%   name, so a Kinetix renamed in the rig file is still the imaging camera,
%   and no other camera - Firefly's Grasshopper3 and Blackfly are GenTL,
%   type 4 - is ever taken in its place. camera is [] and message says why
%   when there is no such camera, or more than one.
camera = [];
message = "";
cameras = [];
try
    cameras = app.getDevice("Camera", "displayWarning", false);
catch err
    message = "Looking up the cameras failed: " + string(err.message);
    return
end
cameras = reshape(cameras, 1, []);
types = arrayfun(@(c) double(read_type(c)), cameras);
match = cameras(types == spec.camera_type);
if isscalar(match)
    camera = match;
    return
end
others = strjoin(arrayfun(@(c, t) sprintf('%s (type %g)', string(c.name), t), ...
    cameras, types, "UniformOutput", false), ", ");
if isempty(others)
    others = "none";
end
if isempty(match)
    message = sprintf(['Hadamard Stim images with the %s (a Luminos camera of type %d, PVCAM), ' ...
        'and this rig has none; its cameras: %s. Check that the Kinetix is in the rig file ' ...
        'and opened without error.'], spec.name, spec.camera_type, others);
else
    message = sprintf(['There are %d cameras of type %d (%s); Hadamard Stim needs exactly ' ...
        'one Kinetix.'], numel(match), spec.camera_type, ...
        strjoin(arrayfun(@(c) string(c.name), match), ", "));
end
end

function t = read_type(c)
t = NaN;
try
    t = double(c.type);
catch
end
if isempty(t)
    t = NaN;
end
end
