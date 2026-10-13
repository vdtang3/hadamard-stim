function report = validate_config(cfg)
%VALIDATE_CONFIG Whether a configuration can run, and how it differs from his.
%
%   report = hadamard_stim.validate_config(cfg)
%
%   report.ok          no errors
%   report.errors      what must be fixed before a run, one sentence each
%   report.deviations  every setting that differs from default_config, as
%                      path, yitong (his value) and value. Empty means the
%                      run is Yitong-compatible; the recipe records them
%                      either way.
%   report.mode        "yitong_compatible" or "modified"
%
%   Settings no evidence fixes (naming.prefix, segmentation.n_exclude,
%   stimulation.orange_start_v, dmd.trigger_edge) are required rather than
%   compared, and the trial range is a run's scope, not a deviation.
reference = hadamard_stim.default_config();
errors = strings(0, 1);

required = ["naming.prefix" "segmentation.n_exclude" "stimulation.orange_start_v" "dmd.trigger_edge"];
for path = required
    v = get_path(cfg, path);
    if isempty(v) || (isstring(v) && all(strlength(v) == 0))
        errors(end+1) = path + " is not set."; %#ok<AGROW>
    end
end
if ~isempty(cfg.dmd.trigger_edge) && strlength(cfg.dmd.trigger_edge) > 0 && ...
        ~ismember(cfg.dmd.trigger_edge, ["rising" "falling"])
    errors(end+1) = "dmd.trigger_edge must be ""rising"" or ""falling"".";
end
if ~isscalar(cfg.sparse.blue_v)
    errors(end+1) = "sparse.blue_v must be one value: with several, his loop loaded a " + ...
        "queue per value but acquired only the last.";
end
codes = cfg.sparse.n_pulses * cfg.sparse.period_frames / cfg.hadamard.frames_per_code;
if codes ~= round(codes) || codes < 1
    errors(end+1) = "A Hadamard trial must last as long as a sparse trial: " + ...
        "sparse.n_pulses x sparse.period_frames / hadamard.frames_per_code is not a whole number.";
elseif mod(cfg.matrix.order, codes) ~= 0
    errors(end+1) = sprintf("matrix.order (%d) must be a multiple of the %d codes per trial.", ...
        cfg.matrix.order, codes);
end
n_had = cfg.trials.n_trial - cfg.trials.n_sparse;
if n_had < 1 || mod(cfg.trials.n_trial, n_had) ~= 0
    errors(end+1) = "trials.n_trial must be a multiple of the number of Hadamard trials " + ...
        "(trials.n_trial - trials.n_sparse).";
end
if cfg.matrix.order ~= cfg.segmentation.threshold
    errors(end+1) = sprintf("segmentation.threshold (%d cells) must equal matrix.order (%d rows).", ...
        cfg.segmentation.threshold, cfg.matrix.order);
end
if cfg.trials.first < 1 || cfg.trials.last > cfg.trials.n_trial || cfg.trials.first > cfg.trials.last
    errors(end+1) = sprintf("Trials %d to %d are not within 1 to %d.", ...
        cfg.trials.first, cfg.trials.last, cfg.trials.n_trial);
end

skip = [required "trials.first" "trials.last"];
deviations = struct("path", {}, "yitong", {}, "value", {});
for path = leaf_paths(reference)
    if ismember(path, skip)
        continue
    end
    if ~has_path(cfg, path)
        errors(end+1) = path + " is missing."; %#ok<AGROW>
        continue
    end
    if ~isequal(get_path(cfg, path), get_path(reference, path))
        deviations(end+1) = struct("path", path, "yitong", get_path(reference, path), ...
            "value", get_path(cfg, path)); %#ok<AGROW>
    end
end

report.ok = isempty(errors);
report.errors = errors;
report.deviations = deviations;
report.mode = "yitong_compatible";
if ~isempty(deviations)
    report.mode = "modified";
end
end

function paths = leaf_paths(s, prefix)
if nargin < 2
    prefix = "";
end
paths = strings(1, 0);
for name = string(fieldnames(s))'
    path = name;
    if strlength(prefix) > 0
        path = prefix + "." + name;
    end
    if isstruct(s.(name)) && isscalar(s.(name))
        paths = [paths leaf_paths(s.(name), path)]; %#ok<AGROW>
    else
        paths(end+1) = path; %#ok<AGROW>
    end
end
end

function v = get_path(s, path)
v = s;
for part = split(path, ".")'
    v = v.(part);
end
end

function tf = has_path(s, path)
tf = true;
v = s;
for part = split(path, ".")'
    if ~isstruct(v) || ~isfield(v, part)
        tf = false;
        return
    end
    v = v.(part);
end
end
