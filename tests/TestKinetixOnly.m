classdef TestKinetixOnly < matlab.unittest.TestCase
    %TESTKINETIXONLY Hadamard Stim images with Firefly's Teledyne Kinetix, and only it.
    %
    %   The Kinetix is found as Luminos's one camera of type 3 (PVCAM), not by
    %   name: renamed, it is still found; missing, the tab says so; the
    %   Grasshopper3 and Blackfly (type 4) are never taken in its place. The
    %   DMD projects through the Kinetix's own stored calibration, selected
    %   when another camera's is active and never replaced by another
    %   camera's. A calibration stored under the camera's former name is
    %   moved once by tools/migrate_dmd_calibration_camera, with a backup.

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
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tools")));
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
        function theKinetixIsFoundByWhatItIsNotItsName(testCase)
            app = hadamard_stim.testing.make_fake_luminos(testCase.Folder);
            profile = hadamard_stim.luminos.firefly_profile();
            [devices, failures] = hadamard_stim.luminos.resolve_hardware(app, profile);
            testCase.verifyEmpty(camera_failures(failures));
            testCase.verifyEqual(string(devices.camera.name), "Teledyne Kinetix");
            % Renamed in the rig file (it was "Kinetix"): still the Kinetix.
            camera = kinetix(app);
            camera.name = "Kinetix";
            [devices, failures] = hadamard_stim.luminos.resolve_hardware(app, profile);
            testCase.verifyEmpty(camera_failures(failures));
            testCase.verifyEqual(string(devices.camera.name), "Kinetix");
            testCase.verifyEqual(double(devices.camera.type), 3);
        end

        function withoutAKinetixNothingElseStandsIn(testCase)
            app = hadamard_stim.testing.make_fake_luminos(testCase.Folder);
            app.Devices(cellfun(@(d) isa(d, "hadamard_stim.testing.FakeLuminosCamera") ...
                && d.type == 3, app.Devices)) = [];
            [devices, failures] = hadamard_stim.luminos.resolve_hardware(app, ...
                hadamard_stim.luminos.firefly_profile());
            testCase.verifyEmpty(devices.camera, "The Grasshopper3 and Blackfly are not substitutes.");
            message = camera_failures(failures).message;
            testCase.verifySubstring(message, "Teledyne Kinetix");
            testCase.verifySubstring(message, "Grasshopper3 (type 4)");
            testCase.verifySubstring(message, "Blackfly (type 4)");

            backend = hadamard_stim.luminos.LuminosBackend(app, blue_threshold=15);
            testCase.verifyEmpty(backend.imaging_camera());
            testCase.verifyEmpty(backend.reference_snaps());
            testCase.verifyError(@() backend.geometry(), "hadamard_stim:NoImagingCamera");
        end

        function twoKinetixCamerasAreAmbiguous(testCase)
            app = hadamard_stim.testing.make_fake_luminos(testCase.Folder);
            second = hadamard_stim.testing.FakeLuminosCamera("Second Kinetix");
            second.type = 3;
            app.Devices{end + 1} = second;
            [devices, failures] = hadamard_stim.luminos.resolve_hardware(app, ...
                hadamard_stim.luminos.firefly_profile());
            testCase.verifyEmpty(devices.camera);
            testCase.verifySubstring(camera_failures(failures).message, "exactly one Kinetix");
        end

        function aRenamedKinetixDrivesTheAcquisitionPlan(testCase)
            % Its frames are frames<k> of its Luminos position, whatever its name.
            cfg = hadamard_stim.default_config();
            waveform = hadamard_stim.protocol.scan_waveform(cfg, 2.52, 0.47, 64, camera_rows=328);
            spec = hadamard_stim.protocol.acquisition_spec("z_stack_plane", "f", waveform, ...
                camera_exposure_ms=2.5);
            plan = hadamard_stim.luminos.camera_plan(spec, ["Kinetix" "Grasshopper3" "Blackfly"], ...
                hadamard_stim.luminos.firefly_profile(), "Kinetix");
            testCase.verifyEqual([plan.role], ["imaging" "behavior" "other"]);
            testCase.verifyEqual(plan(1).frametrigger_source, "External");
            testCase.verifyEqual(plan(1).frames_requested, 640);
        end

        function anotherCamerasActiveCalibrationIsReplacedByTheKinetixs(testCase)
            % At startup Luminos made another camera's calibration active; the
            % Kinetix has its own: Hadamard Stim selects it and draws.
            app = hadamard_stim.testing.make_fake_luminos(testCase.Folder);
            dmd = app.getDevice("ALP_DMD");
            dmd.ActiveIsPair = false;
            geometry = hadamard_stim.luminos.active_geometry(dmd, kinetix(app));
            testCase.verifyEqual(dmd.SelectedCamera, "Teledyne Kinetix");
            testCase.verifyTrue(geometry.identity.selected_by_hadamard_stim);
            testCase.verifyEqual(geometry.identity.camera, "Teledyne Kinetix");
        end

        function noKinetixCalibrationIsARefusalNeverAnotherCameras(testCase)
            app = hadamard_stim.testing.make_fake_luminos(testCase.Folder);
            dmd = app.getDevice("ALP_DMD");
            dmd.CalibratedCamera = "Some other camera";   % only another camera's is stored
            dmd.ActiveIsPair = true;                      % and it is the active one
            err = [];
            try
                hadamard_stim.luminos.active_geometry(dmd, kinetix(app));
            catch err
            end
            testCase.assertNotEmpty(err);
            testCase.verifyEqual(string(err.identifier), "hadamard_stim:NoDmdCalibration");
            testCase.verifySubstring(err.message, "no calibration for Teledyne Kinetix");
            testCase.verifySubstring(err.message, "migrate_dmd_calibration_camera");
            testCase.verifyEqual(dmd.SelectedCamera, "", "Nothing was selected for it.");
        end

        function theFormerNameCalibrationIsMovedOnceWithABackup(testCase)
            file = fullfile(testCase.Folder, "DMD_shared__AdditionalConfigData.mat");
            dmd = FakeCalibrationStoreDmd(file);
            kinetixT = affinetform2d([1.6 -0.2 40; 0.2 1.6 25; 0 0 1]);
            otherT = affinetform2d([1.1 0 3; 0 1.1 4; 0 0 1]);
            % Keyed as Patterning_Device.calibration_key does (makeValidName).
            store = struct("Kinetix", entry("Kinetix", kinetixT, 100), ...
                matlab.lang.makeValidName('Libra 5514 Pro'), entry("Libra 5514 Pro", otherT, 200));
            library = struct("old", entry("Kinetix", kinetixT, 50));
            dmd.additionalConfigData.set("calibrations", store);
            dmd.additionalConfigData.set("saved_calibrations", library);
            dmd.use_calibration_camera("Libra 5514 Pro");   % the most recent at startup

            dry = migrate_dmd_calibration_camera(dmd, "Kinetix", "Teledyne Kinetix", dry_run=true);
            testCase.verifyEqual(dry.status, "dry_run");
            testCase.verifyEmpty(dmd.get_calibration_entry("Teledyne Kinetix"));

            report = migrate_dmd_calibration_camera(dmd, "Kinetix", "Teledyne Kinetix");
            testCase.verifyEqual(report.status, "migrated");
            moved = dmd.get_calibration_entry("Teledyne Kinetix");
            testCase.verifyEqual(moved.tform.A, kinetixT.A, "The transform is unchanged.");
            testCase.verifyEqual(string(moved.camera), "Teledyne Kinetix");
            testCase.verifyEqual(string(moved.migrated_from), "Kinetix");
            testCase.verifyGreaterThan(moved.active_utc, 200, "It is now the most recent.");
            identity = dmd.calibration_identity("Teledyne Kinetix");
            testCase.verifyTrue(identity.active_transform_is_pair_transform, "Selected.");
            % Nothing else changed.
            after = dmd.calibration_store();
            testCase.verifyEqual(after.Kinetix, store.Kinetix);
            key = matlab.lang.makeValidName('Libra 5514 Pro');
            testCase.verifyEqual(after.(key), store.(key));
            testCase.verifyEqual(dmd.additionalConfigData.get("saved_calibrations"), library);
            % The backup is the file as it was.
            testCase.verifyTrue(isfile(report.backup));
            backup = load(report.backup, "-mat");
            testCase.verifyEqual(backup.data.calibrations, store);

            % Again: nothing to do.
            again = migrate_dmd_calibration_camera(dmd, "Kinetix", "Teledyne Kinetix");
            testCase.verifyEqual(again.status, "already_migrated");
        end

        function theMigrationRefusesWhatItCannotVouchFor(testCase)
            file = fullfile(testCase.Folder, "config.mat");
            dmd = FakeCalibrationStoreDmd(file);
            T = affinetform2d([1.6 0 40; 0 1.6 25; 0 0 1]);
            % No entry under the old name.
            testCase.verifyWarning(@() migrate_dmd_calibration_camera(dmd, "Kinetix", "Teledyne Kinetix"), ...
                "migrate_dmd_calibration_camera:Refused");
            % An identity transform (what Luminos writes when there is none).
            dmd.additionalConfigData.set("calibrations", ...
                struct("Kinetix", entry("Kinetix", affinetform2d(eye(3)), 1)));
            testCase.verifyWarning(@() migrate_dmd_calibration_camera(dmd, "Kinetix", "Teledyne Kinetix"), ...
                "migrate_dmd_calibration_camera:Refused");
            % An entry whose recorded camera is not its key.
            dmd.additionalConfigData.set("calibrations", ...
                struct("Kinetix", entry("Libra 5514 Pro", T, 1)));
            testCase.verifyWarning(@() migrate_dmd_calibration_camera(dmd, "Kinetix", "Teledyne Kinetix"), ...
                "migrate_dmd_calibration_camera:Refused");
            % The new name already calibrated, differently: left alone.
            other = affinetform2d([1.2 0 1; 0 1.2 2; 0 0 1]);
            dmd.additionalConfigData.set("calibrations", struct( ...
                "Kinetix", entry("Kinetix", T, 1), ...
                matlab.lang.makeValidName('Teledyne Kinetix'), entry("Teledyne Kinetix", other, 2)));
            testCase.verifyWarning(@() migrate_dmd_calibration_camera(dmd, "Kinetix", "Teledyne Kinetix"), ...
                "migrate_dmd_calibration_camera:Refused");
            kept = dmd.get_calibration_entry("Teledyne Kinetix");
            testCase.verifyEqual(kept.tform.A, other.A);
        end
    end
end

function f = camera_failures(failures)
f = failures(arrayfun(@(x) string(x.role) == "camera", failures));
end

function c = kinetix(app)
cameras = app.getDevice("Camera");
c = cameras(arrayfun(@(x) x.type == 3, cameras));
end

function e = entry(camera, tform, active)
e = struct("camera", char(camera), "tform", tform, "utc", active, "active_utc", active, ...
    "mode", "points", "bin", 1, "roi", [0 0 3200 3200]);
end
