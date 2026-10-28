function result = driver_check(report)
%DRIVER_CHECK Firefly check 1: an ALP driver opens the board and knows its 1024 x 768 DMD.
%
%   result = hadamard_stim.checks.driver_check()          % runs ALP_DMD.Probe_Drivers()
%   result = hadamard_stim.checks.driver_check(report)    % a probe report already taken
%
%   Run it with Luminos closed: a board Luminos holds cannot be opened by
%   the probe. Passes when some driver opened a board, recognised its DMD,
%   and the DMD is 1024 x 768 (his masks are packed for an XGA board).
if nargin < 1
    report = ALP_DMD.Probe_Drivers();
end
rows = strings(0, 1);
good = strings(0, 1);
for r = reshape(report, 1, [])
    if r.status ~= 0
        rows(end+1) = sprintf("%s %s: did not open a board (%s)", r.dll, r.version, r.status_text); %#ok<AGROW>
        continue
    end
    line = sprintf("%s %s (%s): serial %d, %s %dx%d, recognised %s", r.dll, r.version, ...
        r.suite, r.serial, r.chipset, r.width, r.height, string(logical(r.recognised)));
    rows(end+1) = line; %#ok<AGROW>
    if logical(r.recognised) && r.width == 1024 && r.height == 768
        good(end+1) = line; %#ok<AGROW>
    end
end
if isempty(report)
    evidence = "No ALP driver DLL could be loaded.";
elseif isempty(good)
    evidence = "No driver opened a board and recognised a 1024 x 768 DMD: " + strjoin(rows, "; ") + ".";
else
    evidence = "Opens and recognises the board: " + good(1) + ".";
end
result = hadamard_stim.checks.check_result("driver", ~isempty(good), evidence, ...
    struct("drivers", rows));
end
