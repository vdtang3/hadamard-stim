function [x_out, y_out, min_val, excluded, info] = static_image_seg_v5(im, thres, n_exclude, options)
%STATIC_IMAGE_SEG_V5 Yitong's cell finder for the Auto Square patterns.
%
%   [x, y, min_val, excluded, info] = hadamard_stim.yitong.static_image_seg_v5(im, thres, n_exclude, ...)
%
%   im         reference image (camera orientation)
%   thres      number of cells to keep (his ThresholdEditField, 320)
%   n_exclude  how many of the highest-contrast candidates to skip; he
%              typed it at an input() prompt after looking at min_val
%
%   x, y are the cells' maximum pixels (column, row), in ascending order of
%   contrast. That order assigns the stimulation matrix's rows, so it is
%   part of the protocol. min_val is the curve he plotted to choose
%   n_exclude (figure 51). excluded is [x y] of the n_exclude skipped
%   candidates, in ascending contrast, for display and the record only.
%
%   What it does, and what each option changes (the defaults are his):
%     1. The image is filtered with a zero-mean disk of filter_size_px
%        (his gSiz = gSig = 7) and cut into watershed regions.
%     2. Candidates: the candidate_pool regions of highest peak-minus-
%        local-median contrast (his nROILim, 1000; strictly above the
%        pool-th value, so at most candidate_pool - 1) that are larger
%        than min_area_px pixels (his 10). There is no intensity
%        threshold, only this ranking: a larger pool admits lower-contrast
%        regions, and it is what limits how many cells can be selected.
%     3. Selection: candidates ranked by the mean of their 5 brightest
%        pixels minus the local median; the n_exclude highest are skipped
%        and the next thres kept (select_all: every remaining candidate).
%   Both rankings use differences of intensities, on regions found with a
%   zero-mean filter, so an image's gain (another modality's dynamic
%   range) does not change the cells at all, and an offset (its
%   background) changes only regions within a filter's width of the
%   border (the filter pads with zeros), which can move a few candidates
%   across the ranking's cutoff (3 of 640 for +500 on a test image).
%
%   Fewer candidates than thres is not an error: every available one is
%   kept, and info says so. min_val is NaN where the curve would need
%   candidates that do not exist. Only an image with no regions, or no
%   candidate left after skipping n_exclude, refuses (TooFewRegions,
%   TooFewCandidates).
%
%   info: n_regions, n_ranked (regions inside the pool), n_candidates
%   (ranked and large enough), n_available (after skipping n_exclude),
%   n_requested (thres; NaN with select_all), n_selected, limited (fewer
%   than thres were available), and the options used.
%
%   P4 (notebook): his code looked for each region's maximum value in the
%   whole image, and errored when that value also occurred at any other
%   pixel. The port looks only inside the region, taking its first
%   maximum pixel (column-major) when the region holds the value twice.
%   Where his code ran, the value occurred once, inside the region, so
%   every result he could get is unchanged.
%
%   Port of tests/yitong_reference/dragonfly/Utilities/static_image_seg_v5.m
%   SHA-256 81da03515d32a6aeb8184b8eedfe5839c28ad8db18b4b1e8f6a49c0a985246a6
%   Changes: n_exclude is an argument instead of input(); min_val is
%   returned instead of plotted; the skipped candidates are returned
%   (excluded); figures and commented-out code removed; a region's maximum
%   pixel is found within the region (P4); his constants (pool, area, filter
%   size) are options with his values as defaults; fewer regions than the
%   pool ranks them all (a candidate must have positive contrast), and
%   fewer candidates than thres keeps them all,
%   where his code raised an indexing error; the candidates' label matrix
%   is built by lookup rather than one pass over the image per candidate
%   (the same labels; his loop is too slow for large pools).
arguments
    im {mustBeNumeric}
    thres (1, 1) double = 50
    n_exclude (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
    options.candidate_pool (1, 1) double {mustBeInteger, mustBeGreaterThanOrEqual(options.candidate_pool, 2)} = 1000
    options.min_area_px (1, 1) double {mustBeNonnegative} = 10
    options.filter_size_px (1, 1) double {mustBeInteger, mustBePositive} = 7
    options.select_all (1, 1) logical = false
end

im = double(im);

gSig = options.filter_size_px;
gSiz = options.filter_size_px;
psf = fspecial('gaussian', round(gSiz), gSig);
ind_nonzero = (psf(:)>=max(psf(:,1)));
psf = psf-mean(psf(ind_nonzero));
psf(~ind_nonzero) = 0;   % only use pixels within the center disk

upsampl = 1;
if upsampl < 1
    im_b = imresize(imgaussfilt(im,1/upsampl),upsampl);
    im_fb = imfilter(im_b,psf,'same');
else
    im_f = imfilter(im,psf,'same');
    im_fb = imresize(im_f,upsampl);
end
[nr2,nc2] = size(im_fb);

L = watershed(-im_fb);

imRef = im;
stats = regionprops(L, imRef, 'Area', 'PixelValues','WeightedCentroid');
medRange = -5:5;
areas = [stats(:).Area];

pxl_max = arrayfun(@(x) max(x.PixelValues),stats);

pxl_med = arrayfun(@(x) median(reshape(...
    imRef(min(max(round(x.WeightedCentroid(2)) + medRange,1),nr2),...
    min(max(round(x.WeightedCentroid(1)) + medRange,1),nc2)),...
    [],1)),stats);
pxl_contrast = pxl_max - pxl_med;

x = areas;
y = pxl_contrast;

nROILim = options.candidate_pool;
if isempty(y)
    error("hadamard_stim:TooFewRegions", ...
        ['No cells detected: the reference image has no watershed regions. Choose another FOV, ' ...
         'or check that the reference image shows the sample.']);
end
if numel(y) >= nROILim
    pxlContrastSort = sort(y,'descend');
    ranked = y > pxlContrastSort(nROILim);
else
    ranked = true(size(y));   % fewer regions than the pool: all are ranked
end
% A region no brighter than its surroundings is not a candidate. Where his
% code ran the pool's cutoff was positive, so this changes none of his
% results; it stops a featureless image's few regions becoming "cells".
goodROI = ranked & x' > options.min_area_px & y > 0;
goodROIIdx = find(goodROI);
n_candidates = numel(goodROIIdx);
% Make a new label matrix with only the good ROIs: label -> candidate number.
lookup = zeros(numel(stats) + 1, 1);
lookup(goodROIIdx + 1) = 1:n_candidates;
L2 = reshape(lookup(double(L(:)) + 1), size(L));

if n_candidates <= n_exclude
    error("hadamard_stim:TooFewCandidates", ...
        ['No cells detected: segmentation found %d candidate cells and skips the %d of highest ' ...
         'contrast (segmentation.n_exclude). Choose another FOV, lower n_exclude, or admit more ' ...
         'regions (segmentation.candidate_pool, min_area_px).'], n_candidates, n_exclude);
end
n_available = n_candidates - n_exclude;
if options.select_all
    n_keep = n_available;
else
    n_keep = min(thres, n_available);
end

pxl = regionprops(L2,imRef,'Pixelvalues','PixelIdxList');
ctr_val = arrayfun(@(x) max(x.PixelValues),pxl);
ctr_r = zeros(n_candidates,1);
ctr_c = zeros(n_candidates,1);
for j = 1:n_candidates
idx = pxl(j).PixelIdxList(pxl(j).PixelValues == ctr_val(j));   % P4: within the region
[ctr_r(j),ctr_c(j)] = ind2sub(size(imRef),idx(1));
end

pxl_avg = arrayfun(@(x) mean(maxk(x.PixelValues,5)),pxl);

pxl_contrast2 = pxl_avg - pxl_med(goodROI);
[pxl_contrast2_sort,idxSort] = sort(pxl_contrast2);
nTest = 100;
minVal = NaN(nTest,1);   % NaN where the curve needs candidates that do not exist
n = numel(pxl_contrast2_sort);
for j = 1:min(nTest, n)
    k = (n-n_keep+1)-j+1;
    if k >= 1
        minVal(j) = pxl_contrast2_sort(k)/pxl_contrast2_sort(end-j+1);
    end
end
min_val = minVal;

x = n_exclude;
goodROI2 = idxSort((end-n_keep+1:end) - x);

x_out = ctr_c(goodROI2)/upsampl;
y_out = ctr_r(goodROI2)/upsampl;
skipped = idxSort(end-x+1:end);
excluded = [ctr_c(skipped) ctr_r(skipped)]/upsampl;

requested = thres;
if options.select_all
    requested = NaN;
end
info = struct("n_regions", numel(y), "n_ranked", sum(ranked), "n_candidates", n_candidates, ...
    "n_available", n_available, "n_requested", requested, "n_selected", n_keep, ...
    "limited", ~options.select_all && n_keep < thres, ...
    "candidate_pool", nROILim, "min_area_px", options.min_area_px, ...
    "filter_size_px", options.filter_size_px, "select_all", options.select_all);
end
