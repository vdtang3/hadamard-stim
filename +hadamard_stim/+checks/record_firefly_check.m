function file = record_firefly_check(file, result)
%RECORD_FIREFLY_CHECK Write one check's outcome into the Firefly checks file.
%
%   hadamard_stim.checks.record_firefly_check(file, result)
%
%   file    the hardware validation file the tab's rig settings name (JSON)
%   result  from driver_check, trigger_edge_check, queue_support_check or
%           slide_queue_check
%
%   The entry for result.name is replaced; the other checks are kept as they
%   were. Each entry is {"passed", "evidence", "date", "details",
%   "provenance"}, what
%   hadamard_stim.metadata.hardware_gate reads. A failed check is recorded
%   too, so the file says what was tried.
arguments
    file (1, 1) string
    result (1, 1) struct
end
checks = struct();
if isfile(file)
    text = fileread(file);
    if strlength(strtrim(string(text))) > 0
        checks = jsondecode(text);
    end
end
checks.(result.name) = struct("passed", result.passed, "evidence", result.evidence, ...
    "date", result.date, "details", result.details, ...
    "provenance", field_or(result, "provenance", struct()));
folder = fileparts(file);
if strlength(folder) > 0 && ~isfolder(folder)
    mkdir(folder);
end
writelines(string(jsonencode(checks, "PrettyPrint", true)), file);
end

function v = field_or(s, name, default)
v = default;
if isfield(s, name)
    v = s.(name);
end
end
