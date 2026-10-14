function spec = acquisition_spec(kind, folder, waveform, options)
%ACQUISITION_SPEC What one synchronized acquisition is asked to do.
%
%   spec = hadamard_stim.protocol.acquisition_spec(kind, folder, waveform, ...)
%
%   kind      "z_stack_plane", "drift_scan" or "stimulation"
%   folder    his folder name for it (the rig prefixes a time stamp)
%   waveform  struct from scan_waveform or stimulation_waveform
%
%   Every spec has the same fields, so acquisitions can be kept in one
%   struct array. The hardware adapter reads waveform.amplitude and the
%   camera fields; everything else is for the record.
arguments
    kind (1, 1) string {mustBeMember(kind, ["z_stack_plane" "drift_scan" "stimulation"])}
    folder (1, 1) string
    waveform struct
    options.trial (1, 1) double = NaN
    options.camera_exposure_ms (1, 1) double
    options.c_idx_all_it logical = false(0, 0)
end
spec.kind = kind;
spec.folder = folder;
spec.trial = options.trial;
spec.waveform_function = waveform.function_name;
spec.waveform_settings = waveform.settings;
spec.waveform = waveform;
spec.waveform_sha256 = waveform.sha256;   % of the samples (amplitude), as doubles
spec.camera_exposure_ms = options.camera_exposure_ms;
spec.waveform_period_ms = waveform.settings.exposure_ms;
spec.n_frames = waveform.n_camera_frames;
spec.orange_v = waveform.settings.orange_v;
spec.blue_v = waveform.settings.blue_v;
spec.c_idx_all_it = options.c_idx_all_it;
end
