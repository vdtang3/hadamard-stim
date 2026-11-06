function plan = camera_plan(spec, camera_names, profile, imaging_name)
%CAMERA_PLAN How each Luminos camera is set for one acquisition.
%
%   plan = hadamard_stim.luminos.camera_plan(spec, camera_names, profile)
%   plan = hadamard_stim.luminos.camera_plan(..., imaging_name)
%
%   spec          acquisition_spec, with its waveform
%   camera_names  names of the rig's cameras, in Luminos order
%                 (app.getDevice('Camera'); frames<k>.bin follows it)
%   imaging_name  the Kinetix's name as found (find_camera_by_type);
%                 profile.devices.camera.name when not given
%
%   plan(k): name, role ("imaging", "behavior" or "other"),
%   frametrigger_source, frames_requested, acquisition_exposure_s, and
%   file ("frames<k>.bin").
%
%   Nothing is planned from timing: each triggered camera takes one frame
%   per rising edge of its trigger row, exactly as the protocol's samples
%   say, and the imaging camera's count must equal spec.n_frames. Luminos
%   records every camera, so a camera the protocol does not trigger takes
%   one free-running frame ("Off"). The face camera is triggered only when
%   spec.streams.face_camera is on; otherwise its trigger row is not driven
%   (LuminosRig) and it is left like any other untriggered camera.
if nargin < 4
    imaging_name = profile.devices.camera.name;
end
imaging_name = string(imaging_name);
imaging_frames = hadamard_stim.waveform.rising_edges(spec.waveform, profile.camera_trigger_row);
if imaging_frames ~= spec.n_frames
    error("hadamard_stim:CameraFrameMismatch", ...
        "The %s waveform triggers the camera %d times but the acquisition expects %d frames.", ...
        spec.kind, imaging_frames, spec.n_frames);
end
behavior_frames = 0;
if ~isfield(spec, "streams") || isequal(spec.streams.face_camera, true)
    behavior_frames = hadamard_stim.waveform.rising_edges(spec.waveform, profile.behavior_trigger_row);
end

plan = struct("name", {}, "role", {}, "frametrigger_source", {}, ...
    "frames_requested", {}, "acquisition_exposure_s", {}, "file", {});
for k = 1:numel(camera_names)
    name = string(camera_names(k));
    entry = struct("name", name, "role", "other", "frametrigger_source", "Off", ...
        "frames_requested", 1, "acquisition_exposure_s", NaN, ...
        "file", "frames" + k + ".bin");
    if name == imaging_name
        entry.role = "imaging";
        entry.frametrigger_source = "External";
        entry.frames_requested = imaging_frames;
        entry.acquisition_exposure_s = spec.camera_exposure_ms / 1000;
    elseif name == profile.devices.behavior_camera.name
        entry.role = "behavior";
        if behavior_frames > 0
            entry.frametrigger_source = "External";
            entry.frames_requested = behavior_frames;
        end
    end
    plan(k) = entry;
end
if ~any([plan.role] == "imaging")
    error("hadamard_stim:NoImagingCamera", "No camera named %s on this rig.", ...
        imaging_name);
end
end
