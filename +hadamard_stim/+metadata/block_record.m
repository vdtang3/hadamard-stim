function out = block_record(record, recipe_hash)
%BLOCK_RECORD One spontaneous block as written to blocks/block_NN.json.
%
%   out = hadamard_stim.metadata.block_record(record, recipe_hash)
%
%   record is what hadamard_stim.protocol.run_spontaneous returned for the
%   block. The waveform is recorded by its settings and the SHA-256 of its
%   description; the streams say what was recorded beside the voltage
%   movie and where. written_utc is when the block finished.
out.kind = "hadamard_stim_block";
out.schema_version = "1.0.0";
out.recipe_hash = recipe_hash;
out.written_utc = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
out.block = record.block;
out.n_blocks = record.n_blocks;
% A record is written only once its block has finished.
out.status = "completed";
out.started_utc = record.started_utc;
out.folder = record.folder;
out.n_frames = record.n_frames;
out.retarget = record.retarget;
out.orange_v = record.orange_v;
out.blue_v = 0;
out.b0 = record.b0;
out.b1 = record.b1;
out.streams = record.streams;
out.correction = [];
if ~isempty(record.correction)
    c = record.correction;
    out.correction = struct("cell_shift", c.cell_shift, "z_drift", c.z_drift, ...
        "z_fallback", c.z_fallback, "motor_before", c.motor_before, ...
        "motor_after", c.motor_after, "illum_mask_sha256", c.illum_mask_sha256);
end
out.acquisition = [];
a = record.acquisition;
if ~isempty(a)
    out.acquisition = struct("index", a.index, "folder", a.folder, ...
        "motor_z", a.motor_z, "camera_exposure_ms", a.camera_exposure_ms, ...
        "waveform_function", a.waveform_function, ...
        "waveform_settings", a.waveform_settings, ...
        "waveform_sha256", a.waveform_sha256, "n_frames", a.n_frames);
    % What the rig recorded beside the movie (LuminosRig): files, lines,
    % clock. The simulated rig records none.
    for name = ["imaging" "behavior" "encoder"]
        if isfield(a, name)
            out.acquisition.(name) = a.(name);
        end
    end
end
end
