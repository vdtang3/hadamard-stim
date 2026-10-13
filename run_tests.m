function results = run_tests(tier)
%RUN_TESTS Run the hadamard-stim MATLAB tests.
%
%   run_tests            everything, including the full 640-trial protocol
%                        parity run (about ten minutes)
%   run_tests("fast")    everything else (a few minutes)
%
%   Off-rig and self-contained: the tests need neither Luminos nor the lab
%   share. Yitong's frozen reference code is never put on the path here;
%   only tests/golden/generate_yitong_goldens executes it.
arguments
    tier (1, 1) string {mustBeMember(tier, ["full" "fast"])} = "full"
end
root = fileparts(mfilename("fullpath"));
original = path;
cleanup = onCleanup(@() path(original)); %#ok<NASGU>
addpath(root);
suite = testsuite(fullfile(root, "tests"));
if tier == "fast"
    suite = suite(~startsWith(string({suite.Name}), "TestParityProtocol/"));
end
fprintf("hadamard-stim tests, %s tier (%d)\n", tier, numel(suite));
results = run(suite);
assertSuccess(results);
end
