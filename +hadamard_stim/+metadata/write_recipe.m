function write_recipe(run_folder, recipe, arrays)
%WRITE_RECIPE Write run_recipe.json and run_recipe.mat. Never overwrites.
%
%   hadamard_stim.metadata.write_recipe(run_folder, recipe, arrays)
%
%   The recipe is the run's immutable record, so a folder that already has
%   one is refused rather than replaced: a second run needs its own folder,
%   and a resumed run reads the recipe it was started with.
json = fullfile(run_folder, "run_recipe.json");
mat = fullfile(run_folder, "run_recipe.mat");
if isfile(json) || isfile(mat)
    error("hadamard_stim:RecipeExists", ...
        "%s already holds a run recipe. Start a new run in a new folder, or resume this one.", ...
        run_folder);
end
if ~isfolder(run_folder)
    mkdir(run_folder);
end
save(mat, "recipe", "arrays", "-v7.3");
writelines(hadamard_stim.metadata.canonical_json(recipe), json);
end
