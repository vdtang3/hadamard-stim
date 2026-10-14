classdef TestLuminosBoundary < matlab.unittest.TestCase
    %TESTLUMINOSBOUNDARY +luminos only connects; nothing else knows about Luminos or Firefly.
    %
    %   Code only (comments are stripped): +protocol, +yitong and +metadata
    %   never call the adapter or name a Firefly device or port, and +luminos
    %   uses the ported code only to read calibrations and reconstruct
    %   scans, never to run or change the protocol.

    properties
        Package
    end

    methods (TestClassSetup)
        function locate(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.Package = fullfile(root, "+hadamard_stim");
        end
    end

    methods (Test)
        function theProtocolDoesNotKnowTheBackend(testCase)
            code = testCase.codeIn(["+protocol" "+yitong" "+metadata"]);
            testCase.verifyFalse(contains(code, "hadamard_stim.luminos"));
            testCase.verifyFalse(contains(code, "hadamard_stim.testing"));
        end

        function fireflyFactsStayInTheAdapter(testCase)
            profile = hadamard_stim.luminos.firefly_profile();
            names = string(struct2cell(structfun(@(d) d.name, profile.devices, "UniformOutput", false)));
            ports = [profile.channels.port];
            code = testCase.codeIn(["+protocol" "+yitong" "+metadata"]);
            for word = [names(:)' ports "Firefly"]
                testCase.verifyFalse(contains(code, word), word + " appears outside +luminos");
            end
        end

        function theAdapterUsesThePortOnlyForCalibrationAndReconstruction(testCase)
            code = testCase.codeIn("+luminos");
            used = unique(string(regexp(code, "hadamard_stim\.(?:protocol|yitong)\.\w+", "match")));
            allowed = ["hadamard_stim.yitong.linearize_blue_voltage" ...
                "hadamard_stim.yitong.hadamard_pinhole_calibration" ...
                "hadamard_stim.yitong.dmd_hadamard_reconstruct_core" ...
                "hadamard_stim.yitong.hadamard_reconstruct_core"];
            testCase.verifyEmpty(setdiff(used, allowed));
        end

        function bothBackendsOfferTheSameInterface(testCase)
            interface = hadamard_stim.protocol.hardware_interface();
            for backend = ["hadamard_stim.testing.SimulatedRig" "hadamard_stim.luminos.LuminosRig"]
                testCase.verifyEmpty(setdiff(interface, string(methods(backend))), backend);
            end
        end
    end

    methods
        function code = codeIn(testCase, folders)
            code = "";
            for folder = folders
                for f = dir(fullfile(testCase.Package, folder, "*.m"))'
                    lines = splitlines(string(fileread(fullfile(f.folder, f.name))));
                    lines = regexprep(lines, "%.*$", "");      % comments out
                    code = code + strjoin(lines, newline) + newline;
                end
            end
        end
    end
end
