function [recipe, arrays] = read_recipe(run_folder)
%READ_RECIPE A run's recipe, checked against its own hash.
%
%   [recipe, arrays] = hadamard_stim.metadata.read_recipe(run_folder)
mat = fullfile(run_folder, "run_recipe.mat");
if ~isfile(mat)
    error("hadamard_stim:NoRecipe", "%s holds no run recipe.", run_folder);
end
loaded = load(mat, "recipe", "arrays");
recipe = loaded.recipe;
arrays = loaded.arrays;
if ~hadamard_stim.metadata.verify_recipe_hash(recipe)
    error("hadamard_stim:RecipeAltered", ...
        "The recipe in %s no longer matches its hash; it has been edited.", run_folder);
end
end
