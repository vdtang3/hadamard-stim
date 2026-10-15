function streams = stream_record(cfg, context)
%STREAM_RECORD What a run recipe says about its optional companions.
%
%   streams = hadamard_stim.metadata.stream_record(cfg, context)
%
%   streams.face_camera, .wheel_encoder   enabled, status ("recorded" or
%       "disabled in the configuration"), and when enabled the hardware:
%       device identity, mapping, acquisition method, clock and where the
%       data go, as context.streams (the Luminos adapter's facts) gives
%       them. A disabled stream is recorded as deliberately off, so a
%       missing video or encoder file is never left to be guessed at.
%   streams.drift_correction              enabled, and when: before every
%       block (spontaneous) or every drift.retarget_every trials
%       (connectivity)
mode = hadamard_stim.metadata.session_mode(cfg);
facts = struct();
if isfield(context, "streams") && isstruct(context.streams)
    facts = context.streams;
end

streams.face_camera = describe(flag(cfg, "face_camera_enabled", true), facts, "face_camera");
streams.wheel_encoder = describe(flag(cfg, "wheel_encoder_enabled", false), facts, "wheel_encoder");
if mode == "spontaneous"
    streams.drift_correction = struct("enabled", isequal(cfg.spontaneous.drift_correction, true), ...
        "schedule", "before every block");
else
    streams.drift_correction = struct("enabled", isequal(cfg.drift.enabled, true), ...
        "schedule", sprintf("at trial 1 and every %d trials", cfg.drift.retarget_every));
end
end

function s = describe(enabled, facts, name)
s = struct("enabled", enabled, "status", "disabled in the configuration", "hardware", []);
if enabled
    s.status = "recorded";
    if isfield(facts, name)
        s.hardware = facts.(name);
    else
        s.hardware = "not described (simulated rig)";
    end
end
end

function v = flag(cfg, name, default)
v = default;
if isfield(cfg, "behavior") && isfield(cfg.behavior, name)
    v = isequal(cfg.behavior.(name), true);
end
end
