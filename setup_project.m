function setup_project()
%SETUP_PROJECT Put the hadamard-stim package on the MATLAB path.
%
%   Only the repository root is added; +hadamard_stim is a namespace folder,
%   so MATLAB finds it from there. tests/yitong_reference is deliberately
%   never added: Yitong's frozen code is test-only and must not shadow
%   anything at run time.
root = fileparts(mfilename("fullpath"));
addpath(root);
end
