function result = manual_hilo_reconstruct(uniform, structured, options)
%MANUAL_HILO_RECONSTRUCT HiLo from two snapshots taken by hand: U (uniform) and S (structured).
%
%   result = manual_hilo_reconstruct(uniformSnap, structuredSnap)
%   result = manual_hilo_reconstruct("..\Snaps\101500_cam-TeledyneKinetix.mat", ...
%                                    "..\Snaps\101530_cam-TeledyneKinetix.mat", filterScale=8)
%   result = manual_hilo_reconstruct(U, S, cameraName="Teledyne Kinetix", ...
%                                    roi=[x0 y0 width height], bin=1)   % arrays or bare TIFFs
%
%   Offline: no Luminos device is used, nothing on the rig is touched. The
%   reconstruction is Luminos's reconstruct_hilo (src/Experimental_Scripts/
%   HiLo), the HiLo tab's, called as the tab calls it for one plane, with
%   n_averaged = 1 (each of U and S is one snapshot, not a burst average)
%   and sample_pixel_um from the Snap's stage calibration when it has one.
%   Its other parameters are its defaults (hilo_reconstruction_defaults),
%   which are also the tab's, unless given.
%
%   Inputs, each of U and S (hadamard_stim.manual.read_image):
%     * a Luminos Snap .mat (the Snap button's <stem>.mat) - recommended:
%       it records the camera, its acquisition area and binning, and the
%       DMD transforms;
%     * the Snap's .tiff, with its .mat beside it (read from there);
%     * any one-frame TIFF or a 2-D array, with cameraName, roi and bin
%       given (else the result has no camera area: see below).
%   U and S must be the same size and, where recorded, the same camera,
%   area and binning.
%
%   Options:
%     filterScale   reconstruct_hilo's target_thickness_px, sigmaW, in
%                   image pixels (default its 1; the block sweep calls
%                   it filter_scale_px)
%     cameraOffset  camera_offset_adu, subtracted from U and S first
%                   (default its 0, as the tab)
%     reconstruction  struct of any other reconstruct_hilo parameters
%     cameraName, roi ([x0 y0 width height], unbinned sensor pixels), bin
%                   the camera area for images that do not record one
%     output        file stem (path without extension) for <stem>.mat and
%                   <stem>.tif; default: beside U, named
%                   <HHMMSS>_hilo-manual_cam-<camera>, which the Hadamard
%                   Stim tab lists among the camera's Snaps when U is in a
%                   Snaps folder; "none" writes nothing. Arrays without
%                   output are not saved.
%     show          show U, S and HiLo (default true)
%
%   Files:
%     <stem>.mat  "snap": a Luminos Snap of the HiLo image (as
%                 create_hilo_snap writes, as a struct): img (double, the
%                 HiLo image), name, type "HiLo", bin, ref2d (world limits
%                 = the area in unbinned sensor pixels), xdata, ydata, tform
%                 (U's DMD transforms), pixel_to_sample_um, timestamp,
%                 provenance. Only written when the camera area is known.
%                 "hilo": the reconstruction (hilo, hilo_unclipped, hi, lo,
%                 contrast, eta, params), the U and S images, and where
%                 they came from (sources).
%     <stem>.tif  the HiLo image, 32-bit float, unscaled, with the camera,
%                 area, binning, scale and DMD transforms as JSON in the
%                 ImageDescription (read back by manual_segment_dmd).
%
%   Into Hadamard Stim: FOV setup, Load Snap, choose <stem>.mat (listed
%   when it is in today's Snaps folder; else give the path). The tab checks
%   it like any Snap: the Kinetix, in the camera's acquisition area and
%   binning now. Or segment here: manual_segment_dmd(<stem>.mat, dmd).
%
%   result: hilo, hi, lo, contrast, eta, params (reconstruct_hilo's),
%   uniform, structured (the images used), meta (camera area: read_image's),
%   sources, files.
arguments
    uniform
    structured
    options.filterScale double = []
    options.cameraOffset double = []
    options.reconstruction struct = struct()
    options.cameraName (1, 1) string = ""
    options.roi double = []
    options.bin double = []
    options.output (1, 1) string = ""
    options.show (1, 1) logical = true
end
hadamard_stim.manual.require_luminos_hilo(["reconstruct_hilo" "hilo_reconstruction_defaults" "hilo_version"]);

explicit = struct("camera_name", options.cameraName, "roi", options.roi, "bin", options.bin);
[U, uMeta] = hadamard_stim.manual.read_image(uniform, explicit);
[S, sMeta] = hadamard_stim.manual.read_image(structured, explicit);
if ~isequal(size(U), size(S))
    error("hadamard_stim:ManualHiLo", "%s", sprintf(['U is %d x %d and S is %d x %d: they must be ' ...
        'the same field at the same size.'], size(U), size(S)));
end
meta = uMeta;
if uMeta.has_geometry && sMeta.has_geometry
    if ~strcmpi(uMeta.name, sMeta.name) || ~isequal(uMeta.roi, sMeta.roi) || ~isequal(uMeta.bin, sMeta.bin)
        error("hadamard_stim:ManualHiLo", "%s", sprintf(['U was taken on %s at x %g, y %g, %g x %g, ' ...
            'bin %g and S on %s at x %g, y %g, %g x %g, bin %g: take both at one camera area.'], ...
            uMeta.name, uMeta.roi, uMeta.bin, sMeta.name, sMeta.roi, sMeta.bin));
    end
elseif sMeta.has_geometry
    meta = sMeta;
    meta.source = uMeta.source;
    meta.sha256 = uMeta.sha256;
end

params = options.reconstruction;
if ~isempty(options.filterScale)
    params.target_thickness_px = options.filterScale;
end
if ~isempty(options.cameraOffset)
    params.camera_offset_adu = options.cameraOffset;
end
if ~isfield(params, "n_averaged")
    params.n_averaged = 1;          % one snapshot each, not burst averages
end
if ~isfield(params, "sample_pixel_um") && isfinite(meta.um_per_px)
    params.sample_pixel_um = meta.um_per_px;   % as the tab, from the camera's stage calibration
end
recon = reconstruct_hilo(U, S, params);

result = struct();
result.hilo = recon.hilo;
result.hilo_unclipped = recon.hilo_unclipped;
result.hi = recon.hi;
result.lo = recon.lo;
result.contrast = recon.contrast;
result.eta = recon.eta;
result.params = recon.params;
result.uniform = U;
result.structured = S;
result.meta = meta;
result.sources = struct("uniform", source_record(uMeta), "structured", source_record(sMeta));
result.files = struct("mat", "", "tif", "");

stem = output_stem(options.output, uMeta, meta);
if strlength(stem) > 0
    result.files = write_files(stem, result);
    fprintf("HiLo image saved to %s (.mat, .tif)\n", stem);
    if ~meta.has_geometry
        warning("hadamard_stim:ManualHiLoNoArea", ['No camera area is recorded for these images, so the ' ...
            'result is not a Snap: it can be segmented (manual_segment_dmd without a DMD) but not drawn ' ...
            'on the DMD. Give cameraName, roi and bin, or use the Snap .mat files.']);
    end
end
if options.show
    show(result);
end
end


function record = source_record(meta)
record = struct("source", string(meta.source), "camera", meta.name, "roi", meta.roi, "bin", meta.bin, ...
    "sha256", meta.sha256, "timestamp", meta.timestamp, "geometry_from", meta.geometry_from);
end


function stem = output_stem(output, uMeta, meta)
if output == "none"
    stem = "";
    return
end
if strlength(output) > 0
    [folder, name, extension] = fileparts(output);
    if ismember(lower(extension), [".mat" ".tif" ".tiff"])
        output = fullfile(folder, name);
    end
    stem = output;
    return
end
if uMeta.source == "array"
    stem = "";
    fprintf("Not saved: give output=<file stem> to save a reconstruction of arrays.\n");
    return
end
tag = "";
clean = regexprep(meta.name, "[^A-Za-z0-9]", "");   % Luminos camera_name_tag
if strlength(clean) > 0
    tag = "_cam-" + clean;
end
stem = fullfile(fileparts(uMeta.source), string(datetime("now", "Format", "HHmmss")) + "_hilo-manual" + tag);
end


function files = write_files(stem, result)
folder = fileparts(stem);
if strlength(folder) > 0 && ~isfolder(folder)
    mkdir(folder);
end
meta = result.meta;
created = datetime("now");
provenance = struct("source", "manual_hilo_reconstruct", "reconstruction", "reconstruct_hilo", ...
    "params", result.params, "uniform", result.sources.uniform, "structured", result.sources.structured, ...
    "created", string(created, "yyyy-MM-dd HH:mm:ss"));

hilo = rmfield(result, ["files" "meta"]);
files = struct("mat", stem + ".mat", "tif", stem + ".tif");
if meta.has_geometry
    roi = meta.roi;
    snap = struct();
    snap.img = double(result.hilo);
    snap.bin = meta.bin;
    snap.type = 'HiLo';
    snap.name = char(meta.name);
    snap.timestamp = created;
    snap.ref2d = struct("ImageSize", size(snap.img), "XWorldLimits", [roi(1), roi(1) + roi(3)], ...
        "YWorldLimits", [roi(2), roi(2) + roi(4)]);
    snap.xdata = roi(1) + 1:roi(1) + roi(3);
    snap.ydata = roi(2) + 1:roi(2) + roi(4);
    snap.tform = [];
    % U's DMD transforms, as matrices (a polynomial one has none and is left out).
    kept = meta.transforms(arrayfun(@(t) isequal(size(t.matrix), [3 3]), meta.transforms));
    for k = 1:numel(kept)
        m = kept(k).matrix;
        if isequal(m(3, :), [0 0 1])
            tform = affinetform2d(m);
        else
            tform = projtform2d(m);
        end
        snap.tform(k).name = char(kept(k).name); %#ok<AGROW>
        snap.tform(k).tform = tform; %#ok<AGROW>
    end
    snap.pixel_to_sample_um = meta.pixel_to_sample_um;
    snap.provenance = provenance;
    save(files.mat, "snap", "hilo", "-v7.3");
else
    save(files.mat, "hilo", "-v7.3");
end
write_float_tiff(files.tif, result.hilo, description(meta, provenance));
end


function text = description(meta, provenance)
transforms = struct("name", {}, "matrix", {}, "class", {});
for t = reshape(meta.transforms, 1, [])
    transforms(end+1) = struct("name", t.name, "matrix", t.matrix, "class", t.class); %#ok<AGROW>
end
bin = meta.bin;
if ~isfinite(bin), bin = []; end
d = struct("hadamard_stim_manual_hilo", 1, "type", "HiLo", "camera", meta.name, ...
    "roi", meta.roi, "roi_convention", "[x0 y0 width height], unbinned sensor pixels", ...
    "bin", bin, "pixel_to_sample_um", meta.pixel_to_sample_um, "transforms", {transforms}, ...
    "source", provenance.source, "uniform", provenance.uniform.source, ...
    "structured", provenance.structured.source, "created", provenance.created);
text = jsonencode(d);
end


function write_float_tiff(file, image, text)
t = Tiff(file, "w");
closer = onCleanup(@() t.close());
tags = struct();
tags.ImageLength = size(image, 1);
tags.ImageWidth = size(image, 2);
tags.Photometric = Tiff.Photometric.MinIsBlack;
tags.BitsPerSample = 32;
tags.SamplesPerPixel = 1;
tags.SampleFormat = Tiff.SampleFormat.IEEEFP;
tags.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
tags.Compression = Tiff.Compression.None;
tags.ImageDescription = char(text);
t.setTag(tags);
t.write(single(image));
end


function show(result)
figure("Name", "Manual HiLo", "Color", "w");
images = {result.uniform, result.structured, result.hilo};
titles = ["U (uniform)" "S (structured)" "HiLo"];
for k = 1:3
    ax = subplot(1, 3, k);
    im = images{k};
    values = sort(im(:));
    range = values(max(1, round([0.005 0.995] * numel(values))))';
    if range(2) <= range(1), range(2) = range(1) + 1; end
    imagesc(ax, im, range);
    axis(ax, "image");
    colormap(ax, gray);
    title(ax, titles(k));
end
end
