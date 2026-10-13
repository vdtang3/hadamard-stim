classdef TestHardwareInterface < matlab.unittest.TestCase
    %TESTHARDWAREINTERFACE The simulated rig offers exactly what the protocol uses.
    %
    %   The Luminos adapter (Phase 4) is held to the same list.
    methods (TestClassSetup)
        function addPackage(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fileparts(fileparts(mfilename("fullpath")))));
        end
    end
    methods (Test)
        function simulatedRigImplementsTheInterface(testCase)
            offered = string(methods("hadamard_stim.testing.SimulatedRig"));
            testCase.verifyEmpty(setdiff(hadamard_stim.protocol.hardware_interface(), offered));
        end

        function protocolCallsNothingElseOnTheHardware(testCase)
            % Every "hw." / "env.hw." call in +protocol names an interface method.
            root = fileparts(fileparts(mfilename("fullpath")));
            files = dir(fullfile(root, "+hadamard_stim", "+protocol", "*.m"));
            used = strings(1, 0);
            for f = files'
                text = fileread(fullfile(f.folder, f.name));
                tokens = regexp(text, "(?<![\w.])(?:env\.)?hw\.(\w+)", "tokens");
                used = [used cellfun(@(t) string(t{1}), tokens)]; %#ok<AGROW>
            end
            extra = setdiff(unique(used), hadamard_stim.protocol.hardware_interface());
            testCase.verifyEmpty(extra, "Protocol uses hardware operations outside the interface");
        end
    end
end
