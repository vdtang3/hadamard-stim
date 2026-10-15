function report = hardware_gate(context, session_mode)
%HARDWARE_GATE Whether Firefly has passed the checks a real acquisition needs.
%
%   report = hadamard_stim.metadata.hardware_gate(context)
%   report = hadamard_stim.metadata.hardware_gate(context, session_mode)
%
%   A connectivity run on real hardware may start only when
%   context.hardware_validation records all four Firefly checks as passed
%   (docs/notebook.md, Phase 2). A spontaneous run uses no sequence queue
%   and no triggered DMD, so it needs only the driver check:
%
%     driver          which ALP driver and version drives the board, and
%                     that it is the 1024 x 768 DMD his masks assume
%     trigger_edge    the board's power-on trigger edge (his loader
%                     inherited it); it must equal cfg.dmd.trigger_edge
%     queue_support   Supports_Sequence_Queue() is true
%     slide_queue     a small queue stepped by DAQ triggers on a slide
%                     showed what alp_queue_display predicts
%
%   Each is a struct with passed (logical), evidence (text) and date. A
%   simulated run (context.simulated true) needs none. The protocol itself
%   never waits on these: they gate acquisition, not the port.
%
%   report.ok, report.missing (names), report.validation (as recorded)
arguments
    context
    session_mode (1, 1) string = "connectivity"
end
checks = hadamard_stim.metadata.hardware_checks(session_mode);
report.validation = [];
report.missing = strings(1, 0);
if isfield(context, "simulated") && context.simulated
    report.ok = true;
    return
end
v = struct();
if isfield(context, "hardware_validation") && ~isempty(context.hardware_validation)
    v = context.hardware_validation;
end
for name = checks
    if ~isfield(v, name) || ~isfield(v.(name), "passed") || ~isequal(v.(name).passed, true)
        report.missing(end+1) = name;
    end
end
report.validation = v;
report.ok = isempty(report.missing);
end
