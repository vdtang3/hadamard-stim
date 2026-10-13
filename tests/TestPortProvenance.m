classdef TestPortProvenance < matlab.unittest.TestCase
    %TESTPORTPROVENANCE Every +yitong port names the frozen file it ports,
    %and that file has not changed since the port was written.
    %
    %   A port's help text carries two lines:
    %       %   Port of tests/yitong_reference/<path>
    %       %   SHA-256 <hash of that file>
    %   If the frozen reference is ever refrozen with a different file, this
    %   fails until the port has been reviewed against it.

    methods (Test)
        function everyPortMatchesTheManifest(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            manifest = readtable(fullfile(root, "tests", "yitong_reference", "MANIFEST.tsv"), ...
                "FileType", "text", "Delimiter", "\t", "TextType", "string");
            ports = dir(fullfile(root, "+hadamard_stim", "+yitong", "**", "*.m"));
            testCase.assertNotEmpty(ports);
            for p = ports'
                text = fileread(fullfile(p.folder, p.name));
                tokens = regexp(text, ...
                    "Port of tests/yitong_reference/([^\n]+?)\s*\n%\s+SHA-256 ([0-9a-f]{64})", ...
                    "tokens");
                testCase.verifyNotEmpty(tokens, p.name + " does not say what it ports");
                for t = tokens
                    row = manifest.path == string(t{1}{1});
                    testCase.verifyEqual(nnz(row), 1, p.name + ": " + t{1}{1} + " is not frozen");
                    if any(row)
                        testCase.verifyEqual(string(t{1}{2}), manifest.sha256(row), ...
                            p.name + " was written against a different " + t{1}{1});
                    end
                end
            end
        end
    end
end
