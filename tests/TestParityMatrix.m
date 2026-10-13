classdef TestParityMatrix < matlab.unittest.TestCase
    %TESTPARITYMATRIX The stimulation matrix equals the one his script built.
    methods (TestClassSetup)
        function addPackage(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fileparts(fileparts(mfilename("fullpath")))));
        end
    end
    methods (Test)
        function matrixIsHis(testCase)
            golden = load(fixture("matrix"), "had_mat").had_mat;
            testCase.verifyEqual(hadamard_stim.yitong.stim_matrix(320), golden);
        end
        function globalRandomStateIsLeftAlone(testCase)
            rng(12345, "twister");
            before = rng;
            hadamard_stim.yitong.stim_matrix(320);
            testCase.verifyEqual(rng, before);
        end
    end
end

function file = fixture(name)
file = fullfile(fileparts(mfilename("fullpath")), "fixtures", "yitong_" + name + ".mat");
end
