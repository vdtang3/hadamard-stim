function [x_out,y_out] = static_image_seg_v5(im,thres)
if ~exist('thres','var')
    thres = 50;
end

%%
% im_bin = double(im);
im = double(im);
[nr,nc] = size(im);

%%

% im_f = im_high_pass_filt(im_bin,20);

gSig = 7; 
gSiz = 7; 
psf = fspecial('gaussian', round(gSiz), gSig);
ind_nonzero = (psf(:)>=max(psf(:,1)));
psf = psf-mean(psf(ind_nonzero));
psf(~ind_nonzero) = 0;   % only use pixels within the center disk

% im_f([1:3 end-3:end],:) = 0;
% im_f(:,[1:3 end-3:end]) = 0;

upsampl = 1;
if upsampl < 1
    im_b = imresize(imgaussfilt(im,1/upsampl),upsampl);
    im_fb = imfilter(im_b,psf,'same');
else
    im_f = imfilter(im,psf,'same');
    im_fb = imresize(im_f,upsampl);
end
[nr2,nc2] = size(im_fb);
% im_fb = imgaussfilt(im_fb,1.5);

L = watershed(-im_fb); 
%%
% stats = regionprops(L, im_fb, 'Area', 'PixelValues');

% imRef = im_fb + rand(nr2,nc2)*min(abs(im_fb(:)))*.01;
imRef = im;
% stats = regionprops(L, imRef, 'Area', 'PixelValues','WeightedCentroid');
stats = regionprops(L, imRef, 'Area', 'PixelValues','WeightedCentroid');
% im_med = median(im_fb(:));
% im_med = median(imRef(:));
medRange = [-5:5];
areas = [stats(:).Area];

pxl_max = arrayfun(@(x) max(x.PixelValues),stats);

pxl_med = arrayfun(@(x) median(reshape(...
    imRef(min(max(round(x.WeightedCentroid(2)) + medRange,1),nr2),...
    min(max(round(x.WeightedCentroid(1)) + medRange,1),nc2)),...
    [],1)),stats);
pxl_contrast = pxl_max - pxl_med;




% x = pxl_bg_cnt;
% y = pxl_max;
x = areas;
y = pxl_contrast;
% y = pxl_sk;

% x = log(pxl_bg_cnt);
% y = (pxl_max_avg_norm-1).*log(pxl_max);

%%
nROILim = 1000;
pxlContrastSort = sort(y,'descend');
goodROI = y > pxlContrastSort(nROILim) & x' > 10;
% goodROI = x' > 10;
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

figure(51);clf
subplot(1,6,1:2)
plot(0:nTest-1,minVal)

x = str2double(input('Enter number of cells to exclude:','s'));

%%
% goodROI2 = gaussCorr>thres;
% gaussCorrSort = sort(gaussCorr,'descend');
% goodROI2 = gaussCorr>=gaussCorrSort(thres);
goodROI2 = idxSort((end-thres+1:end) - x);
length(goodROI2)


% L_bd = bwboundaries((L2>0));

%  
% ctr_val = arrayfun(@(x) max(x.PixelValues),pxl);
% [ctr_r,ctr_c] = ind2sub(size(im_bin),find(ismember(im_bin(:),ctr_val)));

% ctr = regionprops(L2,im_fb,'WeightedCentroid');
% ctr_c = arrayfun(@(x) x.WeightedCentroid(1),ctr);
% ctr_r = arrayfun(@(x) x.WeightedCentroid(2),ctr);


imRef = imresize(imRef,1/upsampl);
subplot(1,6,3:6)
% imshow2(im_f,[prctile(im_f(:),1) prctile(im_f(:),99.5)]) 
% imshow2(im_bin,[prctile(im_bin(:),1) prctile(im_bin(:),99.9)]) 
% imshow2(im,[prctile(im(:),1) prctile(im(:),99.95)]) 
% im_show = im_high_pass_filt(double(im),15);
% im_show = im_fb;
im_show = im;
imshow2(im_show,[prctile(im_show(:),1) prctile(im_show(:),99.95)]) 
% imshow2(min(im_show/prctile(im_show(:),99.5) + (L>0).*reshape([.2 0 0],1,1,3) ,1))
hold on
scatter(ctr_c(goodROI2)/upsampl,ctr_r(goodROI2)/upsampl,'ro')

x_out = ctr_c(goodROI2)/upsampl;
y_out = ctr_r(goodROI2)/upsampl;


end