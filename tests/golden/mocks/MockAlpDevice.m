classdef MockAlpDevice < handle
    %MOCKALPDEVICE Records every ALP device call Yitong's code makes.
    %   height/width follow Yitong's Vialux MATLAB API, where height = 1024
    %   and width = 768: his saved dmd_mask_sequence arrays are 1024x768, and
    %   dmd_draw_hidden allocates false(device.height, device.width).
    properties
        height = 1024
        width = 768
        sequences = []
        calls = struct("op", {}, "args", {})
        queue_max_avail = 0   % what projinquire reports; not modelled
    end
    methods
        function record(obj, op, varargin)
            obj.calls(end+1) = struct("op", string(op), "args", {varargin});
        end
        function cleanup(obj)
            obj.record("device.cleanup");
            obj.sequences = [];
        end
        function projcontrol(obj, type, value)
            obj.record("device.projcontrol", type, value);
        end
        function start(obj, seq)
            obj.record("device.start", seq.id);
        end
        function [ret, value] = projinquire(obj, type)
            obj.record("device.projinquire", type);
            ret = 0;
            value = obj.queue_max_avail;
        end
        function clear_calls(obj)
            obj.calls = struct("op", {}, "args", {});
        end
    end
end
