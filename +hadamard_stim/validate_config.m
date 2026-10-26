function report = validate_config(cfg)
%VALIDATE_CONFIG Whether a configuration can run, and how it differs from his.
%
%   report = hadamard_stim.validate_config(cfg)
%
%   report.ok          no errors
%   report.errors      what must be fixed before a run, one sentence each
%   report.deviations  every setting the session uses that differs from
%                      default_config, as path, yitong (his value) and
%                      value. Empty means the run is Yitong-compatible; the
%                      recipe records them either way.
%   report.warnings    how the session differs from his collection without
%                      changing what it measures: a behaviour stream that
%                      is off, drift correction between blocks off
%   report.mode        "yitong_compatible" or "modified"
%
%   Only the settings the session mode uses are compared (connectivity
%   trials, or spontaneous blocks). Settings no evidence fixes
%   (naming.prefix, segmentation.n_exclude, stimulation.orange_start_v and,
%   for connectivity, dmd.trigger_edge) are required rather than compared;
%   the trial range is a run's scope, and behavior.* are companions, so
%   none of those is a deviation.
reference = hadamard_stim.default_config();
errors = strings(0, 1);
warnings = strings(1, 0);

session = "connectivity";
if has_path(cfg, "session.mode")
    session = string(cfg.session.mode);
end
if ~isscalar(session) || ~ismember(session, ["connectivity" "spontaneous"])
    errors(end+1) = "session.mode must be ""connectivity"" or ""spontaneous"".";
    session = "connectivity";
end
connectivity = session == "connectivity";

required = ["naming.prefix" "segmentation.n_exclude" "stimulation.orange_start_v"];
if connectivity
    required(end+1) = "dmd.trigger_edge";
end
for path = required
    v = get_path(cfg, path);
    if isempty(v) || (isstring(v) && all(strlength(v) == 0))
        errors(end+1) = path + " is not set."; %#ok<AGROW>
    end
end
for path = ["behavior.face_camera_enabled" "behavior.wheel_encoder_enabled"]
    if has_path(cfg, path) && ~is_switch(get_path(cfg, path))
        errors(end+1) = path + " must be true or false."; %#ok<AGROW>
    end
end

if connectivity
    errors = [errors(:); reshape(connectivity_errors(cfg), [], 1)];
else
    errors = [errors(:); reshape(spontaneous_errors(cfg), [], 1)];
end

skip = [required "trials.first" "trials.last" "dmd.trigger_edge"];
deviations = struct("path", {}, "yitong", {}, "value", {});
for path = leaf_paths(reference)
    if ismember(path, skip) || ~used_by(path, session)
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

if has_path(cfg, "behavior.face_camera_enabled") && isequal(cfg.behavior.face_camera_enabled, false)
    warnings(end+1) = "Face camera off: Yitong recorded face video (Grasshopper, 40 Hz) in every paper session.";
end
if ~has_path(cfg, "behavior.wheel_encoder_enabled") || ~isequal(cfg.behavior.wheel_encoder_enabled, true)
    warnings(end+1) = "Wheel encoder off: Yitong recorded the treadmill encoder on every acquisition.";
end
if ~connectivity && has_path(cfg, "spontaneous.drift_correction") ...
        && isequal(cfg.spontaneous.drift_correction, false)
    warnings(end+1) = "Drift correction between blocks off: Yitong corrected drift before every block.";
end

if ~isempty(errors)
    errors = reshape(errors, 1, []);   % one row, as before session modes
end
report.ok = isempty(errors);
report.errors = errors;
report.deviations = deviations;
report.warnings = warnings;
report.mode = "yitong_compatible";
if ~isempty(deviations)
    report.mode = "modified";
end
end

function errors = connectivity_errors(cfg)
errors = strings(0, 1);
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
end

function errors = spontaneous_errors(cfg)
errors = strings(0, 1);
s = cfg.spontaneous;
if ~is_count(s.n_blocks)
    errors(end+1) = "spontaneous.n_blocks must be a whole number of at least 1.";
end
if ~is_count(s.block_frames)
    errors(end+1) = "spontaneous.block_frames must be a whole number of at least 1.";
end
if ~is_switch(s.drift_correction)
    errors(end+1) = "spontaneous.drift_correction must be true or false.";
end
% The bleaching update is measured on each block and applied at the next
% drift correction; it is only measured when it will be applied.
if is_count(s.n_blocks) && is_count(s.block_frames) && isequal(s.drift_correction, true) ...
        && s.n_blocks > 1 && cfg.bleaching.enabled && s.block_frames < max(cfg.bleaching.frames)
    errors(end+1) = sprintf(['The bleaching update reads frames %d to %d of each block, but ' ...
        'blocks are %d frames: lengthen the blocks or turn bleaching.enabled off.'], ...
        min(cfg.bleaching.frames), max(cfg.bleaching.frames), s.block_frames);
end
end

function tf = used_by(path, session)
% Whether a setting changes what a session of this mode does.
if startsWith(path, ["session." "behavior." "calibration_scan." "schema_version" "mode"])
    tf = false;
    return
end
connectivity_only = ["dmd.picture_time_us" "matrix." "sparse." "hadamard." "trials." ...
    "stimulation.n_frames" "stimulation.n_patterns" "z_reference.enabled" ...
    "drift.enabled" "drift.retarget_every"];
if session == "connectivity"
    tf = ~startsWith(path, "spontaneous.");
else
    tf = ~any(path == connectivity_only | startsWith(path, connectivity_only(endsWith(connectivity_only, "."))));
end
end

function tf = is_switch(v)
tf = islogical(v) && isscalar(v) || (isnumeric(v) && isscalar(v) && ismember(v, [0 1]));
end

function tf = is_count(v)
tf = isnumeric(v) && isscalar(v) && isfinite(v) && v >= 1 && v == round(v);
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
