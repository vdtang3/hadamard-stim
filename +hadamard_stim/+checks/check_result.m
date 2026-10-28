function result = check_result(name, passed, evidence, details)
%CHECK_RESULT One Firefly check's outcome, as record_firefly_check writes it.
%
%   result = hadamard_stim.checks.check_result(name, passed, evidence, details)
%
%   name      "driver", "trigger_edge", "queue_support" or "slide_queue"
%             (hadamard_stim.metadata.hardware_checks)
%   passed    logical
%   evidence  one or two sentences saying what was seen
%   details   anything JSON-safe kept beside it
arguments
    name (1, 1) string {mustBeMember(name, ["driver" "trigger_edge" "queue_support" "slide_queue"])}
    passed (1, 1) logical
    evidence (1, 1) string
    details = struct()
end
result = struct("name", name, "passed", passed, "evidence", evidence, ...
    "date", string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
    "details", details);
end
