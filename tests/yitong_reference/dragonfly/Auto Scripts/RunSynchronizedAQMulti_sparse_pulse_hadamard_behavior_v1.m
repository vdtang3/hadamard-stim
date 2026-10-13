%% optogenetic stim sequence to measure postsynaptic potentials and gap junction
addpath('Auto Scripts')
%% get z stack for z correction
zOrig = hMotorZ.position;

Z0 = zOrig - .030;

Z1 = zOrig + .030;

nZ = 20;

zStep = (Z1-Z0)/nZ;

zAll = linspace(Z0,Z1,nZ+1);

nRpt = 1;
%%
file_name_prefix = 'M-YQ0201-29_FOV1_Arch_';


for iRpt = 1:nRpt
    for iz = 1:nZ+1

        zi = Z0+zStep*(iz-1);

        hMotorZ.moveTo(zi)
        file_name = sprintf([file_name_prefix 'z%02u_rpt%02i'],[iz iRpt]);
        hDragonflyApp.appendedfoldernameEditField.Value = file_name;

        while hMotorZ.isMoving(),end

        hDragonflyApp.RunSynchronizedAQ([])

    end
end
hMotorZ.moveTo(zOrig)

%%
n_trial = 640;
nFrameWait = 200; % frames, wait for orange to stabilize;

hadOrangeV = 0.47;

