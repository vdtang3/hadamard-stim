function golden_use_path(ctx, shim_groups, options)
%GOLDEN_USE_PATH Reset the path to Yitong's frozen code plus the given shims.
%
%   The frozen folders are added in the order Yitong's dragonfly_initialize
%   used (each addpath(genpath(...)) prepends, so the last one added wins a
%   name clash). Shims go on top, so they shadow his hardware calls.
arguments
    ctx
    shim_groups (1,:) string = strings(1, 0)
    options.lab_image_processing (1,1) logical = false
end
path(ctx.original_path);
for folder = ["Hardware" "Settings" "Waveforms" "Hadamard" "Utilities" "dmd_control"]
    addpath(genpath(fullfile(ctx.dragonfly, folder)));
end
addpath(fullfile(ctx.dragonfly, "Auto Scripts"));
lab = fullfile(ctx.reference, "external", "lab");
addpath(fullfile(lab, "General Matlab", "VIALUX control", "Patterns"), "-end");
addpath(fullfile(lab, "Image Processing", "NeuroSegmentation"), "-end");
if options.lab_image_processing
    % The vm movie class, used only by Yitong's reconstruction code.
    addpath(fullfile(ctx.paths.lab_code_root, "Image Processing"), "-end");
end
addpath(ctx.golden, fullfile(ctx.golden, "mocks"), fullfile(ctx.repo, "tests", "support"), ctx.tmp);
addpath(fullfile(ctx.golden, "shims", "common"));
for group = shim_groups
    addpath(fullfile(ctx.golden, "shims", group));
end
end
