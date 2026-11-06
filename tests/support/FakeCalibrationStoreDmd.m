classdef FakeCalibrationStoreDmd < handle
    %FAKECALIBRATIONSTOREDMD Patterning_Device's per-camera calibration store, as the migration tool uses it.
    %
    %   Entries live in additionalConfigData "calibrations", keyed by
    %   matlab.lang.makeValidName(camera) (Patterning_Device.calibration_key);
    %   use_calibration_camera loads an entry into tform; calibration_identity
    %   compares tform with the entry. The config is also written to a real
    %   .mat file, so the tool's backup can be checked.
    properties
        name = "DMD (shared)"
        tform = []
        calibration_camera = ""
        additionalConfigData
    end
    methods
        function obj = FakeCalibrationStoreDmd(file)
            obj.additionalConfigData = FakeConfigData(file);
        end
        function entry = get_calibration_entry(obj, camera)
            entry = [];
            store = obj.calibration_store();
            key = matlab.lang.makeValidName(char(strtrim(string(camera))));
            if isfield(store, key)
                entry = store.(key);
            end
        end
        function store = calibration_store(obj)
            store = obj.additionalConfigData.get("calibrations");
            if isempty(store), store = struct(); end
        end
        function status = use_calibration_camera(obj, camera)
            obj.calibration_camera = string(camera);
            entry = obj.get_calibration_entry(camera);
            status = "none";
            if ~isempty(entry)
                obj.tform = entry.tform;
                status = "file";
            end
        end
        function identity = calibration_identity(obj, camera)
            identity = struct("has_pair_calibration", false, ...
                "active_transform_is_pair_transform", false, "pair_transform", []);
            entry = obj.get_calibration_entry(camera);
            if isempty(entry), return, end
            identity.has_pair_calibration = true;
            identity.pair_transform = entry.tform;
            identity.active_transform_is_pair_transform = ~isempty(obj.tform) && ...
                isequal(obj.tform.A, entry.tform.A);
        end
    end
end
