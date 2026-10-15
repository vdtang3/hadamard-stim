function names = hardware_checks(session_mode)
%HARDWARE_CHECKS The Firefly checks a session mode needs recorded as passed.
%
%   names = hadamard_stim.metadata.hardware_checks(session_mode)
%
%   connectivity  driver, trigger_edge, queue_support, slide_queue
%   spontaneous   driver (a static mask: no queue, no DMD triggers)
if session_mode == "spontaneous"
    names = "driver";
else
    names = ["driver" "trigger_edge" "queue_support" "slide_queue"];
end
end
