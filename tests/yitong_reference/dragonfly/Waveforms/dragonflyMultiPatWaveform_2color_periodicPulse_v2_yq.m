function allWaves = dragonflyMultiPatWaveform_2color_periodicPulse_v2_yq(df_app)%nCells,recordFrames,maxBlueIntensity,centeredROI,exposureTime)
%
%   2018-2019 Vicente Parot, 2021 Yitong Qi
%   Cohen Lab - Harvard university
%
%---------- Usage Notes: -----------------
% 1. load dmd sequence of length, n_pat
% 2. specify waveform for each pattern
%-----------------------------------------

% Hardware notes:
% Camera (Teledyne Kinetix) in sychronous readout trigger mode:
%   trigger to exposure delay: 3.75 us
%   trigger to exposure delay jitter: 3.75 us

% DMD max switch rate: 22727 Hz
%% parameter definition section

% Collect app params
dt                  =   1/df_app.ni6343.rateConfigData; % DAQ clock rate
t_pulse_duration    =   dt;  % use dt max precision
t_cam_frame         =  df_app.ExposureTimeMsEditField_waveform.Value*1e-3; % s
t_gs_frame          =  df_app.GSExposureTimemsEditField.Value*1e-3; % s
n_frames            = df_app.camFramesInEditField.Value;
n_gs_frames         = floor(n_frames*t_cam_frame/t_gs_frame);
t_total             = (n_frames)*t_cam_frame;  
n_pat               = df_app.dmdApp.MaskNoTotalEditField.Value; % # of dmd patterns; 
orange_duty_cycle   = 0.8;
blue_duty_cycle     = 1 - orange_duty_cycle;
t_dmd_frame_orange  = floor((t_cam_frame)*orange_duty_cycle/dt)*dt-dt; % expo time orange
t_dmd_frame_blue    = floor((t_cam_frame)*blue_duty_cycle/(n_pat-1)/dt)*dt - dt; % expo time blue

daq_channels        = df_app.ni6343.outChannelsConfigData(:,1);
wait_time           = str2num(df_app.WaveformparamsTextArea.Value{1}) * t_cam_frame;
pulseT              = str2num(df_app.WaveformparamsTextArea.Value{2}) * t_cam_frame;
period              = str2num(df_app.WaveformparamsTextArea.Value{3}) * t_cam_frame;
nRpt                = str2num(df_app.WaveformparamsTextArea.Value{4});
t_rec               = t_total;
t_total             = t_total + wait_time;

v_blue              = df_app.BlueAmpVEditField.Value;
v_ir                = df_app.IRAmpVEditField.Value;
v_orange            = df_app.OrangeAmpVEditField.Value;


% Waveform definition start

wp0 = baseWave(dt,t_pulse_duration); % 0-valued constant wave of pulse duration
wp1 = wp0+1; % 1-valued constant wave of pulse duration

w_stim_frame_orange = [wp0 wp0.extend(t_dmd_frame_orange-dt*2)+1 wp0];
w_stim_frame_blue = [extend(wp0,dt*2) wp0.extend(t_dmd_frame_blue-dt*2)+1 wp0];

w_cam_frame = wp1.extend(t_cam_frame);
w_gs_frame = wp1.extend(t_gs_frame);
w_dmd_frame = extend([wp0.extend(dt) wp1.extend(t_dmd_frame_orange) ...
                    repeat(wp1.extend(t_dmd_frame_blue),n_pat-1)],...
                    t_cam_frame);


w_pat = [wp0.extend(wait_time)+1, wp0.extend(dt),... 
        repeat(extend(...
        [wp0.extend(dt) w_stim_frame_orange],...
        t_cam_frame),n_frames)];
for ii=2:n_pat
    w_pat = [w_pat;
        wp0.extend(wait_time), wp0.extend(dt),... 
        repeat(extend(...
        [wp0.extend(dt) wp0.extend(t_dmd_frame_orange) ...
        wp0.extend(t_dmd_frame_blue*(ii-2)) w_stim_frame_blue],...
        t_cam_frame),n_frames)
        ];
end
w_cam = extend([wp0.extend(wait_time) w_cam_frame.repeat(n_frames)],t_total);
w_gs = extend([wp0.extend(wait_time) w_gs_frame.repeat(n_gs_frames)],t_total);  % extra trigger to initiate recording
w_ir = (wp0.extend(t_total)+1) * v_ir;

