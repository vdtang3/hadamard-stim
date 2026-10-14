classdef FakeLuminosDevice < handle
    %FAKELUMINOSDEVICE Common part of the fake Luminos devices (make_fake_luminos).
    %
    %   Every fake logs the operations it is asked for into the app's Log,
    %   so tests can check their order, and fails on request: an operation
    %   named in FailOn throws "fake:Injected" instead of happening, once
    %   for each time it is named.
    properties
        name (1, 1) string = ""
        LuminosTypes (1, :) string = strings(1, 0)   % what getDevice matches
        FailOn (1, :) string = strings(1, 0)
        App = []
    end

    methods
        function check(obj, operation)
            if ~isempty(obj.App)
                obj.App.Log(end+1, 1) = obj.name + ":" + operation;
            end
            if ismember(operation, obj.FailOn)
                % Once, like a transient fault: what cleanup does next works.
                obj.FailOn(find(obj.FailOn == operation, 1)) = [];
                error("fake:Injected", "Injected failure: %s %s.", obj.name, operation);
            end
        end
    end
end
