function ctx = golden_context()
%GOLDEN_CONTEXT Shared state for one generate_yitong_goldens run.
here = string(fileparts(mfilename("fullpath")));
ctx.repo = fileparts(fileparts(here));
ctx.golden = here;
ctx.reference = fullfile(ctx.repo, "tests", "yitong_reference");
ctx.dragonfly = fullfile(ctx.reference, "dragonfly");
ctx.fixtures = fullfile(ctx.repo, "tests", "fixtures");
ctx.original_path = path;
ctx.original_dir = pwd;
ctx.tmp = tempname;
mkdir(ctx.tmp);

ctx.manifest = golden_verify_manifest(ctx.reference);
ctx.paths = golden_load_paths(ctx.repo);

% Yitong's load_sequence_multi is a method file of @vialuxDMDControl. Put a
% byte-identical copy in the mock class folder so his real method runs
% against the recording ALP device.
mock_class = fullfile(ctx.tmp, "@MockVialuxDMD");
mkdir(mock_class);
copyfile(fullfile(here, "templates", "@MockVialuxDMD", "MockVialuxDMD.m"), mock_class);
source = fullfile(ctx.dragonfly, "Hardware", "@vialuxDMDControl", "load_sequence_multi.m");
copyfile(source, mock_class);
assert(golden_file_sha256(fullfile(mock_class, "load_sequence_multi.m")) == ...
    golden_file_sha256(source), "load_sequence_multi copy differs from the frozen reference");

ctx.provenance = struct( ...
    "generator", "tests/golden/generate_yitong_goldens.m", ...
    "generated_utc", string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
    "hadamard_stim_git", golden_git_state(ctx.repo), ...
    "yitong_manifest_sha256", golden_file_sha256(fullfile(ctx.reference, "MANIFEST.tsv")), ...
    "matlab_version", string(version), ...
    "toolboxes", golden_toolbox_versions());
end
