function mode = session_mode(cfg)
%SESSION_MODE "connectivity" or "spontaneous": what kind of session cfg describes.
%
%   mode = hadamard_stim.metadata.session_mode(cfg)
%
%   A configuration written before session modes existed is connectivity.
mode = "connectivity";
if isfield(cfg, "session") && isfield(cfg.session, "mode")
    mode = string(cfg.session.mode);
end
end
