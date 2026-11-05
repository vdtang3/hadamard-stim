function [image, snap] = read_reference_snap(file)
%READ_REFERENCE_SNAP A Luminos Snap, as written by the Snap button or the HiLo tab.
%
%   [image, snap] = hadamard_stim.luminos.read_reference_snap(file)
%
%   file is the Snap's .mat (<datafolder>/Snaps/<stem>.mat): variable
%   "snap", a CL_RefImage (or a struct with its fields). The rules are
%   Adaptive Optopatch's read_reference_snapshot, which reads the same
%   files (copied, not shared: the packages do not depend on each other):
%   img, name and ref2d are required; bin and timestamp are optional
%   (older Snaps); ref2d's world limits are the acquisition ROI in
%   unbinned sensor pixels; tform holds every DMD's transform when the
%   Snap was taken, by name.
%
%   image is snap.img as double, exactly: not resampled, flipped,
%   transposed, cropped or rescaled.
%   snap describes it: file, sha256 (of the image), name (camera), type
%   ("Camera", "HiLo", ...), bin, roi [x0 y0 width height] (unbinned
%   sensor pixels), image_size, timestamp, transforms (name, matrix in
%   affinetform2d's A convention, class), provenance when the Snap
%   carries one (HiLo Snaps do), and the camera's stage calibration:
%   pixel_to_sample_um (2 x 2, microns per image pixel; [] when the camera
%   was not calibrated) and um_per_px, sqrt(abs(det)) of it (NaN without).
%   Segmentation's sizes are in image pixels, so um_per_px is what says
%   how large they are on the sample - which differs between cameras.
%
%   Refuses (hadamard_stim:InvalidSnap) a file that is not a Snap, or an
%   image that is not one finite 2-D frame. Whether the Snap fits the
%   DMD calibration is check_reference_snap's question.
arguments
    file (1, 1) string
end
[~, ~, extension] = fileparts(file);
if ~isfile(file)
    error("hadamard_stim:InvalidSnap", "No Snap file at %s.", file);
end
if ~strcmpi(extension, ".mat")
    error("hadamard_stim:InvalidSnap", ...
        "Choose the Snap's .mat file (%s is not one): only it records the camera area and the DMD transforms.", file);
end
try
    variables = whos("-file", file);
catch cause
    err = MException("hadamard_stim:InvalidSnap", "%s is not a readable MATLAB file.", file);
    throw(addCause(err, cause));
end
entry = variables(strcmp({variables.name}, "snap"));
if isempty(entry)
    error("hadamard_stim:InvalidSnap", "%s holds no Luminos Snap (no variable ""snap"").", file);
end
if entry.class == "CL_RefImage" && exist("CL_RefImage", "class") ~= 8
    error("hadamard_stim:InvalidSnap", ...
        "%s is a CL_RefImage, and MATLAB cannot find that class: load it from Luminos (src/utils/Data_Structures on the path).", file);
end
loaded = load(file, "snap");
s = loaded.snap;
if ~isscalar(s) || ~(isstruct(s) || isobject(s))
    error("hadamard_stim:InvalidSnap", "%s: ""snap"" is not one Luminos Snap.", file);
end
missing = ["img" "name" "ref2d"];
missing = missing(~arrayfun(@(name) has(s, name), missing));
if ~isempty(missing)
    error("hadamard_stim:InvalidSnap", "%s is missing %s, which a Luminos Snap records.", file, strjoin(missing, ", "));
end
if ~isnumeric(s.img) || ~ismatrix(s.img) || isempty(s.img) || ~isreal(s.img)
    error("hadamard_stim:InvalidSnap", "%s: the Snap's image is not one 2-D frame.", file);
end
image = double(s.img);
if any(~isfinite(image(:)))
    error("hadamard_stim:InvalidSnap", "%s: the Snap's image contains NaN or Inf.", file);
end

bin = NaN;
if has(s, "bin") && isnumeric(s.bin) && isscalar(s.bin) && isfinite(s.bin) && s.bin > 0
    bin = double(s.bin);
end
x = [0 size(image, 2)];
y = [0 size(image, 1)];
if has(s.ref2d, "XWorldLimits"), x = double(s.ref2d.XWorldLimits); end
if has(s.ref2d, "YWorldLimits"), y = double(s.ref2d.YWorldLimits); end

snap = struct();
snap.file = file;
snap.sha256 = hadamard_stim.metadata.sha256(image);
snap.name = string(s.name);
snap.type = "";
if has(s, "type"), snap.type = string(s.type); end
snap.bin = bin;
snap.roi = [x(1) y(1) diff(x) diff(y)];
snap.image_size = size(image);
snap.timestamp = "";
if has(s, "timestamp") && ~isempty(s.timestamp)
    snap.timestamp = string(s.timestamp);
end
snap.transforms = transforms(s);
snap.provenance = [];
if has(s, "provenance") && ~isempty(s.provenance)
    snap.provenance = s.provenance;
end
snap.pixel_to_sample_um = [];
snap.um_per_px = NaN;
if has(s, "pixel_to_sample_um") && isnumeric(s.pixel_to_sample_um) ...
        && isequal(size(s.pixel_to_sample_um), [2 2]) && all(isfinite(s.pixel_to_sample_um(:)))
    snap.pixel_to_sample_um = double(s.pixel_to_sample_um);
    snap.um_per_px = sqrt(abs(det(snap.pixel_to_sample_um)));
end
end

function list = transforms(s)
% Every DMD transform the Snap recorded. Before multi-DMD Luminos the
% transform itself was stored, with no name.
list = struct("name", {}, "matrix", {}, "class", {});
if ~has(s, "tform") || isempty(s.tform)
    return
end
t = s.tform;
if ~(isstruct(t) && isfield(t, "tform"))
    list(1) = struct("name", "", "matrix", hadamard_stim.luminos.affine_matrix(t), "class", string(class(t)));
    return
end
for k = 1:numel(t)
    name = "";
    if isfield(t, "name"), name = string(t(k).name); end
    list(end+1) = struct("name", name, "matrix", hadamard_stim.luminos.affine_matrix(t(k).tform), ...
        "class", string(class(t(k).tform))); %#ok<AGROW>
end
end

function tf = has(value, name)
tf = (isstruct(value) && isfield(value, name)) || (isobject(value) && isprop(value, name));
end
