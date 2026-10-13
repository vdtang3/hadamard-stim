function load_sequence_multi(obj,alp_patterns,n_rpts)

nSeqs = length(alp_patterns);

obj.device.cleanup();

% obj.device.free;

% obj.init

ModeStringSyncOrUninterrupted = 'uninterrupted';
% setup_load_start_sequence
%%
% obj.device.stop;
% obj.device.halt;

BitPlanes = 1;
PicOffset = 0;
PicNum = cellfun(@(x) size(x,3),alp_patterns);

% PictureTimeSpacing = ceil(ExposureMilliseconds*128/5); % [us]
TriggerInDelay = obj.api.DEFAULT; % -30 + ceil(9.75*ceil(CameraLines/2)); % [us] only relevant in slave mode
%             PictureTimeExcess = 25; % [us] % must be > 2 us per instructions. not a dmd parameter, for parameter calculation only

TriggerSynchDelay = obj.api.DEFAULT; % [us] only relevant in master mode
TriggerSynchPulseWidth = obj.api.DEFAULT; % [us]
PictureTime = 44; % api.DEFAULT; % floor(ExposureMilliseconds*1000/1.023)-PictureTimeSpacing; % [us]
IlluminateTime = obj.api.DEFAULT; % PictureTime-TriggerInDelay-PictureTimeExcess-TriggerSynchDelay; % [us]
%             fprintf('PictureTime: %d us\nIlluminateTime: %d us\n',PictureTime,IlluminateTime)

obj.device.projcontrol(obj.api.PROJ_MODE,obj.api.SLAVE_VD);
obj.device.projcontrol(obj.api.PROJ_QUEUE_MODE,obj.api.PROJ_SEQUENCE_QUEUE);

for ii = 1:nSeqs
    alpsequence(obj.device);
    obj.seq = obj.device.sequences;
    obj.seq(ii).alloc(BitPlanes,PicNum(ii));
    
    obj.seq(ii).control(obj.api.DATA_FORMAT,obj.api.DATA_BINARY_TOPDOWN);
    obj.seq(ii).control(obj.api.SEQ_REPEAT,n_rpts(ii));
    switch ModeStringSyncOrUninterrupted
        case 'uninterrupted'
            obj.seq(ii).control(obj.api.BIN_MODE,obj.api.BIN_UNINTERRUPTED); % to display the pattern
            % until next trigger, even in slave mode, regardless of IlluminateTime.
            % Watch for bleedthrough into the rolling shutter due to delayed
            % responsivity.  
        case 'sync' % do nothing
        otherwise % do nothing
    end
    obj.seq(ii).timing(IlluminateTime, PictureTime, TriggerSynchDelay, TriggerSynchPulseWidth, TriggerInDelay);
    [~, PictureTime] = obj.seq(ii).inquire(obj.api.PICTURE_TIME);
    [~, IlluminateTime] = obj.seq(ii).inquire(obj.api.ILLUMINATE_TIME);
    fprintf('PictureTime: %d us\nIlluminateTime: %d us\n',PictureTime,IlluminateTime)
    fprintf('loading %d patterns ... \n',PicNum(ii))
    obj.seq(ii).put(PicOffset,PicNum(ii),permute(alp_patterns{ii},[3 1 2]));
    obj.device.start(obj.seq(ii));
    [~, queueMaxAvail] = obj.device.projinquire(obj.api.PROJ_QUEUE_MAX_AVAIL);
    [~, queueAvail] = obj.device.projinquire(obj.api.PROJ_QUEUE_AVAIL);
    fprintf('queueMaxAvail: %d \nqueueAvail: %d \n',[queueMaxAvail,queueAvail])
end

fprintf([8 'done\n'])
end