if period > pulseT
    w_dmd_1st_frame = extend([wp0.extend(dt) wp0.extend(t_dmd_frame_orange) ...
                    repeat(wp1.extend(t_dmd_frame_blue),n_pat-1)],...
                    t_cam_frame);
else
    w_dmd_1st_frame = extend([wp0.extend(dt) wp1.extend(t_dmd_frame_orange) ...
                    repeat(wp1.extend(t_dmd_frame_blue),n_pat-1)],...
                    t_cam_frame);
end
pulseFrames = str2num(df_app.WaveformparamsTextArea.Value{2});
w_dmd_frame_period = w_dmd_frame.repeat(pulseFrames-1);

w_dmd = [wp0.extend(wait_time) wp0.extend(dt)];
for ii = 1:nRpt
    w_dmd = [w_dmd extend([wp1.extend(period - pulseT) w_dmd_1st_frame w_dmd_frame_period], period) ];
end
w_dmd = extend([w_dmd wp1], t_total);
%% waveform definition section
w_orange = flexRampTrainWave(dt,t_rec);
w_orange.tBefore = 0;
w_orange.tRamp = t_rec;
w_orange.period = t_rec;
w_orange = extend([wp0.extend(wait_time)+1 w_orange],t_total);

% intens = [v_orange;v_blue;max(v_blue*0.2,0.2)];
intens = [v_orange;v_blue+eps];

% %----periodic pulse sequence------
w_stim1 = flexRampTrainWave(dt,period * nRpt);
w_stim1.tBefore = period - pulseT; % duration off 
w_stim1.tRamp = pulseT; %duration on
w_stim1.period = period; % duration on
w_stim1 = extend([wp0.extend(wait_time) w_stim1.extend(t_rec)],t_total);

w_stim = [w_orange; w_stim1]*intens;
% %------------end---------------------

%----periodic ramp pulse sequence------
% w_stim1 = flexRampTrainWave(dt,t_total-203.2e-3);
% w_stim1.tBefore = 202.3e-3 - pulseT; % duration off 
% w_stim1.tRamp = pulseT; %duration on
% w_stim1.initialHeight = 0;
% w_stim1.finalHeight = 1;
% w_stim1.offset = 0;
% w_stim1.period = 203.2e-3; % duration on, 160 frames @ 1.27e-3 s expo time
% w_stim1 = extend(w_stim1,t_total);
% 
% w_stim = [w_orange; w_stim1]*intens;
%------------end---------------------

%%

w_stim_all = extend(w_pat,t_total).*w_stim;
w_blue = baseWave(dt,t_total);
w_orange = baseWave(dt,t_total);

w_orange = w_orange + w_stim_all.amplitude(1,:);
for ii=2:n_pat
%     w_blue = w_blue+AOTF_LUT(w_stim_all.amplitude(ii,:));
    w_blue = w_blue + w_stim_all.amplitude(ii,:);
end

w_blue = map(w_blue,@linearize_blue_voltage);
% w_blue_correction = zeros(size(w_blue.amplitude));
% w_blue_correction(w_blue.amplitude<.2 & w_blue.amplitude > 0) = ...
%     .2 - w_blue.amplitude(w_blue.amplitude<.2 & w_blue.amplitude > 0);
% w_blue = w_blue+w_blue_correction;
%% DAQ waveform definition

w_out{1,1} = 'cam';
w_out{1,2} = w_cam;

w_out{2,1} = 'blueIntensity';
w_out{2,2} = w_blue;

w_out{4,1} = 'orangeIntensity';
w_out{4,2} = w_orange;

w_out{3,1} = 'dmd';
w_out{3,2} = w_dmd;

w_out{5,1} = 'grashopper';
w_out{5,2} = w_gs;

w_out{6,1} = 'IR';
w_out{6,2} = w_ir;
% 
% w_out{4,1} = 'blueShutter';
% w_out{4,2} = wp0.extend(t_total)+1;
% 
% w_out{5,1} = 'pololu';
% w_out{5,2} = wp0.extend(t_total)+0;

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

figure(101);clf
plot(allWaves+[0:size(allWaves.amplitude,1)-1]'*2)
legend(daq_channels)
end