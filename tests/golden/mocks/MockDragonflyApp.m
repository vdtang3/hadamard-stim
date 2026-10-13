classdef MockDragonflyApp < handle
    %MOCKDRAGONFLYAPP The dragonflyApp fields read by Yitong's protocol
    %script, drift correction and waveform functions. RunSynchronizedAQ
    %records a snapshot of the acquisition settings in the rig instead of
    %acquiring.
    properties
        rig
        dmdApp
        motorZ
        ni6343
        camApp
        OrangeAmpVEditField = struct("Value", 0)
        BlueAmpVEditField = struct("Value", 0)
        IRAmpVEditField = struct("Value", 0)
        WaveformparamsTextArea = struct("Value", {{''; ''; ''; ''}})
        appendedfoldernameEditField = struct("Value", '')
        WaveformFunctionDropDown = struct("Value", '', "Items", {{}})
        ExposureTimeMsEditField_waveform = struct("Value", 0)
        GSExposureTimemsEditField = struct("Value", 0)
        camFramesInEditField = struct("Value", 0)
        RepeatEditField = struct("Value", 0)
    end
    methods
        function obj = MockDragonflyApp(rig, dmdApp, motorZ)
            obj.rig = rig;
            obj.dmdApp = dmdApp;
            obj.motorZ = motorZ;
        end
        function RunSynchronizedAQ(obj, ~)
            obj.rig.acquire(obj);
        end
    end
end
