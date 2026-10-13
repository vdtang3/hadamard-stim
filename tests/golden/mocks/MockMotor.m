classdef MockMotor < handle
    %MOCKMOTOR Z focus motor: moves are instantaneous and logged.
    properties
        position = 0
        moves = zeros(0, 2)   % [from, to]
    end
    methods
        function obj = MockMotor(position)
            obj.position = position;
        end
        function moveTo(obj, z)
            obj.moves(end+1, :) = [obj.position, z];
            obj.position = z;
        end
        function tf = isMoving(~)
            tf = false;
        end
    end
end
