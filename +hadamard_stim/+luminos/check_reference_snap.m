function fit = check_reference_snap(snap, dmd, camera_name, camera_roi, camera_bin)
%CHECK_REFERENCE_SNAP Whether a Snap can stand in for the reference scan on this DMD calibration.
%
%   fit = hadamard_stim.luminos.check_reference_snap(snap, dmd, camera_name, camera_roi, camera_bin)
%
%   snap is read_reference_snap's description. Cells are found on the
%   Snap and drawn on the DMD in the Snap's own pixel grid: its recorded
%   camera area and binning, composed with the camera's stored calibration
%   (active_geometry), which belongs to the camera, not to a field of view.
%   Nothing is resampled, shifted, flipped or transposed.
%
%   Refuses (hadamard_stim:IncompatibleSnap), listing every problem, only
%   when its pixels cannot be placed on the DMD:
%     * the Snap is from another camera than the imaging camera (the
%       Kinetix under either of its names is the same camera);
%     * the DMD has no calibration stored for that camera;
%     * the image is not one frame of the Snap's own recorded area and
%       binning ([height width] / bin), or no binning is recorded: its
%       pixels cannot be located on the sensor.
%   Warns (fit.warnings), and accepts, when:
%     * the camera now acquires another area or binning than the Snap's:
%       the mask is right (drawn from the Snap's area), but the run's images
%       are in another pixel grid than the reference image and its cells;
%     * the Snap recorded another transform for this DMD than the stored
%       calibration: it was taken while another calibration was active (at
%       startup Luminos reactivates the last one used, which may be another
%       camera's) or before a recalibration. The stored calibration is used.
%   Where the Snap lies beyond the area the calibration was measured on is
%   active_geometry's warning (extrapolation), not a refusal.
%
%   fit: camera, dmd, grid [rows cols], roi, bin (the Snap's), camera_roi,
%   camera_bin (the camera's now), calibration_roi, calibration_bin,
%   transform_recorded, transform_matches, warnings.
arguments
    snap struct
    dmd
    camera_name (1, 1) string
    camera_roi (1, 4) double        % [x0 y0 width height], camera_grid
    camera_bin (1, 1) double
end
problems = strings(0, 1);
warnings = strings(0, 1);
if ~same_camera(snap.name, camera_name)
    problems(end+1) = sprintf("it was taken on %s; the DMD is calibrated for %s", snap.name, camera_name);
end
identity = dmd.calibration_identity(camera_name);
if identity.status == "none" || ~identity.has_pair_calibration
    problems(end+1) = sprintf("%s has no calibration for %s", dmd.name, camera_name);
end

frame = [snap.roi(4) snap.roi(3)] / snap.bin;
if isnan(snap.bin) || ~isequal(snap.image_size, frame)
    problems(end+1) = sprintf(['its image is %d x %d, not one frame of its own camera area ' ...
        '(%g x %g at bin %g): it is transposed, cropped or resampled, or its binning is not recorded'], ...
        snap.image_size(1), snap.image_size(2), frame(1), frame(2), snap.bin);
end
grid = snap.image_size;
calibration_roi = double(reshape(identity.roi, 1, []));
calibration_bin = double(identity.bin);
if ~isequal(double(reshape(snap.roi, 1, [])), camera_roi) || ~isequal(double(snap.bin), camera_bin)
    warnings(end+1) = sprintf(['The Snap was taken at camera area x %g, y %g, %g x %g, bin %g; %s acquires ' ...
        'x %g, y %g, %g x %g, bin %g now. Its cells are drawn on the DMD from the Snap''s area (no ' ...
        'recalibration needed), but the run''s images will be in another pixel grid than the reference.'], ...
        snap.roi, snap.bin, camera_name, camera_roi, camera_bin);
end

recorded = [];
matches = true;
if ~isempty(snap.transforms)
    recorded = snap.transforms(strcmpi(strtrim([snap.transforms.name]), strtrim(string(dmd.name))));
end
if ~isempty(recorded) && identity.has_pair_calibration
    in_use = hadamard_stim.luminos.affine_matrix(identity.pair_transform);
    matches = ~(isempty(in_use) || isempty(recorded(1).matrix) || ~isequal(size(in_use), size(recorded(1).matrix)) ...
        || max(abs(in_use(:) - recorded(1).matrix(:))) > 1e-9 * max(1, max(abs(in_use(:)))));
    if ~matches
        warnings(end+1) = sprintf(['The Snap recorded another %s transform than the %s calibration: it ' ...
            'was taken while another calibration was active, or before a recalibration. The stored ' ...
            '%s calibration is used.'], dmd.name, camera_name, camera_name);
    end
end

if ~isempty(problems)
    error("hadamard_stim:IncompatibleSnap", "The Snap %s cannot be the reference image: %s.", ...
        snap.file, strjoin(problems, "; "));
end
fit = struct("camera", camera_name, "dmd", string(dmd.name), "grid", grid, ...
    "roi", double(reshape(snap.roi, 1, [])), "bin", double(snap.bin), ...
    "camera_roi", camera_roi, "camera_bin", camera_bin, ...
    "calibration_roi", calibration_roi, "calibration_bin", calibration_bin, ...
    "transform_recorded", ~isempty(recorded), "transform_matches", matches, ...
    "warnings", warnings);
end

function tf = same_camera(a, b)
% One camera: the same name, or the Kinetix under either of its names
% ("Kinetix", "Teledyne Kinetix"; it was renamed in the rig file).
a = lower(strtrim(string(a)));
b = lower(strtrim(string(b)));
tf = a == b || (contains(a, "kinetix") && contains(b, "kinetix"));
end
