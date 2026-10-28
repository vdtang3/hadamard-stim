classdef TestLuminosPreflight < matlab.unittest.TestCase
    %TESTLUMINOSPREFLIGHT The adapter's readiness: what blocks, what only warns, and why.
    %
    %   Blockers are what cannot be done or would fight another owner of the
    %   hardware; they refuse begin. Warnings are scientific or data-quality
    %   risks; begin goes ahead and the report says what they mean.

    properties
        Folder
    end

    properties (TestParameter)
        % Each case breaks one thing on a fake Firefly that otherwise passes,
        % and names the words the blocker must contain.
        Blocker = struct( ...
            "wrong_rig",          {{@(app, rig) assign(app, "rigName", "Adaptive_Upright"), "not Firefly"}}, ...
            "acquiring",          {{@(app, rig) assign(app, "acquisition_active", true), "middle of an acquisition"}}, ...
            "no_dmd",             {{@(app, rig) remove_device(app, "DMD (shared)"), "No ALP_DMD named ""DMD (shared)"""}}, ...
            "no_stage",           {{@(app, rig) remove_device(app, "NewportTRB25CC"), "NewportTRB25CC"}}, ...
            "no_grasshopper",     {{@(app, rig) remove_device(app, "Grasshopper3"), "Grasshopper3"}}, ...
            "no_blue",            {{@(app, rig) remove_device(app, "Blue LED 488"), "Blue LED 488"}}, ...
            "board_closed",       {{@(app, rig) assign(dmd(app), "mexPointer", 0), "no open board"}}, ...
            "no_queue",           {{@(app, rig) assign(dmd(app), "SupportsQueue", false), "no sequence-queue support"}}, ...
            "dmd_owned",          {{@(app, rig) assign(dmd(app), "pattern_owner", "adaptive_optopatch"), "owned by ""adaptive_optopatch"""}}, ...
            "dmd_size",           {{@(app, rig) assign(dmd(app), "Dimensions", [800 600]), "canvas"}}, ...
            "dmd_inverted",       {{@(app, rig) assign(dmd(app), "invert_output", true), "invert_output"}}, ...
            "conflicting_output", {{@(app, rig) add_ambient(app, "Dev1/ao2"), "already drives Dev1/ao2"}}, ...
            "compressed",         {{@(app, rig) assign(camera(app), "compression_method", "FSE"), "compression"}}, ...
            "blue_uncalibrated",  {{@(app, rig) assign(blue(app), "iscalibrated", []), "no active calibration"}}, ...
            "blue_out_of_range",  {{@(app, rig) assign(blue(app), "max", 4), "modulator range"}}, ...
            "no_dmd_calibration", {{@(app, rig) assign(dmd(app), "CalibratedCamera", "Grasshopper3"), "no calibration for Teledyne Kinetix"}}, ...
            "other_transform",    {{@(app, rig) assign(dmd(app), "ActiveIsPair", false), "not its Teledyne Kinetix calibration"}})
        % Each case changes one thing that differs from his rig but still
        % defines the acquisition: the check, and the words of its message.
        Warning = struct( ...
            "unrelated_output",   {{@(app, rig) add_ambient(app, "Dev1/ao5"), "daq_outputs", "schedules Dev1/ao5"}}, ...
            "binned",             {{@(app, rig) assign(camera(app), "bin", 2), "camera_settings", "binned 2"}}, ...
            "calibration_roi",    {{@(app, rig) assign(dmd(app), "ReferenceRoi", [0 0 512 512]), "dmd_calibration", "calibrate at the acquisition ROI"}}, ...
            "old_calibration_roi", {{@(app, rig) old_mismatched_geometry(app), "dmd_calibration", "calibrate at the acquisition ROI"}})
        % Otherwise compatible calibrations of any age: shown, never judged.
        AgeDays = struct("one_day", 1, "a_month", 30, "a_year", 365)
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "support")));
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
        function theFakeFireflyPasses(testCase)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            report = rig.begin(cfg);
            testCase.verifyTrue(report.can_run, strjoin(report.failures, newline));
            testCase.verifyEmpty(report.blockers);
            testCase.verifyEmpty(report.warnings);
        end

        function eachBlockerIsRefusedWithAReason(testCase, Blocker)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            Blocker{1}(app, rig);
            report = rig.begin(cfg);
            testCase.verifyFalse(report.can_run);
            testCase.verifySubstring(strjoin(report.failures, newline), Blocker{2});
            testCase.verifyFalse(any([report.blockers.overrideable]));
            % A refused begin leaves nothing to restore and touched nothing.
            testCase.verifyEmpty(app.Log);
            testCase.verifyEqual(rig.release().steps, strings(0, 1));
        end

        function eachWarningIsSaidAndDoesNotRefuse(testCase, Warning)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            Warning{1}(app, rig);
            report = rig.begin(cfg);
            testCase.verifyTrue(report.can_run, strjoin(report.failures, newline));
            item = report.checks(string({report.checks.id}) == Warning{2});
            testCase.verifyEqual(item.status, "warning");
            testCase.verifyTrue(item.overrideable);
            testCase.verifySubstring(item.message, Warning{3});
            testCase.verifyNotEmpty(char(item.consequence), "a warning says what it means");
            testCase.verifyEmpty(app.Log);
            testCase.verifyEqual(rig.release().steps, strings(0, 1));
        end

        function anotherWaveformsTabRateIsOnlyANote(testCase)
            % Each acquisition sets the protocol's rate and puts the tab's back.
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            set_gp(app, "rate", 2e5);
            report = rig.begin(cfg);
            testCase.verifyTrue(report.can_run);
            item = report.checks(string({report.checks.id}) == "daq_rate");
            testCase.verifyEqual(item.status, "info");
            testCase.verifySubstring(item.message, "200000 Hz");
        end

        function calibrationAgeAloneIsOnlyShown(testCase, AgeDays)
            % A compatible blue or DMD calibration 1, 30 or 365 days old:
            % runnable and passing, differing only in the age it shows.
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            recorded_blue(app, AgeDays);
            board = dmd(app);
            board.MeasuredUtc = string(datetime("now", "TimeZone", "UTC") - days(AgeDays), ...
                "yyyy-MM-dd'T'HH:mm:ss'Z'");
            report = rig.begin(cfg);
            testCase.verifyTrue(report.can_run);
            testCase.verifyEmpty(report.warnings);
            for id = ["blue_calibration" "dmd_calibration"]
                item = report.checks(string({report.checks.id}) == id);
                testCase.verifyEqual(item.status, "pass", id);
                testCase.verifyEqual(item.details.age_days, AgeDays, id);
                expected = hadamard_stim.metadata.calibration_age( ...
                    datetime("now", "TimeZone", "UTC") - days(AgeDays));
                testCase.verifySubstring(item.message, expected.ago, id);
                testCase.verifySubstring(item.message, "reused", id);
                testCase.verifyEmpty(char(item.consequence), id);
            end
        end

        function todaysAndUndatedCalibrationsBothPass(testCase)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            recorded_blue(app, 0);
            item = rig.begin(cfg).checks;
            blue = item(string({item.id}) == "blue_calibration");
            testCase.verifyEqual(blue.status, "pass");
            testCase.verifySubstring(blue.message, "Taken today");
            geometry = item(string({item.id}) == "dmd_calibration");
            testCase.verifyEqual(geometry.status, "pass");
            testCase.verifySubstring(geometry.message, "Date not recorded");
        end

        function anOldCompatibleBlueCalibrationRunsAndAMissingOneBlocks(testCase)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            recorded_blue(app, 400);
            testCase.verifyTrue(rig.begin(cfg).can_run);
            modulator = app.getDevice("NI_DAQ_Modulator", "name", "Blue LED 488");
            modulator.calibration_curve = [];
            report = rig.begin(cfg);
            testCase.verifyFalse(report.can_run);
            item = report.checks(string({report.checks.id}) == "blue_calibration");
            testCase.verifyEqual(item.status, "blocker");
            testCase.verifySubstring(item.consequence, "no blue command is defined");
        end

        function everyProblemIsListedAtOnce(testCase)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            assign(app, "rigName", "Other");
            assign(dmd(app), "SupportsQueue", false);
            assign(camera(app), "compression_method", "FSE");
            report = rig.begin(cfg);
            testCase.verifyNumElements(report.blockers, 3);
        end

        function aStageIsNeededOnlyForZOrDrift(testCase)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            remove_device(app, "NewportTRB25CC");
            cfg.z_reference.enabled = false;
            cfg.drift.enabled = false;
            report = rig.begin(cfg);
            testCase.verifyTrue(report.can_run, strjoin(report.failures, newline));
        end

        function theBlueThresholdMustBeChosen(testCase)
            [app, cfg] = fake_firefly(testCase.Folder);
            rig = hadamard_stim.luminos.LuminosRig(app);
            report = rig.begin(cfg);
            testCase.verifySubstring(strjoin(report.failures, newline), "blue_threshold is not set");
        end

        function checkingChangesNothing(testCase)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            before = snapshot(app);
            rig.begin(cfg);
            testCase.verifyEqual(snapshot(app), before);
            testCase.verifyEmpty(app.Log);
        end
    end
