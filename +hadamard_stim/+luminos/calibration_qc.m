function qc = calibration_qc(m_q, movies, scorr, options)
%CALIBRATION_QC How good a Hadamard calibration looks, from what the rig uses.
%
%   qc = hadamard_stim.luminos.calibration_qc(m_q, movies, scorr)
%   qc = hadamard_stim.luminos.calibration_qc(..., saturation=4095, offset=20)
%
%   m_q         cfg.scan.m_q
%   movies      the calibration movies scan_reconstruction was given (uint8
%               or uint16 [rows x cols x frames] as recorded, one per
%               recording, on a uniform slide)
%   scorr       the calibration it computed from them (hadamard_pinhole_calibration)
%   saturation  the count at which the camera saturates (camera_format's;
%               default the largest value of the movies' class)
%   offset      the camera's dark offset in the movies' counts, the one
%               the calibration subtracted (camera_format's; default his
%               100)
%
%   Nothing is recomputed differently for display: the images are the
%   movies, the calibration's own reconstruction of them, its first stage
%   (each pixel's correlation with the pinhole codes, before upsampling)
%   and scorr rewritten in the pinhole basis it was built in.
%
%   qc.widefield      [rows x cols] mean frame above the camera offset,
%                     all recordings: the illumination on the slide
%   qc.had            [rows x cols x n_recordings] each recording
%                     reconstructed with scorr (dmd_hadamard_reconstruct_core,
%                     as the reference image and drift scans are). On a
%                     uniform slide it should follow widefield, smooth.
%   qc.ratio          mean(had, 3) ./ widefield inside the illuminated area
%                     (NaN outside): smooth when every pixel's pinhole is
%                     right; a grid or speckle where it is not. Hadamard
%                     images are optically sectioned, so out-of-focus
%                     features of the slide also show here, as smooth blobs.
%   qc.contrast       [rows x cols] how clearly each pixel saw one pinhole:
%                     its strongest code correlation over the median of all
%                     m (the calibration's ccorr, before it is normalised
%                     and upsampled). About 3 for noise; high where lit.
%   qc.code           [rows x cols] uint8, the pinhole (1..m) scorr assigns
%                     each pixel: a regular lattice where the calibration
%                     saw the pattern, noise where it did not
%   qc.illuminated    [rows x cols] logical, widefield above half its 99th
%                     percentile
%   qc.summary        numbers for the record (see below); counts are the
%                     camera's, in its mode (an 8-bit count is not a
%                     16-bit one). dark_median_raw, the median raw count
%                     outside the illuminated area, shows whether the
%                     offset subtracted (summary.offset) holds.
arguments
    m_q (1, 2) double
    movies cell
    scorr double
    options.saturation double = []
    options.offset (1, 1) double = 100
end
offset = options.offset;
saturation = options.saturation;
if isempty(saturation)
    saturation = double(intmax(class(movies{1})));
end
m = m_q(1);
n = m + 1;
[rows, cols, ~] = size(movies{1});
k_rec = numel(movies);
[sr, sc, ~] = size(scorr);
if ~isequal([sr sc], [rows cols])
    error("hadamard_stim:CalibrationSize", ...
        "The calibration is %d x %d but its movies are %d x %d.", sr, sc, rows, cols);
end

means = zeros(rows, cols, k_rec);
raw_means = zeros(rows, cols);
saturated = 0;
pixels = 0;
peak = 0;
frames = zeros(1, k_rec);
for k = 1:k_rec
    mov = movies{k};
    frames(k) = size(mov, 3);
    means(:, :, k) = mean(double(mov), 3) - offset;
    raw_means = raw_means + means(:, :, k) + offset;
    saturated = saturated + nnz(mov >= saturation);
    pixels = pixels + numel(mov);
    peak = max(peak, double(max(mov(:))));
end
widefield = mean(means, 3);
illuminated = widefield > 0.5 * prctile(widefield(:), 99);

had = hadamard_stim.yitong.dmd_hadamard_reconstruct_core(m_q, movies, scorr, offset);
ratio = mean(had, 3) ./ widefield;
ratio(~illuminated) = NaN;

% The calibration's first stage, as hadamard_pinhole_calibration does it:
% recordings summed (his: offset 100 subtracted in the movies' class,
% saturating at 0 in uint16; 8-bit movies or another offset: in double),
% repeats averaged, each pixel correlated with the m codes.
his = offset == 100 && ~any(cellfun(@(c) isa(c, "uint8"), movies));
codes = double(hadamard_stim.yitong.hadamard_bincode_nopermutation(m)') * 2 - 1;
summed = zeros(rows, cols, size(movies{1}, 3));
for k = 1:k_rec
    if his
        summed = summed + double(movies{k} - 100);
    else
        summed = summed + (double(movies{k}) - offset);
    end
end
pattern_means = mean(reshape(summed, rows * cols, n, []), 3);
clear summed
a = abs(pattern_means * codes);
contrast = reshape(max(a, [], 2) ./ max(median(a, 2), eps), rows, cols);

% scorr = (pinhole weights) * codes', codes [n x m] of full column rank, so
% the weights are recovered exactly by the pseudo-inverse.
[~, code] = max(abs(reshape(scorr, sr * sc, n) * pinv(codes')), [], 2);
code = uint8(reshape(code, sr, sc));

lit = illuminated(:);
consistency = NaN;
if k_rec > 1
    pairs = nchoosek(1:k_rec, 2);
    r = zeros(size(pairs, 1), 1);
    for p = 1:size(pairs, 1)
        a = had(:, :, pairs(p, 1));
        b = had(:, :, pairs(p, 2));
        c = corrcoef(a(lit), b(lit));
        r(p) = c(1, 2);
    end
    consistency = min(r);
end
ratio_lit = ratio(lit);
recording_counts = arrayfun(@(k) median(reshape(means(:, :, k), [], 1)), 1:k_rec);
recording_counts_lit = arrayfun(@(k) median(means(find(lit) + (k - 1) * rows * cols)), 1:k_rec);

qc.widefield = single(widefield);
qc.had = single(had);
qc.ratio = single(ratio);
qc.code = code;
qc.contrast = single(contrast);
qc.illuminated = illuminated;
qc.summary = struct( ...
    "m_q", m_q, ...
    "n_recordings", k_rec, ...
    "frames", frames, ...
    "frame_size", [rows cols], ...
    "storage_class", string(class(movies{1})), ...
    "saturation_count", saturation, ...
    "offset", offset, ...
    "dark_median_raw", median(raw_means(~illuminated) / k_rec), ...
    "illuminated_fraction", mean(lit), ...
    "widefield_median_counts_illuminated", median(widefield(lit)), ...
    "recording_median_counts", recording_counts, ...
    "recording_median_counts_illuminated", recording_counts_lit, ...
    "peak_raw_value", peak, ...
    "saturated_fraction", saturated / pixels, ...
    "pinholes_used_illuminated", numel(unique(code(lit))), ...
    "pinholes_expected", m, ...
    "contrast_median_illuminated", median(contrast(lit)), ...
    "contrast_median_dark", median(contrast(~lit)), ...
    "ratio_median_illuminated", median(ratio_lit), ...
    "ratio_cv_illuminated", std(ratio_lit) / mean(ratio_lit), ...
    "recording_consistency_min_r", consistency);
end
