classdef MockVialuxDMD < handle
    %MOCKVIALUXDMD Stand-in for Yitong's vialuxDMDControl.
    %   The generator copies Yitong's frozen load_sequence_multi.m, byte for
    %   byte, into this class folder, so the sequence-queue calls recorded by
    %   MockAlpDevice come from his real method.
    properties
        api
        device
        seq
    end
    methods
        function obj = MockVialuxDMD(device)
            obj.api = alp_api_constants();
            obj.device = device;
        end
        function project(obj, pattern)
            obj.device.record("dmd.project", size(pattern), golden_sha256(pattern));
        end
        function load_sequence(obj, alp_patterns)
            obj.device.record("dmd.load_sequence", size(alp_patterns), golden_sha256(alp_patterns));
        end
    end
end
