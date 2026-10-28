function report = hardware_gate(context, session_mode, current)
%HARDWARE_GATE What the recorded DMD commissioning checks say about this rig.
%
%   report = hadamard_stim.metadata.hardware_gate(context)
%   report = hadamard_stim.metadata.hardware_gate(context, session_mode)
%   report = hadamard_stim.metadata.hardware_gate(context, session_mode, current)
%
%   Two checks are run from the tab and kept in the hardware validation
%   file (docs/notebook.md, 2026-10-28). A connectivity session uses both;
%   a spontaneous one neither (a static mask: no queue, no DMD triggers):
%
%     queue_support   Supports_Sequence_Queue() was true. History only:
%                     the preflight asks the live driver every time
%                     (dmd_queue), and that live answer is what blocks.
%                     Never a warning, whatever the record says.
%     slide_queue     a small queue, loaded by Load_Sequence_Queue on the
%                     protocol's edge and stepped by DAQ triggers on a
%                     uniform slide, showed what alp_queue_display
%                     predicts. Not recorded, failed, or no longer
%                     evidence about this rig (another DMD, another edge,
%                     Luminos's DMD code changed since) is a warning.
%
%   The driver probe (checks.driver_check) and the board's power-on edge
%   (checks.trigger_edge_check) are not readiness: the probe needs Luminos
%   closed and is an installation step (README), and the queue's edge is
%   set explicitly by the protocol (cfg.dmd.trigger_edge, "rising").
%
%   Age never changes a status: it is shown (calibration_age) and the
%   experimenter decides whether to rerun.
%
%   Each record is {passed, evidence, date, details, provenance}
%   (hadamard_stim.checks.check_result). current, all optional, is what the
%   records are compared with:
%     now               datetime (default: now)
%     trigger_edge      the edge the protocol loads queues on
%     luminos_commit    the Luminos commit running now
%     hadamard_commit   this package's commit
%     dmd_serial        the open board's serial
%     dmd_code_changed  whether Luminos's DMD code differs between the
%                       slide_queue record's commit and now: true, false,
%                       or [] when it could not be told (dmd_code_changed)
%     dmd_code_changes  the files that differ, when changed
%
%   report.items       one readiness_item per check (group "commissioning");
%                      empty for a simulated context
%   report.missing     the evidence checks this mode uses that are not
%                      recorded as passed (hardware_checks)
%   report.all_passed  isempty(missing)
%   report.validation  the records, as read
arguments
    context
    session_mode (1, 1) string = "connectivity"
    current struct = struct()
end
needed = hadamard_stim.metadata.hardware_checks(session_mode);
report.validation = [];
report.missing = strings(1, 0);
report.items = hadamard_stim.metadata.readiness_report(struct([])).checks;
v = struct();
if isfield(context, "hardware_validation") && ~isempty(context.hardware_validation)
    v = context.hardware_validation;
end
report.validation = v;
simulated = isfield(context, "simulated") && isequal(context.simulated, true);
for name = needed
    if ~passed(v, name)
        report.missing(end+1) = name;
    end
end
report.all_passed = simulated || isempty(report.missing);
if simulated
    report.missing = strings(1, 0);
    return
end
now_utc = option(current, "now", datetime("now", "TimeZone", "UTC"));
labels = struct("queue_support", "Sequence queue", "slide_queue", "Queue playback on slide");
if session_mode == "spontaneous"
    for name = ["queue_support" "slide_queue"]
        report.items(end+1) = hadamard_stim.metadata.readiness_item("firefly_" + name, ...
            labels.(name), "not_needed", group="commissioning", ...
            message="Not needed: spontaneous blocks use no sequence queue or DMD triggers.");
    end
    return
end
report.items(end+1) = queue_support_item(v, labels.queue_support, now_utc);
report.items(end+1) = slide_queue_item(v, labels.slide_queue, now_utc, current);
end

function item = queue_support_item(v, label, now_utc)
% The recorded answer, shown as history: the live preflight answer is the
% one that counts.
id = "firefly_queue_support";
details = record_details(v, "queue_support", now_utc, "tab");
live = "The preflight asks the live driver every time (DMD sequence queue support).";
if ~details.recorded
    item = hadamard_stim.metadata.readiness_item(id, label, "info", group="commissioning", ...
        details=details, message="No run of this check recorded. " + live);
elseif ~details.passed
    item = hadamard_stim.metadata.readiness_item(id, label, "info", group="commissioning", ...
        details=details, message="Recorded unsupported " + details.ago + ". " + live);
else
    item = hadamard_stim.metadata.readiness_item(id, label, "pass", group="commissioning", ...
        details=details, message="Supported, recorded " + details.ago + ".");
end
end

function item = slide_queue_item(v, label, now_utc, current)
id = "firefly_slide_queue";
details = record_details(v, "slide_queue", now_utc, "tab (uniform slide in place)");
if ~details.recorded
    item = hadamard_stim.metadata.readiness_item(id, label, "warning", group="commissioning", ...
        details=details, message="Never run on this rig.", consequence= ...
        "DMD sequence playback has not been verified on a slide. The queue may not step through " + ...
        "the pictures as the protocol models, so the patterns delivered could differ from the " + ...
        "patterns in the trial records.");
    return
end
r = v.slide_queue;
edge = "";
if isfield(r, "details") && isstruct(r.details) && isfield(r.details, "trigger_edge")
    edge = string(r.details.trigger_edge);
end
details.trigger_edge = edge;
if ~details.passed
    item = hadamard_stim.metadata.readiness_item(id, label, "warning", group="commissioning", ...
        details=details, message="FAILED " + details.ago + ": " + details.evidence, consequence= ...
        "The last slide test showed the DMD queue NOT playing as the protocol models. Stimulation " + ...
        "patterns in this run may not be the patterns in the trial records; continue only to " + ...
        "collect diagnostic data.");
    return
end
% Passed: is it still evidence about this rig?
warnings = strings(1, 0);
notes = strings(1, 0);
configured = string(option(current, "trigger_edge", ""));
if strlength(configured) > 0 && strlength(edge) > 0 && configured ~= edge
    warnings(end+1) = sprintf(['It was run on the %s edge; the protocol loads queues on the ' ...
        '%s edge, which this record says nothing about.'], edge, configured);
end
p = details.provenance;
if isempty(p)
    notes(end+1) = "Recorded before software provenance was kept with each check.";
else
    now_serial = string(option(current, "dmd_serial", ""));
    then_serial = text_of(p, "dmd_serial");
    if differs(now_serial, then_serial)
        warnings(end+1) = sprintf("It was run on DMD serial %s; the open board is %s.", ...
            then_serial, now_serial);
    end
    now_luminos = string(option(current, "luminos_commit", ""));
    then_luminos = text_of(p, "luminos_commit");
    if differs(now_luminos, then_luminos)
        changed = option(current, "dmd_code_changed", []);
        if isequal(changed, true)
            files = string(option(current, "dmd_code_changes", strings(1, 0)));
            warnings(end+1) = sprintf(['Luminos''s DMD code changed since it was run (Luminos %s, ' ...
                'now %s: %s).'], short(then_luminos), short(now_luminos), list(files));
        elseif isequal(changed, false)
            notes(end+1) = sprintf(['Run under Luminos %s (now %s); Luminos''s DMD code is the ' ...
                'same.'], short(then_luminos), short(now_luminos));
        else
            notes(end+1) = sprintf(['Run under Luminos %s (now %s); whether its DMD code changed ' ...
                'could not be told.'], short(then_luminos), short(now_luminos));
        end
    end
    now_package = string(option(current, "hadamard_commit", ""));
    then_package = text_of(p, "hadamard_stim_commit");
    if differs(now_package, then_package)
        notes(end+1) = sprintf("Run under hadamard-stim %s (now %s).", ...
            short(then_package), short(now_package));
    end
end
message = "Verified " + details.ago + ": " + details.evidence;
if ~isempty(notes)
    message = message + " " + strjoin(notes, " ");
end
if ~isempty(warnings)
    item = hadamard_stim.metadata.readiness_item(id, label, "warning", group="commissioning", ...
        details=details, message=message, consequence=strjoin(warnings, " ") + ...
        " Run it again on the slide to verify playback on this rig as it is now.");
elseif ~isempty(notes)
    item = hadamard_stim.metadata.readiness_item(id, label, "info", group="commissioning", ...
        details=details, message=message);
else
    item = hadamard_stim.metadata.readiness_item(id, label, "pass", group="commissioning", ...
        details=details, message=message);
end
end

function details = record_details(v, name, now_utc, rerun)
details = struct("check", name, "recorded", false, "passed", false, "date", "", ...
    "taken", "", "ago", "", "age_days", [], "evidence", "", "provenance", [], "rerun", rerun);
if ~isfield(v, name) || ~isstruct(v.(name)) || ~isfield(v.(name), "passed")
    return
end
r = v.(name);
details.recorded = true;
details.passed = isequal(r.passed, true);
details.date = text_of(r, "date");
details.evidence = text_of(r, "evidence");
if isfield(r, "provenance")
    details.provenance = r.provenance;
end
age = hadamard_stim.metadata.calibration_age(details.date, now_utc);
details.taken = age.taken;
details.ago = age.ago;
details.age_days = age.age_days;
end

function tf = passed(v, name)
tf = isfield(v, name) && isstruct(v.(name)) && isfield(v.(name), "passed") ...
    && isequal(v.(name).passed, true);
end

function v = option(s, name, default)
v = default;
if isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
end
end

function t = text_of(s, name)
t = "";
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    t = string(s.(name));
end
end

function tf = differs(now_value, then_value)
% Only two known values can differ: "unknown", "unavailable" or "Luminos
% closed" say nothing.
known = @(x) strlength(x) > 0 && ~ismember(lower(x), ["unknown" "unavailable" "not_applicable"]) ...
    && ~startsWith(lower(x), "luminos closed");
tf = known(string(now_value)) && known(string(then_value)) && string(now_value) ~= string(then_value);
end

function t = short(commit)
t = extractBefore(string(commit) + "        ", 9);
t = strip(t);
end

function t = list(files)
files = reshape(string(files), 1, []);
if isempty(files)
    t = "files not listed";
elseif numel(files) <= 3
    t = strjoin(files, ", ");
else
    t = strjoin(files(1:3), ", ") + sprintf(" and %d more", numel(files) - 3);
end
end
