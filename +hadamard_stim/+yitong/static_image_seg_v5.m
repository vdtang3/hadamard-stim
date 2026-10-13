function [x_out, y_out, min_val] = static_image_seg_v5(im, thres, n_exclude)
%STATIC_IMAGE_SEG_V5 Yitong's cell finder for the Auto Square patterns.
%
%   [x, y, min_val] = hadamard_stim.yitong.static_image_seg_v5(im, thres, n_exclude)
%
%   im         reference image (camera orientation)
%   thres      number of cells to keep (his ThresholdEditField, 320)
%   n_exclude  how many of the highest-contrast candidates to skip; he
%              typed it at an input() prompt after looking at min_val
%
%   x, y are the cells' maximum pixels (column, row), in ascending order of
%   contrast. That order assigns the stimulation matrix's rows, so it is
%   part of the protocol. min_val is the curve he plotted to choose
%   n_exclude (figure 51).
%
%   Behaviour kept for parity (notebook, P4): it errors when two region
%   maxima tie in value, and when there are fewer than 1000 watershed
%   regions.
%
%   Port of tests/yitong_reference/dragonfly/Utilities/static_image_seg_v5.m
%   SHA-256 81da03515d32a6aeb8184b8eedfe5839c28ad8db18b4b1e8f6a49c0a985246a6
%   Changes: n_exclude is an argument instead of input(); min_val is
%   returned instead of plotted; figures and commented-out code removed.
arguments
    im {mustBeNumeric}
    thres (1, 1) double = 50
    n_exclude (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
end

im = double(im);

gSig = 7;
gSiz = 7;
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

nROILim = 1000;
pxlContrastSort = sort(y,'descend');
goodROI = y > pxlContrastSort(nROILim) & x' > 10;
goodROIIdx = find(goodROI);
L2 = zeros(size(L));  % Make a new label matrix with only the good ROIs
for j = 1:sum(goodROI)
    L2(L(:) == goodROIIdx(j)) = j;
end

pxl = regionprops(L2,imRef,'Pixelvalues');
ctr_val = arrayfun(@(x) max(x.PixelValues),pxl);
ctr_r = zeros(sum(goodROI),1);
ctr_c = zeros(sum(goodROI),1);
for j = 1:sum(goodROI)
[ctr_r(j),ctr_c(j)] = ind2sub(size(imRef),find(ismember(imRef(:),ctr_val(j))));
end

pxl_avg = arrayfun(@(x) mean(maxk(x.PixelValues,5)),pxl);

pxl_contrast2 = pxl_avg - pxl_med(goodROI);
[pxl_contrast2_sort,idxSort] = sort(pxl_contrast2);
nTest = 100;
minVal = zeros(nTest,1);
for j = 1:nTest
    minVal(j) = pxl_contrast2_sort((end-thres+1)-j+1)/pxl_contrast2_sort(end-j+1);
end
min_val = minVal;

x = n_exclude;
goodROI2 = idxSort((end-thres+1:end) - x);

x_out = ctr_c(goodROI2)/upsampl;
y_out = ctr_r(goodROI2)/upsampl;
end
