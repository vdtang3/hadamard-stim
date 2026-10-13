function save_checkpoint(run_folder, state, recipe_hash)
%SAVE_CHECKPOINT Write run_checkpoint.mat: what a resumed run needs.
%
%   hadamard_stim.metadata.save_checkpoint(run_folder, state, recipe_hash)
%
%   Only state that changes during the run is kept here; the canonical
%   cells, references and matrix are the recipe's. The file is written to a
%   temporary name and moved into place, so a crash mid-write leaves the
%   previous checkpoint intact.
checkpoint.kind = "hadamard_stim_checkpoint";
checkpoint.schema_version = "1.0.0";
checkpoint.recipe_hash = recipe_hash;
checkpoint.saved_utc = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
for name = ["next_trial" "cnt" "cnt_had" "picked" "sparse_pictures" "orange_v" ...
        "exposure_waveform_ms" "b0" "b1"]
    checkpoint.(name) = state.(name);
end
checkpoint.cells_current = state.cells.current;
checkpoint.cells_corrections = state.cells.corrections;

file = fullfile(run_folder, "run_checkpoint.mat");
partial = file + ".partial";
save(partial, "checkpoint", "-v7.3");
movefile(partial, file, "f");
end
