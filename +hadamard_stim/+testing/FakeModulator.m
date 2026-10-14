classdef FakeModulator < hadamard_stim.testing.FakeLuminosDevice
    %FAKEMODULATOR A Luminos NI_DAQ_Modulator: its calibration state only.
    properties
        port = "Dev1/ao2"
        min = 0
        max = 5
        iscalibrated = []
        calibration_curve = []    % [volts; power], as Calibrate_DAQ_Modulator writes it
    end
    methods
        function obj = FakeModulator(name)
            obj.name = name;
            obj.LuminosTypes = ["NI_DAQ_Modulator" "Modulator_Device"];
        end
    end
end
