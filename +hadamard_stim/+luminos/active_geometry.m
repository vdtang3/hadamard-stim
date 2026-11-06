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
%   Refuses (hadamard_stim:NoDmdCalibration) when no transform can be
%   applied as recorded: the DMD holds no calibration for this camera, or
%   the transform in use is not that calibration (the record would name a
%   transform that was not used), or there is no reference image to say
%   where the calibration was measured.
%
%   mismatch (a warning, never a refusal) says when part of the camera's
%   area lies outside the area the calibration was measured on: there the
%   transform is extrapolated, and is only as good as its fit holds beyond
%   the calibrated points. Empty otherwise.
identity = dmd.calibration_identity(camera.name);
problems = strings(0, 1);
mismatch = struct("message", "", "consequence", "");
if identity.status == "none" || ~identity.has_pair_calibration
    problems(end+1) = sprintf("%s has no calibration for %s", dmd.name, camera.name);
elseif ~identity.active_transform_is_pair_transform
    problems(end+1) = sprintf(['the transform %s is using is not its %s calibration ' ...
        '(select that camera''s calibration)'], dmd.name, camera.name);
end
if isempty(dmd.refimage)
    problems(end+1) = sprintf("%s has no calibration reference image", dmd.name);
end
if ~isempty(problems)
    error("hadamard_stim:NoDmdCalibration", ...
        "The DMD cannot be used for this run: %s.", strjoin(problems, "; "));
end

[ref_bin, ref_roi] = dmd.reference_geometry();
ref_bin = double(ref_bin);
ref_roi = double(reshape(ref_roi, 1, []));
[camera_roi, camera_bin] = hadamard_stim.luminos.camera_grid(camera);
grid = [camera_roi(4) camera_roi(3)] / camera_bin;
native = isequal(camera_bin, ref_bin) && isequal(camera_roi, ref_roi) ...
    && isequal(size(dmd.refimage.img), grid);
if native
    drawn_by = "setPatterningROI";
else
    drawn_by = "calibration composed with the camera area's sensor origin";
    inside = camera_roi(1) >= ref_roi(1) && camera_roi(2) >= ref_roi(2) ...
        && camera_roi(1) + camera_roi(3) <= ref_roi(1) + ref_roi(3) ...
        && camera_roi(2) + camera_roi(4) <= ref_roi(2) + ref_roi(4);
    if ~inside
        mismatch.message = sprintf(['%s acquires x %g, y %g, %g x %g (bin %g), which extends beyond ' ...
            'the area the DMD calibration was measured on (x %g, y %g, %g x %g): there the ' ...
            'calibration is extrapolated.'], camera.name, camera_roi, camera_bin, ref_roi);
        mismatch.consequence = ['Spots outside the calibrated area land where the calibration''s ' ...
            'fit, extended, puts them; check them in the orange preview.'];
    end
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
    "camera_grid", grid, "canvas", canvas, ...
    "camera_roi", camera_roi, "camera_bin", camera_bin, ...
    "drawn_by", drawn_by, "extrapolated", strlength(mismatch.message) > 0);

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
            warped = warp_from_area(camera_mask, identity.pair_transform, camera_roi, canvas);
        end
        mask = logical(warped > 0.5);
        if ~isequal(size(mask), canvas)
            error("hadamard_stim:CanvasSize", ...
                "%s returned a %d x %d mask; the canvas is %d x %d.", dmd.name, ...
                size(mask, 1), size(mask, 2), canvas(1), canvas(2));
        end
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
