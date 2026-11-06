classdef FakeConfigData < handle
    %FAKECONFIGDATA AdditionalConfigData: a struct "data" saved to filePath on every set.
    properties
        filePath string
        data = struct()
    end
    methods
        function obj = FakeConfigData(file)
            obj.filePath = string(file);
            obj.save_();
        end
        function v = get(obj, key)
            v = [];
            if isfield(obj.data, char(key)), v = obj.data.(char(key)); end
        end
        function set(obj, key, value)
            obj.data.(char(key)) = value;
            obj.save_();
        end
        function save_(obj)
            data = obj.data; %#ok<PROPLC,NASGU>
            save(obj.filePath, "data");
        end
    end
end
