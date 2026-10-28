function item = readiness_item(id, label, status, options)
%READINESS_ITEM One line of a readiness report: what was checked and what it means.
%
%   item = hadamard_stim.metadata.readiness_item(id, label, status, ...
%       message=..., consequence=..., group=..., details=...)
%
%   status       what was found:
%     "pass"        nothing to say beyond the message
%     "info"        worth knowing; nothing to acknowledge
%     "warning"     a scientific or data-quality risk; a run may still
%                   start, but only after the operator has seen it and
%                   chosen to continue (recorded)
%     "blocker"     the action is impossible, undefined, or conflicts with
%                   another owner of the hardware; no override
%     "disabled"    switched off in the configuration
%     "not_needed"  this session does not use it
%   message      what was found, in one or two sentences
%   consequence  for a warning or blocker: what it means for the data or
%                the rig, in concrete terms
%   group        where the tab shows it: "session", "rig", "calibration",
%                "commissioning" or "fov"
%   details      anything JSON-safe the tab or the record may show (dates,
%                identities, what can be reused)
%
%   item.severity is the status for warning, blocker and info, else "none";
%   item.overrideable is true exactly for a warning.
arguments
    id (1, 1) string
    label (1, 1) string
    status (1, 1) string {mustBeMember(status, ["pass" "info" "warning" "blocker" "disabled" "not_needed"])}
    options.message (1, 1) string = ""
    options.consequence (1, 1) string = ""
    options.group (1, 1) string {mustBeMember(options.group, ["session" "rig" "calibration" "commissioning" "fov"])} = "rig"
    options.details = struct()
end
severity = "none";
if ismember(status, ["warning" "blocker" "info"])
    severity = status;
end
item = struct("id", id, "label", label, "severity", severity, "status", status, ...
    "message", options.message, "consequence", options.consequence, ...
    "overrideable", status == "warning", "group", options.group, ...
    "details", options.details);
end
