function streams = acquisition_streams(cfg, kind)
%ACQUISITION_STREAMS Which optional companions an acquisition records.
%
%   streams = hadamard_stim.protocol.acquisition_streams(cfg, kind)
%
%   streams.face_camera    the Grasshopper records face video. Only in
%                          acquisitions whose waveform triggers it
%                          (stimulation trials and spontaneous blocks), and
%                          only when cfg.behavior.face_camera_enabled
%   streams.wheel_encoder  the encoder's A/B lines are sampled on the
%                          acquisition clock, in every acquisition, as his
%                          DAQ recorded them, when
%                          cfg.behavior.wheel_encoder_enabled
%
%   Neither changes what the protocol plays: with the face camera off the
%   rig leaves its trigger (and the IR light) undriven, and the samples
%   the protocol computed are unchanged.
triggered = ismember(kind, ["stimulation" "spontaneous"]);
streams.face_camera = triggered && isequal(field(cfg, "face_camera_enabled", true), true);
streams.wheel_encoder = isequal(field(cfg, "wheel_encoder_enabled", false), true);
end

function v = field(cfg, name, default)
v = default;
if isfield(cfg, "behavior") && isfield(cfg.behavior, name)
    v = cfg.behavior.(name);
end
end
