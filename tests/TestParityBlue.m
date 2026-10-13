classdef TestParityBlue < matlab.unittest.TestCase
    %TESTPARITYBLUE linearize_blue_voltage gives his values, NaNs included,
    %with his blueCal.mat passed in as the calibration.
    methods (TestClassSetup)
        function addPackage(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fileparts(fileparts(mfilename("fullpath")))));
        end
    end
    methods (Test)
        function gridMatchesHis(testCase)
            golden = load(fixture("blue"));
            calibration = yitong_blue_calibration();
            testCase.verifyTrue(isequaln( ...
                hadamard_stim.yitong.linearize_blue_voltage(golden.v_grid, calibration), ...
                golden.v_linear_grid));
            testCase.verifyTrue(isequaln( ...
                hadamard_stim.yitong.linearize_blue_voltage(golden.v_edge, calibration), ...
                golden.v_linear_edge));
        end
        function calibrationIsHisFile(testCase)
            % The fixture stored the curve it was computed from; the test
            % input must be that same curve.
            golden = load(fixture("blue"));
            calibration = yitong_blue_calibration();
            testCase.verifyEqual(calibration.v_blue, golden.v_blue);
            testCase.verifyEqual(calibration.blue_intens_c, golden.blue_intens_c);
        end
    end
end

function file = fixture(name)
file = fullfile(fileparts(mfilename("fullpath")), "fixtures", "yitong_" + name + ".mat");
end

function calibration = yitong_blue_calibration()
% Loaded by file path: the frozen reference is never put on the path.
cal = load(fullfile(fileparts(mfilename("fullpath")), "yitong_reference", ...
    "dragonfly", "Utilities", "blueCal.mat"));
calibration = struct("v_blue", cal.vBlue, "blue_intens_c", cal.blueIntensC);
end
