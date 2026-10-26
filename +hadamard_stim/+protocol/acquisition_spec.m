function spec = acquisition_spec(kind, folder, waveform, options)
%ACQUISITION_SPEC What one synchronized acquisition is asked to do.
%
%   spec = hadamard_stim.protocol.acquisition_spec(kind, folder, waveform, ...)
%
%   kind      "z_stack_plane", "drift_scan", "stimulation",
%             "reference_scan" (acquire_reference_image) or "spontaneous"
%             (one block of run_spontaneous) or "calibration_scan"
%             (acquire_calibration_scans, on a slide)
%   folder    his folder name for it (the rig prefixes a time stamp)
%   waveform  struct from scan_waveform, stimulation_waveform (dense:
%             amplitude) or spontaneous_waveform (repeated: rows)
%   streams   the optional companions to record (acquisition_streams):
%             face_camera, wheel_encoder; both off unless given
%
%   Every spec has the same fields, so acquisitions can be kept in one
%   struct array. The hardware adapter reads the waveform, the camera
%   fields and the streams; everything else is for the record.
arguments
    kind (1, 1) string {mustBeMember(kind, ["z_stack_plane" "drift_scan" "stimulation" "reference_scan" "spontaneous" "calibration_scan"])}
    folder (1, 1) string
    waveform struct
    options.trial (1, 1) double = NaN
    options.camera_exposure_ms (1, 1) double
    options.c_idx_all_it logical = false(0, 0)
    options.streams struct = struct("face_camera", false, "wheel_encoder", false)
end
spec.kind = kind;
spec.folder = folder;
spec.trial = options.trial;
spec.waveform_function = waveform.function_name;
spec.waveform_settings = waveform.settings;
spec.waveform = waveform;
spec.waveform_sha256 = waveform.sha256;   % of the samples (dense) or of the description (repeated)
spec.camera_exposure_ms = options.camera_exposure_ms;
spec.waveform_period_ms = waveform.settings.exposure_ms;
spec.n_frames = waveform.n_camera_frames;
spec.orange_v = waveform.settings.orange_v;
spec.blue_v = waveform.settings.blue_v;
spec.c_idx_all_it = options.c_idx_all_it;
spec.streams = options.streams;
end
