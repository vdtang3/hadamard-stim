function plan = camera_plan(spec, camera_names, profile)
%CAMERA_PLAN How each Luminos camera is set for one acquisition.
%
%   plan = hadamard_stim.luminos.camera_plan(spec, camera_names, profile)
%
%   spec          acquisition_spec, with its waveform
%   camera_names  names of the rig's cameras, in Luminos order
%                 (app.getDevice('Camera'); frames<k>.bin follows it)
%
%   plan(k): name, role ("imaging", "behavior" or "other"),
%   frametrigger_source, frames_requested, acquisition_exposure_s, and
%   file ("frames<k>.bin").
%
%   Nothing is planned from timing: each triggered camera takes one frame
%   per rising edge of its trigger row, exactly as the protocol's samples
%   say, and the imaging camera's count must equal spec.n_frames. Luminos
%   records every camera, so a camera the protocol does not trigger takes
%   one free-running frame ("Off").
rows = string(spec.waveform.channels(:));
imaging_frames = rising_edges(spec.waveform, rows, profile.camera_trigger_row);
if imaging_frames ~= spec.n_frames
    error("hadamard_stim:CameraFrameMismatch", ...
        "The %s waveform triggers the camera %d times but the acquisition expects %d frames.", ...
        spec.kind, imaging_frames, spec.n_frames);
end
behavior_frames = rising_edges(spec.waveform, rows, profile.behavior_trigger_row);

plan = struct("name", {}, "role", {}, "frametrigger_source", {}, ...
    "frames_requested", {}, "acquisition_exposure_s", {}, "file", {});
for k = 1:numel(camera_names)
    name = string(camera_names(k));
    entry = struct("name", name, "role", "other", "frametrigger_source", "Off", ...
        "frames_requested", 1, "acquisition_exposure_s", NaN, ...
        "file", "frames" + k + ".bin");
    if name == profile.devices.camera.name
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
        profile.devices.camera.name);
end
end

function n = rising_edges(waveform, rows, name)
k = find(rows == name, 1);
if isempty(k)
    n = 0;
    return
end
x = waveform.amplitude(k, :) > 0;
n = nnz(diff([false x]) > 0);
end
