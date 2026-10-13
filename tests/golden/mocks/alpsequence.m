classdef alpsequence < handle
    %ALPSEQUENCE Recording stand-in for the Vialux MATLAB API class of the
    %same name. Constructing one registers it with the device, as the real
    %API does (load_sequence_multi reads device.sequences right after).
    properties
        device
        id
        picnum = 0
        repeat = []
        picture_time = []
        illuminate_time = []
        data = []          % uint8 bytes exactly as passed to put()
    end
    methods
        function obj = alpsequence(device)
            obj.device = device;
            if isempty(device.sequences)
                device.sequences = obj;
            else
                device.sequences(end+1) = obj;
            end
            obj.id = numel(device.sequences);
            device.record("alpsequence", obj.id);
        end
        function alloc(obj, bitplanes, picnum)
            obj.picnum = picnum;
            obj.device.record("seq.alloc", obj.id, bitplanes, picnum);
        end
        function control(obj, type, value)
            api = alp_api_constants();
            if type == api.SEQ_REPEAT
                obj.repeat = value;
            end
            obj.device.record("seq.control", obj.id, type, value);
        end
        function timing(obj, illuminate, picture, synch_delay, synch_width, trigger_in_delay)
            obj.illuminate_time = illuminate;
            obj.picture_time = picture;
            obj.device.record("seq.timing", obj.id, illuminate, picture, ...
                synch_delay, synch_width, trigger_in_delay);
        end
        function [ret, value] = inquire(obj, type)
            % Echo what timing() set. The real controller derives
            % ILLUMINATE_TIME from PICTURE_TIME; only the log matters here.
            api = alp_api_constants();
            ret = 0;
            switch type
                case api.PICTURE_TIME,    value = obj.picture_time;
                case api.ILLUMINATE_TIME, value = obj.illuminate_time;
                otherwise,                value = 0;
            end
            obj.device.record("seq.inquire", obj.id, type);
        end
        function put(obj, offset, picnum, data)
            obj.data = data;
            obj.device.record("seq.put", obj.id, offset, picnum, ...
                size(data), class(data), golden_sha256(data));
        end
    end
end
