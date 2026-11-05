classdef TestReferenceSnap < matlab.unittest.TestCase
    %TESTREFERENCESNAP A Luminos Snap (e.g. from the HiLo tab) as the reference image.
    %
    %   HiLo tab -> Snap -> load_reference_snap -> segment -> approve ->
    %   orange DMD mask -> preview / export. The Snap must be in the DMD
    %   calibration's camera grid (luminos.check_reference_snap) and is
    %   used exactly as saved. Loading needs no prepared rig (so no
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
                "another ROI origin",    testCase.writeSnap(im, roi=[8 0 448 328]), "IncompatibleSnap", "camera area"
                "another binning",       testCase.writeSnap(im(1:2:end, 1:2:end), bin=2), "IncompatibleSnap", "camera area"
                "another area",          testCase.writeSnap(im(1:300, 1:400), roi=[0 0 400 300]), "IncompatibleSnap", "camera area"
                "another calibration",   testCase.writeSnap(im, transform=[1 0 3; 0 1 0; 0 0 1]), "IncompatibleSnap", "another DMD calibration"
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
            % The calibration of the Hadamard tests (448 x 328): refused.
            testCase.verifyError(@() hadamard_stim.luminos.check_reference_snap(snap, dmd, "Teledyne Kinetix"), ...
                "hadamard_stim:IncompatibleSnap");
            % Calibrated at the Snap's area, with the Snap's transform: fits.
            dmd.refimage = struct("img", zeros(3200, 3200), "bin", 1);
            dmd.ReferenceRoi = [0 0 3200 3200];
            dmd.PairTransform = raw.snap.tform(1).tform;
            fit = hadamard_stim.luminos.check_reference_snap(snap, dmd, "Teledyne Kinetix");
            testCase.verifyTrue(fit.transform_recorded);
            testCase.verifyEqual(fit.grid, [3200 3200]);
            % The same area under another transform: taken under another calibration.
            dmd.PairTransform = affinetform2d([1 0 2; 0 1 0; 0 0 1]);
            testCase.verifyError(@() hadamard_stim.luminos.check_reference_snap(snap, dmd, "Teledyne Kinetix"), ...
                "hadamard_stim:IncompatibleSnap");
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
            file = fullfile(testCase.Folder, string(java.util.UUID.randomUUID()) + "_hilo_cam-TeledyneKinetix.mat");
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
