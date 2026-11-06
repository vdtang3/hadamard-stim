function [image, meta] = read_image(source, explicit)
%READ_IMAGE One camera image and where on the sensor it was taken, for the manual HiLo tools.
%
%   [image, meta] = hadamard_stim.manual.read_image(source, explicit)
%
%   source is one of
%     * a Luminos Snap .mat (variable "snap": the Snap button's, the HiLo
%       tab's, or manual_hilo_reconstruct's), read by
%       hadamard_stim.luminos.read_reference_snap, the Hadamard Stim tab's
%       reader;
%     * a manual_hilo_reconstruct .mat saved without a camera area
%       (variable "hilo", no "snap");
%     * a TIFF: one frame. Its area comes from manual_hilo_reconstruct's JSON
%       in the ImageDescription, else from the Snap .mat of the same name
%       beside it (Luminos writes <stem>.tiff and <stem>.mat together);
%     * a numeric 2-D array.
%   explicit: struct with camera_name (string, "" for none), roi
%   ([x0 y0 width height] in unbinned sensor pixels, [] for none) and bin
%   ([] for none), used when the source records no area. A source that
%   records one must agree with any explicit value given.
%
%   image is double, exactly as stored: not resampled, flipped or cropped.
%   meta: source, name, type, roi, bin, image_size, transforms (read_
%   reference_snap's), pixel_to_sample_um, um_per_px, timestamp,
%   provenance, sha256, has_geometry (camera, area and binning all known),
%   geometry_from ("snap", "tiff", "explicit" or "none"). When has_geometry,
%   the image is checked to be one frame of that area: [height width]/bin.
arguments
    source
    explicit struct = struct("camera_name", "", "roi", [], "bin", [])
end
meta = struct("source", "array", "name", "", "type", "", "roi", [], "bin", NaN, ...
    "image_size", [], "transforms", struct("name", {}, "matrix", {}, "class", {}), ...
    "pixel_to_sample_um", [], "um_per_px", NaN, "timestamp", "", "provenance", [], ...
    "sha256", "", "has_geometry", false, "geometry_from", "none");

if isnumeric(source) || islogical(source)
    if ~ismatrix(source) || isempty(source) || ~isreal(source)
        error("hadamard_stim:ManualImage", "The image must be one real 2-D frame, not %s.", mat2str(size(source)));
    end
    image = double(source);
else
    file = string(source);
    if ~isscalar(file) || ~isfile(file)
        error("hadamard_stim:ManualImage", "No image file at %s.", strjoin(file, ", "));
    end
    meta.source = file;
    [~, ~, extension] = fileparts(file);
    switch lower(extension)
        case ".mat"
            [image, meta] = from_mat(file, meta);
        case {".tif", ".tiff"}
            [image, meta] = from_tiff(file, meta);
        otherwise
            error("hadamard_stim:ManualImage", "%s: give a Luminos Snap .mat, a TIFF or an array.", file);
    end
end
if any(~isfinite(image(:)))
    error("hadamard_stim:ManualImage", "The image contains NaN or Inf.");
end
meta.image_size = size(image);
meta.sha256 = hadamard_stim.metadata.sha256(image);
meta = apply_explicit(meta, explicit);
meta.has_geometry = strlength(meta.name) > 0 && numel(meta.roi) == 4 && isfinite(meta.bin);
if meta.has_geometry
    frame = [meta.roi(4) meta.roi(3)] / meta.bin;
    if ~isequal(meta.image_size, frame)
        error("hadamard_stim:ManualImage", "%s", sprintf(['The image is %d x %d, not one frame of its ' ...
            'camera area (x %g, y %g, %g x %g at bin %g gives %g x %g): it is transposed, cropped or ' ...
            'resampled, or the area given is wrong.'], meta.image_size, meta.roi, meta.bin, frame));
    end
end
end


function [image, meta] = from_mat(file, meta)
names = string({whos("-file", file).name});
if ismember("snap", names)
    [image, snap] = hadamard_stim.luminos.read_reference_snap(file);
    meta = from_snap(meta, snap, "snap");
elseif ismember("hilo", names)
    % manual_hilo_reconstruct's result with no camera area recorded.
    loaded = load(file, "hilo");
    image = double(loaded.hilo.hilo);
    meta.type = "HiLo";
    meta.provenance = rmfield(loaded.hilo, intersect(fieldnames(loaded.hilo), ...
        {'hilo', 'hilo_unclipped', 'hi', 'lo', 'contrast', 'uniform', 'structured'}));
else
    error("hadamard_stim:ManualImage", "%s holds no Luminos Snap (""snap"") or HiLo result (""hilo"").", file);
end
end


function [image, meta] = from_tiff(file, meta)
info = imfinfo(file);
if numel(info) ~= 1
    error("hadamard_stim:ManualImage", "%s holds %d frames; give one image.", file, numel(info));
end
image = double(imread(file));
if ~ismatrix(image)
    error("hadamard_stim:ManualImage", "%s is not a single-channel image.", file);
end
described = [];
if isfield(info, "ImageDescription") && ~isempty(info.ImageDescription)
    try
        described = jsondecode(info.ImageDescription);
    catch
    end
end
if isstruct(described) && isfield(described, "hadamard_stim_manual_hilo")
    meta.name = string(described.camera);
    meta.type = string(described.type);
    meta.roi = reshape(double(described.roi), 1, []);
    meta.bin = double(described.bin);
    if isempty(meta.bin), meta.bin = NaN; end
    if ~isempty(described.pixel_to_sample_um)
        meta.pixel_to_sample_um = reshape(double(described.pixel_to_sample_um), 2, 2);
        meta.um_per_px = sqrt(abs(det(meta.pixel_to_sample_um)));
    end
    for t = reshape(described.transforms, 1, [])
        meta.transforms(end+1) = struct("name", string(t.name), ...
            "matrix", reshape(double(t.matrix), 3, 3), "class", string(t.class));
    end
    meta.geometry_from = "tiff";
    return
end
[folder, stem] = fileparts(file);
beside = fullfile(folder, stem + ".mat");
if isfile(beside) && ismember("snap", string({whos("-file", beside).name}))
    [stored, snap] = hadamard_stim.luminos.read_reference_snap(beside);
    if ~isequal(stored, image)
        error("hadamard_stim:ManualImage", ['%s and the Snap %s beside it hold different images; ' ...
            'give the .mat.'], file, beside);
    end
    meta = from_snap(meta, snap, "snap");
    meta.source = file;
end
end


function meta = from_snap(meta, snap, from)
meta.name = snap.name;
meta.type = snap.type;
meta.roi = snap.roi;
meta.bin = snap.bin;
meta.transforms = snap.transforms;
meta.pixel_to_sample_um = snap.pixel_to_sample_um;
meta.um_per_px = snap.um_per_px;
meta.timestamp = snap.timestamp;
meta.provenance = snap.provenance;
meta.geometry_from = from;
end


function meta = apply_explicit(meta, explicit)
given = struct("name", field_or(explicit, "camera_name", ""), ...
    "roi", double(reshape(field_or(explicit, "roi", []), 1, [])), ...
    "bin", double(field_or(explicit, "bin", [])));
recorded = meta.geometry_from ~= "none";
if recorded
    conflicts = strings(0, 1);
    if strlength(string(given.name)) > 0 && ~strcmpi(strtrim(string(given.name)), strtrim(meta.name))
        conflicts(end+1) = sprintf("camera %s (recorded %s)", given.name, meta.name);
    end
    if ~isempty(given.roi) && ~isequal(given.roi, meta.roi)
        conflicts(end+1) = sprintf("area %s (recorded %s)", mat2str(given.roi), mat2str(meta.roi));
    end
    if ~isempty(given.bin) && ~isequal(given.bin, meta.bin) && isfinite(meta.bin)
        conflicts(end+1) = sprintf("bin %g (recorded %g)", given.bin, meta.bin);
    end
    if ~isempty(conflicts)
        error("hadamard_stim:ManualImage", "%s records its camera area; the values given differ: %s.", ...
            meta.source, strjoin(conflicts, "; "));
    end
    if ~isfinite(meta.bin) && ~isempty(given.bin)
        meta.bin = given.bin;     % an old Snap without bin
    end
    return
end
if strlength(string(given.name)) > 0 || ~isempty(given.roi) || ~isempty(given.bin)
    meta.name = string(given.name);
    meta.roi = given.roi;
    if ~isempty(given.bin), meta.bin = given.bin; end
    meta.geometry_from = "explicit";
end
end


function v = field_or(s, name, default)
v = default;
if isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
end
end
