function ok = verify_recipe_hash(recipe)
%VERIFY_RECIPE_HASH Whether a recipe still hashes to the hash it carries.
%
%   ok = hadamard_stim.metadata.verify_recipe_hash(recipe)
claimed = recipe.recipe_hash;
recipe = rmfield(recipe, "recipe_hash");
text = hadamard_stim.metadata.canonical_json(recipe);
ok = hadamard_stim.metadata.sha256(unicode2native(char(text), "UTF-8")) == claimed;
end
