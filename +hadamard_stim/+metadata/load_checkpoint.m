function state = load_checkpoint(run_folder)
%LOAD_CHECKPOINT Rebuild a run's state from its recipe and checkpoint.
%
%   state = hadamard_stim.metadata.load_checkpoint(run_folder)
%
%   Refuses when the checkpoint was written for a different recipe, or the
%   recipe was edited: resuming must continue the run that was started.
[recipe, arrays] = hadamard_stim.metadata.read_recipe(run_folder);
file = fullfile(run_folder, "run_checkpoint.mat");
if ~isfile(file)
    error("hadamard_stim:NoCheckpoint", "%s has no checkpoint to resume from.", run_folder);
end
checkpoint = load(file, "checkpoint").checkpoint;
if checkpoint.recipe_hash ~= recipe.recipe_hash
    error("hadamard_stim:CheckpointMismatch", ...
        "The checkpoint in %s belongs to recipe %s, not this run's %s.", ...
        run_folder, checkpoint.recipe_hash, recipe.recipe_hash);
end

cfg = recipe.config;
if hadamard_stim.metadata.session_mode(cfg) == "spontaneous"
    state = hadamard_stim.protocol.new_spontaneous_state(cfg, arrays.canonical, arrays.reference);
else
    state = hadamard_stim.protocol.new_run_state(cfg, arrays.canonical, arrays.reference);
    if ~isequal(state.had_mat, arrays.had_mat)
        error("hadamard_stim:MatrixMismatch", ...
            "The stimulation matrix no longer regenerates the recipe's; refusing to resume.");
    end
end
for name = hadamard_stim.metadata.checkpoint_fields(state)
    state.(name) = checkpoint.(name);
end
state.cells.current = checkpoint.cells_current;
state.cells.corrections = checkpoint.cells_corrections;
end
