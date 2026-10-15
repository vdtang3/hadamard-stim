classdef SimulatedRig < handle
    %SIMULATEDRIG Firefly's hardware, simulated, for running the protocol off-rig.
    %
    %   rig = hadamard_stim.testing.SimulatedRig(world, z_start)
    %
    %   Implements the hardware interface the protocol uses (see
    %   hadamard_stim.protocol.run_protocol), the same one the Luminos adapter
    %   implements on the rig:
    %
    %     z = hw.motor_position()
    %     hw.motor_move_to(z)
    %     hw.dmd_load_stack(masks)            scan patterns, canvas [W x L x n]
    %     hw.dmd_load_queue(sequences, repeats)
    %                                         sequences{k} canvas [W x L x n_k]
    %     hw.dmd_show_mask(mask)              one static picture, canvas [W x L]
    %     acq = hw.acquire(spec)              one synchronized acquisition
    %     im = hw.movie_mean(acq, frames)     mean of those frames of its movie
    %     report = hw.begin(cfg)              always ready (see readiness)
    %     report = hw.release()               nothing to restore
    %     hw.abort()                          later operations refuse until begin
    %
    %   Every acquisition is recorded in ACQUISITIONS with what was configured
    %   at that moment, in the fields the golden trace records, so a whole run
    %   can be compared with Yitong's. The DMD is recorded as he loaded it:
    %   queue bytes are packed with his alp_logical_to_btd and hashed in the
    %   layout his load_sequence_multi handed to AlpSeqPut.
    %
    %   What the camera sees comes from WORLD, a struct of function handles:
    %     world.scan_image(rig, acq)          reconstructed scan image
    %     world.movie_mean(rig, acq, frames)  stimulation movie mean
    %   The parity tests give it the synthetic sample the goldens used.

    properties
        world
        position = 0
        moves = zeros(0, 2)          % [from, to]
        acquisitions = struct([])
        stack = struct("sha256", "", "size", [0 0 0])
        queue = []
        n_drift_scans = 0
        n_stim = 0
        % Called with (operation_name) before each operation; tests use it
        % to inject failures.
        before_operation = []
        % What begin() reports; tests set it to refuse a configuration.
        readiness = struct("ok", true, "failures", strings(0, 1))
        sessions = 0                 % begin() calls
        releases = 0                 % release() calls
        aborted = false              % abort() called since the last begin()
    end

    methods
        function obj = SimulatedRig(world, z_start)
            obj.world = world;
            obj.position = z_start;
        end

        function z = motor_position(obj)
            z = obj.position;
        end

        function motor_move_to(obj, z)
            obj.check("motor_move_to");
            obj.moves(end+1, :) = [obj.position, z];
            obj.position = z;
        end

        function dmd_load_stack(obj, masks)
            obj.check("dmd_load_stack");
            his = permute(masks, [2 1 3]);
            obj.stack = struct("sha256", hadamard_stim.metadata.sha256(his), "size", size(his));
            obj.queue = [];
        end

        function dmd_load_queue(obj, sequences, repeats)
            obj.check("dmd_load_queue");
            obj.queue = hadamard_stim.metadata.queue_fingerprint(sequences, repeats);
            obj.stack = struct("sha256", "", "size", [0 0 0]);
        end

        function dmd_show_mask(obj, mask)
            obj.check("dmd_show_mask");
            his = permute(mask, [2 1 3]);
            obj.stack = struct("sha256", hadamard_stim.metadata.sha256(his), "size", size(his, [1 2 3]));
            obj.queue = [];
        end

        function acq = acquire(obj, spec)
            obj.check("acquire");
            acq = spec;
            acq.index = numel(obj.acquisitions) + 1;
            acq.motor_z = obj.position;
            acq.dmd_stack = obj.stack;
            acq.queue = obj.queue;
            switch spec.kind
                case "drift_scan"
                    obj.n_drift_scans = obj.n_drift_scans + 1;
                    acq.drift_scan_number = obj.n_drift_scans;
                    acq.stim_index = NaN;
                case {"z_stack_plane" "reference_scan"}
                    acq.drift_scan_number = NaN;
                    acq.stim_index = NaN;
                case "stimulation"
                    acq.drift_scan_number = NaN;
                    acq.stim_index = obj.n_stim;
                    obj.n_stim = obj.n_stim + 1;
                case "spontaneous"
                    acq.drift_scan_number = NaN;
                    acq.stim_index = NaN;
            end
            if ~ismember(spec.kind, ["stimulation" "spontaneous"])
                acq.image = obj.world.scan_image(obj, acq);
            end
            stored = rmfield(acq, intersect(fieldnames(acq), ["waveform" "image"]));
            if isempty(obj.acquisitions)
                obj.acquisitions = stored;
            else
                obj.acquisitions(end+1, 1) = stored;
            end
        end

        function report = begin(obj, cfg) %#ok<INUSD>
            obj.check("begin");
            obj.aborted = false;
            obj.sessions = obj.sessions + 1;
            report = obj.readiness;
        end

        function report = release(obj)
            % Nothing to restore off the rig; counted so tests can see it ran.
            obj.releases = obj.releases + 1;
            report = struct("steps", "simulated", "errors", strings(0, 1), "ok", true);
        end

        function abort(obj)
            obj.aborted = true;
        end

        function im = movie_mean(obj, acq, frames)
            obj.check("movie_mean");
            im = obj.world.movie_mean(obj, acq, frames);
        end
    end

    methods (Access = private)
        function check(obj, operation)
            if obj.aborted && operation ~= "begin"
                error("hadamard_stim:Aborted", "The run was aborted before %s.", operation);
            end
            if ~isempty(obj.before_operation)
                obj.before_operation(operation);
            end
        end
    end
end
