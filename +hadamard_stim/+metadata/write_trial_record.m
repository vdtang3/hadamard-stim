function file = write_trial_record(run_folder, record, recipe_hash)
%WRITE_TRIAL_RECORD Write trials/trial_NNNN.json for one trial.
%
%   file = hadamard_stim.metadata.write_trial_record(run_folder, record, recipe_hash)
folder = fullfile(run_folder, "trials");
if ~isfolder(folder)
    mkdir(folder);
end
file = fullfile(folder, sprintf("trial_%04d.json", record.trial));
writelines(hadamard_stim.metadata.canonical_json( ...
    hadamard_stim.metadata.trial_record(record, recipe_hash)), file);
end
