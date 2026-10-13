function geometry = yitong_affine_geometry(registration_data, camera_offset, options)
%YITONG_AFFINE_GEOMETRY Camera-to-DMD mapping as Yitong's DMD app did it.
%
%   geometry = hadamard_stim.testing.yitong_affine_geometry(registration_data, camera_offset)
%   geometry = ...(..., dmd_size=[1024 768], saved_mask=[])
%
%   His 3 x 2 affine registration plus the camera ROI offset, rasterised
%   with his own code. The parity tests use it so masks can be compared bit
%   for bit with the goldens. On the rig the Luminos geometric calibration
%   replaces it (a recorded deviation), behind the same interface:
%
%     mask = geometry.rasterize(spots, kind)
%         spots  camera-space spots (cell of [n x 2] x, y)
%         kind   "auto_square": how his initial illumination pattern was
%                drawn (whole-DMD inpolygon, ANDed with saved_mask)
%                "hidden": every later pattern (dmd_draw_hidden, no
%                saved_mask; notebook P3)
%         mask   logical, Luminos canvas orientation [W x L]: rows are ALP
%                lines. That is exactly the array he passed to
%                alp_logical_to_btd.
%     geometry.scan_area   the mask his scan patterns are ANDed with
%                          (saved_mask, or all true)
%     geometry.identity    struct saying what this mapping is
arguments
    registration_data (3, 2) double
    camera_offset (1, 2) double
    options.dmd_size (1, 2) double = [1024 768]
    options.saved_mask = []
end
size_ = options.dmd_size;
saved = options.saved_mask;
geometry.identity = struct("source", "yitong_affine", ...
    "registration_data", registration_data, "camera_offset", camera_offset, ...
    "saved_mask_sha256", hadamard_stim.metadata.sha256(logical(saved)));
geometry.rasterize = @rasterize;
if isempty(saved)
    geometry.scan_area = true(size_);
else
    geometry.scan_area = saved;
end

    function mask = rasterize(spots, kind)
        switch kind
            case "auto_square"
                m = hadamard_stim.yitong.dmd_draw_rasterize(spots, registration_data, ...
                    camera_offset, size_, saved);
            case "hidden"
                m = hadamard_stim.yitong.dmd_draw_hidden(spots, registration_data, ...
                    camera_offset, size_);
            otherwise
                error("hadamard_stim:RasterKind", "Unknown rasterisation kind %s.", kind);
        end
        mask = logical(m');
    end
end
