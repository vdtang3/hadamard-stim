classdef TestFireflyCommissioningRegressions < matlab.unittest.TestCase
    %TESTFIREFLYCOMMISSIONINGREGRESSIONS What the first Run on slide on Firefly ran into (2026-10-28).
    %
    %   - A full-sensor camera area (3200 rows) made the scan waveform ask
    %     for a negative duration and fail with an indexing error.
    %   - tests/golden/shims/trace on the path (added with subfolders)
    %     shadowed dir, so the slide movie could not be read.
    %   - writelines (R2022a) does not exist on Firefly's R2021b, so the
    %     check's result, and every run record, could not be written.

    properties
        Root
        Folder
    end

    methods (TestClassSetup)
        function setUp(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
            incoming = rng;
            testCase.addTeardown(@() rng(incoming));
        end
    end

    methods (TestMethodSetup)
        function makeFolder(testCase)
            testCase.Folder = string(tempname);
            mkdir(testCase.Folder);
            testCase.addTeardown(@() rmdir(testCase.Folder, "s"));
        end
    end

    methods (Test)
        % ---- A camera area too tall for the scan frame -------------------

        function aTallAreaIsRefusedBeforeTheWaveformIsBuilt(testCase)
            cfg = hadamard_stim.default_config();
            testCase.verifyEqual(hadamard_stim.protocol.max_scan_rows(cfg.scan.waveform_period_ms, 1e5), 671);
            % 11 ms frames light for floor(11e-3 / 1e-5) * 1e-5 = 10.99 ms in
            % floating point, as in his waveform.
            testCase.verifyEqual(hadamard_stim.protocol.max_scan_rows( ...
                cfg.calibration_scan.waveform_period_ms, 1e5), 2930);
            c = cfg.calibration_scan;
            testCase.verifyError(@() hadamard_stim.protocol.scan_waveform(cfg, ...
                c.waveform_period_ms, c.orange_v, 16, 1, camera_rows=3200), "hadamard_stim:CameraAreaTooTall");
            try
                hadamard_stim.protocol.scan_waveform(cfg, c.waveform_period_ms, c.orange_v, 16, 1, camera_rows=3200);
            catch err
                testCase.verifySubstring(err.message, "3200 rows");
                testCase.verifySubstring(err.message, "at most 2930 rows in the Camera tab");
            end
            % The limit itself still builds, and so does his 328.
            hadamard_stim.protocol.scan_waveform(cfg, c.waveform_period_ms, c.orange_v, 16, 1, camera_rows=2930);
            hadamard_stim.protocol.scan_waveform(cfg, cfg.scan.waveform_period_ms, cfg.scan.orange_v, 4, 1, ...
                camera_rows=671);
            testCase.verifyError(@() hadamard_stim.protocol.scan_waveform(cfg, cfg.scan.waveform_period_ms, ...
                cfg.scan.orange_v, 4, 1, camera_rows=672), "hadamard_stim:CameraAreaTooTall");
        end

        function preflightBlocksATallAreaForTheScansItWillRun(testCase)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            kinetix = app.getDevice("Camera", "name", "Teledyne Kinetix");
            item = @(report) report.checks(string({report.checks.id}) == "camera_area");
            testCase.verifyEqual(item(rig.begin(cfg)).status, "pass");
            rig.release();
            % 1000 rows: too tall for 2.52 ms scans, fine for the slide's 11 ms.
            kinetix.ROI = [0 448 0 1000];
            report = rig.begin(cfg);
            testCase.verifyEqual(item(report).status, "blocker");
            testCase.verifySubstring(item(report).message, "at most 671");
            rig.release();
            testCase.verifyEqual(item(rig.begin(cfg, "calibration_scan")).status, "pass");
            rig.release();
            kinetix.ROI = [0 3200 0 3200];
            report = rig.begin(cfg, "calibration_scan");
            testCase.verifyEqual(item(report).status, "blocker");
            testCase.verifySubstring(item(report).consequence, "at most 2930 rows in the Camera tab");
            rig.release();
        end

        function runOnSlideWithAFullSensorSaysSoAndTouchesNothing(testCase)
            [c, app] = tab_session(testCase.Folder);
            app.getDevice("Camera", "name", "Teledyne Kinetix").ROI = [0 3200 0 3200];
            dmd = app.getDevice("ALP_DMD");
            n = numel(app.Acquisitions);
            r = hadamard_stim.apply_controller_action(c, "run_commissioning_check", ...
                struct("name", "slide_queue"), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:HardwareNotReady");
            testCase.verifySubstring(r.message, "3200 rows");
            testCase.verifyEqual(numel(app.Acquisitions), n);
            testCase.verifyEmpty(dmd.Queue);
            testCase.verifyEqual(dmd.pattern_owner, "");
        end

        % ---- Test shims on the path --------------------------------------

        function setupProjectRemovesFoldersAddedWithSubfolders(testCase)
            original = path;
            testCase.addTeardown(@() path(original));
            addpath(genpath(testCase.Root));   % "Add with Subfolders"
            testCase.verifyTrue(startsWith(string(which("dir")), string(testCase.Root)), ...
                "the trace shim shadows dir, as on the rig");
            testCase.verifyNotEmpty(hadamard_stim.stray_path_folders());
            testCase.verifyWarning(@() setup_project(), "hadamard_stim:StrayPath");
            testCase.verifyFalse(startsWith(string(which("dir")), string(testCase.Root)));
            testCase.verifyEmpty(hadamard_stim.stray_path_folders("all"));
            testCase.verifyTrue(contains(path, testCase.Root));
        end

        function setupProjectFromCleanAddsOnlyTheRoot(testCase)
            original = path;
            testCase.addTeardown(@() path(original));
            path(strjoin(setdiff(strsplit(path, pathsep), ...
                cellstr(hadamard_stim.stray_path_folders("all")), "stable"), pathsep));
            testCase.verifyWarningFree(@() setup_project());
            testCase.verifyEmpty(hadamard_stim.stray_path_folders());
            testCase.verifyFalse(startsWith(string(which("dir")), string(testCase.Root)));
        end

        function preflightBlocksWhileATestShimIsOnThePath(testCase)
            [~, cfg, ~, rig] = fake_firefly(testCase.Folder);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "golden", "shims", "trace")));
            report = rig.begin(cfg);
            item = report.checks(string({report.checks.id}) == "package_path");
            testCase.verifyEqual(item.status, "blocker");
            testCase.verifySubstring(item.consequence, "setup_project");
            testCase.verifyFalse(report.can_run);
            rig.release();
        end

        % ---- R2021b --------------------------------------------------------

        function theCheckRecordIsWrittenWithoutWritelines(testCase)
            file = fullfile(testCase.Folder, "Users", "firefly_checks.json");
            first = hadamard_stim.checks.check_result("queue_support", true, "Supports_Sequence_Queue() returned true.");
            hadamard_stim.checks.record_firefly_check(file, first);
            second = hadamard_stim.checks.check_result("slide_queue", true, "12 of 12 triggers — µ ok.");
            hadamard_stim.checks.record_firefly_check(file, second);
            text = fileread(file);
            saved = jsondecode(text);
            testCase.verifyTrue(saved.queue_support.passed);
            testCase.verifyEqual(string(saved.slide_queue.evidence), "12 of 12 triggers — µ ok.");
            testCase.verifyTrue(contains(text, newline + "  "), "pretty-printed");
            % Replacing one check keeps the other.
            hadamard_stim.checks.record_firefly_check(file, ...
                hadamard_stim.checks.check_result("slide_queue", false, "9 of 12."));
            saved = jsondecode(fileread(file));
            testCase.verifyFalse(saved.slide_queue.passed);
            testCase.verifyTrue(saved.queue_support.passed);
        end

        function writeTextWritesEachLineAndFailsClearly(testCase)
            file = fullfile(testCase.Folder, "lines.txt");
            hadamard_stim.metadata.write_text(["one" "two"], file);
            testCase.verifyEqual(string(fileread(file)), "one" + newline + "two" + newline);
            testCase.verifyError(@() hadamard_stim.metadata.write_text("x", ...
                fullfile(testCase.Folder, "missing", "folder", "x.txt")), "hadamard_stim:CannotWrite");
        end

        function liveCodeUsesNothingNewerThanR2021b(testCase)
            % Functions Firefly's R2021b does not have that the package
            % has used or could easily reach for. Comments are ignored.
            newer = ["writelines" "allfinite" "anynan" "tensorprod" "dictionary" ...
                "combinations" "isuniform" "paddata" "trimdata" "fillmissing2" "clip"];
            files = [dir(fullfile(testCase.Root, "+hadamard_stim", "**", "*.m")); ...
                dir(fullfile(testCase.Root, "setup_project.m")); dir(fullfile(testCase.Root, "run_tests.m"))];
            for f = reshape(files, 1, [])
                lines = string(splitlines(fileread(fullfile(f.folder, f.name))));
                code = lines(~startsWith(strtrim(lines), "%"));
                for name = newer
                    hits = code(~cellfun(@isempty, regexp(code, "(?<![\w.])" + name + "\s*\(", "once")));
                    testCase.verifyEmpty(hits, f.name + " calls " + name);
                end
            end
        end
    end
end
