classdef FakeNewportStage < hadamard_stim.testing.FakeLuminosDevice
    %FAKENEWPORTSTAGE A Luminos Newport_Motor_Controller (mm, blocking moves).
    properties
        position_units = "mm"
        pos = 6
    end
    methods
        function obj = FakeNewportStage(name, z)
            obj.name = name;
            obj.pos = z;
            obj.LuminosTypes = ["Newport_Motor_Controller" "Linear1D_Controller" "Motion_Controller"];
        end
        function z = Get_Current_Position(obj)
            z = obj.pos;
        end
        function success = Move_To_Position(obj, z)
            obj.check("Move_To_Position");
            obj.pos = z;
            success = 0;
        end
    end
end
