function paths = golden_load_paths(repo)
%GOLDEN_LOAD_PATHS Read config/paths.local.m.
file = fullfile(repo, "config", "paths.local.m");
assert(isfile(file), "Missing %s. Copy config/paths.example.m to " + ...
    "config/paths.local.m and set the paths for this machine.", file);
hadamard_stim_paths = struct();
% run() rejects a file name containing a second dot, so evaluate the text.
eval(fileread(file));
paths = hadamard_stim_paths;
end
