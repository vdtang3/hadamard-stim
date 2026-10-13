function results = run_tests()
%RUN_TESTS Run the hadamard-stim MATLAB tests.
%
%   Off-rig and self-contained: the tests need neither Luminos nor the lab
%   share. Yitong's frozen reference code is never put on the path here;
%   only tests/golden/generate_yitong_goldens executes it.
root = fileparts(mfilename("fullpath"));
original = path;
cleanup = onCleanup(@() path(original)); %#ok<NASGU>
addpath(root);
suite = testsuite(fullfile(root, "tests"));
fprintf("hadamard-stim tests (%d)\n", numel(suite));
results = run(suite);
assertSuccess(results);
end
