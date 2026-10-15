function result = drift_correction(hadCur, hadRef, hadZStack, zAll, cell_coord, mask_sequence_rois_ref, options)
%DRIFT_CORRECTION The analysis half of Yitong's square_target_drift_correction_v4.
%
%   result = hadamard_stim.yitong.drift_correction(hadCur, hadRef, hadZStack, zAll, cell_coord, rois_ref)
%   result = hadamard_stim.yitong.drift_correction(..., smooth=false)
%
%   hadCur     Hadamard image of the sample now (the drift scan)
%   hadRef     the reference Hadamard image the cells were found on
%   hadZStack  reference z-stack, one plane per zAll entry
%   zAll       motor positions of those planes
%   cell_coord the cells (he passes the reference cells every time, so
%              corrections never accumulate)
%   rois_ref   {illumination ROIs, stimulation ROIs}, NaN-separated, as
%              they were when the cells were approved
%   smooth     true (default): each cell's shift is the mean over cells
%              within 400 um, as v4 does. false: each cell's own flow, as
%              square_target_drift_correction_single_v1 (his behaviour
%              script) does; that is v4's only analysis difference.
%
%   result.illum_spots / stim_spots  the shifted spots (cell, 1 x n)
%   result.cell_shift                [n x 2] (Vx, Vy) per cell, smoothed
%                                    unless smooth is false
%   result.flow_at_cells             [n x 2] mean flow in each cell's box
%   result.z_drift                   motor units; the protocol moves the
%                                    stage to (position - z_drift)
%   result.img_corr, result.fit_coeffs, result.z_fallback
%                                    the Z estimate and whether it fell
%                                    back to the best plane
%
%   The acquisition half (switching to the scan waveform, doubling the
%   exposure, loading the scan patterns, restoring everything) is
%   hadamard_stim.protocol.run_drift_correction.
%
%   Port of tests/yitong_reference/dragonfly/Auto Scripts/square_target_drift_correction_v4.m
%   SHA-256 3c547f4d070bc0e6c90337f995c8bcac6a87c8dbb2875eb574f968969b2a1f67
%   Changes: the analysis after the scan only, with the images passed in;
%   it returns the shifted spots instead of redrawing them into the DMD
%   app (the caller rasterises them, as he did with dmd_draw_hidden), and
%   returns z_drift instead of moving the motor.
%
%   smooth=false mirrors his Dragonfly_yq_v1_2026_02_09/Auto Scripts/
%   square_target_drift_correction_single_v1.m, SHA-256
%   04a14583bbe5a3ada1dbced0b2d14d592fedff8e42591c26ba07884189a8f8aa:
%   v4 without the smoothing, the stimulation spots and the blue reset. It
%   is not in the frozen reference, because adding it would change the
%   manifest every golden fixture records (notebook, 2026-10-15).
arguments
    hadCur
    hadRef
    hadZStack
    zAll
    cell_coord
    mask_sequence_rois_ref
    options.smooth (1, 1) logical = true
end
[nrows,ncols] = size(hadRef);

%% correct x-y drift
movImg = hadCur;
refImg = hadRef;

[~,flowXY ]= hadamard_stim.yitong.optical_flow_motion_correction_single_frame(movImg,refImg);

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
cell_shift = zeros(nCells,2);
for ii = 1:nCells
    if options.smooth
        in = distMat(ii,:)<rLim;
        Vx_i = mean(Vx(in));
        Vy_i = mean(Vy(in));
    else
        Vx_i = Vx(ii);
        Vy_i = Vy(ii);
    end
    cell_shift(ii,:) = [Vx_i Vy_i];

    illumSpot_i = illumSpotRois(spot_rois_idx(ii)-nPts+1:spot_rois_idx(ii)-1,:);
    illumSpotRoisNew{ii} = illumSpot_i + [Vx_i Vy_i];

    stimSpot_i = stimSpotRois(spot_rois_idx(ii)-nPts+1:spot_rois_idx(ii)-1,:);
    stimSpotRoisNew{ii} = stimSpot_i + [Vx_i Vy_i];
end

%% correct z drift
hadCurFft = fftshift(abs(fft2(hadCur-mean(hadCur,[1 2]))));

hadZStackFft = zeros(size(hadZStack));
for ii = 1:size(hadZStack,3)
hadZStackFft(:,:,ii) = fftshift(abs(fft2(hadZStack(:,:,ii)-mean(hadZStack(:,:,ii),[1 2]))));
end

imgCorr = hadamard_stim.yitong.tovec((hadCurFft-mean(hadCurFft,[1 2]))./std(hadCurFft,0,[1 2]))' * ...
    hadamard_stim.yitong.tovec((hadZStackFft-mean(hadZStackFft,[1 2]))./std(hadZStackFft,0,[1 2]));

f = fit(zAll'-mean(zAll), imgCorr','poly2');
fitCoeffs = coeffvalues(f);

zDrift = -fitCoeffs(2)/2/fitCoeffs(1);
z_fallback = false;
if abs(zDrift) > max(abs(zAll-mean(zAll)))
    [~,idxZDrift] = max(imgCorr);
    zDrift = zAll(idxZDrift) - mean(zAll);
    z_fallback = true;
end

result.illum_spots = illumSpotRoisNew';
result.stim_spots = stimSpotRoisNew';
result.cell_shift = cell_shift;
result.flow_at_cells = [Vx Vy];
result.z_drift = zDrift;
result.img_corr = imgCorr;
result.fit_coeffs = fitCoeffs;
result.z_fallback = z_fallback;
end
