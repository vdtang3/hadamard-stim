classdef TestLuminosPreflight < matlab.unittest.TestCase
    %TESTLUMINOSPREFLIGHT The adapter refuses a rig it cannot run on, and says why.

    properties
        Folder
    end

    properties (TestParameter)
        % Each case breaks one thing on a fake Firefly that otherwise passes,
        % and names the words the refusal must contain.
        Fault = struct( ...
            "wrong_rig",          {{@(app, rig) assign(app, "rigName", "Adaptive_Upright"), "not Firefly"}}, ...
            "acquiring",          {{@(app, rig) assign(app, "acquisition_active", true), "middle of an acquisition"}}, ...
            "no_dmd",             {{@(app, rig) remove_device(app, "DMD (shared)"), "No ALP_DMD named ""DMD (shared)"""}}, ...
            "no_stage",           {{@(app, rig) remove_device(app, "NewportTRB25CC"), "NewportTRB25CC"}}, ...
            "no_grasshopper",     {{@(app, rig) remove_device(app, "Grasshopper3"), "Grasshopper3"}}, ...
            "no_blue",            {{@(app, rig) remove_device(app, "Blue LED 488"), "Blue LED 488"}}, ...
            "no_queue",           {{@(app, rig) assign(dmd(app), "SupportsQueue", false), "sequence-queue support"}}, ...
            "dmd_owned",          {{@(app, rig) assign(dmd(app), "pattern_owner", "adaptive_optopatch"), "owned by ""adaptive_optopatch"""}}, ...
            "dmd_size",           {{@(app, rig) assign(dmd(app), "Dimensions", [800 600]), "canvas"}}, ...
            "dmd_inverted",       {{@(app, rig) assign(dmd(app), "invert_output", true), "invert_output"}}, ...
            "daq_rate",           {{@(app, rig) set_gp(app, "rate", 2e5), "DAQ rate is 200000"}}, ...
            "camera_clock",       {{@(app, rig) set_gp(app, "clock_source", "/Dev1/PFI1"), "clocked from /Dev1/PFI1"}}, ...
            "clock_override",     {{@(app, rig) assign(daq(app), "external_clock_rate", 2e5), "external clock rate"}}, ...
            "ambient_output",     {{@(app, rig) add_ambient(app), "already drives Dev1/ao2"}}, ...
            "compressed",         {{@(app, rig) assign(camera(app), "compression_method", "FSE"), "compression"}}, ...
            "binned",             {{@(app, rig) assign(camera(app), "bin", 2), "binned 2"}}, ...
            "blue_uncalibrated",  {{@(app, rig) assign(blue(app), "iscalibrated", []), "no active calibration"}}, ...
            "blue_out_of_range",  {{@(app, rig) assign(blue(app), "max", 4), "modulator range"}}, ...
            "no_dmd_calibration", {{@(app, rig) assign(dmd(app), "CalibratedCamera", "Grasshopper3"), "no calibration for Teledyne Kinetix"}}, ...
            "other_transform",    {{@(app, rig) assign(dmd(app), "ActiveIsPair", false), "not its Teledyne Kinetix calibration"}}, ...
            "calibration_roi",    {{@(app, rig) assign(dmd(app), "ReferenceRoi", [0 0 512 512]), "calibrate at the acquisition ROI"}})
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
            testCase.verifyTrue(report.ok, strjoin(report.failures, newline));
        end

        function eachProblemIsRefusedWithAReason(testCase, Fault)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            Fault{1}(app, rig);
            report = rig.begin(cfg);
            testCase.verifyFalse(report.ok);
            testCase.verifySubstring(strjoin(report.failures, newline), Fault{2});
            % A refused begin leaves nothing to restore and touched nothing.
            testCase.verifyEmpty(app.Log);
            testCase.verifyEqual(rig.release().steps, strings(0, 1));
        end

        function everyProblemIsListedAtOnce(testCase)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            assign(app, "rigName", "Other");
            assign(dmd(app), "SupportsQueue", false);
            assign(camera(app), "compression_method", "FSE");
            report = rig.begin(cfg);
            testCase.verifyNumElements(report.failures, 3);
        end

        function aStageIsNeededOnlyForZOrDrift(testCase)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            remove_device(app, "NewportTRB25CC");
            cfg.z_reference.enabled = false;
            cfg.drift.enabled = false;
            report = rig.begin(cfg);
            testCase.verifyTrue(report.ok, strjoin(report.failures, newline));
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

function add_ambient(app)
d = daq(app);
wf = d.wfm_data_;
wf.ao(end+1) = struct("name", 'Blue LED 488', "port", 'Dev1/ao2', ...
    "wavefile", 'awfm_constant', "params", {{1}}, "operation", 'Addition', "concatTime", []);
d.wfm_data_ = wf;
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
