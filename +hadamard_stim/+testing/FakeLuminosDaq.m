classdef FakeLuminosDaq < hadamard_stim.testing.FakeLuminosDevice
    %FAKELUMINOSDAQ A Luminos DAQ: global_props and wfm_data, as the Waveforms tab holds them.
    properties
        global_props_ = struct("rate", 1e5, "total_time", 1, "clock_source", "Internal Dev1", ...
            "trigger_source", "None", "completion_trigger", "None", "daq_master", true)
        wfm_data_ = struct("ao", struct("name", {}, "port", {}, "wavefile", {}, "params", {}, ...
            "operation", {}, "concatTime", {}), "do", struct("name", {}, "port", {}, ...
            "wavefile", {}, "params", {}, "operation", {}, "concatTime", {}), ...
            "ai", struct([]), "di", struct([]), "ctri", struct([]))
        waveforms_built = false
        external_clock_rate = []
    end
    properties (Dependent)
        global_props
        wfm_data
    end
    methods
        function obj = FakeLuminosDaq(name)
            obj.name = name;
            obj.LuminosTypes = "DAQ";
        end
        function gp = Default_Global_Props(~)
            % Luminos DAQ.Default_Global_Props for a Dev1 DAQ with no rig
            % defaults: the Waveforms tab's starting settings.
            gp = struct('rate', 1e5, 'total_time', 3, 'trigger_source', '/Dev1/PFI0', ...
                'completion_trigger', 'None', 'clock_source', 'Internal Dev1', 'daq_master', true);
        end
        function never_configured(obj)
            % As Luminos starts: the Waveforms tab has set nothing.
            obj.global_props_ = [];
            obj.wfm_data_ = [];
        end
        function v = get.global_props(obj), v = obj.global_props_; end
        function v = get.wfm_data(obj), v = obj.wfm_data_; end
        function set.global_props(obj, v)
            obj.check("set_global_props");
            obj.global_props_ = v;
        end
        function set.wfm_data(obj, v)
            obj.check("set_wfm_data");
            obj.wfm_data_ = v;
        end
    end
end
