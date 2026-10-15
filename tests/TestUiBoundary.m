classdef TestUiBoundary < matlab.unittest.TestCase
    %TESTUIBOUNDARY What a frontend can reach, and what the display code may do.
    %
    %   Code only (comments are stripped). The display products (+ui,
    %   controller_view) never touch hardware or the backend's environment,
    %   and use the ported code only to draw and number what the protocol
    %   already holds. The write surface is exactly the controller's legal
    %   actions.

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
        function displayCodeNeverTouchesTheRig(testCase)
            code = testCase.displayCode();
            for word = ["hw." "Env.hw" "hadamard_stim.luminos" ".begin(" ".release(" ".abort(" ...
                    "environment(" "set_settings(" "apply_controller_action" "run_protocol" ...
                    "run_trial" "acquire"]
                testCase.verifyFalse(contains(code, word), word);
            end
            % Only these controller methods are called: all read-only.
            calls = unique(string(regexp(code, "(?<=controller\.)\w+(?=\()", "match")));
            testCase.verifyEmpty(setdiff(calls, ["getState"]), strjoin(calls, ", "));
        end

        function displayCodeUsesThePortOnlyToDraw(testCase)
            code = testCase.displayCode();
            used = unique(string(regexp(code, "hadamard_stim\.(?:protocol|yitong)\.\w+", "match")));
            testCase.verifyEmpty(setdiff(used, ["hadamard_stim.yitong.split_rois" ...
                "hadamard_stim.yitong.stim_matrix"]), strjoin(used, ", "));
        end

        function theWriteSurfaceIsTheLegalActions(testCase)
            text = fileread(fullfile(testCase.Package, "apply_controller_action.m"));
            known = regexp(text, "known = \[(.*?)\];", "tokens", "once");
            known = string(regexp(known{1}, """(\w+)""", "tokens"));
            legal = string(fieldnames(hadamard_stim.HadamardStimController(struct()).legalActions()));
            testCase.verifyEqual(sort(known(:)), sort(legal(:)));
        end
    end

    methods
        function code = displayCode(testCase)
            files = [dir(fullfile(testCase.Package, "+ui", "*.m")); ...
                dir(fullfile(testCase.Package, "controller_view.m"))];
            code = "";
            for f = files'
                lines = splitlines(string(fileread(fullfile(f.folder, f.name))));
                lines = regexprep(lines, "%.*$", "");
                code = code + strjoin(lines, newline) + newline;
            end
        end
    end
end
