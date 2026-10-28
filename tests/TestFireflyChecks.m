classdef TestFireflyChecks < matlab.unittest.TestCase
    %TESTFIREFLYCHECKS The four Firefly checks, run and recorded from MATLAB.
    %
    %   Each check reads the rig (driver probe, trigger edge, queue support)
    %   or runs a small queue on a slide and compares the camera with the
    %   queue model; record_firefly_check writes the outcome into the file
    %   the rig settings name, which is what lets real runs start.

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
        function theDriverMustRecogniseAnXgaBoard(testCase)
            good = probe("alp4395.dll", 0, true, 1024, 768);
            r = hadamard_stim.checks.driver_check([probe("alp439x.dll", 1, false, 0, 0), good]);
            testCase.verifyTrue(r.passed);
            testCase.verifySubstring(r.evidence, "alp4395.dll");
            testCase.verifyNumElements(r.details.drivers, 2);
            r = hadamard_stim.checks.driver_check(probe("alp4395.dll", 0, false, 1024, 768));
            testCase.verifyFalse(r.passed);
            r = hadamard_stim.checks.driver_check(probe("alp4395.dll", 0, true, 1920, 1080));
            testCase.verifyFalse(r.passed);
            r = hadamard_stim.checks.driver_check(struct([]));
            testCase.verifyFalse(r.passed);
            testCase.verifySubstring(r.evidence, "No ALP driver");
        end

        function theTriggerEdgeIsWhatTheBoardReports(testCase)
            [~, app] = tab_session(testCase.Folder);
            dmd = app.getDevice("ALP_DMD");
            r = hadamard_stim.checks.trigger_edge_check(app);
            testCase.verifyTrue(r.passed);
            testCase.verifyEqual(r.details.trigger_edge, "rising");
            dmd.PowerOnEdge = 2008;
            testCase.verifyEqual(hadamard_stim.checks.trigger_edge_check(app).details.trigger_edge, "falling");
            dmd.PowerOnEdge = [];
            testCase.verifyFalse(hadamard_stim.checks.trigger_edge_check(app).passed);
        end

        function queueSupportIsTheDriversAnswer(testCase)
            [~, app] = tab_session(testCase.Folder);
            testCase.verifyTrue(hadamard_stim.checks.queue_support_check(app).passed);
            app.getDevice("ALP_DMD").SupportsQueue = false;
            r = hadamard_stim.checks.queue_support_check(app);
            testCase.verifyFalse(r.passed);
            testCase.verifySubstring(r.evidence, "returned false");
        end

        function theSlideQueuePlaysAsModelled(testCase)
            [~, app] = tab_session(testCase.Folder);
            n = numel(app.Acquisitions);
            r = hadamard_stim.checks.slide_queue_check(app, ...
                acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition, ...
                frame_means=@(acq) slide_means(0));
            testCase.verifyTrue(r.passed, r.evidence);
            testCase.verifyEqual(r.name, "slide_queue");
            testCase.verifySubstring(r.evidence, "12 of 12 triggers");
            testCase.verifySubstring(r.evidence, "rising edge");
            testCase.verifySubstring(r.evidence, "held picture 5");
            % Through the protocol's own queue call: the queue, the edge, one
            % acquisition of 16 frames, then the DMD handed back.
            a = app.Acquisitions(n + 1:end);
            testCase.assertNumElements(a, 1);
            testCase.verifyEqual(a.queue_settings.trigger_edge, "rising");
            testCase.verifyEqual(a.queue.picnum, [3 2]);
            testCase.verifyEqual(a.queue.repeat, [2 3]);
            kinetix = a.cameras([a.cameras.name] == "Teledyne Kinetix");
            testCase.verifyEqual(kinetix.frames, 16);
            testCase.verifyFalse(any([a.ports.port] == "Dev1/ao2"), "blue driven");
            dmd = app.getDevice("ALP_DMD");
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyEqual(dmd.Displaying, "dark");
        end

        function aQueueOneTriggerBehindFails(testCase)
            [~, app] = tab_session(testCase.Folder);
            r = hadamard_stim.checks.slide_queue_check(app, ...
                acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition, ...
                frame_means=@(acq) slide_means(1));
            testCase.verifyFalse(r.passed);
            testCase.verifyNotEqual(r.details.classified, r.details.expected);
        end

        function withoutQueueSupportNothingIsLoaded(testCase)
            [~, app] = tab_session(testCase.Folder);
            app.getDevice("ALP_DMD").SupportsQueue = false;
            n = numel(app.Acquisitions);
            r = hadamard_stim.checks.slide_queue_check(app, trigger_edge="rising", ...
                acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition);
            testCase.verifyFalse(r.passed);
            testCase.verifySubstring(r.evidence, "Not run");
            testCase.verifyEqual(numel(app.Acquisitions), n);
        end

        function recordedChecksLetRealRunsStart(testCase)
            [~, app] = tab_session(testCase.Folder, validated=false);
            file = fullfile(testCase.Folder, "firefly_checks.json");
            backend = hadamard_stim.luminos.LuminosBackend(app, blue_threshold=15, ...
                hardware_validation_file=file, calibration_movies={uint16(zeros(16, 600, 64))}, ...
                acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition);
            c = hadamard_stim.HadamardStimController(backend);
            gate = @() string({c.Preflight.checks(startsWith(string({c.Preflight.checks.id}), "firefly_")).status});
            c.runPreflight();
            testCase.verifyEqual(gate(), repmat("fail", 1, 4));

            results = {hadamard_stim.checks.driver_check(probe("alp4395.dll", 0, true, 1024, 768)), ...
                hadamard_stim.checks.trigger_edge_check(app), ...
                hadamard_stim.checks.queue_support_check(app), ...
                hadamard_stim.checks.slide_queue_check(app, ...
                    acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition, ...
                    frame_means=@(acq) slide_means(0))};
            for k = 1:numel(results)
                hadamard_stim.checks.record_firefly_check(file, results{k});
            end
            c.runPreflight();
            testCase.verifyEqual(gate(), repmat("pass", 1, 4));
            saved = jsondecode(fileread(file));
            testCase.verifySubstring(saved.slide_queue.evidence, "12 of 12");
            testCase.verifyTrue(hadamard_stim.metadata.hardware_gate( ...
                struct("hardware_validation", saved)).ok);
            % A failed rerun replaces that entry only, and is kept as failed.
            app.getDevice("ALP_DMD").SupportsQueue = false;
            hadamard_stim.checks.record_firefly_check(file, hadamard_stim.checks.queue_support_check(app));
            saved = jsondecode(fileread(file));
            testCase.verifyFalse(saved.queue_support.passed);
            testCase.verifyTrue(saved.driver.passed);
        end
    end
end

function r = probe(dll, status, recognised, width, height)
r = struct("dll", string(dll), "suite", "4.3", "version", "1.0.19.8", "serial", 1234, ...
    "status", status, "status_text", "board not found", "recognised", recognised, ...
    "chipset", "XGA", "width", width, "height", height);
end

function means = slide_means(shift)
% A uniform slide's frame means for the check's queue: 100 counts dark plus
% 40 per band, as the model predicts it (shifted by shift frames to fake a
% queue that runs one trigger behind), holding the last picture once dry.
shown = hadamard_stim.protocol.alp_queue_display([3 2], [2 3], 16);
offset = [0 3];
picture = zeros(1, 16);
live = shown.sequence > 0;
picture(live) = offset(shown.sequence(live)) + shown.picture(live);
picture(~live) = 5;
picture = [repmat(picture(1), 1, shift) picture(1:end - shift)];
rng(5);
means = 100 + 40 * picture + randn(1, 16);
end
