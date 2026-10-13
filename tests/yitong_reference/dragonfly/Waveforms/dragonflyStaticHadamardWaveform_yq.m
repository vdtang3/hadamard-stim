function allWaves = dragonflyStaticHadamardWaveform_yq(df_app)%nCells,recordFrames,maxBlueIntensity,centeredROI,exposureTime)
%
%   2018-2019 Vicente Parot, 2021 Yitong Qi
%   Cohen Lab - Harvard university
%

% Camera in sychronous readout trigger mode
%   trigger to exposure delay: 165.58 us
%   trigger to exposure delay jitter: 9.74 us


% Collect app params
dt                  =   1/df_app.ni6343.rateConfigData; % DAQ clock rate
t_pulse_duration    =   dt;  % use dt max precision
t_cam_frame_daq     =  df_app.ExposureTimeMsEditField_waveform.Value*1e-3; % s
n_pat               = size(df_app.dmdApp.mask_sequence,3); % # of dmd patterns; 
n_rpt               = df_app.RepeatEditField.Value;
n_frames            = n_pat * n_rpt;
% n_frames            = df_app.camFramesInEditField.Value;
t_total             = (n_frames)*t_cam_frame_daq + 10e-3;  
t_dmd_frame_illum  = floor((t_cam_frame_daq)/dt)*dt; % expo time orange

v_blue              = df_app.BlueAmpVEditField.Value;
v_orange            = df_app.OrangeAmpVEditField.Value;


daq_channels        = df_app.ni6343.outChannelsConfigData(:,1);

nRows               = df_app.camApp.liveArea(1);
t_rollingShutter    = 3.75e-6 * nRows; %s rolling shutter wait time
% Waveform definition start


wp0 = baseWave(dt,t_pulse_duration); % 0-valued constant wave of pulse duration
wp1 = wp0+1; % 1-valued constant wave of pulse duration

w_cam_frame = wp1.extend(t_cam_frame_daq);
w_dmd_frame = extend([wp0 wp1.extend(t_dmd_frame_illum)], ...
                    t_cam_frame_daq);
w_illum_frame = [wp0.extend(t_rollingShutter) wp0.extend(t_dmd_frame_illum-t_rollingShutter)+1];


w_illum = extend([ repeat(extend(...
        [w_illum_frame],...
        t_cam_frame_daq),n_frames) ],t_total);
w_cam = extend([wp0 w_cam_frame.repeat(n_frames)],t_total);  % extra trigger to initiate recording    
w_dmd = extend([w_dmd_frame.repeat(n_frames)],t_total);
%----constant stim sequence------
% w_stim = flexRampTrainWave(dt,t_total);
% w_stim.tBefore = 0; % duration off 
% w_stim.tRamp = t_total; % duration on
% w_stim.period = t_total; % seconds
%------------end---------------------

%----optopatch stim sequence---
% w_stim = baseWave(dt,.5);
% for amp_factor = [.1 .2 .5 1]
% w_stim = [w_stim extend(baseWave(dt,.5)+1*amp_factor,1)];
% end
% w_ramp = rampWave(dt,5); w_ramp.tRamp = 5;
% w_stim = [w_stim w_ramp];
% w_stim = w_stim.extend(t_total);
%---------- end --------------

%----stair sequence---
% w_stim = [];
% w_wait = baseWave(dt,.5); 
% for amp_factor = logspace(-1.92,0,10) %0.1-5 V
%     w_stim = [w_stim w_wait baseWave(dt,1.5)+1*amp_factor];
% end
% w_stim = w_stim.extend(t_total);
% w_dmd = extend([wp0],t_total);
%---------- end --------------

%----pulse sequence test---
% w_stim = [];
% w_wait = baseWave(dt,.5); 
% 
% for pulse_width = (0.1:0.1:1)*1e-3 %0.1-5 V
%     w_stim_p = flexRampTrainWave(dt,0.5);
%     w_stim_p.tBefore = 0; % duration off 
%     w_stim_p.tRamp = pulse_width-5e-5; % duration on
%     w_stim_p.period = pulse_width; % seconds
%     w_stim = [w_stim w_wait w_stim_p];
%     pulse_width;
% end
% w_stim = w_stim.extend(t_total);
% % w_dmd = extend([wp0],t_total);
%---------- end --------------


w_blue = w_illum * v_blue;
w_orange = w_illum * v_orange;

%%

w_out{1,1} = 'cam';
w_out{1,2} = w_cam;

w_out{4,1} = 'blueIntensity';
w_out{4,2} = w_blue;

w_out{2,1} = 'orangeIntensity';
w_out{2,2} = w_orange;

% w_out{3,1} = 'AOTFVoltage';
% w_out{3,2} = w_stim*AOTF_LUT(.2);
% 
% w_out{3,1} = 'blueShutter';
% w_out{3,2} = wp0.extend(t_total)+1;
% 
% w_out{4,1} = 'pololu';
% w_out{4,2} = wp0.extend(t_total)+0;

w_out{3,1} = 'dmd';
w_out{3,2} = w_dmd;
%%
idx_daq_ch = [];
for ii=1:size(w_out,1)
    idx_daq_ch = [idx_daq_ch find(cellfun(@(x)...
                    contains(x,w_out{ii,1},'ignorecase',1),daq_channels))];

end

allWaves = [];
for ii=1:length(daq_channels)
    is_used = find(idx_daq_ch==ii);
    if is_used
        allWaves = [allWaves; w_out{is_used,2}];
    else
        allWaves = [allWaves; wp0.extend(t_total)];
    end
    
end

% 
figure(101);clf
plot(allWaves+[0:size(allWaves.amplitude,1)-1]'*2)
legend(daq_channels)
end