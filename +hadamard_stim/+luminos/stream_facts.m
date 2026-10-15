function facts = stream_facts(devices, profile, encoder_lines, daq_rate)
%STREAM_FACTS The optional streams' hardware, as the run recipe records it.
%
%   facts = hadamard_stim.luminos.stream_facts(devices, profile, encoder_lines, daq_rate)
%
%   facts.face_camera    the behaviour camera Luminos records, the line that
%                        triggers it and the IR light's output
%   facts.wheel_encoder  the A/B lines, how and on what clock they are
%                        sampled, and where Luminos stores them
%   Whether each stream is on is the configuration's (stream_record).
cam = devices.behavior_camera;
name = profile.devices.behavior_camera.name;
if isempty(cam)
    camera = struct("name", name, "present", false);
else
    camera = struct("name", string(cam.name), "present", true, ...
        "type", fact(cam, "type"), "cam_id", fact(cam, "cam_id"));
end
port = @(row) string(profile.channels(string({profile.channels.name}) == row).port);
facts.face_camera = struct("camera", camera, ...
    "trigger", struct("row", profile.behavior_trigger_row, "port", port(profile.behavior_trigger_row)), ...
    "illumination", struct("row", "IRVoltage", "port", port("IRVoltage")), ...
    "method", "Luminos camera acquisition, one frame per DAQ trigger edge (replaces SpinView)", ...
    "file", "frames<k>.bin in each acquisition folder (k: the camera's Luminos order)");
facts.wheel_encoder = struct("names", profile.wheel_encoder.names, "lines", encoder_lines, ...
    "line_source", profile.wheel_encoder.source, ...
    "method", "Luminos buffered digital input (wfm_data.di): raw A/B levels, not decoded", ...
    "clock", "the acquisition's DAQ sample clock, shared with the camera triggers", ...
    "rate_hz", daq_rate, ...
    "file", "output_data.mat in each acquisition folder (Device_Data, the DAQ's digital-input task)");
end

function v = fact(object, name)
v = "unavailable";
try
    if isprop(object, name)
        v = object.(name);
    end
catch
end
end
