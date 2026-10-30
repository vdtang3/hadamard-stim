function file = write_resume_record(run_folder, recipe_hash, position, comparison, continued, override)
%WRITE_RESUME_RECORD Write resumes/resume_NNN.json for one resume of a run.
%
%   file = hadamard_stim.metadata.write_resume_record(run_folder, recipe_hash, ...
%       position, comparison, continued, override)
%
%   position is where the run continues: struct("next_trial", n) for a
%   connectivity run, struct("next_block", n) for a spontaneous one; its
%   field is copied into the record as it is.
%
%   The recipe is immutable, so what changed when a run was resumed is
%   recorded beside it: when, at which trial, the recorded and current
%   calibration identities (calibration_comparison) and whether the run
%   was continued on changed calibrations by an explicit override.
%   override is what the operator acknowledged to resume (the
%   controller's readiness warnings, the changed calibrations among them,
%   with the note), or [] when nothing needed acknowledging; it is recorded
%   as start_override is in a recipe.
%   Numbered in order; an existing record is never overwritten.
folder = fullfile(run_folder, "resumes");
if ~isfolder(folder)
    mkdir(folder);
end
n = numel(dir(fullfile(folder, "resume_*.json"))) + 1;
file = fullfile(folder, sprintf("resume_%03d.json", n));
while isfile(file)
    n = n + 1;
    file = fullfile(folder, sprintf("resume_%03d.json", n));
end
out.kind = "hadamard_stim_resume";
out.schema_version = "1.0.0";
out.recipe_hash = recipe_hash;
out.resumed_utc = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
if isnumeric(position)
    position = struct("next_trial", position);
end
for name = string(fieldnames(position))'
    out.(name) = position.(name);
end
out.calibration_changed = comparison.changed;
out.continued_with_changed_calibration = continued && comparison.changed;
out.consequence = comparison.consequence;
out.calibrations = struct("blue", comparison.blue, "geometry", comparison.geometry);
if nargin < 6
    override = [];
end
out.operator_override = ~isempty(override);
out.override = override;
hadamard_stim.metadata.write_text(hadamard_stim.metadata.canonical_json(out), file);
end
