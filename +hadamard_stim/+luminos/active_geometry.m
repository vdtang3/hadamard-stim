function [geometry, mismatch] = active_geometry(dmd, camera)
%ACTIVE_GEOMETRY Camera-to-DMD mapping from the active Luminos calibration.
%
%   [geometry, mismatch] = hadamard_stim.luminos.active_geometry(dmd, camera)
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
%   Spots are in the pixel grid of the camera as it acquires now (its
%   acquisition ROI and binning): the grid Snaps, reference scans and run
%   images are taken in. Luminos's DMD calibration maps unbinned SENSOR
%   coordinates to the DMD (Patterning_Device.setPatterningROI composes the
%   reference image's origin into it: "one calibration serves every crop").
%   So:
%     * the camera's grid is the calibration reference image's: drawn by
%       setPatterningROI itself, exactly as before;
%     * any other area or binning: drawn by the same steps setPatterningROI
%       takes (imresize to unbinned pixels, imwarp onto the canvas), with
%       the calibration composed with THIS grid's sensor origin instead of
%       the reference image's - or, for a calibration with no matrix
%       (polynomial), the mask padded out to its sensor position, as
%       Luminos does. No recalibration at the new area is needed.
%
%   The Kinetix's own calibration is made the DMD's active one first when
%   it holds one and is using another camera's (use_kinetix_calibration).
%   The calibration belongs to the camera and the light path, not to a field
%   of view: any stage position, camera area or binning is drawn through
%   it, and Luminos's calibration having been read from disk (status
%   "file") is fine. Refuses (hadamard_stim:NoDmdCalibration) only when no
%   usable transform exists for this camera: none stored for it (another
%   camera's is never used), or its matrix is not finite or not invertible.
%   The DMD tab's loaded reference image (dmd.refimage) is not needed: it
%   is only the image the DMD tab shows, not a record of the calibration,
%   and Luminos does not restore it at startup. When it is this camera's
%   grid and the active transform is the calibration, setPatterningROI
%   draws as before; otherwise the stored transform is applied directly.
%
%   mismatch (a warning, never a refusal) says when part of the camera's
%   area lies outside the area the calibration was measured on (its stored
%   roi): there the same transform is applied, extrapolated, and is only as
%   good as its fit holds beyond the calibrated points. Empty otherwise.
%
%   geometry.to_dmd(xy) maps points in the camera grid ([n x 2] x, y, the
%   cells' coordinates) to DMD mirror coordinates by the same transform;
%   geometry.off_dmd(xy) says which land off the DMD canvas (their spots
%   are clipped to the canvas, as imwarp clips any mask).
selected = hadamard_stim.luminos.use_kinetix_calibration(dmd, camera);
identity = dmd.calibration_identity(camera.name);
mismatch = struct("message", "", "consequence", "");
if identity.status == "none" || ~identity.has_pair_calibration
    error("hadamard_stim:NoDmdCalibration", ['The DMD cannot be used: %s has no calibration for %s ' ...
        '(calibrate it in the DMD tab; a calibration stored under the camera''s former name ' ...
        '"Kinetix" can be moved to it once with tools/migrate_dmd_calibration_camera).'], ...
        dmd.name, camera.name);
end
pair = identity.pair_transform;
matrix = transform_matrix(pair);
if ~isempty(matrix) && (~isequal(size(matrix), [3 3]) || any(~isfinite(matrix(:))) ...
        || abs(det(matrix)) < 1e-12)
    error("hadamard_stim:NoDmdCalibration", ['The DMD cannot be used: the %s calibration stored for ' ...
        '%s is not a usable transform (its matrix is not finite or not invertible). Calibrate again.'], ...
        dmd.name, camera.name);
end

[camera_roi, camera_bin] = hadamard_stim.luminos.camera_grid(camera);
grid = [camera_roi(4) camera_roi(3)] / camera_bin;
ref_roi = [];
ref_bin = NaN;
if ~isempty(dmd.refimage)
    [ref_bin, ref_roi] = dmd.reference_geometry();
    ref_bin = double(ref_bin);
    ref_roi = double(reshape(ref_roi, 1, []));
end
native = identity.active_transform_is_pair_transform && ~isempty(ref_roi) ...
    && isequal(camera_bin, ref_bin) && isequal(camera_roi, ref_roi) ...
    && isequal(size(dmd.refimage.img), grid);
% Where the calibration was measured: its own record, else (older entries)
% the DMD tab's reference image.
calibrated_roi = double(reshape(identity.roi, 1, []));
if numel(calibrated_roi) ~= 4
    calibrated_roi = ref_roi;
end
if native
    drawn_by = "setPatterningROI";
else
    drawn_by = "calibration composed with the camera area's sensor origin";
end
if numel(calibrated_roi) == 4
    inside = camera_roi(1) >= calibrated_roi(1) && camera_roi(2) >= calibrated_roi(2) ...
        && camera_roi(1) + camera_roi(3) <= calibrated_roi(1) + calibrated_roi(3) ...
        && camera_roi(2) + camera_roi(4) <= calibrated_roi(2) + calibrated_roi(4);
    if ~inside
        mismatch.message = sprintf(['%s area x %g, y %g, %g x %g (bin %g) extends beyond ' ...
            'the area the DMD calibration was measured on (x %g, y %g, %g x %g): there the ' ...
            'calibration is extrapolated.'], camera.name, camera_roi, camera_bin, calibrated_roi);
        mismatch.consequence = ['Spots outside the calibrated area land where the calibration''s ' ...
            'fit, extended, puts them; check them in the orange preview.'];
    end
end

canvas = dmd.Pattern_Canvas_Size();
geometry.scan_area = true(fliplr(canvas));
geometry.rasterize = @rasterize;
geometry.to_dmd = @to_dmd;
geometry.off_dmd = @off_dmd;
geometry.identity = struct("source", "luminos_dmd_calibration", ...
    "device", string(dmd.name), "camera", string(camera.name), ...
    "status", string(identity.status), "measured_utc", identity.measured_utc, ...
    "bin", identity.bin, "roi", identity.roi, "mode", string(identity.mode), ...
    "transform", transform_matrix(identity.pair_transform), ...
    "transform_class", string(class(identity.pair_transform)), ...
    "camera_grid", grid, "canvas", canvas, ...
    "camera_roi", camera_roi, "camera_bin", camera_bin, ...
    "calibrated_roi", calibrated_roi, ...
    "drawn_by", drawn_by, "extrapolated", strlength(mismatch.message) > 0, ...
    "selected_by_hadamard_stim", selected);

    function mask = rasterize(spots, kind)
        if ~ismember(kind, ["auto_square" "hidden"])
            error("hadamard_stim:RasterKind", "Unknown rasterisation kind %s.", kind);
        end
        camera_mask = false(grid);
        for k = 1:numel(spots)
            xy = spots{k};
            camera_mask = camera_mask | poly2mask(xy(:, 1), xy(:, 2), grid(1), grid(2));
        end
        if native
            warped = dmd.setPatterningROI(camera_mask, "write_when_complete", false);
        else
            warped = warp_from_area(camera_mask, pair, camera_roi, canvas);
        end
        mask = logical(warped > 0.5);
        if ~isequal(size(mask), canvas)
            error("hadamard_stim:CanvasSize", ...
                "%s returned a %d x %d mask; the canvas is %d x %d.", dmd.name, ...
                size(mask, 1), size(mask, 2), canvas(1), canvas(2));
        end
    end

    function uv = to_dmd(xy)
        % Camera-grid points -> unbinned sensor pixels (the warp's own
        % convention: imresize to sensor pixels, then the area's origin)
        % -> DMD mirrors, by the stored transform.
        sensor = (double(xy) - 0.5) * camera_bin + 0.5 + camera_roi(1:2);
        uv = transformPointsForward(as_transform(pair), sensor);
    end

    function out = off_dmd(xy)
        uv = to_dmd(xy);
        out = ~all(isfinite(uv), 2) | uv(:, 1) < 0.5 | uv(:, 2) < 0.5 ...
            | uv(:, 1) > canvas(2) + 0.5 | uv(:, 2) > canvas(1) + 0.5;
    end
end

function warped = warp_from_area(camera_mask, transform, area, canvas)
% Patterning_Device.setPatterningROI's warp, for a mask in a camera area
% other than the reference image's: area is [x0 y0 width height] in
% unbinned sensor pixels, transform maps sensor coordinates to the DMD.
upsampled = imresize(camera_mask, [area(4) area(3)]);
composed = compose_origin_shift(transform, area(1:2));
if isempty(composed)
    % No matrix to compose into (a polynomial fit): pad the mask out to its
    % place on the sensor, as Luminos does.
    padded = zeros(area(4) + area(2), area(3) + area(1));
    padded(area(2) + 1:end, area(1) + 1:end) = upsampled;
    upsampled = padded;
    composed = transform;
end
warped = imwarp(upsampled, composed, "OutputView", imref2d(canvas));
end

function t = as_transform(transform)
% A struct holding only A (what tests and old entries may carry) as a transform.
t = transform;
if isstruct(transform) && isfield(transform, "A")
    t = projtform2d(double(transform.A));
end
end

function local = compose_origin_shift(transform, origin)
% Patterning_Device.compose_origin_shift: transform * T(origin), [] when
% the transform has no homogeneous matrix.
shift = eye(3);
shift(1, 3) = origin(1);
shift(2, 3) = origin(2);
if isa(transform, "affinetform2d")
    local = affinetform2d(transform.A * shift);
elseif isa(transform, "projtform2d")
    local = projtform2d(transform.A * shift);
elseif isa(transform, "affine2d")
    local = affine2d(shift' * transform.T);
elseif isa(transform, "projective2d")
    local = projective2d(shift' * transform.T);
elseif isstruct(transform) && isfield(transform, "A")
    local = projtform2d(double(transform.A) * shift);
else
    local = [];
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
