function waves = multipat_periodic_pulse_v2_waveform(p)
%MULTIPAT_PERIODIC_PULSE_V2_WAVEFORM DAQ samples of a stimulation trial.
%
%   waves = hadamard_stim.yitong.multipat_periodic_pulse_v2_waveform(p)
%
%   p fields (Yitong's app field in brackets):
%     daq_rate         Hz [ni6343.rateConfigData]
%     channels         DAQ output channel names, rig order [outChannelsConfigData(:,1)]
%     exposure_ms      waveform frame period [ExposureTimeMsEditField_waveform]
%     gs_ms            Grasshopper frame period [GSExposureTimemsEditField]
%     n_frames         camera frames [camFramesInEditField]
%     n_pat            DMD patterns per sequence [dmdApp.MaskNoTotalEditField]
%     params           [wait pulse period nRpt] in frames [WaveformparamsTextArea]
%     blue_v, ir_v, orange_v  [BlueAmpVEditField, IRAmpVEditField, OrangeAmpVEditField]
%     blue_calibration struct(v_blue, blue_intens_c), for linearize_blue_voltage
%
%   waves.channels   p.channels as a string column
%   waves.amplitude  [numel(channels) x samples], his allWaves.amplitude
%
%   2018-2019 Vicente Parot, 2021 Yitong Qi
%   Cohen Lab - Harvard university
%
%   Port of tests/yitong_reference/dragonfly/Waveforms/dragonflyMultiPatWaveform_2color_periodicPulse_v2_yq.m
%   SHA-256 7c590de8c82c0d8800550db38cfd1b0078fe518e8690d5a984ad1cbcfe6725a9
%   Changes: settings come from p instead of the app (params as numbers, not
%   the text his code str2num'd); the blue calibration is an argument of
%   linearize_blue_voltage; helper classes are package qualified; the
%   result is returned as channels + amplitude; no figure.

% Hardware notes:
% Camera (Teledyne Kinetix) in sychronous readout trigger mode:
%   trigger to exposure delay: 3.75 us
%   trigger to exposure delay jitter: 3.75 us

% DMD max switch rate: 22727 Hz
%% parameter definition section

% Collect app params
dt                  =   1/p.daq_rate; % DAQ clock rate
t_pulse_duration    =   dt;  % use dt max precision
t_cam_frame         =  p.exposure_ms*1e-3; % s
t_gs_frame          =  p.gs_ms*1e-3; % s
n_frames            = p.n_frames;
n_gs_frames         = floor(n_frames*t_cam_frame/t_gs_frame);
t_total             = (n_frames)*t_cam_frame;  
n_pat               = p.n_pat; % # of dmd patterns; 
orange_duty_cycle   = 0.8;
blue_duty_cycle     = 1 - orange_duty_cycle;
t_dmd_frame_orange  = floor((t_cam_frame)*orange_duty_cycle/dt)*dt-dt; % expo time orange
t_dmd_frame_blue    = floor((t_cam_frame)*blue_duty_cycle/(n_pat-1)/dt)*dt - dt; % expo time blue

daq_channels        = cellstr(p.channels(:));
wait_time           = p.params(1) * t_cam_frame;
pulseT              = p.params(2) * t_cam_frame;
period              = p.params(3) * t_cam_frame;
nRpt                = p.params(4);
t_rec               = t_total;
t_total             = t_total + wait_time;

v_blue              = p.blue_v;
v_ir                = p.ir_v;
v_orange            = p.orange_v;


% Waveform definition start

wp0 = hadamard_stim.yitong.baseWave(dt,t_pulse_duration); % 0-valued constant wave of pulse duration
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
pulseFrames = p.params(2);
w_dmd_frame_period = w_dmd_frame.repeat(pulseFrames-1);

w_dmd = [wp0.extend(wait_time) wp0.extend(dt)];
for ii = 1:nRpt
    w_dmd = [w_dmd extend([wp1.extend(period - pulseT) w_dmd_1st_frame w_dmd_frame_period], period) ];
end
w_dmd = extend([w_dmd wp1], t_total);
%% waveform definition section
w_orange = hadamard_stim.yitong.flexRampTrainWave(dt,t_rec);
w_orange.tBefore = 0;
w_orange.tRamp = t_rec;
w_orange.period = t_rec;
w_orange = extend([wp0.extend(wait_time)+1 w_orange],t_total);

intens = [v_orange;v_blue+eps];

% %----periodic pulse sequence------
w_stim1 = hadamard_stim.yitong.flexRampTrainWave(dt,period * nRpt);
w_stim1.tBefore = period - pulseT; % duration off 
w_stim1.tRamp = pulseT; %duration on
w_stim1.period = period; % duration on
w_stim1 = extend([wp0.extend(wait_time) w_stim1.extend(t_rec)],t_total);

w_stim = [w_orange; w_stim1]*intens;
% %------------end---------------------

w_stim_all = extend(w_pat,t_total).*w_stim;
w_blue = hadamard_stim.yitong.baseWave(dt,t_total);
w_orange = hadamard_stim.yitong.baseWave(dt,t_total);

w_orange = w_orange + w_stim_all.amplitude(1,:);
for ii=2:n_pat
    w_blue = w_blue + w_stim_all.amplitude(ii,:);
end

w_blue = map(w_blue,@(v) hadamard_stim.yitong.linearize_blue_voltage(v, p.blue_calibration));
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

waves.channels = string(p.channels(:));
waves.amplitude = allWaves.amplitude;
end
