function geometry = active_geometry(dmd, camera)
%ACTIVE_GEOMETRY Camera-to-DMD mapping from the active Luminos calibration.
%
%   geometry = hadamard_stim.luminos.active_geometry(dmd, camera)
%
%   The rig's counterpart of hadamard_stim.testing.yitong_affine_geometry,
%   behind the same interface:
%     mask = geometry.rasterize(spots, kind)
%         spots are camera-space polygons ({[n x 2] x, y}) in the pixel grid
%         of the reference image the cells were found on; mask is logical,
%         Luminos canvas orientation (dmd.Pattern_Canvas_Size()).
%     geometry.scan_area   all true, in his [L x W] orientation
%     geometry.identity    the calibration used, JSON-safe
%
%   Spots are filled in camera space and warped onto the DMD by Luminos's
%   own setPatterningROI (write_when_complete = false, so nothing is
%   projected). Parity is at the level of camera-space ROIs (notebook,
%   finding 4); his affine registration and lost correction transform are
%   replaced, a standing deviation. Without his saved_mask both kinds of
%   drawing are the same (P3 is moot on the rig).
%
%   Refuses unless the DMD holds a per-camera calibration for this camera,
%   that calibration is the transform in use, and its reference image has
%   the camera's acquisition size and binning.
identity = dmd.calibration_identity(camera.name);
problems = strings(0, 1);
if identity.status == "none" || ~identity.has_pair_calibration
    problems(end+1) = sprintf("%s has no calibration for %s", dmd.name, camera.name);
elseif ~identity.active_transform_is_pair_transform
    problems(end+1) = sprintf(['the transform %s is using is not its %s calibration ' ...
        '(select that camera''s calibration)'], dmd.name, camera.name);
end
if isempty(dmd.refimage)
    problems(end+1) = sprintf("%s has no calibration reference image", dmd.name);
    grid = [];
else
    grid = size(dmd.refimage.img);
    [ref_bin, ref_roi] = dmd.reference_geometry();
    roi = camera.getROIForAcquisition();
    if ~isequal(double(ref_bin), double(camera.bin)) || ~isequal(double(ref_roi(3:4)), double(roi([2 4])))
        problems(end+1) = sprintf(['the calibration''s reference image is %g x %g at bin %g but ' ...
            '%s acquires %g x %g at bin %g; calibrate at the acquisition ROI'], ...
            ref_roi(3), ref_roi(4), ref_bin, camera.name, roi(2), roi(4), camera.bin);
    end
end
if ~isempty(problems)
    error("hadamard_stim:NoDmdCalibration", ...
        "The DMD cannot be used for this run: %s.", strjoin(problems, "; "));
end

canvas = dmd.Pattern_Canvas_Size();
geometry.scan_area = true(fliplr(canvas));
geometry.rasterize = @rasterize;
geometry.identity = struct("source", "luminos_dmd_calibration", ...
    "device", string(dmd.name), "camera", string(camera.name), ...
    "status", string(identity.status), "measured_utc", identity.measured_utc, ...
    "bin", identity.bin, "roi", identity.roi, "mode", string(identity.mode), ...
    "transform", transform_matrix(identity.pair_transform), ...
    "transform_class", string(class(identity.pair_transform)), ...
    "camera_grid", grid, "canvas", canvas);

    function mask = rasterize(spots, kind)
        if ~ismember(kind, ["auto_square" "hidden"])
            error("hadamard_stim:RasterKind", "Unknown rasterisation kind %s.", kind);
        end
        camera_mask = false(grid);
        for k = 1:numel(spots)
            xy = spots{k};
            camera_mask = camera_mask | poly2mask(xy(:, 1), xy(:, 2), grid(1), grid(2));
        end
        warped = dmd.setPatterningROI(camera_mask, "write_when_complete", false);
        mask = logical(warped > 0.5);
        if ~isequal(size(mask), canvas)
            error("hadamard_stim:CanvasSize", ...
                "%s returned a %d x %d mask; the canvas is %d x %d.", dmd.name, ...
                size(mask, 1), size(mask, 2), canvas(1), canvas(2));
        end
    end
end

function m = transform_matrix(t)
% The matrix of a MATLAB geometric transform, or [] if it has none
% (e.g. a polynomial fit), so the identity stays JSON-safe.
m = [];
for p = ["A" "T"]
    if isprop(t, p) || (isstruct(t) && isfield(t, p))
        m = double(t.(p));
        return
    end
end
end
