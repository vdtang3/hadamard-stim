function out = trial_record(record, recipe_hash)
%TRIAL_RECORD One trial as written to trials/trial_NNNN.json.
%
%   out = hadamard_stim.metadata.trial_record(record, recipe_hash)
%
%   record is what hadamard_stim.protocol.run_trial returned. The cells of
%   each pulse or code are listed by number (1-based, matrix row order), the
%   DMD queue by its shape and SHA-256, the waveform by its settings and
%   the SHA-256 of its samples. written_utc is when the trial finished.
out.kind = "hadamard_stim_trial";
out.schema_version = "1.0.0";
out.recipe_hash = recipe_hash;
out.written_utc = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
out.trial = record.trial;
out.trial_kind = record.kind;
out.skipped = record.skipped;
% A record is written only once its trial has finished.
out.status = "completed";
if record.skipped
    out.status = "skipped";
end
out.started_utc = record.started_utc;
out.folder = record.folder;
out.retarget = record.retarget;
out.orange_v = record.orange_v;
out.blue_v = record.blue_v;
out.params = record.params;
out.cells_per_pulse = arrayfun(@(k) find(record.c_idx_all_it(:, k))', ...
    1:size(record.c_idx_all_it, 2), "UniformOutput", false);
out.queue = struct("pictures", record.picnum, "repeats", record.repeats);
out.b0 = record.b0;
out.b1 = record.b1;
out.correction = [];
if ~isempty(record.correction)
    c = record.correction;
    out.correction = struct("cell_shift", c.cell_shift, "z_drift", c.z_drift, ...
        "z_fallback", c.z_fallback, "motor_before", c.motor_before, ...
        "motor_after", c.motor_after, "illum_mask_sha256", c.illum_mask_sha256, ...
        "stim_mask_sha256", c.stim_mask_sha256);
end
out.acquisition = [];
a = record.acquisition;
if ~isempty(a)
    out.acquisition = struct("index", a.index, "folder", a.folder, ...
        "motor_z", a.motor_z, "camera_exposure_ms", a.camera_exposure_ms, ...
        "waveform_function", a.waveform_function, ...
        "waveform_settings", a.waveform_settings, ...
        "waveform_sha256", a.waveform_sha256, "n_frames", a.n_frames);
    if isfield(a, "queue") && ~isempty(a.queue)
        out.queue.sha256 = a.queue.combined_sha256;
    end
end
end
