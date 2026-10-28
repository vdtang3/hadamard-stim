function result = check_result(name, passed, evidence, details, provenance)
%CHECK_RESULT One Firefly check's outcome, as record_firefly_check writes it.
%
%   result = hadamard_stim.checks.check_result(name, passed, evidence, details, provenance)
%
%   name      "queue_support" or "slide_queue" (the tab's DMD commissioning
%             checks, hardware_gate), or the diagnostics "driver" and
%             "trigger_edge", which readiness does not read
%   passed    logical
%   evidence  one or two sentences saying what was seen
%   details   anything JSON-safe kept beside it
%   provenance  which software and board it ran on (check_provenance);
%             default: this package's commit only
%
%   A check is evidence about the rig, not a step of every session: it is
%   recorded once and shown with its date and provenance until it is run
%   again (hardware_gate says when it is no longer evidence about this rig;
%   age alone never is).
arguments
    name (1, 1) string {mustBeMember(name, ["driver" "trigger_edge" "queue_support" "slide_queue"])}
    passed (1, 1) logical
    evidence (1, 1) string
    details = struct()
    provenance struct = hadamard_stim.checks.check_provenance()
end
result = struct("name", name, "passed", passed, "evidence", evidence, ...
    "date", string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
    "details", details, "provenance", provenance);
end
