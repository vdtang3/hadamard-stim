function square_target_drift_correction_v4(dfApp,dmdApp, fname, hadZStack, hadRef, mask_sequence_rois_ref, zAll, hadOrangeV)

[nrows,ncols] = size(hadRef);
%% take hadamard section
curWavFun = dfApp.WaveformFunctionDropDown.Value;
wavFuns = dfApp.WaveformFunctionDropDown.Items;
nWavFuns = length(wavFuns);

for ii = 1:nWavFuns
    if contains(wavFuns{ii},'Hadamard')
        dfApp.WaveformFunctionDropDown.Value = wavFuns{ii};
    end
end


maskSequence = dmdApp.mask_sequence;
maskSequenceROIs = dmdApp.mask_sequence_rois;

if ~isempty(dmdApp.saved_mask)
    static_Hadamard_patterns(dmdApp,dmdApp.saved_mask);
else
    static_Hadamard_patterns(dmdApp);
end
dmd_send_sequence(dmdApp);
pause(.5)

fnameCur = dfApp.appendedfoldernameEditField.Value;
dfApp.appendedfoldernameEditField.Value = fname;

orangeVCur = dfApp.OrangeAmpVEditField.Value;
dfApp.OrangeAmpVEditField.Value = hadOrangeV;

dfApp.BlueAmpVEditField.Value = 0;

tExpOrig = dfApp.camApp.ExposureTimeMsEditField.Value;
dfApp.camApp.ExposureTimeMsEditField.Value = tExpOrig*2;
dfApp.camApp.liveExposureTimeSeconds = tExpOrig*2/1000;
dfApp.ExposureTimeMsEditField_waveform.Value = tExpOrig*2 + .02;

dfApp.RunSynchronizedAQ([])

hadCur = dmd_hadamard_reconstruct(dmdApp,[63 14],'E:\',[],fname);

% return to original values
dfApp.WaveformFunctionDropDown.Value = curWavFun;
dfApp.appendedfoldernameEditField.Value = fnameCur;
dfApp.OrangeAmpVEditField.Value = orangeVCur;
dfApp.camApp.ExposureTimeMsEditField.Value = tExpOrig;
dfApp.camApp.liveExposureTimeSeconds = tExpOrig/1000;
dfApp.ExposureTimeMsEditField_waveform.Value = tExpOrig + .02;

dmdApp.mask_sequence_rois = mask_sequence_rois_ref;
dmdApp.mask_sequence = maskSequence;
%% correct x-y drift
movImg = hadCur;
refImg = hadRef;

[imgMC,flowXY ]= optical_flow_motion_correction_single_frame(movImg,refImg);

cell_coord = dmdApp.function_data.cell_coord;
distMat = squareform(pdist(cell_coord));
nCells = length(cell_coord);

illumSpotRoisNew = cell(nCells,1);
stimSpotRoisNew = cell(nCells,1);

illumSpotRois = mask_sequence_rois_ref{1};
stimSpotRois = mask_sequence_rois_ref{2};
spot_rois_idx = find(ismissing(illumSpotRois(:,1)));
nPts = diff(spot_rois_idx([1 2]));


[X,Y] = meshgrid(1:ncols,1:nrows);

boxSz = 3;
boxX = ([0 1 1 0 0]-.5) * boxSz;
boxY = ([0 0 1 1 0]-.5) * boxSz;

xc = cell_coord(:,1);
yc = cell_coord(:,2);

Fx = squeeze(flowXY(:,:,1));
Fy = squeeze(flowXY(:,:,2));

Vx = zeros(nCells,1);
Vy = zeros(nCells,1);
for ii = 1:nCells
    in = inpolygon(X,Y,boxX+xc(ii),boxY+yc(ii));    
    Vx_i = mean(Fx(in));
    Vy_i = mean(Fy(in));
    
    Vx(ii) = Vx_i;
    Vy(ii) = Vy_i;
end

% smooth x-y displacement by moving average
rLim = 400/6.5;
for ii = 1:nCells
    in = distMat(ii,:)<rLim;
    Vx_i = mean(Vx(in));
    Vy_i = mean(Vy(in));
    
    illumSpot_i = illumSpotRois(spot_rois_idx(ii)-nPts+1:spot_rois_idx(ii)-1,:);
    illumSpotRoisNew{ii} = illumSpot_i + [Vx_i Vy_i];
    
    stimSpot_i = stimSpotRois(spot_rois_idx(ii)-nPts+1:spot_rois_idx(ii)-1,:);
    stimSpotRoisNew{ii} = stimSpot_i + [Vx_i Vy_i];
end

[dmdApp.mask_sequence(:,:,1),...
    dmdApp.mask_sequence_rois(1)] = dmd_draw_hidden(dmdApp,illumSpotRoisNew,false);
[dmdApp.mask_sequence(:,:,2),...
    dmdApp.mask_sequence_rois(2)] = dmd_draw_hidden(dmdApp,stimSpotRoisNew,false);

%% correct z drift
% imgMCFft = fftshift(abs(fft2(imgMC-mean(imgMC,[1 2]))));
hadCurFft = fftshift(abs(fft2(hadCur-mean(hadCur,[1 2]))));

hadZStackFft = zeros(size(hadZStack));
for ii = 1:size(hadZStack,3)
hadZStackFft(:,:,ii) = fftshift(abs(fft2(hadZStack(:,:,ii)-mean(hadZStack(:,:,ii),[1 2]))));
end

imgCorr = tovec((hadCurFft-mean(hadCurFft,[1 2]))./std(hadCurFft,0,[1 2]))' * ...
    tovec((hadZStackFft-mean(hadZStackFft,[1 2]))./std(hadZStackFft,0,[1 2]));

f = fit(zAll'-mean(zAll), imgCorr','poly2');
fitCoeffs = coeffvalues(f);

zDrift = -fitCoeffs(2)/2/fitCoeffs(1);
if abs(zDrift) > max(abs(zAll-mean(zAll)))
    [~,idxZDrift] = max(imgCorr);
    zDrift = zAll(idxZDrift) - mean(zAll);
end
zOrig = dfApp.motorZ.position;
dfApp.motorZ.moveTo(zOrig - zDrift)
pause(.5)