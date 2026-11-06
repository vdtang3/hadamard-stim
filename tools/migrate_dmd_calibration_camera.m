function report = migrate_dmd_calibration_camera(dmd, from, to, options)
%MIGRATE_DMD_CALIBRATION_CAMERA Give a DMD's stored camera calibration the camera's new name. Once.
%
%   report = migrate_dmd_calibration_camera(dmd, "Kinetix", "Teledyne Kinetix")
%   report = migrate_dmd_calibration_camera(..., dry_run=true)
%
%   Run on the rig, in Luminos's MATLAB, with the DMD device:
%       dmd = app.getDevice("ALP_DMD");
%       migrate_dmd_calibration_camera(dmd, "Kinetix", "Teledyne Kinetix")
%
%   Luminos stores one camera-to-DMD calibration per camera NAME
%   (Patterning_Device, additionalConfigData "calibrations"), so when Firefly's
%   Kinetix was renamed from "Kinetix" to "Teledyne Kinetix" its calibration
%   stayed under the old name and the new name has none. The transform is in
%   sensor coordinates and belongs to the camera and light path, not to the
%   name, so it is copied to the new name unchanged:
%
%     * the "from" entry must exist, be recorded for that camera, and hold a
%       non-identity, finite transform with a matrix;
%     * a "to" entry that already exists is left alone: an identical one is
%       reported as already migrated, a different one is a refusal (the camera
%       was calibrated under its new name since - nothing to migrate);
%     * the DMD's config file is copied to <file>.backup-<UTC time> first;
%     * the "from" entry, every other camera's entry (the Libra's included) and
%       the saved-calibration library are not touched;
%     * the copy records migrated_from and migrated_utc, and is made the most
%       recently active calibration and selected (use_calibration_camera), so
%       the DMD projects through it now and at the next start;
%     * afterwards calibration_identity(to) must report the copied transform as
%       the active one, or the tool says so.
%
%   dry_run reports what would happen and changes nothing.
arguments
    dmd
    from (1, 1) string
    to (1, 1) string
    options.dry_run (1, 1) logical = false
end
report = struct("status", "", "message", "", "backup", "", "from", from, "to", to, ...
    "transform", []);

source = dmd.get_calibration_entry(from);
if isempty(source) || ~isfield(source, "tform") || isempty(source.tform)
    report = refuse(report, sprintf('%s holds no calibration stored for "%s".', dmd.name, from));
    return
end
if isfield(source, "camera") && strlength(string(source.camera)) > 0 ...
        && ~strcmpi(strtrim(string(source.camera)), strtrim(from))
    report = refuse(report, sprintf(['The entry stored under "%s" says it was measured on "%s"; ' ...
        'not migrating an entry whose identity does not match its key.'], from, string(source.camera)));
    return
end
matrix = transform_matrix(source.tform);
if isempty(matrix) || any(~isfinite(matrix(:))) || isequal(matrix, eye(3))
    report = refuse(report, sprintf(['The "%s" calibration has no usable matrix (empty, identity ' ...
        'or not finite); calibrate the camera instead.'], from));
    return
end
report.transform = matrix;

existing = dmd.get_calibration_entry(to);
if ~isempty(existing) && isfield(existing, "tform") && ~isempty(existing.tform)
    if same_matrix(transform_matrix(existing.tform), matrix)
        report.status = "already_migrated";
        report.message = sprintf('"%s" already holds the "%s" calibration.', to, from);
        if ~options.dry_run
            dmd.use_calibration_camera(to);
        end
        return
    end
    report = refuse(report, sprintf(['"%s" already has its own, different calibration; ' ...
        'nothing was changed.'], to));
    return
end

if options.dry_run
    report.status = "dry_run";
    report.message = sprintf('Would copy the "%s" calibration of %s to "%s".', from, dmd.name, to);
    return
end

file = string(dmd.additionalConfigData.filePath);
if isfile(file)
    stamp = string(datetime("now", "TimeZone", "UTC", "Format", "yyyyMMdd'T'HHmmss'Z'"));
    report.backup = file + ".backup-" + stamp;
    copyfile(file, report.backup);
end

entry = source;
entry.camera = char(to);
entry.migrated_from = char(from);
now_ = posixtime(datetime("now", "TimeZone", "UTC"));
entry.migrated_utc = now_;
entry.active_utc = now_;
store = dmd.calibration_store();
key = matlab.lang.makeValidName(char(strtrim(to)));   % Patterning_Device.calibration_key
store.(key) = entry;
dmd.additionalConfigData.set("calibrations", store);
dmd.use_calibration_camera(to);

identity = dmd.calibration_identity(to);
if ~identity.has_pair_calibration || ~identity.active_transform_is_pair_transform ...
        || ~same_matrix(transform_matrix(identity.pair_transform), matrix)
    report = refuse(report, sprintf(['Copied, but %s does not report the copied transform as the ' ...
        'active "%s" calibration. The original file is at %s.'], dmd.name, to, report.backup));
    return
end
report.status = "migrated";
report.message = sprintf(['Copied the "%s" calibration of %s to "%s" and selected it; "%s" and ' ...
    'every other camera''s entry are unchanged. Backup: %s.'], from, dmd.name, to, from, report.backup);
fprintf('%s\n', report.message);
end


function report = refuse(report, message)
report.status = "refused";
report.message = string(message);
warning("migrate_dmd_calibration_camera:Refused", "%s", message);
end

function m = transform_matrix(t)
m = [];
if isa(t, "affinetform2d") || isa(t, "projtform2d")
    m = double(t.A);
elseif isa(t, "affine2d") || isa(t, "projective2d")
    m = double(t.T)';
elseif isstruct(t) && isfield(t, "A")
    m = double(t.A);
end
end

function tf = same_matrix(a, b)
tf = ~isempty(a) && ~isempty(b) && isequal(size(a), size(b)) ...
    && max(abs(a(:) / a(end) - b(:) / b(end))) < 1e-9;
end
