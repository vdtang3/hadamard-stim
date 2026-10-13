function waves = static_hadamard_waveform(p)
%STATIC_HADAMARD_WAVEFORM DAQ samples of a Hadamard structured-illumination scan.
%
%   waves = hadamard_stim.yitong.static_hadamard_waveform(p)
%
%   p fields (Yitong's app field in brackets):
%     daq_rate      Hz [ni6343.rateConfigData]
%     channels      DAQ output channel names, rig order [outChannelsConfigData(:,1)]
%     exposure_ms   waveform frame period [ExposureTimeMsEditField_waveform]
%     n_pat         DMD patterns loaded [size(dmdApp.mask_sequence, 3)]
%     repeat        repeats of the pattern set [RepeatEditField]
%     n_rows        camera rows, for the rolling-shutter wait [camApp.liveArea(1)]
%     orange_v, blue_v  [OrangeAmpVEditField, BlueAmpVEditField]
%
%   waves.channels   p.channels as a string column
%   waves.amplitude  [numel(channels) x samples], his allWaves.amplitude
%
%   2018-2019 Vicente Parot, 2021 Yitong Qi
%   Cohen Lab - Harvard university
%
%   Port of tests/yitong_reference/dragonfly/Waveforms/dragonflyStaticHadamardWaveform_yq.m
%   SHA-256 325ad0a14f7f7651473795dc8b0e62eef389eb967814fc0133833e70a3aa8bd0
%   Changes: settings come from p instead of the app; helper classes are
%   package qualified; the result is returned as channels + amplitude; no
%   figure.

% Camera in sychronous readout trigger mode
%   trigger to exposure delay: 165.58 us
%   trigger to exposure delay jitter: 9.74 us


% Collect app params
dt                  =   1/p.daq_rate; % DAQ clock rate
t_pulse_duration    =   dt;  % use dt max precision
t_cam_frame_daq     =  p.exposure_ms*1e-3; % s
n_pat               = p.n_pat; % # of dmd patterns; 
n_rpt               = p.repeat;
n_frames            = n_pat * n_rpt;
t_total             = (n_frames)*t_cam_frame_daq + 10e-3;  
t_dmd_frame_illum  = floor((t_cam_frame_daq)/dt)*dt; % expo time orange

v_blue              = p.blue_v;
v_orange            = p.orange_v;


daq_channels        = cellstr(p.channels(:));

nRows               = p.n_rows;
t_rollingShutter    = 3.75e-6 * nRows; %s rolling shutter wait time
% Waveform definition start


wp0 = hadamard_stim.yitong.baseWave(dt,t_pulse_duration); % 0-valued constant wave of pulse duration
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

w_blue = w_illum * v_blue;
w_orange = w_illum * v_orange;

%%

w_out{1,1} = 'cam';
w_out{1,2} = w_cam;

w_out{4,1} = 'blueIntensity';
w_out{4,2} = w_blue;

w_out{2,1} = 'orangeIntensity';
w_out{2,2} = w_orange;

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

waves.channels = string(p.channels(:));
waves.amplitude = allWaves.amplitude;
end
