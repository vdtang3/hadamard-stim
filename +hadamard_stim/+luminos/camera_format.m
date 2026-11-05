function f = camera_format(camera, options)
%CAMERA_FORMAT How a camera's frames are stored in its recordings.
%
%   f = hadamard_stim.luminos.camera_format(camera)   a Luminos Camera
%   f = hadamard_stim.luminos.camera_format(bits)     8 or 16, nothing else known
%   f = hadamard_stim.luminos.camera_format(record)   a recorded f (jsondecode)
%   f = hadamard_stim.luminos.camera_format(..., offsets=profile.camera_offsets)
%
%   Luminos's Camera.bit_depth is the storage depth: what each pixel takes
%   in frames<k>.bin (8 or 16), read back from the camera after every mode
%   change (sync_bit_depth_from_camera, Get_Storage_Bit_Depth). It is what
%   Extract_Mov sizes a recording by, and it is the one used here.
%   Camera.pixel_bit_depth is what the sensor delivers (a 12-bit mode is
%   stored in 16 bits) and sets where the counts saturate; bit_mode_id and
%   bit_mode_label name the readout mode. The UI label is never parsed.
%
%   f.storage_bits     8 or 16 when supported
%   f.bytes_per_pixel  1 or 2
%   f.class            "uint8" or "uint16", the class frames are read in
%   f.pixel_bits       bits the camera delivers (storage_bits if unknown)
%   f.saturation       2^pixel_bits - 1, the largest count
%   f.mode_id, f.mode_label   the readout mode, as Luminos names it
%   f.compression      Camera.compression_method ("None": raw)
%   f.supported        raw 8- or 16-bit frames
%   f.description      e.g. "raw 8-bit frames (uint8)"
%   f.offset           the mode's dark offset in its counts, what the
%                      calibration and reconstructions subtract; NaN when
%                      not known (an 8-bit mode not in offsets)
%   f.offset_source    where it comes from
%   f.offset_known     whether there is one
%
%   The offset is looked up by mode (id and label, firefly_profile
%   camera_offsets). A 16-bit mode not listed, or 16 bits with no mode
%   (a number, a record from before modes were recorded), takes his 100 -
%   on his camera (unlisted_16bit_offset_camera, the Kinetix) only. A camera
%   object of any other name (the Libra) has no offset for a mode not listed,
%   whatever its depth: its black level is not his. A recorded f keeps the
%   offset it recorded.
arguments
    camera
    options.offsets struct = hadamard_stim.luminos.firefly_profile().camera_offsets
    options.unlisted_16bit_offset_camera (1, 1) string = ...
        hadamard_stim.luminos.firefly_profile().unlisted_16bit_offset_camera
end
his_camera = true;
if isnumeric(camera)
    f = describe(double(camera), double(camera), "", "", "None");
elseif isstruct(camera) && isfield(camera, "storage_bits")
    f = describe(double(camera.storage_bits), double(camera.pixel_bits), ...
        string(camera.mode_id), string(camera.mode_label), string(camera.compression));
    if isfield(camera, "offset")
        % As recorded; JSON writes NaN as null.
        f.offset = double(camera.offset);
        if isempty(f.offset)
            f.offset = NaN;
        end
        f.offset_source = string(camera.offset_source);
        f.offset_known = isfinite(f.offset);
        return
    end
else
    storage = double(read(camera, "bit_depth", 16));
    his_camera = string(read(camera, "name", options.unlisted_16bit_offset_camera)) ...
        == options.unlisted_16bit_offset_camera;
    f = describe(storage, double(read(camera, "pixel_bit_depth", storage)), ...
        string(read(camera, "bit_mode_id", "")), string(read(camera, "bit_mode_label", "")), ...
        string(read(camera, "compression_method", "None")));
end
f = with_offset(f, options.offsets, his_camera);
end

function f = with_offset(f, offsets, his_camera)
k = find(arrayfun(@(o) o.mode_id == f.mode_id && o.mode_label == f.mode_label ...
    && o.storage_bits == f.storage_bits, offsets), 1);
if ~isempty(k)
    f.offset = offsets(k).offset;
    f.offset_source = offsets(k).source;
elseif f.storage_bits == 16 && his_camera
    f.offset = 100;
    f.offset_source = "Yitong's 100 (16-bit; mode not in camera_offsets)";
else
    f.offset = NaN;
    f.offset_source = "unknown: no measured offset for this mode in camera_offsets";
end
f.offset_known = isfinite(f.offset);
end

function f = describe(storage, pixel, mode_id, mode_label, compression)
cls = class_of(storage);
if isempty(pixel) || ~isfinite(pixel) || pixel < 1
    pixel = storage;
end
f = struct("storage_bits", storage, "bytes_per_pixel", storage / 8, ...
    "class", cls, "pixel_bits", pixel, "saturation", 2^pixel - 1, ...
    "mode_id", mode_id, "mode_label", mode_label, "compression", compression, ...
    "supported", false, "description", "", ...
    "offset", NaN, "offset_source", "", "offset_known", false);
raw = compression == "None";
f.supported = raw && strlength(cls) > 0 && pixel <= storage;
if ~raw
    f.description = string(sprintf("%s-compressed %g-bit frames", compression, storage));
elseif strlength(cls) == 0
    f.description = string(sprintf("%g-bit frames", storage));
    f.bytes_per_pixel = NaN;
else
    f.description = string(sprintf("raw %d-bit frames (%s)", storage, cls));
end
end

function c = class_of(storage)
switch storage
    case 8
        c = "uint8";
    case 16
        c = "uint16";
    otherwise
        c = "";
end
end

function v = read(object, name, default)
v = default;
try
    if isprop(object, name) || (isstruct(object) && isfield(object, name))
        v = object.(name);
    end
catch
end
if isempty(v)
    v = default;
end
end
