classdef FakeModulator < hadamard_stim.testing.FakeLuminosDevice
    %FAKEMODULATOR A Luminos NI_DAQ_Modulator: its calibration state only.
    properties
        port = "Dev1/ao2"
        min = 0
        max = 5
        iscalibrated = []
        calibration_curve = []    % [command; output], as Luminos records it
        calibration_info = struct([])   % what Set_Calibration recorded with it
    end
    methods
        function obj = FakeModulator(name)
            obj.name = name;
            obj.LuminosTypes = ["NI_DAQ_Modulator" "Modulator_Device"];
        end

        function Set_Calibration(obj, curve, info, options)
            % As Luminos's Modulator_Device.Set_Calibration (no saving here).
            arguments
                obj
                curve (2, :) double
                info (1, 1) struct
                options.persist (1, 1) logical = true %#ok<INUSA>
            end
            obj.check("Set_Calibration");
            obj.calibration_curve = curve;
            obj.calibration_info = info;
        end
    end
end
