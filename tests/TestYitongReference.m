classdef TestYitongReference < matlab.unittest.TestCase
    %TESTYITONGREFERENCE The frozen copy of Yitong's code is intact, minimal
    %and test-only.

    properties
        Root
        Reference
    end

    methods (TestClassSetup)
        function locate(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.Reference = fullfile(testCase.Root, "tests", "yitong_reference");
        end
    end

    methods (Test)
        function everyFileMatchesItsManifestHash(testCase)
            manifest = read_manifest(testCase.Reference);
            for k = 1:height(manifest)
                file = fullfile(testCase.Reference, manifest.path(k));
                testCase.verifyEqual(file_sha256(file), manifest.sha256(k), ...
                    "Frozen file changed: " + manifest.path(k));
            end
        end

        function nothingIsFrozenWithoutAManifestEntry(testCase)
            % Keeps the reference minimal: a file can only be added by
            % tools/freeze_yitong_reference.sh, which records why.
            manifest = read_manifest(testCase.Reference);
            listing = dir(fullfile(testCase.Reference, "**", "*"));
            listing = listing(~[listing.isdir]);
            files = string(fullfile({listing.folder}, {listing.name}));
            files = erase(files, testCase.Reference + filesep);
            files = setdiff(files, ["MANIFEST.tsv" "README.md"]);
            testCase.verifyEmpty(setdiff(files, manifest.path), ...
                "Files in tests/yitong_reference without a MANIFEST entry");
        end

        function everyEntryExplainsWhyItIsFrozen(testCase)
            manifest = read_manifest(testCase.Reference);
            testCase.verifyTrue(all(strlength(manifest.why) > 0));
        end

        function setupProjectDoesNotExposeTheReference(testCase)
            original = path;
            restore = onCleanup(@() path(original));
            setup_project_from(testCase.Root);
            entries = string(strsplit(path, pathsep));
            testCase.verifyFalse(any(startsWith(entries, testCase.Reference)), ...
                "Yitong's frozen code must never be on the runtime path");
            testCase.verifyEmpty(which("static_image_seg_v5"));
        end
    end
end

function manifest = read_manifest(reference)
manifest = readtable(fullfile(reference, "MANIFEST.tsv"), "FileType", "text", ...
    "Delimiter", "\t", "TextType", "string");
end

function setup_project_from(root)
old = cd(root);
back = onCleanup(@() cd(old));
setup_project();
end

function hex = file_sha256(file)
md = java.security.MessageDigest.getInstance("SHA-256");
md.update(typecast(fileread_bytes(file), "int8"));
hex = string(lower(reshape(dec2hex(typecast(md.digest(), "uint8"), 2).', 1, [])));
end

function bytes = fileread_bytes(file)
fid = fopen(file, "r");
closer = onCleanup(@() fclose(fid));
bytes = fread(fid, inf, "*uint8");
end
