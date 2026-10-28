function names = hardware_checks(session_mode)
%HARDWARE_CHECKS The recorded Firefly checks that are evidence for a session mode.
%
%   names = hadamard_stim.metadata.hardware_checks(session_mode)
%
%   connectivity  slide_queue (queue_support is history: the live driver
%                 is asked at every preflight)
%   spontaneous   none (a static mask: no queue, no DMD triggers)
%
%   The driver probe and the power-on trigger edge are not readiness
%   (hardware_gate).
if session_mode == "spontaneous"
    names = strings(1, 0);
else
    names = "slide_queue";
end
end
