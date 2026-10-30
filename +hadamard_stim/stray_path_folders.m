function folders = stray_path_folders(scope)
%STRAY_PATH_FOLDERS Folders of this repository on the MATLAB path that must not be.
%
%   folders = hadamard_stim.stray_path_folders()        test-only code
%   folders = hadamard_stim.stray_path_folders("all")   every subfolder
%
%   Only the repository root belongs on the path (setup_project). With
%   "Add with Subfolders" (genpath), tests/golden/shims/* shadows MATLAB
%   built-ins - shims/trace/dir.m replaces dir, so reading a movie fails -
%   and tests/yitong_reference puts Yitong's frozen code ahead of the port.
%   The default scope is those test-only folders, which no live session
%   and no test of the package ever needs; preflight blocks on them.
%   "all" is every folder under the root, which setup_project removes.
arguments
    scope (1, 1) string {mustBeMember(scope, ["test_only" "all"])} = "test_only"
end
root = string(fileparts(fileparts(mfilename("fullpath"))));
entries = string(strsplit(path, pathsep));
key = @(p) p;
if ispc
    key = @(p) lower(p);
end
under = @(sub) startsWith(key(entries), key(fullfile(root, sub)) + filesep) ...
    | key(entries) == key(fullfile(root, sub));
if scope == "all"
    stray = startsWith(key(entries), key(root) + filesep);
else
    stray = under(fullfile("tests", "golden")) | under(fullfile("tests", "yitong_reference"));
end
folders = reshape(entries(stray), 1, []);
end
