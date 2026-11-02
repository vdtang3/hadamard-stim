function written = write_calibration_qc(qc, folders, scorr_sha256, options)
%WRITE_CALIBRATION_QC Save a calibration's QC beside each of its recordings.
%
%   written = hadamard_stim.luminos.write_calibration_qc(qc, folders, scorr_sha256)
%
%   qc            hadamard_stim.luminos.calibration_qc
%   folders       the calibration folders (the scan set), each of which gets
%                 hadamard_calibration_qc.png   the panels (render)
%                 hadamard_calibration_qc.json  qc.summary, folders, identity
%                 hadamard_calibration_qc.mat   qc (the images, single)
%   scorr_sha256  the calibration's identity, as the run recipe records it
%   format        optional: the scans' camera format (camera_format), recorded
%                 in the JSON and shown, since every count is in its mode
%
%   written is the PNG paths. A folder whose JSON already names this
%   scorr_sha256 is left alone, so preparing the rig again rewrites nothing.
arguments
    qc struct
    folders string
    scorr_sha256 (1, 1) string
    options.format = []
end
written = strings(0, 1);
generated = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
record = struct("kind", "hadamard_stim_calibration_qc", "schema_version", "1.0.0", ...
    "generated_utc", generated, "scorr_sha256", scorr_sha256, ...
    "folders", reshape(folders, 1, []), "camera_format", options.format, "summary", qc.summary);
figure_ = [];
for folder = reshape(folders, 1, [])
    json = fullfile(folder, "hadamard_calibration_qc.json");
    if isfile(json)
        try
            old = jsondecode(fileread(json));
            if string(old.scorr_sha256) == scorr_sha256
                continue
            end
        catch
        end
    end
    if isempty(figure_)
        figure_ = render(qc, folders, scorr_sha256, generated, options.format);
        closer = onCleanup(@() close(figure_)); %#ok<NASGU>
    end
    png = fullfile(folder, "hadamard_calibration_qc.png");
    exportgraphics(figure_, png, "Resolution", 110);
    save(fullfile(folder, "hadamard_calibration_qc.mat"), "qc", "record", "-v7");
    hadamard_stim.metadata.write_text(string(jsonencode(record, "PrettyPrint", true)), json);
    written(end+1, 1) = png; %#ok<AGROW>
end
end

function f = render(qc, folders, scorr_sha256, generated, format)
s = qc.summary;
f = figure("Visible", "off", "Color", "w", "Position", [0 0 1500 980]);
t = tiledlayout(f, 3, 3, "TileSpacing", "compact", "Padding", "compact");

wf = double(qc.widefield);
show(t, wf, prctile(wf(:), [1 99.7]), gray(256), "1. Widefield: mean frame above offset", ...
    "the illumination on the slide (all recordings)");

had = mean(double(qc.had), 3);
show(t, had, prctile(had(:), [1 99.7]), gray(256), "2. The scans reconstructed with this calibration", ...
    "should follow 1 smoothly; a grid or speckle is a bad calibration");

ratio = double(qc.ratio);
show(t, ratio, s.ratio_median_illuminated * [0.5 1.5], parula(256), ...
    sprintf("3. Ratio 2 / 1 where lit (CV %.3f)", s.ratio_cv_illuminated), ...
    "smooth: pinholes right (blobs: out-of-focus features)");

contrast = double(qc.contrast);
show(t, contrast, [1 max(4, prctile(contrast(qc.illuminated), 95))], parula(256), ...
    sprintf("4. Pinhole contrast (median %.1f lit, %.1f dark)", ...
    s.contrast_median_illuminated, s.contrast_median_dark), ...
    "how clearly each pixel saw one pinhole; ~3 is noise");

code = double(qc.code);
[cr, cc] = zoom_box(qc.illuminated, 48);
show(t, code(cr, cc), [1 s.pinholes_expected], hsv(s.pinholes_expected), ...
    sprintf("5. Pinhole per pixel, rows %d-%d, cols %d-%d", cr(1), cr(end), cc(1), cc(end)), ...
    "a regular lattice of tiles; noise means the pattern was not seen");

