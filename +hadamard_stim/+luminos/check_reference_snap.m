function fit = check_reference_snap(snap, dmd, camera_name, camera_roi, camera_bin)
%CHECK_REFERENCE_SNAP Whether a Snap can stand in for the reference scan on this DMD calibration.
%
%   fit = hadamard_stim.luminos.check_reference_snap(snap, dmd, camera_name, camera_roi, camera_bin)
%
%   snap is read_reference_snap's description. Cells are found on the
%   reference image and drawn on the DMD in the camera's current pixel grid
%   (active_geometry), so the Snap must be in that grid: the camera's
%   acquisition area and binning now. It need NOT be the DMD calibration's
%   area: Luminos's calibration is in sensor coordinates and serves every
%   camera area (active_geometry composes it with the area's origin), so a
%   Snap at a new field of view needs no recalibration. Nothing is
%   resampled, shifted, flipped or transposed to make a Snap fit. Refuses
%   (hadamard_stim:IncompatibleSnap), listing every problem, when:
%     * the Snap is from another camera than the one the DMD is calibrated for;
%     * the DMD has no calibration for that camera, or its active transform
%       is not that calibration, or it has no calibration reference image
%       (active_geometry's rule);
%     * the image is not one frame of the Snap's own ROI and binning
%       ([height width] / bin): a transposed or otherwise reshaped image;
%     * its ROI (origin and size, unbinned sensor pixels) or binning differ
%       from the camera's acquisition area now (camera_roi, camera_bin);
%     * the Snap recorded a transform for this DMD and it is not the
%       calibration in use (the Snap was taken under another calibration).
%   A Snap that recorded no transform for this DMD is accepted, and fit
%   says so (fit.transform_recorded false).
%
%   fit: camera, dmd, grid [rows cols], roi, bin (the Snap's, which are
%   the camera's), calibration_roi, calibration_bin, transform_recorded.
arguments
    snap struct
    dmd
    camera_name (1, 1) string
    camera_roi (1, 4) double        % [x0 y0 width height], camera_grid
    camera_bin (1, 1) double
end
problems = strings(0, 1);
if ~strcmpi(strtrim(snap.name), strtrim(camera_name))
    problems(end+1) = sprintf("it was taken on %s; the DMD is calibrated for %s", snap.name, camera_name);
end
identity = dmd.calibration_identity(camera_name);
if identity.status == "none" || ~identity.has_pair_calibration
    problems(end+1) = sprintf("%s has no calibration for %s", dmd.name, camera_name);
elseif ~identity.active_transform_is_pair_transform
    problems(end+1) = sprintf("the transform %s is using is not its %s calibration", dmd.name, camera_name);
end

frame = [snap.roi(4) snap.roi(3)] / snap.bin;
if isnan(snap.bin) || ~isequal(snap.image_size, frame)
    problems(end+1) = sprintf(['its image is %d x %d, not one frame of its own camera area ' ...
        '(%g x %g at bin %g): it is transposed, cropped or resampled'], ...
        snap.image_size(1), snap.image_size(2), frame(1), frame(2), snap.bin);
end
grid = snap.image_size;
ref_roi = [];
ref_bin = NaN;
if isempty(dmd.refimage)
    problems(end+1) = sprintf("%s has no calibration reference image (where it was calibrated is unknown)", dmd.name);
else
    [ref_bin, ref_roi] = dmd.reference_geometry();
    ref_roi = double(reshape(ref_roi, 1, []));
end
if ~isequal(double(reshape(snap.roi, 1, [])), camera_roi) || ~isequal(double(snap.bin), camera_bin)
    problems(end+1) = sprintf(['it was taken at camera area x %g, y %g, %g x %g, bin %g; %s acquires ' ...
        'x %g, y %g, %g x %g, bin %g now: set the camera to the Snap''s area and binning, or take ' ...
        'the Snap at the camera''s (no DMD recalibration is needed either way)'], snap.roi, snap.bin, ...
        camera_name, camera_roi, camera_bin);
end

recorded = [];
if ~isempty(snap.transforms)
    recorded = snap.transforms(strcmpi(strtrim([snap.transforms.name]), strtrim(string(dmd.name))));
end
if ~isempty(recorded) && identity.has_pair_calibration
    in_use = hadamard_stim.luminos.affine_matrix(identity.pair_transform);
    if isempty(in_use) || isempty(recorded(1).matrix) || ~isequal(size(in_use), size(recorded(1).matrix)) ...
            || max(abs(in_use(:) - recorded(1).matrix(:))) > 1e-9 * max(1, max(abs(in_use(:))))
        problems(end+1) = sprintf(['it recorded a different %s transform than the calibration in use: ' ...
            'it was taken under another DMD calibration; take it again'], dmd.name);
    end
end

if ~isempty(problems)
    error("hadamard_stim:IncompatibleSnap", "The Snap %s cannot be the reference image: %s.", ...
        snap.file, strjoin(problems, "; "));
end
fit = struct("camera", camera_name, "dmd", string(dmd.name), "grid", grid, ...
    "roi", double(reshape(snap.roi, 1, [])), "bin", double(snap.bin), ...
    "calibration_roi", ref_roi, "calibration_bin", double(ref_bin), ...
    "transform_recorded", ~isempty(recorded));
end