[hadZStack,~] = hadamard_reconstruct([63 14],'E:\','had_cal_1x_arch','M-YQ0201-29_FOV1_Arch_z*_rpt01');
hadRef = hDMDApp.function_data.hadamard_ref;
% tform = findZFromPrevSession_rotation(hadRef,'M-YQ0201-24_zStackReference.mat');
% findZFromPrevSession_rotation(hadRef,'M-YQ0201-24_zStackReference.mat',tform);
% findZFromPrevSession_rotation(hadZStack,'M-YQ0201-24_zStackReference.mat',tform);
%%
nPat = 2;
hadOrder = 320;
hadMat = hadamard(hadOrder);
hadMat(1,randperm(hadOrder,hadOrder/2)) = -1;
hadMat(randperm(hadOrder,hadOrder/2),1) = -1;
rng(0,'twister')
hadMat = xor(hadMat, rand(hadOrder)>.5);
rng('default')

mask_sequence_rois_ref = hDMDApp.mask_sequence_rois(1:nPat);
mask_sequence_ref = hDMDApp.mask_sequence(:,:,1:nPat);

cell_coord = hDMDApp.function_data.cell_coord;
nCells = length(cell_coord);

if nCells ~= hadOrder
    fprintf('nCell ~= hadOrder!\n')
end
%%

file_name_prefix = sprintf('M-YQ0201-29_FOV1_SPulseHad%i_DC',hadOrder);
had_file_name_prefix = 'M-YQ0201-29_FOV1_had_trial';

nTrialsRetarget = 40; % ~10 s per trial, 10 min

% sparse pulse section
blueV = 4;%[2 4];
nFramePulse = 16;

nTrialSP = 240*2;
distCutoff = 123; % 0.8 mm, 6.5 um per pixel
nIt = 30; % number of pulses per trial
nFramePerPulse = 160;
picked = zeros(nCells,n_trial * length(blueV));
cnt = 0;
illumPatAll = cell(nIt,1);
nRptPat = ones(nIt,1)*nFramePulse;
nRptPat(end) = nRptPat(end)*2;
% hadamard section
blueVHad = 2;
nFrameHCode = 600; % unit, camera frames, blue on duration

nTrialHad = n_trial - nTrialSP;
nCodePerIt = nIt*nFramePerPulse/nFrameHCode;
nItHCycle = nIt*nFramePerPulse/nFrameHCode;
illumPatHadAll = cell(nCodePerIt,1);
nRptPatHad = ones(nCodePerIt,1)*nFrameHCode;
nRptPatHad(end) = nRptPatHad(end)*2;
cntHad = 0;

trialRatio = n_trial/nTrialHad;
%% define spinview window location
xy_spinview_taskbar = [2580, 1050];
xy_txtarea = [3500, 20];
xy_start_rec = [3760, 670];
xy_stop_rec = xy_start_rec + [-100 0];
%% bleaching calc variables
nPixCell = 5; % rough number pixels per cell
orangeV0 = hDragonflyApp.OrangeAmpVEditField.Value;
%%
tic
for iTrial = 5:n_trial
    
%     if mod(iTrial,nTrialsRetarget) == 0
    if mod(iTrial,nTrialsRetarget) == 0 || iTrial == 1
%     if mod(iTrial,nTrialsRetarget) == 0 || iTrial == 606
        had_file_name = [had_file_name_prefix num2str(iTrial)];
        square_target_drift_correction_v4(hDragonflyApp,hDMDApp, had_file_name, hadZStack, hadRef, mask_sequence_rois_ref, zAll, hadOrangeV);
        mask_sequence_cur = hDMDApp.mask_sequence(:,:,1:nPat);
        mask_sequence_rois_cur = hDMDApp.mask_sequence_rois(1:nPat);
        cell_coord = hDMDApp.function_data.cell_coord;
        nCells = length(cell_coord);
        
        % adjust orange due to bleaching
        if iTrial > 1
            orangeV1 = hDragonflyApp.OrangeAmpVEditField.Value;
            orangeV2 = orangeV1 * b0/b1;
            hDragonflyApp.OrangeAmpVEditField.Value = orangeV2;
        end
    end
    
    %% sparse pulse section
    if mod(iTrial,trialRatio) ~= 0 
        for blueV_i = blueV
            
            cnt = cnt+1;
            
            for pulseT_i = nFramePulse
                idxNull = false(nCells,1);
                nRem = nCells; 
                cIdxAllIt = false(nCells,nIt);

                for it = 1:nIt
                    if isempty(setdiff(1:nCells,find(idxNull))),continue;end

                    cIdx = quasi_equidist_hardsphere_v2(cell_coord,distCutoff,find(idxNull),picked);
                    cIdxAllIt(:,it) = cIdx;
                    idxNull = cIdx | idxNull;
                    nRem = length(idxNull)-sum(idxNull);

%                     figure(10);clf
%                     plot(cell_coord(:,1),cell_coord(:,2),'bo','markerfacecolor','b')
%                     hold on
%                     plot(cell_coord(idxNull,1),cell_coord(idxNull,2),'o','color',[0 .5 0],'markerfacecolor',[0 .5 0])
%                     plot(cell_coord(cIdx,1),cell_coord(cIdx,2),'ro','markerfacecolor','r')
%                     daspect([1 1 1])

% 
                    fprintf('it: %g, cell chose: %g cell left: %g\n',[it sum(cIdx) nRem])
    
                    hDMDApp.function_data.cIdx = cIdx;
%                     hDMDApp.FunArgsTextArea.Value = sprintf('app.function_data.cIdx,2');
                    hDMDApp.mask_sequence_rois(1) = mask_sequence_rois_cur(2); 
                    
                    % this function updates both mask sequence and rois
                    spot_select_sequence(hDMDApp,cIdx,2) 
                    
                    hDMDApp.mask_sequence_rois(1) = mask_sequence_rois_cur(1);

                    illumPatAll{it} = alp_logical_to_btd(permute(hDMDApp.mask_sequence,[2 1 3]));

            %         figure(10);clf
            %         plot(hDMDApp.mask_sequence_rois{2}(:,1),hDMDApp.mask_sequence_rois{2}(:,2),'r')

                end 

                picked(idxNull,cnt) = 1;
                dmd_send_btd_sequence_multi(hDMDApp,illumPatAll,nRptPat)

                file_name = sprintf([file_name_prefix '_%.0fV_%.1f_%02i'],[blueV_i pulseT_i iTrial] );
                hDragonflyApp.appendedfoldernameEditField.Value = file_name;

                hDMDApp.mask_sequence_rois = mask_sequence_rois_cur;
                hDMDApp.mask_sequence = mask_sequence_cur;
                hDMDApp.MaskNoTotalEditField.Value = 2; % for waveform generation
                hDMDApp.function_data.cIdxAllIt = cIdxAllIt;

                hDragonflyApp.BlueAmpVEditField.Value = blueV_i;
                hDragonflyApp.WaveformparamsTextArea.Value{1} = num2str(nFrameWait); % wait time
                hDragonflyApp.WaveformparamsTextArea.Value{2} = num2str(pulseT_i); % on time
                hDragonflyApp.WaveformparamsTextArea.Value{3} = num2str(nFramePerPulse); % period
                hDragonflyApp.WaveformparamsTextArea.Value{4} = num2str(nIt); % wait time
            end
        end
    else
    %% hadamard section
        cIdxAllIt = false(nCells,nCodePerIt);
        for itHad = 1:nCodePerIt
            cIdx = hadMat(:,cntHad+itHad)>0;
            cIdxAllIt(:,itHad) = cIdx;

%             figure(10);clf
%             plot(cell_coord(:,1),cell_coord(:,2),'bo','markerfacecolor','b')
%             hold on
%             plot(cell_coord(cIdx,1),cell_coord(cIdx,2),'ro','markerfacecolor','r')
%             daspect([1 1 1])
% 
%             fprintf('it hadamard: %i\n',cntHad+itHad)
            
            hDMDApp.function_data.cIdx = cIdx;
%             hDMDApp.FunArgsTextArea.Value = sprintf('app.function_data.cIdx,2');
            hDMDApp.mask_sequence_rois(1) = mask_sequence_rois_cur(2); 
%             tic
%             dmd_run_quick_function(hDMDApp);
%             toc
            spot_select_sequence(hDMDApp,cIdx,2)
            hDMDApp.mask_sequence_rois(1) = mask_sequence_rois_cur(1);
            
            illumPatHadAll{itHad} = alp_logical_to_btd(permute(hDMDApp.mask_sequence,[2 1 3]));
            
        end
        toc
        cntHad = mod(cntHad + nCodePerIt, hadOrder);
        dmd_send_btd_sequence_multi(hDMDApp,illumPatHadAll,nRptPatHad)

        file_name = sprintf([file_name_prefix '_%.0fV_%.1f_%02i'],[blueVHad nFrameHCode iTrial] );
        hDragonflyApp.appendedfoldernameEditField.Value = file_name;

        hDMDApp.mask_sequence_rois = mask_sequence_rois_cur;
        hDMDApp.mask_sequence = mask_sequence_cur;
        hDMDApp.MaskNoTotalEditField.Value = 2; % for waveform generation
        hDMDApp.function_data.cIdxAllIt = cIdxAllIt;

        hDragonflyApp.BlueAmpVEditField.Value = blueVHad;
        hDragonflyApp.WaveformparamsTextArea.Value{1} = num2str(nFrameWait); % wait time
        hDragonflyApp.WaveformparamsTextArea.Value{2} = num2str(nFrameHCode); % on time 
        hDragonflyApp.WaveformparamsTextArea.Value{3} = num2str(nFrameHCode); % period
        hDragonflyApp.WaveformparamsTextArea.Value{4} = num2str(nCodePerIt); % number of pulses
    
    end
    
    % click spinview buttons
    mouse_task_bar_click(xy_spinview_taskbar)
    paste_to_textarea(xy_txtarea,['E:\' file_name])
    mouse_move_click(xy_start_rec)

    hDragonflyApp.RunSynchronizedAQ([])
    mouse_move_click(xy_stop_rec)
    
    % calculate bleaching to adjust orange level
    if iTrial == 1
        f = dir(fullfile('E:',['*' file_name]));
        mov = vm(fullfile(f.folder,f.name),[501:1000]);
        imVec = sort(tovec(mov.mean),'descend');
        b0 = median(imVec(1:nCells*nPixCell)) - median(imVec);
    end
    f = dir(fullfile('E:',['*' file_name]));
    mov = vm(fullfile(f.folder,f.name),[501:1000]);
    imVec = sort(tovec(mov.mean),'descend');
    b1 = median(imVec(1:nCells*nPixCell)) - median(imVec);
    
    toc
end

%% get z stack for GFP
zOrig = hMotorZ.position;

Z0 = zOrig - .045;

Z1 = zOrig + .045;

nZ = 30;

zStep = (Z1-Z0)/nZ;

zAll_GFP = linspace(Z0,Z1,nZ+1);

nRpt = 1;
%%
file_name_prefix = 'M-YQ0201-29_FOV1_GFP_';


for iRpt = 1
    for iz = 1:nZ+1

        zi = Z0+zStep*(iz-1);

        hMotorZ.moveTo(zi)
        file_name = sprintf([file_name_prefix 'z%02u_rpt%02i'],[iz iRpt]);
        hDragonflyApp.appendedfoldernameEditField.Value = file_name;

        while hMotorZ.isMoving(),end

        hDragonflyApp.RunSynchronizedAQ([])

    end
end
hMotorZ.moveTo(zOrig)
%%
[hadZStack_gfp,~] = hadamard_reconstruct([63 14],'E:\','had_cal_1x_gfp','M-YQ0201-29_FOV1_GFP_z*_rpt01');