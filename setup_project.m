function setup_project()
%SETUP_PROJECT Put the hadamard-stim package on the MATLAB path.
%
%   Only the repository root is added; +hadamard_stim is a namespace folder,
%   so MATLAB finds it from there. Nothing under it belongs on the path:
%   tests/golden/shims shadows MATLAB built-ins (dir) and tests/
%   yitong_reference is Yitong's frozen, test-only code. Any of them left
%   there by "Add with Subfolders" are removed, with a warning.
%
%   In the rig's startup.m: run("<repo>/setup_project.m"), or addpath of
%   the root alone - never genpath.
root = fileparts(mfilename("fullpath"));
addpath(root);
stray = hadamard_stim.stray_path_folders("all");
if ~isempty(stray)
    rmpath(stray{:});
    warning("hadamard_stim:StrayPath", ...
        ['Removed %d hadamard-stim subfolders from the MATLAB path (only the repository ' ...
         'root belongs there; were they added with subfolders?):\n  %s'], ...
        numel(stray), strjoin(stray, newline + "  "));
end
end
