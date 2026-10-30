function file = write_block_record(run_folder, record, recipe_hash)
%WRITE_BLOCK_RECORD Write blocks/block_NN.json for one spontaneous block.
%
%   file = hadamard_stim.metadata.write_block_record(run_folder, record, recipe_hash)
folder = fullfile(run_folder, "blocks");
if ~isfolder(folder)
    mkdir(folder);
end
file = fullfile(folder, sprintf("block_%02d.json", record.block));
hadamard_stim.metadata.write_text(hadamard_stim.metadata.canonical_json( ...
    hadamard_stim.metadata.block_record(record, recipe_hash)), file);
end
