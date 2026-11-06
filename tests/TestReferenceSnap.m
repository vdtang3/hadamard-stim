classdef TestReferenceSnap < matlab.unittest.TestCase
    %TESTREFERENCESNAP A Luminos Snap (e.g. from the HiLo tab) as the reference image.
    %
    %   HiLo tab -> Snap -> load_reference_snap -> segment -> approve ->
    %   orange DMD mask -> preview / export. The Snap must be in the
    %   camera's acquisition grid (luminos.check_reference_snap) - any area,
    %   not only the DMD calibration's - and is used exactly as saved. Loading needs no prepared rig (so no
    %   Hadamard calibration scans) and touches no device. From the image
    %   on, it is the scan reference's path: the same cells and masks for
    %   the same image and geometry.

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
        function aSnapGivesTheMaskTheScanReferenceGives(testCase)
            % The acceptance test: the same image and DMD calibration, once
            % as a Hadamard reference scan on a prepared rig and once as a
            % Snap on an unprepared one, give the same cells and masks.
            [scan, ~] = testCase.session("scan");
            act(scan, "prepare_rig");
            use_parity_scans(scan, testCase.Root);
            for step = ["acquire_reference_image" "propose_cells" "approve_cells"]
                act(scan, step);
            end

            [c, app] = testCase.session("snap");
            file = testCase.writeSnap(scan.ReferenceImage);
            act(c, "load_reference_snap", struct("file", file));
            act(c, "propose_cells");
            act(c, "approve_cells");

            testCase.verifyFalse(c.hasEnvironment(), "The rig was never prepared.");
            for name = ["cell_coord" "excluded_coord" "min_val" "illum_rois" "stim_rois" "illum_mask" "stim_mask"]
                testCase.verifyEqual(c.Cells.(name), scan.Cells.(name), name);
            end
            testCase.verifyEqual(c.CellsGeometry, scan.CellsGeometry, ...
                "The same DMD calibration drew both.");

            % Exported, it is the array Luminos's DMD tab projects.
            stem = fullfile(testCase.Folder, "snap_orange_mask");
            act(c, "export_orange_mask", struct("file_stem", stem));
            saved = load(stem + ".mat");
            testCase.verifyEqual(saved.mask, scan.Cells.illum_mask);
            testCase.verifyEqual(saved.info.reference.source.kind, "snap");
            testCase.verifyEqual(saved.info.reference.source.file, file);
            testCase.verifyEqual(saved.info.reference.source.snap.type, "HiLo");
            testCase.verifyEqual(saved.info.dmd_calibration, scan.CellsGeometry);
            presets = fullfile(fileparts(testCase.Root), "luminos-private", "src", "Devices", ...
                "Patterning", "DMD", "Preset_pattern");
            if isfile(fullfile(presets, "pdHadamard_Stim_Orange_Mask.m"))
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(presets));
                loaded = pdHadamard_Stim_Orange_Mask(app.getDevice("ALP_DMD"), struct("maskFile", stem + ".mat"));
                testCase.verifyEqual(loaded, scan.Cells.illum_mask);
            end
            % The orange preview (a hardware session: it needs the prepared
            % rig, as for a scan reference) shows it.
            [p, papp] = testCase.session("snap_prepared");
            act(p, "prepare_rig");
            act(p, "load_reference_snap", struct("file", file));
            act(p, "propose_cells");
            act(p, "approve_cells");
            act(p, "start_orange_preview");
            testCase.verifyEqual(logical(papp.getDevice("ALP_DMD").Target), scan.Cells.illum_mask);
            act(p, "stop_orange_preview");
        end

        function loadingNeedsNoHadamardCalibrationAndTouchesNoHardware(testCase)
            % No calibration scans (Prepare would refuse) and commissioning
            % not passed: a Snap still loads, segments, approves and exports.
            [c, app] = testCase.session("bare", calibration_movies={}, validated=false);
            dmd = app.getDevice("ALP_DMD");
            before = snapshot(app);
            log_before = app.Log;
            n = numel(app.Acquisitions);
            testCase.verifyTrue(c.legalActions().load_reference_snap);
            act(c, "load_reference_snap", struct("file", testCase.writeSnap(testCase.image())));
            testCase.verifyTrue(c.legalActions().propose_cells);
            act(c, "propose_cells");
            act(c, "approve_cells");
            act(c, "export_orange_mask", struct("file_stem", fullfile(testCase.Folder, "bare_mask")));
            testCase.verifyEqual(c.LifecycleState, "CELLS_APPROVED");
            testCase.verifyGreaterThan(nnz(c.Cells.illum_mask), 0);
            testCase.verifyEqual(snapshot(app), before);
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyEqual(numel(app.Acquisitions), n);
            new_calls = setdiff(app.Log, log_before);
            testCase.verifyFalse(any(contains(new_calls, ["DMD" "LED" "Ownership" "Write" "set_level" "begin"])), ...
                strjoin(new_calls, ", "));
        end

        function theImageIsUsedExactlyAndItsSourceRecorded(testCase)
            [c, ~] = testCase.session("exact");
            image = uint16(round(testCase.image()));
            file = testCase.writeSnap(image);
            r = act(c, "load_reference_snap", struct("file", file));
            testCase.verifyClass(c.ReferenceImage, "double");
            testCase.verifyEqual(c.ReferenceImage, double(image));
            testCase.verifyEqual(r.state.reference.source, "snap");
            testCase.verifyEqual(r.state.reference.file, file);
            testCase.verifyEqual(r.state.reference.snap.type, "HiLo");
            testCase.verifyEqual(r.state.reference.snap.camera, "Teledyne Kinetix");
            testCase.verifyEqual(r.state.reference.snap.roi, [0 0 448 328]);
            testCase.verifyEqual(r.state.reference.snap.sha256, hadamard_stim.metadata.sha256(double(image)));
            testCase.verifyTrue(r.state.reference.snap.transform_recorded);
            testCase.verifyEqual(c.ReferenceSource.snap.provenance.source, "HiLo");
            % A new FOV forgets it.
            act(c, "propose_cells");
            act(c, "approve_cells");
            act(c, "new_session");
            testCase.verifyEmpty(c.ReferenceImage);
            testCase.verifyEqual(c.ReferenceSource.kind, "");
            testCase.verifyEmpty(c.CellsGeometry);
        end

        function incompatibleSnapsAreRefusedAndChangeNothing(testCase)
            [c, ~] = testCase.session("refused");
            im = testCase.image();
            cases = {
                "another camera",        testCase.writeSnap(im, name="Orca Fusion"), "IncompatibleSnap", "DMD is calibrated for Teledyne Kinetix"
                "transposed",            testCase.writeSnap(im'), "IncompatibleSnap", "transposed"
                "no binning recorded",   testCase.writeSnap(im, bin=NaN), "IncompatibleSnap", "binning is not recorded"
                "not finite",            testCase.writeSnap([NaN(1, 448); im(2:end, :)]), "InvalidSnap", "NaN"
                "a TIFF",                testCase.writeFile("snap.tiff"), "InvalidSnap", ".mat"
                "no snap",               testCase.writeFile("other.mat"), "InvalidSnap", "no variable"
                "missing",               fullfile(testCase.Folder, "absent.mat"), "InvalidSnap", "No Snap file"
            };
            for k = 1:size(cases, 1)
                revision = c.Revision;
                r = hadamard_stim.apply_controller_action(c, "load_reference_snap", ...
                    struct("file", cases{k, 2}), c.Revision);
                testCase.verifyFalse(r.ok, cases{k, 1});
                testCase.verifyEqual(r.identifier, "hadamard_stim:" + cases{k, 3}, cases{k, 1});
                testCase.verifySubstring(r.message, cases{k, 4}, cases{k, 1});
                testCase.verifyEmpty(c.ReferenceImage, cases{k, 1});
                testCase.verifyEqual(c.Revision, revision, cases{k, 1});
            end
            r = hadamard_stim.apply_controller_action(c, "load_reference_snap", struct(), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:NoSnapFile");
        end

        function otherAreasAndCalibrationsLoadWithANotice(testCase)
            % Another camera area or binning than the camera's now, or a
            % transform recorded under another active calibration (e.g. the
            % Libra's, reactivated at startup): the pixels are still placed
            % on the sensor, so the Snap loads, with a notice, and its cells
            % are drawn from its own area through the stored calibration.
            im = testCase.image();
            cases = {
                "another ROI origin",  testCase.writeSnap(im, roi=[8 0 448 328]), "run's images", [8 0 448 328], 1
                "another binning",     testCase.writeSnap(im(1:2:end, 1:2:end), bin=2), "run's images", [0 0 448 328], 2
                "another area",        testCase.writeSnap(im(1:300, 1:400), roi=[0 0 400 300]), "run's images", [0 0 400 300], 1
                "another calibration", testCase.writeSnap(im, transform=[1 0 3; 0 1 0; 0 0 1]), "stored Teledyne Kinetix calibration is used", [0 0 448 328], 1
            };
            for k = 1:size(cases, 1)
                [c, ~] = testCase.session("notice" + k);
                act(c, "load_reference_snap", struct("file", cases{k, 2}));
                testCase.verifySubstring(c.SetupNotice, cases{k, 3}, cases{k, 1});
                act(c, "propose_cells");
                testCase.verifySubstring(c.SetupNotice, cases{k, 3}, cases{k, 1} + ": kept through segmentation");
                testCase.verifyEqual(c.ProposalGeometry.camera_roi, cases{k, 4}, cases{k, 1});
                testCase.verifyEqual(c.ProposalGeometry.camera_bin, cases{k, 5}, cases{k, 1});
                act(c, "approve_cells");
                testCase.verifyGreaterThan(nnz(c.Cells.illum_mask), 0, cases{k, 1});
            end
        end

        function theCameraAreaChangingAfterApprovalDoesNotStopThePreview(testCase)
            % The mask is on the DMD already: a new camera area, or the
            % Kinetix calibration having been selected by Hadamard Stim (at
            % startup another camera's was active), does not move it.
            [p, app] = testCase.session("area_changed");
            dmd = app.getDevice("ALP_DMD");
            act(p, "prepare_rig");
            dmd.ActiveIsPair = false;     % another camera's calibration active
            act(p, "load_reference_snap", struct("file", testCase.writeSnap(testCase.image())));
            act(p, "propose_cells");
            act(p, "approve_cells");
            testCase.verifyEqual(dmd.SelectedCamera, "Teledyne Kinetix");
            cameras = app.getDevice("Camera");
            camera = cameras(strcmp([cameras.name], "Teledyne Kinetix"));
            camera.ROI = [64 320 40 240];
            camera.bin = 2;
            act(p, "start_orange_preview");
            testCase.verifyEqual(logical(dmd.Target), p.Cells.illum_mask);
            act(p, "stop_orange_preview");
        end

        function aSnapAtANewFieldOfViewNeedsNoRecalibration(testCase)
            % Once the animal is on: the camera at a smaller area, binned,
            % that the DMD was never calibrated at. The Snap taken there
            % loads, segments and draws through the same calibration.
            [c, app] = testCase.session("new_fov");
            cameras = app.getDevice("Camera");
            camera = cameras(strcmp([cameras.name], "Teledyne Kinetix"));
            camera.ROI = [64 320 40 240];     % [left width top height]
            camera.bin = 2;
            im = testCase.image();
            im = im(40 + (1:2:240), 64 + (1:2:320));
            file = testCase.writeSnap(im, roi=[64 40 320 240], bin=2);
            act(c, "load_reference_snap", struct("file", file));
            testCase.verifyEqual(c.ReferenceImage, im);
            act(c, "propose_cells");
            act(c, "approve_cells");
            testCase.verifyNotEmpty(c.Cells.illum_mask);
            testCase.verifyEqual(c.CellsGeometry.camera_roi, [64 40 320 240]);
            testCase.verifyEqual(c.CellsGeometry.camera_bin, 2);
            testCase.verifyNotEqual(c.CellsGeometry.drawn_by, "setPatterningROI");
            testCase.verifyFalse(c.CellsGeometry.extrapolated);
        end

        function aDmdWithoutCalibrationRefusesTheSnap(testCase)
            [c, app] = testCase.session("uncalibrated");
            app.getDevice("ALP_DMD").CalibratedCamera = "Grasshopper3";
            r = hadamard_stim.apply_controller_action(c, "load_reference_snap", ...
                struct("file", testCase.writeSnap(testCase.image())), c.Revision);
            testCase.verifyFalse(r.ok);
            testCase.verifySubstring(r.message, "has no calibration for Teledyne Kinetix");
        end

        function aSnapWithoutATransformLoadsAndSaysSo(testCase)
            [c, ~] = testCase.session("untransformed");
            r = act(c, "load_reference_snap", struct("file", ...
                testCase.writeSnap(testCase.image(), transform=[])));
            testCase.verifyFalse(r.state.reference.snap.transform_recorded);
        end

        function aDriftCorrectedRunCannotUseASnapReference(testCase)
            % Drift correction registers Hadamard scans to the reference
            % image; a Snap is not one. Cells and the mask are fine.
            [c, ~] = testCase.session("drift");
            act(c, "load_reference_snap", struct("file", testCase.writeSnap(testCase.image())));
            act(c, "propose_cells");
            act(c, "approve_cells");
            blockers = [c.getState().readiness.blockers.id];
            testCase.verifyTrue(ismember("reference_kind", blockers));
            testCase.verifyFalse(c.legalActions().start_run);

            cfg = c.Config;
            cfg.session.mode = "spontaneous";
            cfg.spontaneous.drift_correction = false;
            act(c, "set_config", struct("config", cfg));
            ids = [c.getState().readiness.checks.id];
            testCase.verifyFalse(ismember("reference_kind", ids), ...
                "Without drift correction the reference image is only where the cells came from.");
        end

        function theCameraSnapsAreListedNewestFirst(testCase)
            [c, app] = testCase.session("listing");
            today = fullfile(testCase.Folder, "data", "20261103");
            yesterday = fullfile(testCase.Folder, "data", "20261102");
            mkdir(fullfile(today, "Snaps"));
            mkdir(fullfile(yesterday, "Snaps"));
            app.datafolder = today;
            files = [fullfile(yesterday, "Snaps", "101010_hilo_cam-TeledyneKinetix.mat")
                fullfile(today, "Snaps", "090000_cam-TeledyneKinetix.mat")
                fullfile(today, "Snaps", "120000_hilo_cam-TeledyneKinetix.mat")
                fullfile(today, "Snaps", "130000_cam-Grasshopper3.mat")
                fullfile(today, "Snaps", "temp.mat")];
            stamps = datetime(2026, 11, [2 3 3 3 3], [10 9 12 13 14], 0, 0);
            for k = 1:numel(files)
                fclose(fopen(files(k), "w"));
                touch(files(k), stamps(k));
            end
            view = hadamard_stim.controller_view(c, "reference_snaps");
            testCase.verifyTrue(view.ok, view.message);
            testCase.verifyEqual([view.data.file], files([3 2 1])');
            testCase.verifyEqual(view.data(1).name, "20261103/120000_hilo_cam-TeledyneKinetix.mat");
        end

        function aRealFireflySnapIsReadAndCheckedAgainstItsArea(testCase)
            % A Camera Snap from Firefly (20261030, full sensor, Teledyne
            % Kinetix): read as Luminos wrote it, and fitted only where the
            % DMD calibration's area and transform are the Snap's.
            file = "/mnt/cohen-lab/Lab/Labmembers/Vincent Tang/data/firefly/20261030/Snaps/161218_cam-TeledyneKinetix.mat";
            classes = fullfile(fileparts(testCase.Root), "luminos-private", "src", "utils", "Data_Structures");
            testCase.assumeTrue(isfile(file) && isfolder(classes), "The Firefly Snap or Luminos is not available.");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(classes));
            [image, snap] = hadamard_stim.luminos.read_reference_snap(file);
            raw = load(file, "snap");
            testCase.verifyEqual(image, double(raw.snap.img));
            testCase.verifyEqual(snap.name, "Teledyne Kinetix");
            testCase.verifyEqual(snap.roi, [0 0 3200 3200]);
            testCase.verifyEqual(snap.bin, 1);
            testCase.verifyEqual(snap.transforms(1).name, "DMD (shared)");
            testCase.verifyEqual(snap.transforms(1).matrix, raw.snap.tform(1).tform.T');

            dmd = hadamard_stim.testing.FakeAlpDmd("DMD (shared)");
            dmd.PairTransform = raw.snap.tform(1).tform;
            % Calibrated on a 448 x 328 area, the camera acquiring the full
            % sensor as the Snap was: fits, no recalibration at the Snap's area.
            fit = hadamard_stim.luminos.check_reference_snap(snap, dmd, "Teledyne Kinetix", [0 0 3200 3200], 1);
            testCase.verifyTrue(fit.transform_recorded);
            testCase.verifyEqual(fit.grid, [3200 3200]);
            testCase.verifyEqual(fit.calibration_roi, [0 0 448 328]);
            % The camera now acquires another area: the Snap's pixels are not
            % the run's.
            fit = hadamard_stim.luminos.check_reference_snap(snap, dmd, "Teledyne Kinetix", [0 0 448 328], 1);
            testCase.verifyNotEmpty(fit.warnings);
            % Under another transform: taken under another calibration, said.
            dmd.PairTransform = affinetform2d([1 0 2; 0 1 0; 0 0 1]);
            fit = hadamard_stim.luminos.check_reference_snap(snap, dmd, "Teledyne Kinetix", [0 0 3200 3200], 1);
            testCase.verifyFalse(fit.transform_matches);
        end
    end

    methods
        function [c, app] = session(testCase, name, options)
            arguments
                testCase
                name (1, 1) string
                options.calibration_movies cell = {[]}
                options.validated (1, 1) logical = true
            end
            [c, app, cfg] = tab_session(fullfile(testCase.Folder, name), ...
                calibration_movies=options.calibration_movies, validated=options.validated);
            act(c, "set_config", struct("config", cfg));
        end

        function im = image(testCase)
            % His reference image: what the scan reference reconstructs to.
            [~, ~, ~, inputs] = parity_environment(fullfile(testCase.Root, "tests", "fixtures"));
            im = double(inputs.ref_im);
        end

        function file = writeSnap(testCase, image, options)
            % A Snap as create_hilo_snap writes it, as a struct (the fields
            % of a CL_RefImage). Defaults fit the fake DMD's calibration:
            % Teledyne Kinetix, 448 x 328 at x 0, y 0, bin 1, identity.
            arguments
                testCase
                image
                options.name (1, 1) string = "Teledyne Kinetix"
                options.roi (1, 4) double = [0 0 448 328]
                options.bin (1, 1) double = 1
                options.transform = eye(3)
                options.pixel_to_sample_um = []
            end
            snap = struct();
            snap.img = image;
            snap.bin = options.bin;
            snap.type = 'HiLo';
            snap.name = char(options.name);
            snap.timestamp = datetime(2026, 11, 3, 12, 0, 0);
            snap.ref2d = struct("ImageSize", size(image), ...
                "XWorldLimits", options.roi(1) + [0 options.roi(3)], ...
                "YWorldLimits", options.roi(2) + [0 options.roi(4)]);
            snap.tform = [];
            if ~isempty(options.transform)
                snap.tform = struct("name", {'DMD (shared)', 'Other DMD'}, ...
                    "tform", {affinetform2d(options.transform), affinetform2d([2 0 0; 0 2 0; 0 0 1])});
            end
            snap.provenance = struct("source", "HiLo", "mode", "current_plane");
            if ~isempty(options.pixel_to_sample_um)
                snap.pixel_to_sample_um = options.pixel_to_sample_um;
            end
            file = fullfile(testCase.Folder, string(java.util.UUID.randomUUID()) + "_hilo_cam-" ...
                + regexprep(options.name, "[^A-Za-z0-9]", "") + ".mat");
            save(file, "snap", "-v7.3");
        end

        function file = writeFile(testCase, name)
            file = fullfile(testCase.Folder, name);
            other = 1; %#ok<NASGU>
            if endsWith(name, ".mat")
                save(file, "other");
            else
                fclose(fopen(file, "w"));
            end
        end
    end
end

function r = act(c, action, payload)
if nargin < 3
    payload = struct();
end
r = hadamard_stim.apply_controller_action(c, action, payload, c.Revision);
assert(r.ok, "%s: %s", action, r.message);
end

function touch(file, when)
% Give a file a modification time (Linux and macOS).
[status, out] = system(sprintf('touch -d "%s" "%s"', string(when, "yyyy-MM-dd HH:mm:ss"), file));
assert(status == 0, out);
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
end
