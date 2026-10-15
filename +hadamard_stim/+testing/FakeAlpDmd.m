classdef FakeAlpDmd < hadamard_stim.testing.FakeLuminosDevice
    %FAKEALPDMD A Luminos ALP_DMD, as far as the adapter relies on it.
    %
    %   Mirrors the Luminos rules the adapter depends on (DMD.m, ALP_DMD.m
    %   at f5b464d93): ownership (another owner is refused, release restores
    %   auto_write_stack, Record_Owned_Pattern needs the owner),
    %   Load_Sequence_Queue's checks and that any stack write frees the
    %   queue. What was loaded is kept as hashes in his byte layout, the
    %   same ones SimulatedRig records, never as pattern data.
    properties
        Dimensions = [1024 768]        % [width height]
        pattern_stack = []
        auto_write_stack = true
        pattern_owner (1, 1) string = ""
        invert_output = false
        trigger_channel = "Dev1/port0/line8"
        model = struct("serial", 1, "dmd_type", "fake", "width", 1024, "height", 768)
        serial = 1
        api_version = "fake"
        SupportsQueue = true
        sequence_queue = struct([])
        % Luminos calibration state for one camera (calibration_identity).
        CalibratedCamera = "Teledyne Kinetix"
        ActiveIsPair = true
        refimage = struct("img", zeros(328, 448), "bin", 1)
        ReferenceRoi = [0 0 448 328]   % reference_geometry: [x0 y0 width height]
        % What the adapter loaded, as SimulatedRig records it.
        Stack = struct("sha256", "", "size", [0 0 0])
        Queue = []
        QueueSettings = []
        Displaying = "nothing"         % "stack", "queue" or "dark"
    end

    properties (Access = private)
        saved_auto_write = true
    end

    methods
        function obj = FakeAlpDmd(name)
            obj.name = name;
            obj.LuminosTypes = ["ALP_DMD" "DMD" "Patterning_Device"];
        end

        function sz = Pattern_Canvas_Size(obj)
            sz = [obj.Dimensions(2), obj.Dimensions(1)];
        end

        function tf = Supports_Sequence_Queue(obj)
            tf = obj.SupportsQueue;
        end

        function state = Get_Queue_State(obj)
            % The real one returns the MEX's view of the ALP queue.
            state = struct("n_sequences", numel(obj.sequence_queue), ...
                "displaying", obj.Displaying);
        end

        function previous = Claim_Pattern_Ownership(obj, owner)
            obj.check("Claim_Pattern_Ownership");
            already = obj.pattern_owner == owner;
            if strlength(obj.pattern_owner) > 0 && ~already
                error("DMD:PatternOwnershipHeld", "%s is owned by %s.", obj.name, obj.pattern_owner);
            end
            previous = struct("device", obj.name, "owner", owner, ...
                "auto_write_stack", obj.auto_write_stack, "already_owned", already);
            if ~already
                obj.saved_auto_write = obj.auto_write_stack;
                obj.auto_write_stack = false;
                obj.pattern_owner = owner;
            end
        end

        function Release_Pattern_Ownership(obj, owner)
            obj.check("Release_Pattern_Ownership");
            if strlength(obj.pattern_owner) == 0
                return
            end
            if obj.pattern_owner ~= owner
                warning("DMD:PatternOwnershipNotHeld", "%s is owned by %s.", obj.name, obj.pattern_owner);
                return
            end
            obj.pattern_owner = "";
            obj.auto_write_stack = obj.saved_auto_write;
        end

        function fingerprint = Record_Owned_Pattern(obj, owner)
            obj.check("Record_Owned_Pattern");
            if obj.pattern_owner ~= owner
                error("DMD:PatternOwnershipNotHeld", "%s is not owned by %s.", obj.name, owner);
            end
            fingerprint = obj.Displaying;
        end

        function Write_Stack(obj, mode)
            obj.check("Write_Stack");
            assert(mode == "slave");
            his = permute(obj.pattern_stack, [2 1 3]);
            obj.Stack = struct("sha256", hadamard_stim.metadata.sha256(his), "size", size(his));
            obj.sequence_queue = struct([]);
            obj.Queue = [];
            obj.Displaying = "stack";
        end

        function report = Load_Sequence_Queue(obj, owner, masks, repeats, picture_time_us, trigger_edge)
            obj.check("Load_Sequence_Queue");
            if obj.pattern_owner ~= owner
                error("ALP_DMD:QueueNotOwned", "%s is not owned by %s.", obj.name, owner);
            end
            if numel(repeats) ~= numel(masks)
                error("ALP_DMD:QueueRepeats", "%d repeat counts for %d stacks.", numel(repeats), numel(masks));
            end
            for k = 1:numel(masks)
                if ~isequal([size(masks{k}, 1) size(masks{k}, 2)], obj.Pattern_Canvas_Size())
                    error("ALP_DMD:PatternSize", "Stack %d is not canvas-sized.", k);
                end
            end
            obj.Queue = hadamard_stim.metadata.queue_fingerprint(masks, repeats);
            obj.QueueSettings = struct("picture_time_us", picture_time_us, "trigger_edge", trigger_edge);
            obj.sequence_queue = struct("pictures", obj.Queue.picnum, "repeats", repeats, ...
                "picture_time_us", picture_time_us, "trigger_edge", trigger_edge, ...
                "fingerprint", obj.Queue.combined_sha256);
            obj.Displaying = "queue";
            report = struct("queue_avail", zeros(1, numel(masks)));
        end

        function Reset_Sequence_Queue(obj)
            obj.check("Reset_Sequence_Queue");
            obj.sequence_queue = struct([]);
            obj.Queue = [];
        end

        function Write_Dark(obj)
            obj.check("Write_Dark");
            obj.sequence_queue = struct([]);
            obj.Queue = [];
            obj.Displaying = "dark";
        end

        function identity = calibration_identity(obj, camera)
            calibrated = string(camera) == obj.CalibratedCamera;
            status = "none";
            if calibrated
                status = "session";
            end
            identity = struct("status", status, "has_pair_calibration", calibrated, ...
                "active_transform_is_pair_transform", calibrated && obj.ActiveIsPair, ...
                "pair_transform", struct("A", eye(3)), "measured_utc", 0, "bin", 1, ...
                "roi", obj.ReferenceRoi, "mode", "fake");
        end

        function [bin, roi] = reference_geometry(obj)
            bin = obj.refimage.bin;
            roi = obj.ReferenceRoi;
        end

        function tmask = setPatterningROI(obj, rmask, options)
            % A stand-in warp: the camera mask, transposed onto the canvas.
            arguments
                obj
                rmask
                options.write_when_complete logical = true
            end
            assert(~options.write_when_complete, "The adapter must not project while drawing.");
            canvas = obj.Pattern_Canvas_Size();
            tmask = zeros(canvas);
            m = double(rmask');
            r = min(size(m, 1), canvas(1));
            c = min(size(m, 2), canvas(2));
            tmask(1:r, 1:c) = m(1:r, 1:c);
        end
    end
end
