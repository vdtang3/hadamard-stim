classdef FakeLuminosApp < handle
    %FAKELUMINOSAPP The parts of Rig_Control_App the adapter touches (make_fake_luminos).
    properties
        rigName = "Firefly"
        User = struct("name", "test")
        Devices = {}
        datafolder = ""
        expfolder = ""
        acquisition_active = false
        exp_complete = true
        round_complete = true
        last_run_aborted = false
        Log = strings(0, 1)              % device operations, in order
        Acquisitions = struct([])        % what each acquisition played (fake_luminos_acquisition)
        FailOnAcquisition = []           % acquisition number that throws
        LeaveRunning = false             % the acquisition never completes
        AbortOnAcquisition = []          % acquisition number Luminos reports aborted
    end
    methods
        function found = getDevice(obj, type, options)
            arguments
                obj
                type (1, 1) string
                options.name string = string.empty
                options.displayWarning = true
            end
            found = [];
            for k = 1:numel(obj.Devices)
                d = obj.Devices{k};
                if ismember(type, d.LuminosTypes) && (isempty(options.name) || d.name == options.name)
                    found = [found d]; %#ok<AGROW>
                end
            end
        end
        function abortAcquisition(obj)
            obj.Log(end+1, 1) = "app:abortAcquisition";
            obj.acquisition_active = false;
            obj.exp_complete = true;
            obj.round_complete = true;
            obj.last_run_aborted = true;
        end
    end
end
