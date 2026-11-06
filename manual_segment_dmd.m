function result = manual_segment_dmd(source, dmd, options)
%MANUAL_SEGMENT_DMD Yitong's cell segmentation on one image, tunable, then the orange DMD mask of the cells kept.
%
%   Tune interactively (settings, Segment again, click cells to drop them, Accept):
%       m = manual_segment_dmd("..\Snaps\101600_hilo-manual_cam-TeledyneKinetix.mat", dmd, review=true);
%   Explicit settings (the tab's, by its names):
%       m = manual_segment_dmd(file, dmd, nExclude=5, threshold=320, candidatePool=1000, ...
%                              minAreaPx=10, filterSizePx=7, illumSpotSize=5, stimSpotSize=3, keep=[1:40 45]);
%       m = manual_segment_dmd(file, dmd, settings="my_settings.json", nExclude=3);
%       m = manual_segment_dmd(file, [], nExclude=5);           % segmentation only, no DMD
%   Project the mask (explicit, never automatic):
%       manual_hilo_display(dmd, m.files.mat)   or   upload=true
%
%   dmd is the orange DMD, app.getDevice("ALP_DMD") ("DMD (shared)"), or []
%   for segmentation only. This is the Hadamard Stim tab's FOV setup without
%   the tab, by the same code, in two steps:
%     1. segmentation: protocol.segment_cells (his static_image_seg_v5,
%        Auto Square illumination spots, the smaller stimulation spots)
%        with the tab's settings struct (cfg.segmentation; defaults his,
%        default_config). It needs no DMD and no calibration, and never
%        changes the image: run it again with other settings at will.
%     2. after the cells are accepted, and only with a DMD: the kept cells'
%        masks (protocol.draw_cells) through the Kinetix's stored DMD
%        calibration applied at the image's own camera area and binning
%        (active_geometry: any FOV, area or binning; beyond the calibrated
%        area it is extrapolated, with a warning), checked as a Snap loaded
%        into the tab is (check_reference_snap), and saved in the tab's
%        export format (write_orange_mask), which the DMD tab's "Hadamard
%        Stim Orange Mask" pattern projects. The mask is refused - not
%        guessed - when the image records no camera area, is not the
%        Kinetix's, or the DMD holds no usable Kinetix calibration.
%   Nothing here acquires or triggers; nothing is projected unless upload.
%
%   source: anything hadamard_stim.manual.read_image reads - a
%   manual_hilo_reconstruct .mat or .tif, a Luminos Snap .mat (or its .tiff
%   with the .mat beside it), or a 2-D array (with cameraName, roi, bin for
%   a mask).
%
%   Settings (the tab's "Segmentation" fields, hadamard_stim.ui.config_fields):
%     nExclude      n_exclude: top-contrast candidates to skip. Required, as
%                   in the tab (no default: look at min_val; his FOV needed 5)
%     threshold     cells to keep (320)
%     selectAll     keep all detected candidates instead (false)
%     candidatePool regions ranked as candidates, the sensitivity (1000)
%     minAreaPx     candidates larger than this many pixels (10)
%     filterSizePx  detection filter size, px (7)
%     illumSpotSize orange spot size, px (5)
%     stimSpotSize  blue spot size, px (3)
%     settings      a struct with these fields by the tab's names
%                   (n_exclude, ...), or a file: a .json from
%                   saveSettings / the tuner's Save, or an earlier result
%                   .mat. Name-value settings win over it.
%     saveSettings  write the settings used to this .json
%   The tab has no camera-offset, cell-diameter, background, maximum-area or
%   dilation setting, so neither has this.
%
%   Other options:
%     keep          cell numbers to keep (default all), as the tab numbers
%                   them (row of cell_coord)
%     review        open the tuner (segmentation_tuner): edit settings,
%                   Segment, click cells, Save/Load settings, Accept. Cancel
%                   returns the result without a mask (accepted false).
%     cameraName, roi ([x0 y0 width height], unbinned sensor pixels), bin
%                   the camera area of an image that does not record one
%     output        file stem for <stem>.mat and <stem>.png; default beside
%                   the source, <source name>_orange_mask; "none" writes
%                   nothing. Arrays without output are not saved.
%     upload        show the mask on the DMD when done (default false)
%     show          draw the cells over the image (default true; not with review)
%
%   result: image, meta (read_image's), settings, cells (cell_coord,
%   illum_rois, stim_rois, min_val, excluded_coord, segmentation), kept,
%   accepted, mask (the kept cells' orange mask, DMD canvas, logical; []
%   without a DMD), stim_mask, off_dmd (kept cells mapped off the DMD),
%   geometry (the calibration used), files. <stem>.mat holds "mask" and
%   "info" (the tab's export) and "segmentation" (cells, kept, settings,
%   image meta); without a DMD only "segmentation" and "info".
arguments
    source
    dmd = []
    options.settings = struct()
    options.nExclude double = []
    options.threshold double = []
    options.selectAll logical = logical([])
    options.candidatePool double = []
    options.minAreaPx double = []
    options.filterSizePx double = []
    options.illumSpotSize double = []
    options.stimSpotSize double = []
    options.saveSettings (1, 1) string = ""
    options.keep double = []
    options.review (1, 1) logical = false
    options.cameraName (1, 1) string = ""
    options.roi double = []
    options.bin double = []
    options.output (1, 1) string = ""
    options.upload (1, 1) logical = false
    options.show (1, 1) logical = true
end
explicit = struct("camera_name", options.cameraName, "roi", options.roi, "bin", options.bin);
[image, meta] = hadamard_stim.manual.read_image(source, explicit);
settings = hadamard_stim.manual.segmentation_settings(options.settings, given_settings(options));

% 1. Segmentation (no DMD).
accepted = true;
if options.review
    tuner = hadamard_stim.manual.segmentation_tuner(image, settings, options.keep);
    uiwait(tuner.fig);
    st = tuner.state();
    accepted = st.accepted;
    if isempty(st.cells)
        error("hadamard_stim:ManualCancelled", "Nothing was segmented; no result.");
    end
    settings = st.settings;
    cells = st.cells;
    kept = st.kept;
else
    cells = hadamard_stim.manual.segment(image, settings);
    kept = choose(options.keep, size(cells.cell_coord, 1));
end
n = size(cells.cell_coord, 1);
fprintf("%d cells found, %d kept.\n", n, numel(kept));
if strlength(options.saveSettings) > 0
    hadamard_stim.manual.write_segmentation_settings(options.saveSettings, settings);
end

result = struct("image", image, "meta", meta, "settings", settings, "cells", cells, "kept", kept, ...
    "accepted", accepted, "mask", [], "stim_mask", [], "illum_rois", [], "stim_rois", [], ...
    "off_dmd", [], "geometry", struct("source", "none"), "files", struct("mat", "", "png", ""));

% 2. The mask of the accepted cells.
chosen = struct("cell_coord", cells.cell_coord(kept, :));
online = ~isempty(dmd) && accepted;
if online
    geometry = mask_geometry(meta, dmd);
    chosen = hadamard_stim.protocol.draw_cells(chosen, settings, geometry);
    result.mask = chosen.illum_mask;
    result.stim_mask = chosen.stim_mask;
    result.off_dmd = kept(chosen.off_dmd);
    result.geometry = geometry.identity;
    if ~isempty(result.off_dmd)
        warning("hadamard_stim:ManualOffDmd", "Cells %s map off the DMD: their spots are clipped to its edge or absent.", ...
            strjoin(string(result.off_dmd), ", "));
    end
else
    chosen = hadamard_stim.protocol.draw_cells(chosen, settings, ...
        struct("rasterize", @(spots, kind) [], "identity", struct("source", "none")));
end
result.illum_rois = chosen.illum_rois;
result.stim_rois = chosen.stim_rois;

stem = output_stem(options.output, meta);
if strlength(stem) > 0 && accepted
    result.files = save_result(stem, result, online);
    fprintf("Saved to %s\n", result.files.mat);
end
if options.show && ~options.review
    show(image, cells, kept);
end
if options.upload
    if ~online
        error("hadamard_stim:ManualNoDmd", "No accepted mask to show (no DMD given, or the review was cancelled).");
    end
    manual_hilo_display(dmd, result.mask);
end
end


function overrides = given_settings(options)
% The tab's settings given by name: camelCase here, its snake_case in cfg.segmentation.
overrides = struct();
names = ["nExclude" "threshold" "selectAll" "candidatePool" "minAreaPx" "filterSizePx" ...
    "illumSpotSize" "stimSpotSize"];
for name = names
    if ~isempty(options.(name))
        overrides.(snake(name)) = options.(name);
    end
end
end

function s = snake(name)
s = lower(regexprep(name, "([A-Z])", "_$1"));
end

function kept = choose(keep, n)
kept = 1:n;
if ~isempty(keep)
    kept = unique(round(keep(:)'));
    if any(kept < 1 | kept > n)
        error("hadamard_stim:ManualKeep", "keep lists cells outside 1..%d.", n);
    end
end
end


function geometry = mask_geometry(meta, dmd)
% The Kinetix's stored calibration at the image's own camera area.
if ~meta.has_geometry
    error("hadamard_stim:ManualNoArea", ['%s records no camera area, so its cells cannot be placed ' ...
        'on the DMD without guessing. Give cameraName, roi and bin, use the Snap .mat, or pass [] ' ...
        'for the DMD to segment only.'], string(meta.source));
end
if ~contains(meta.name, "Kinetix", "IgnoreCase", true)
    error("hadamard_stim:ManualNotKinetix", ['The image was taken on %s. Only the Kinetix''s DMD ' ...
        'calibration is used; another camera''s (the Libra''s) never is.'], meta.name);
end
camera = struct("name", meta.name, "roi", meta.roi, "bin", meta.bin);
hadamard_stim.luminos.use_kinetix_calibration(dmd, camera);
snap = meta;
snap.file = string(meta.source);
fit = hadamard_stim.luminos.check_reference_snap(snap, dmd, meta.name, meta.roi, meta.bin);
for w = reshape(fit.warnings, 1, [])
    warning("hadamard_stim:ManualSnapNotice", "%s", w);
end
[geometry, mismatch] = hadamard_stim.luminos.active_geometry(dmd, camera);
if strlength(mismatch.message) > 0
    warning("hadamard_stim:ManualExtrapolated", "%s %s", mismatch.message, mismatch.consequence);
end
end


function stem = output_stem(output, meta)
stem = "";
if output == "none"
    return
end
if strlength(output) > 0
    [folder, name, extension] = fileparts(output);
    if ismember(lower(extension), [".mat" ".png"])
        output = fullfile(folder, name);
    end
    stem = output;
elseif meta.source ~= "array"
    [folder, name] = fileparts(meta.source);
    stem = fullfile(folder, name + "_orange_mask");
else
    fprintf("Not saved: give output=<file stem> to save the cells and mask of an array.\n");
end
end


function files = save_result(stem, result, online)
created = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
info = struct("created_utc", created, "source", "manual_segment_dmd", ...
    "image", struct("file", string(result.meta.source), "sha256", result.meta.sha256, ...
        "camera", result.meta.name, "roi", result.meta.roi, "bin", result.meta.bin, ...
        "type", result.meta.type), ...
    "n_cells", numel(result.kept), "kept", result.kept, "n_found", size(result.cells.cell_coord, 1), ...
    "off_dmd", result.off_dmd, "segmentation_settings", result.settings, "dmd_calibration", result.geometry);
segmentation = struct("cells", result.cells, "kept", result.kept, "settings", result.settings, ...
    "meta", result.meta, "illum_rois", result.illum_rois, "stim_rois", result.stim_rois, ...
    "stim_mask", result.stim_mask);
if online
    files = hadamard_stim.metadata.write_orange_mask(stem, result.mask, info);
    save(files.mat, "segmentation", "-append");
else
    folder = fileparts(stem);
    if strlength(folder) > 0 && ~isfolder(folder)
        mkdir(folder);
    end
    files = struct("mat", stem + ".mat", "png", "");
    save(files.mat, "segmentation", "info", "-v7");
end
end


function show(image, cells, kept)
f = figure("Name", "Manual segmentation", "Color", "w");
ax = axes(f);
values = sort(image(:));
limits = values(max(1, round([0.005 0.995] * numel(values))))';
if limits(2) <= limits(1), limits(2) = limits(1) + 1; end
imagesc(ax, image, limits);
colormap(ax, gray);
axis(ax, "image");
hold(ax, "on");
spots = hadamard_stim.yitong.split_rois(cells.illum_rois);
for k = 1:numel(spots)
    colour = [0.85 0.2 0.2];
    if ismember(k, kept), colour = [0.2 0.9 0.3]; end
    p = spots{k};
    plot(ax, p([1:end 1], 1), p([1:end 1], 2), "-", "Color", colour, "LineWidth", 1);
    text(ax, cells.cell_coord(k, 1), cells.cell_coord(k, 2), string(k), "Color", colour, ...
        "FontSize", 7, "HorizontalAlignment", "center");
end
hold(ax, "off");
title(ax, sprintf("%d of %d cells kept (green)", numel(kept), size(cells.cell_coord, 1)));
end
