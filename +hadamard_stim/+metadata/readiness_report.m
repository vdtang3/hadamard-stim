function report = readiness_report(checks)
%READINESS_REPORT Whether an action can go ahead, from its readiness items.
%
%   report = hadamard_stim.metadata.readiness_report(checks)
%
%   checks  struct array of hadamard_stim.metadata.readiness_item
%
%   report.can_run   no blockers. Warnings never make it false: they need
%                    the operator's "Continue anyway" before a run starts
%                    (HadamardStimController.startRun), nothing more.
%   report.blockers  the items with status "blocker"
%   report.warnings  the items with status "warning"
%   report.info      the items with status "info"
%   report.checks    every item, in order
%   report.failures  the blockers' messages, one string each, for an
%                    error that names them all
%
%   The policy (Vincent, 2026-10-27): scientific uncertainty is shown,
%   warned about and recorded; only a hardware conflict or an undefined
%   execution blocks.
arguments
    checks struct
end
if isempty(checks)
    checks = hadamard_stim.metadata.readiness_item("none", "none", "pass");
    checks = checks([]);
end
checks = reshape(checks, 1, []);
status = string({checks.status});
report.can_run = ~any(status == "blocker");
report.blockers = checks(status == "blocker");
report.warnings = checks(status == "warning");
report.info = checks(status == "info");
report.checks = checks;
report.failures = strings(0, 1);
for b = report.blockers
    text = b.message;
    if strlength(b.consequence) > 0
        text = text + " " + b.consequence;
    end
    report.failures(end+1, 1) = strip(text);
end
end
