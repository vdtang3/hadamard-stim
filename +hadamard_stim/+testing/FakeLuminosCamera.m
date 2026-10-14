classdef FakeLuminosCamera < hadamard_stim.testing.FakeLuminosDevice
    %FAKELUMINOSCAMERA A Luminos Camera: the settings an acquisition uses.
    properties
        type = 3
        cam_id = ""
        trigger = ""
        bin = 1
        compression_method = "None"
        ROI = [0 448 0 328]            % [left width top height]
        frametrigger_source_ = "Off"
        frames_requested_ = 1
        acquisition_exposuretime_ = 0.15
    end
    properties (Dependent)
        frametrigger_source
        frames_requested
        acquisition_exposuretime
    end
    methods
        function obj = FakeLuminosCamera(name)
            obj.name = name;
            obj.LuminosTypes = "Camera";
        end
        function roi = getROIForAcquisition(obj)
            roi = obj.ROI;
        end
        function v = get.frametrigger_source(obj), v = obj.frametrigger_source_; end
        function v = get.frames_requested(obj), v = obj.frames_requested_; end
        function v = get.acquisition_exposuretime(obj), v = obj.acquisition_exposuretime_; end
        function set.frametrigger_source(obj, v)
            obj.check("set_frametrigger_source");
            obj.frametrigger_source_ = string(v);
        end
        function set.frames_requested(obj, v)
            obj.check("set_frames_requested");
            obj.frames_requested_ = v;
        end
        function set.acquisition_exposuretime(obj, v)
            obj.check("set_acquisition_exposuretime");
            obj.acquisition_exposuretime_ = v;
        end
    end
end
