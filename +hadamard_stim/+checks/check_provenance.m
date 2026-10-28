function p = check_provenance(app, profile)
%CHECK_PROVENANCE Which software and hardware a Firefly check ran on.
%
%   p = hadamard_stim.checks.check_provenance()           % Luminos closed
%   p = hadamard_stim.checks.check_provenance(app)
%   p = hadamard_stim.checks.check_provenance(app, profile)
%
%   p.hadamard_stim_commit, p.hadamard_stim_dirty   this package
%   p.luminos_commit, p.luminos_dirty               the Luminos session
%   p.dmd_serial, p.dmd_model, p.dmd_api_version    the open board
%   p.camera, p.daq                                 the imaging camera and DAQ
%
%   Kept with each recorded check (check_result), so a later preflight
%   can say when a check was recorded on other software or another board
%   (hardware_gate). Anything that cannot be read is "unavailable".
arguments
    app = []
    profile struct = hadamard_stim.luminos.firefly_profile()
end
repo = fileparts(fileparts(fileparts(mfilename("fullpath"))));
package = hadamard_stim.metadata.git_provenance(repo);
p = struct("hadamard_stim_commit", package.commit, "hadamard_stim_dirty", package.dirty, ...
    "luminos_commit", "unavailable", "luminos_dirty", missing, ...
    "dmd_serial", "unavailable", "dmd_model", "unavailable", "dmd_api_version", "unavailable", ...
    "camera", "unavailable", "daq", "unavailable");
if isempty(app)
    p.luminos_commit = "Luminos closed";
    return
end
try
    info = luminos_session_info(app);
    p.luminos_commit = string(info.git.commit);
    p.luminos_dirty = logical(info.git.dirty);
catch
end
[devices, ~] = hadamard_stim.luminos.resolve_hardware(app, profile);
if ~isempty(devices.dmd)
    p.dmd_serial = read(devices.dmd, "serial");
    p.dmd_model = read(devices.dmd, "model");
    p.dmd_api_version = read(devices.dmd, "api_version");
end
if ~isempty(devices.camera)
    p.camera = string(devices.camera.name) + " " + string(read(devices.camera, "cam_id"));
end
if ~isempty(devices.daq)
    p.daq = string(devices.daq.name);
end
end

function v = read(object, name)
v = "unavailable";
try
    if isprop(object, name) || (isstruct(object) && isfield(object, name))
        v = object.(name);
    end
catch
end
if ischar(v)
    v = string(v);
end
end