end

function assign(object, name, value)
object.(name) = value;
end

function d = find_device(app, name)
names = device_names(app);
d = app.Devices{names == name};
end

function d = dmd(app), d = find_device(app, "DMD (shared)"); end
function d = daq(app), d = find_device(app, "DAQ_Session"); end
function d = camera(app), d = find_device(app, "Teledyne Kinetix"); end
function d = blue(app), d = find_device(app, "Blue LED 488"); end

function remove_device(app, name)
names = device_names(app);
app.Devices(names == name) = [];
end

function set_gp(app, field, value)
d = daq(app);
gp = d.global_props_;
gp.(field) = value;
d.global_props_ = gp;
end

function add_ambient(app, port)
d = daq(app);
wf = d.wfm_data_;
wf.ao(end+1) = struct("name", 'Ambient', "port", char(port), ...
    "wavefile", 'awfm_constant', "params", {{1}}, "operation", 'Addition', "concatTime", []);
d.wfm_data_ = wf;
end

function clear_gp(app)
d = daq(app);
d.global_props_ = [];
end

function old_mismatched_geometry(app)
% A DMD calibration taken at another area 5 minutes ago: new, still a warning.
d = dmd(app);
d.ReferenceRoi = [0 0 512 512];
d.MeasuredUtc = string(datetime("now", "TimeZone", "UTC") - minutes(5), "yyyy-MM-dd'T'HH:mm:ss'Z'");
end

function recorded_blue(app, age_days)
% The blue calibration as Luminos's slide routine records it, age_days old.
b = blue(app);
b.calibration_info = struct("method", "Calibrate_Modulator_On_Slide", "units", "counts", ...
    "measured_utc", string(datetime("now", "TimeZone", "UTC") - days(age_days), ...
    "yyyy-MM-dd'T'HH:mm:ss'Z'"), "camera", "Teledyne Kinetix");
end

function s = snapshot(app)
% Every public property of every device, as values.
s = struct();
for k = 1:numel(app.Devices)
    d = app.Devices{k};
    p = struct();
    for name = string(properties(d))'
        if name ~= "App"
            p.(name) = d.(name);
        end
    end
    s.(matlab.lang.makeValidName(d.name)) = p;
end
s.app = struct("acquisition_active", app.acquisition_active, "expfolder", app.expfolder);
end

function names = device_names(app)
names = cellfun(@(x) x.name, app.Devices, "UniformOutput", false);
names = [names{:}];
end