ax = nexttile(t);
axis(ax, "off");
[~, names] = arrayfun(@fileparts, folders, "UniformOutput", false);
lines = [
    "Hadamard calibration QC"
    "  " + string(names(:))
    "scorr " + extractBefore(scorr_sha256 + "            ", 13) + ", " + generated
    ""
    sprintf("recordings %d, frames %s, frame %d x %d", s.n_recordings, mat2str(s.frames), s.frame_size)
    format_line(format, s)
    sprintf("m_q [%d %d]", s.m_q)
    sprintf("illuminated %.1f %% of the frame", 100 * s.illuminated_fraction)
    sprintf("widefield median (lit) %.0f counts", s.widefield_median_counts_illuminated)
    "per recording (lit) " + strjoin(compose("%.0f", s.recording_median_counts_illuminated), ", ")
    sprintf("peak raw %d of %d, saturated %.4f %%", s.peak_raw_value, s.saturation_count, 100 * s.saturated_fraction)
    sprintf("dark median raw %.1f (offset subtracted: %g)", s.dark_median_raw, qc_offset(s))
    sprintf("pinholes used (lit) %d / %d", s.pinholes_used_illuminated, s.pinholes_expected)
    sprintf("contrast median lit %.1f, dark %.1f", s.contrast_median_illuminated, s.contrast_median_dark)
    sprintf("ratio 2/1 median %.3g, CV %.3f", s.ratio_median_illuminated, s.ratio_cv_illuminated)
    sprintf("recording consistency min r %.3f", s.recording_consistency_min_r)
    ];
text(ax, 0, 1, lines, "VerticalAlignment", "top", "FontName", "monospaced", "FontSize", 9, ...
    "Interpreter", "none");

ax = nexttile(t, [1 3]);
k = size(qc.had, 3);
if k > 1
    strip = [];
    for j = 1:k
        p = double(qc.had(:, :, j));
        strip = [strip, p, nan(size(p, 1), 8)]; %#ok<AGROW>
    end
    imagesc(ax, strip(:, 1:end - 8), prctile(had(:), [1 99.7]));
    axis(ax, "image", "off");
    colormap(ax, gray(256));
    title(ax, sprintf("7. Each recording reconstructed (min pairwise r %.3f where lit): should agree", ...
        s.recording_consistency_min_r), "FontWeight", "normal");
else
    axis(ax, "off");
    title(ax, "7. One recording: nothing to compare", "FontWeight", "normal");
end
end

function t = format_line(format, s)
% The camera mode the counts are in.
if isstruct(format)
    t = "camera: " + format.description;
    if strlength(string(format.mode_label)) > 0
        t = t + ", " + string(format.mode_label);
    end
else
    t = "camera: " + s.storage_class + " frames, mode not recorded";
end
end

function show(t, im, lim, map, heading, note)
ax = nexttile(t);
if ~all(isfinite(lim)) || lim(1) >= lim(2)
    lim = [min(im(:)) max(im(:)) + eps];
end
imagesc(ax, im, lim);
axis(ax, "image");
ax.XTick = [];
ax.YTick = [];
colormap(ax, map);
colorbar(ax);
title(ax, heading, "FontWeight", "normal", "Interpreter", "none");
xlabel(ax, note, "Interpreter", "none");
end

function [r, c] = zoom_box(lit, half)
% A square around the illuminated area's centroid, inside the frame.
[rows, cols] = size(lit);
[y, x] = find(lit);
if isempty(y)
    y = rows / 2;
    x = cols / 2;
end
cy = round(mean(y));
cx = round(mean(x));
r = max(1, min(rows - 2 * half + 1, cy - half)):min(rows, max(2 * half, cy + half - 1));
c = max(1, min(cols - 2 * half + 1, cx - half)):min(cols, max(2 * half, cx + half - 1));
end

function v = qc_offset(s)
% QC saved before the offset was recorded subtracted his 100.
v = 100;
if isfield(s, "offset")
    v = s.offset;
end
end
