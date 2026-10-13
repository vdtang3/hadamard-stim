classdef MockRig < handle
    %MOCKRIG Plays the camera, sample and SpinView for the trace golden.
    %   Every RunSynchronizedAQ call becomes one entry in ACQUISITIONS: a
    %   snapshot of what Yitong's code had configured at that moment (the
    %   DAQ waveform settings, the DMD queue it loaded, the masks, the
    %   motor). Hadamard scans and stimulation movies are synthesised from
    %   REF so the drift-correction and bleaching code have something real
    %   to work on.
    properties
        ref                     % sample image (camera orientation)
        z_center                % motor position at the reference z-stack centre
        drift_xy = zeros(0, 2)  % sample XY drift (px) at the k-th drift scan
        drift_z = zeros(0, 1)   % sample focal drift (motor units) at the k-th drift scan
        full_log_acquisitions = []   % acquisition indices whose ALP calls are kept verbatim
        acquisitions = struct([])
        operator_steps = strings(0, 1)
        n_drift_scans = 0
        n_stim = 0
        last_call = 0
        current_scan = []       % image served by dmd_hadamard_reconstruct
        stack_z = []            % motor positions of the reference z-stack planes
        spinview = strings(0, 1)
    end
    methods
        function acquire(obj, app)
            index = numel(obj.acquisitions) + 1;
            device = app.dmdApp.dmd.device;
            fn = string(app.WaveformFunctionDropDown.Value);
            a = struct();
            a.index = index;
            a.folder = string(app.appendedfoldernameEditField.Value);
            a.waveform_function = fn;
            a.orange_v = app.OrangeAmpVEditField.Value;
            a.blue_v = app.BlueAmpVEditField.Value;
            a.ir_v = app.IRAmpVEditField.Value;
            a.waveform_params = string(app.WaveformparamsTextArea.Value(:)).';
            a.exposure_waveform_ms = app.ExposureTimeMsEditField_waveform.Value;
            a.camera_exposure_ms = app.camApp.ExposureTimeMsEditField.Value;
            a.cam_frames_in = app.camFramesInEditField.Value;
            a.mask_no_total = app.dmdApp.MaskNoTotalEditField.Value;
            a.motor_z = app.motorZ.position;
            a.mask_sequence_size = size(app.dmdApp.mask_sequence);
            a.mask_sequence_sha256 = string(golden_sha256(app.dmdApp.mask_sequence));
            a.mask_sequence_rois_sha256 = string(golden_sha256(cell2mat(app.dmdApp.mask_sequence_rois(:))));
            if isfield(app.dmdApp.function_data, "cIdxAllIt")
                a.c_idx_all_it = app.dmdApp.function_data.cIdxAllIt;
            else
                a.c_idx_all_it = false(0, 0);
            end
            a.queue = obj.queue_snapshot(device, ismember(index, obj.full_log_acquisitions));
            calls = device.calls(obj.last_call+1:end);
            a.n_alp_calls = numel(calls);
            if ismember(index, obj.full_log_acquisitions)
                a.alp_calls = calls;
            else
                a.alp_calls = struct("op", {}, "args", {});
            end
            obj.last_call = numel(device.calls);
            a.spinview = obj.spinview;
            obj.spinview = strings(0, 1);

            if contains(fn, "Hadamard")
                if obj.is_drift_scan(a.folder)
                    obj.n_drift_scans = obj.n_drift_scans + 1;
                    k = obj.n_drift_scans;
                    d = obj.drift_xy(min(k, size(obj.drift_xy, 1)), :);
                    dz = obj.drift_z(min(k, numel(obj.drift_z))) + (app.motorZ.position - obj.z_center);
                    obj.current_scan = synthetic_drift_scan(obj.ref, d(1), d(2), dz);
                    a.kind = "drift_scan";
                    a.sample_drift = [d dz];
                else
                    a.kind = "z_stack_plane";
                    a.sample_drift = [0 0 app.motorZ.position - obj.z_center];
                    obj.stack_z(end+1) = app.motorZ.position;
                end
                a.stim_index = NaN;
            else
                a.kind = "stimulation";
                a.sample_drift = [NaN NaN NaN];
                a.stim_index = obj.n_stim;     % movie = synthetic_movie_mean(ref, orange_v, stim_index)
                obj.n_stim = obj.n_stim + 1;
            end
            obj.acquisitions = [obj.acquisitions; orderfields(a)];
        end
        function tf = is_drift_scan(~, folder)
            tf = contains(folder, "had_trial");
        end
        function im = movie_mean(obj, name)
            % Look up the stimulation movie Yitong's bleaching code opens.
            % Folder names are prefixed "HHMMSS_" by RunSynchronizedAQ; the
            % mock uses "000000_".
            folder = extractAfter(string(name), "000000_");
            match = find([obj.acquisitions.folder] == folder & ...
                [obj.acquisitions.kind] == "stimulation", 1, "last");
            assert(~isempty(match), "No stimulation acquisition named %s", folder);
            a = obj.acquisitions(match);
            im = synthetic_movie_mean(obj.ref, a.orange_v, a.stim_index);
        end
        function note(obj, step)
            obj.operator_steps(end+1) = string(step);
        end
    end
    methods (Static)
        function q = queue_snapshot(device, per_sequence)
            % The DMD sequence queue as loaded. combined_sha256 covers every
            % sequence's bytes in order; per-sequence hashes are kept only
            % for the acquisitions whose ALP calls are logged verbatim.
            seqs = device.sequences;
            n = numel(seqs);
            q.n_sequences = n;
            q.picnum = zeros(1, n);
            q.repeat = zeros(1, n);
            q.sha256 = strings(1, 0);
            all_bytes = cell(1, n);
            for k = 1:n
                q.picnum(k) = seqs(k).picnum;
                if ~isempty(seqs(k).repeat)
                    q.repeat(k) = seqs(k).repeat;
                end
                all_bytes{k} = reshape(seqs(k).data, [], 1);
                if per_sequence
                    q.sha256(k) = string(golden_sha256(seqs(k).data));
                end
            end
            q.combined_sha256 = string(golden_sha256(vertcat(uint8([]), all_bytes{:})));
        end
    end
end
