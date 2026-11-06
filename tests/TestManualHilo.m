classdef TestManualHilo < matlab.unittest.TestCase
    %TESTMANUALHILO The manual HiLo tools: patterns, reconstruction from two Snaps, segmentation and mask.
    %
    %   manual_hilo_patterns / manual_hilo_display: Luminos's own HiLo
    %   patterns on the DMD canvas, shown by Target + Write_Static.
    %   manual_hilo_reconstruct: Luminos's reconstruct_hilo, offline, on two
    %   Snaps; its file is a Snap the Hadamard Stim tab loads.
    %   manual_segment_dmd: the tab's segmentation and orange mask, from any
    %   image that records its camera area. None of them acquires or triggers.
    %   Tests that run Luminos's HiLo code need luminos-private beside this
    %   repository and are skipped without it.

    properties
        Root
        Folder
        LuminosHiLo
    end

    methods (TestClassSetup)
        function setUp(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
            luminos = fullfile(fileparts(testCase.Root), "luminos-private", "src");
            testCase.LuminosHiLo = fullfile(luminos, "Experimental_Scripts", "HiLo");
            if isfolder(testCase.LuminosHiLo)
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.LuminosHiLo));
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                    fullfile(luminos, "utils", "Data_Structures")));
            end
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
        % ---- Script 1: patterns ------------------------------------------

        function thePatternsAreTheHiLoTabsOnTheDmdCanvas(testCase)
            testCase.needLuminos();
            dmd = hadamard_stim.testing.FakeAlpDmd("DMD (shared)");
            canvas = dmd.Pattern_Canvas_Size();
            before = rng;
            file = fullfile(testCase.Folder, "patterns.mat");
            p = manual_hilo_patterns(dmd, blockSize=8, seed=0, output=file);
            testCase.verifyEqual(rng, before, "MATLAB's global stream is not touched.");
            testCase.verifyEqual(size(p.uniform), canvas, "[rows columns] of the canvas");
            testCase.verifyEqual(size(p.structured), canvas);
            testCase.verifyClass(p.structured, "logical");
            testCase.verifyTrue(all(p.uniform(:)), "U is the whole canvas without a camera.");
            testCase.verifyEqual(p.structured, generate_hilo_pattern(true(canvas), 0, 2, block_size=8));
            % 8 x 8 mirror blocks from the top-left mirror, about half on.
            blocks = p.structured(1:8:end, 1:8:end);
            testCase.verifyEqual(p.structured, logical(repelem(blocks, 8, 8)));
            testCase.verifyEqual(nnz(p.structured) / numel(p.structured), 0.5, "AbsTol", 0.03);
            saved = load(file, "patterns");
            testCase.verifyEqual(saved.patterns.structured, p.structured);
            testCase.verifyEqual(saved.patterns.params.seed, 0);
            testCase.verifyEqual(saved.patterns.params.block_size, 8);
            testCase.verifyEqual(saved.patterns.params.structured_sha256, ...
                hadamard_stim.metadata.sha256(p.structured));
            % The same seed again: the same pattern. Another seed: another.
            again = manual_hilo_patterns(dmd, blockSize=8, seed=0, output="none");
            testCase.verifyEqual(again.structured, p.structured);
            other = manual_hilo_patterns(dmd, blockSize=8, seed=1, output="none");
            testCase.verifyNotEqual(other.structured, p.structured);
        end

        function withACameraUIsTheTabsFieldMaskAndSIsItsFirstPlane(testCase)
            % As run_hilo_acquisition: U = hilo_fov_mask(dmd, camera, 0.05),
            % plane 1's S = generate_hilo_pattern(U, seed, 2) (block 1).
            testCase.needLuminos();
            dmd = LuminosWarpDmd("DMD (shared)");
            dmd.PairTransform = struct("A", [1.6 0 40; 0 1.6 25; 0 0 1]);
            camera = hadamard_stim.testing.FakeLuminosCamera("Teledyne Kinetix");
            camera.ROI = [0 300 0 200];
            p = manual_hilo_patterns(dmd, seed=1234, camera=camera, output="none");
            tab_u = hilo_fov_mask(dmd, struct("name", "Teledyne Kinetix", "roi", camera.ROI, "bin", 1), 0.05);
            testCase.verifyEqual(p.uniform, tab_u);
            testCase.verifyFalse(all(p.uniform(:)));
            testCase.verifyEqual(p.structured, generate_hilo_pattern(tab_u, 1234, 2));
            testCase.verifyFalse(any(p.structured(:) & ~p.uniform(:)), "S lies inside U.");
        end

        function aPatternIsShownAsTheDmdTabShowsOne(testCase)
            dmd = hadamard_stim.testing.FakeAlpDmd("DMD (shared)");
            canvas = dmd.Pattern_Canvas_Size();
            pattern = false(canvas);
            pattern(1:8, 1:16) = true;
            manual_hilo_display(dmd, pattern);
            testCase.verifyEqual(dmd.Target, pattern);
            testCase.verifyEqual(dmd.Displaying, "static");
            manual_hilo_display(dmd, "dark");
            testCase.verifyEqual(dmd.Displaying, "dark");
            % A mask file (variable "mask"), as manual_segment_dmd and the tab write.
            file = fullfile(testCase.Folder, "mask.mat");
            mask = false(canvas);
            mask(100:140, 200:260) = true;
            save(file, "mask");
            manual_hilo_display(dmd, file);
            testCase.verifyEqual(dmd.Target, mask);
            % Never resized, never over a protocol that holds the DMD.
            testCase.verifyError(@() manual_hilo_display(dmd, pattern'), "hadamard_stim:PatternSize");
            dmd.Claim_Pattern_Ownership("hadamard_stim");
            testCase.verifyError(@() manual_hilo_display(dmd, pattern), "hadamard_stim:DmdOwned");
        end

        % ---- Script 2: reconstruction --------------------------------------

        function theReconstructionIsTheTabsOnTwoSnaps(testCase)
            testCase.needLuminos();
            [U, S, roi, bin] = testCase.pair();
            scale = [0.5 0.01; -0.01 0.5];
            snaps = fullfile(testCase.Folder, "data", "20261106", "Snaps");
            u = testCase.writeSnap(U, folder=snaps, stem="101500", roi=roi, bin=bin, pixel_to_sample_um=scale);
            s = testCase.writeSnap(S, folder=snaps, stem="101530", roi=roi, bin=bin, pixel_to_sample_um=scale);
            r = manual_hilo_reconstruct(u, s, filterScale=2, cameraOffset=100, show=false);

            tab = reconstruct_hilo(U, S, struct("target_thickness_px", 2, "camera_offset_adu", 100, ...
                "n_averaged", 1, "sample_pixel_um", sqrt(abs(det(scale)))));
            testCase.verifyEqual(r.hilo, tab.hilo, "The tab's numbers, exactly.");
            testCase.verifyEqual(r.params, tab.params);
            testCase.verifyEqual(size(r.hilo), size(U), "Nothing cropped or resampled.");

            % The .mat is a Snap of the HiLo image at the snapshots' area.
            [image, snap] = hadamard_stim.luminos.read_reference_snap(r.files.mat);
            testCase.verifyEqual(image, r.hilo);
            testCase.verifyEqual(snap.name, "Teledyne Kinetix");
            testCase.verifyEqual(snap.type, "HiLo");
            testCase.verifyEqual(snap.roi, roi);
            testCase.verifyEqual(snap.bin, bin);
            testCase.verifyEqual(snap.pixel_to_sample_um, scale);
            testCase.verifyEqual(snap.transforms(1).name, "DMD (shared)");
            testCase.verifyEqual(snap.transforms(1).matrix, eye(3));
            testCase.verifyEqual(snap.provenance.uniform.source, u);
            testCase.verifyMatches(r.files.mat, "_hilo-manual_cam-TeledyneKinetix\.mat$");
            testCase.verifyEqual(fileparts(r.files.mat), snaps, "Beside the snapshots.");
            % The TIFF: the same numbers (float32) and the same area.
            testCase.verifyEqual(double(imread(r.files.tif)), double(single(r.hilo)));
            [~, tiffMeta] = hadamard_stim.manual.read_image(r.files.tif);
            testCase.verifyEqual(tiffMeta.geometry_from, "tiff");
            for name = ["name" "roi" "bin" "pixel_to_sample_um"]
                testCase.verifyEqual(tiffMeta.(name), snap.(name), name);
            end
            testCase.verifyEqual(tiffMeta.transforms(1).matrix, eye(3));
        end

        function luminosTiffsAndArraysGiveTheSameImage(testCase)
            testCase.needLuminos();
            [U, S, roi, bin] = testCase.pair();
            U = double(uint16(U));     % camera counts, as the TIFF holds them
            S = double(uint16(S));
            u = testCase.writeSnap(U, stem="u", roi=roi, bin=bin, tiff=true);
            s = testCase.writeSnap(S, stem="s", roi=roi, bin=bin, tiff=true);
            fromMat = manual_hilo_reconstruct(u, s, show=false, output="none");
            % The Snap's .tiff, its .mat beside it.
            fromTiff = manual_hilo_reconstruct(replace(u, ".mat", ".tiff"), replace(s, ".mat", ".tiff"), ...
                show=false, output="none");
            testCase.verifyEqual(fromTiff.hilo, fromMat.hilo);
            testCase.verifyEqual(fromTiff.meta.roi, roi);
            % Arrays with their area given.
            fromArrays = manual_hilo_reconstruct(U, S, cameraName="Teledyne Kinetix", roi=roi, bin=bin, ...
                show=false, output=fullfile(testCase.Folder, "arrays"));
            testCase.verifyEqual(fromArrays.hilo, fromMat.hilo);
            [~, snap] = hadamard_stim.luminos.read_reference_snap(fromArrays.files.mat);
            testCase.verifyEqual(snap.roi, roi);
            % An area given that the Snap contradicts is refused.
            testCase.verifyError(@() manual_hilo_reconstruct(u, s, roi=[0 0 448 328], show=false, ...
                output="none"), "hadamard_stim:ManualImage");
        end

        function snapshotsThatDoNotPairAreRefused(testCase)
            testCase.needLuminos();
            [U, S, roi, bin] = testCase.pair();
            u = testCase.writeSnap(U, stem="u", roi=roi, bin=bin);
            testCase.verifyError(@() manual_hilo_reconstruct(U, S(1:end - 1, :), show=false), ...
                "hadamard_stim:ManualHiLo");
            moved = testCase.writeSnap(S, stem="s", roi=roi + [2 0 0 0], bin=bin);
            testCase.verifyError(@() manual_hilo_reconstruct(u, moved, show=false, output="none"), ...
                "hadamard_stim:ManualHiLo");
            % One frame of its area or nothing: a transposed image is refused.
            testCase.verifyError(@() manual_hilo_reconstruct(U', S', cameraName="Teledyne Kinetix", ...
                roi=roi, bin=bin, show=false), "hadamard_stim:ManualImage");
        end

        function withoutACameraAreaTheResultIsNoSnap(testCase)
            testCase.needLuminos();
            [U, S] = testCase.pair();
            stem = fullfile(testCase.Folder, "bare");
            testCase.verifyWarning(@() manual_hilo_reconstruct(U, S, show=false, output=stem), ...
                "hadamard_stim:ManualHiLoNoArea");
            testCase.verifyFalse(ismember("snap", string({whos("-file", stem + ".mat").name})));
            testCase.verifyError(@() hadamard_stim.luminos.read_reference_snap(stem + ".mat"), ...
                "hadamard_stim:InvalidSnap");
            % Segmentation still works; the DMD is refused, not guessed.
            dmd = hadamard_stim.testing.FakeAlpDmd("DMD (shared)");
            testCase.verifyError(@() manual_segment_dmd(stem + ".mat", dmd, nExclude=0, threshold=20, ...
                show=false, output="none"), "hadamard_stim:ManualNoArea");
            seg = manual_segment_dmd(stem + ".mat", [], nExclude=0, threshold=20, show=false, output="none");
            testCase.verifyNotEmpty(seg.cells.cell_coord);
            testCase.verifyEmpty(seg.mask);
        end

        function aReconstructionLoadsIntoTheTabWithoutAnotherSnap(testCase)
            % HiLo -> Hadamard Stim tab: listed among the Kinetix's Snaps,
            % loaded, segmented, approved, the orange mask exported - no
            % camera image taken. The camera acquires at the snapshots'
            % (cropped, binned) area, as it did when they were taken.
            testCase.needLuminos();
            [U, S, roi, bin] = testCase.pair();
            [c, app] = testCase.tab(roi, bin);
            snaps = fullfile(string(app.datafolder), "Snaps");
            u = testCase.writeSnap(U, folder=snaps, stem="101500", roi=roi, bin=bin);
            s = testCase.writeSnap(S, folder=snaps, stem="101530", roi=roi, bin=bin);
            r = manual_hilo_reconstruct(u, s, show=false);
            listed = hadamard_stim.controller_view(c, "reference_snaps");
            testCase.verifyTrue(ismember(r.files.mat, [listed.data.file]), "Listed with the camera's Snaps.");

            n = numel(app.Acquisitions);
            act(c, "load_reference_snap", struct("file", r.files.mat));
            testCase.verifyEqual(c.ReferenceImage, r.hilo);
            act(c, "propose_cells");
            act(c, "approve_cells");
            testCase.verifyEqual(numel(app.Acquisitions), n, "No image was acquired.");
            testCase.verifyEqual(c.CellsGeometry.camera_roi, roi);
            testCase.verifyEqual(c.CellsGeometry.camera_bin, bin);

            % Script 3 on the same file: the same cells and the same mask.
            seg = c.Config.segmentation;
            m = manual_segment_dmd(r.files.mat, app.getDevice("ALP_DMD"), nExclude=seg.n_exclude, ...
                threshold=seg.threshold, show=false, output=fullfile(testCase.Folder, "manual_mask"));
            for name = ["cell_coord" "excluded_coord" "min_val" "illum_rois" "stim_rois"]
                testCase.verifyEqual(m.cells.(name), c.Cells.(name), name);
            end
            testCase.verifyEqual(m.mask, c.Cells.illum_mask);
            testCase.verifyEqual(m.stim_mask, c.Cells.stim_mask);
            testCase.verifyEqual(m.geometry, c.CellsGeometry, "The same calibration, the same area.");
            % Its file is the tab's export format.
            stem = fullfile(testCase.Folder, "tab_mask");
            act(c, "export_orange_mask", struct("file_stem", stem));
            tabFile = load(stem + ".mat");
            manualFile = load(m.files.mat);
            testCase.verifyEqual(manualFile.mask, tabFile.mask);
            testCase.verifyEqual(manualFile.info.mask_sha256, tabFile.info.mask_sha256);
            testCase.verifyEqual(manualFile.info.canvas_size, tabFile.info.canvas_size);
        end

        % ---- Script 3: segmentation and mask --------------------------------

        function theSegmentationAndMaskAreTheTabs(testCase)
            % No Luminos needed: a Snap written as Luminos writes one.
            [c, app] = testCase.tab([0 0 448 328], 1);
            image = testCase.image();
            file = testCase.writeSnap(image, folder=fullfile(string(app.datafolder), "Snaps"), stem="120000", ...
                roi=[0 0 448 328], bin=1);
            act(c, "load_reference_snap", struct("file", file));
            act(c, "propose_cells");
            act(c, "approve_cells");
            seg = c.Config.segmentation;
            dmd = app.getDevice("ALP_DMD");
            log_before = app.Log;
            m = manual_segment_dmd(file, dmd, nExclude=seg.n_exclude, threshold=seg.threshold, show=false);
            testCase.verifyEqual(m.cells.cell_coord, c.Cells.cell_coord);
            testCase.verifyEqual(m.mask, c.Cells.illum_mask);
            testCase.verifyEqual(m.kept, 1:size(c.Cells.cell_coord, 1));
            testCase.verifyEqual(m.files.mat, replace(file, ".mat", "_orange_mask.mat"));
            saved = load(m.files.mat);
            testCase.verifyEqual(saved.mask, c.Cells.illum_mask);
            testCase.verifyEqual(saved.segmentation.cells.cell_coord, c.Cells.cell_coord);
            testCase.verifyEqual(saved.info.image.sha256, hadamard_stim.metadata.sha256(image));
            new_calls = setdiff(app.Log, log_before);
            testCase.verifyFalse(any(contains(new_calls, ["Write" "LED" "set_level" "begin" "Ownership" "Queue"])), ...
                strjoin(new_calls, ", "));
            testCase.verifyNotEqual(dmd.Displaying, "static", "Nothing was projected.");

            % Some cells dropped: the mask of the rest, drawn by the same rules.
            keep = [1 3 5 8];
            k = manual_segment_dmd(file, dmd, nExclude=seg.n_exclude, threshold=seg.threshold, keep=keep, ...
                show=false, output="none");
            subset = hadamard_stim.protocol.draw_cells(struct("cell_coord", c.Cells.cell_coord(keep, :)), ...
                seg, hadamard_stim.luminos.active_geometry(dmd, struct("name", "Teledyne Kinetix", ...
                "roi", [0 0 448 328], "bin", 1)));
            testCase.verifyEqual(k.mask, subset.illum_mask);
            testCase.verifyFalse(any(k.mask(:) & ~c.Cells.illum_mask(:)));
            testCase.verifyLessThan(nnz(k.mask), nnz(c.Cells.illum_mask));

            % upload: shown as the tab's preview shows it.
            manual_segment_dmd(file, dmd, nExclude=seg.n_exclude, threshold=seg.threshold, keep=keep, ...
                show=false, output="none", upload=true);
            testCase.verifyEqual(logical(dmd.Target), k.mask);
            testCase.verifyEqual(dmd.Displaying, "static");
        end

        function aCroppedBinnedImageLandsWhereItWasOnTheSensor(testCase)
            % A cell found in a cropped, binned image is drawn at the DMD
            % position the calibration gives its unbinned sensor position.
            dmd = LuminosWarpDmd("DMD (shared)");
            theta = deg2rad(7);
            A = [1.6 * cos(theta), -1.6 * sin(theta), 40; 1.6 * sin(theta), 1.6 * cos(theta), 25; 0 0 1];
            dmd.PairTransform = struct("A", A);
            full = testCase.image();
            roi = [64 40 320 240];
            bin = 2;
            crop = full(roi(2) + (1:roi(4)), roi(1) + (1:roi(3)));
            binned = (crop(1:2:end, 1:2:end) + crop(2:2:end, 1:2:end) + crop(1:2:end, 2:2:end) ...
                + crop(2:2:end, 2:2:end)) / 4;
            file = testCase.writeSnap(binned, stem="cropped", roi=roi, bin=bin, transform=A);
            m = manual_segment_dmd(file, dmd, nExclude=0, threshold=40, keep=1, show=false, output="none");
            testCase.verifyEqual(m.geometry.camera_roi, roi);
            testCase.verifyEqual(m.geometry.camera_bin, bin);
            local = m.cells.cell_coord(1, :);
            sensor = roi(1:2) + local * bin;
            expected = A * [sensor 1]';
            [rows, cols] = find(m.mask);
            testCase.verifyLessThan(norm([mean(cols) mean(rows)] - expected(1:2)'), 4, ...
                "The spot sits where the calibration puts its sensor position.");
        end

        function onlyTheKinetixCalibrationIsUsed(testCase)
            dmd = hadamard_stim.testing.FakeAlpDmd("DMD (shared)");
            dmd.CalibratedCamera = "Libra 5514 Pro";
            file = testCase.writeSnap(testCase.image(), stem="libra", name="Libra 5514 Pro");
            testCase.verifyError(@() manual_segment_dmd(file, dmd, nExclude=0, show=false, output="none"), ...
                "hadamard_stim:ManualNotKinetix");
            testCase.verifyEqual(dmd.SelectedCamera, "", "No calibration was selected.");
            % A Kinetix image on a DMD with no Kinetix calibration: refused.
            file = testCase.writeSnap(testCase.image(), stem="kinetix");
            testCase.verifyError(@() manual_segment_dmd(file, dmd, nExclude=0, show=false, output="none"), ...
                "hadamard_stim:IncompatibleSnap");
        end

        function noToolAcquiresOrTriggers(testCase)
            % The manual tools name no camera, DAQ or trigger API.
            files = [fullfile(testCase.Root, ["manual_hilo_patterns.m" "manual_hilo_display.m" ...
                "manual_hilo_reconstruct.m" "manual_segment_dmd.m"]), ...
                string(fullfile(testCase.Root, "+hadamard_stim", "+manual", {dir(fullfile(testCase.Root, ...
                "+hadamard_stim", "+manual", "*.m")).name}))];
            forbidden = ["Snap(" "Prepare_Sync_Aq" "Start_Acquisition" "Waveform_Camera_Sync_Acquisition" ...
                "frametrigger_source" "frames_requested" "exposuretime" "wfm_data" "global_props" ...
                "Write_Stack" "Load_Sequence_Queue" "trigger_channel" "set_level"];
            for f = files
                code = strjoin(readlines(f), newline);
                code = regexprep(code, "(?m)^\s*%.*$", "");    % comments may name them
                for name = forbidden
                    testCase.verifyFalse(contains(code, name), f + " calls " + name);
                end
            end
        end
    end

    methods
        function needLuminos(testCase)
            testCase.assumeTrue(exist("reconstruct_hilo", "file") == 2, ...
                "Luminos's HiLo code (luminos-private beside this repository) is not available.");
        end

        function [c, app] = tab(testCase, roi, bin)
            % The tab on a fake Firefly, the Kinetix acquiring at roi
            % ([x0 y0 width height]) and bin, as when the images were taken.
            [c, app, cfg] = tab_session(fullfile(testCase.Folder, "tab"));
            act(c, "set_config", struct("config", cfg));
            cameras = app.getDevice("Camera");
            camera = cameras(strcmp([cameras.name], "Teledyne Kinetix"));
            app.datafolder = fullfile(testCase.Folder, "data", "20261106");
            mkdir(fullfile(app.datafolder, "Snaps"));
            camera.ROI = roi([1 3 2 4]);      % Luminos: [left width top height]
            camera.bin = bin;
        end

        function im = image(testCase)
            % His reference image (448 x 328), which has cells to find.
            [~, ~, ~, inputs] = parity_environment(fullfile(testCase.Root, "tests", "fixtures"));
            im = double(inputs.ref_im);
        end

        function [U, S, roi, bin] = pair(testCase)
            % U and S of his field, cropped and binned as on the rig: S
            % under a 4 x 4 random block pattern (half the light).
            roi = [64 40 320 240];
            bin = 2;
            full = testCase.image();
            crop = full(roi(2) + (1:roi(4)), roi(1) + (1:roi(3)));
            U = 100 + (crop(1:2:end, 1:2:end) + crop(2:2:end, 1:2:end) + crop(1:2:end, 2:2:end) ...
                + crop(2:2:end, 2:2:end));
            stream = RandStream("mrg32k3a", "Seed", 7);
            pattern = repelem(rand(stream, ceil(size(U) / 4)) >= 0.5, 4, 4);
            pattern = pattern(1:size(U, 1), 1:size(U, 2));
            S = round(100 + (U - 100) .* (0.1 + 0.9 * pattern));   % camera counts
            U = round(U);
        end

        function file = writeSnap(testCase, image, options)
            % A Snap as Luminos's Camera_Snap writes it (a struct with a
            % CL_RefImage's fields), at <folder>/<stem>_cam-<camera>.mat;
            % with tiff, its .tiff beside it.
            arguments
                testCase
                image
                options.folder (1, 1) string = testCase.Folder
                options.stem (1, 1) string = "snap"
                options.name (1, 1) string = "Teledyne Kinetix"
                options.roi (1, 4) double = [0 0 448 328]
                options.bin (1, 1) double = 1
                options.transform = eye(3)
                options.pixel_to_sample_um = []
                options.tiff (1, 1) logical = false
            end
            if ~isfolder(options.folder)
                mkdir(options.folder);
            end
            if options.tiff
                image = uint16(image);    % what the camera gives; the .tiff and .mat agree
            end
            snap = struct();
            snap.img = image;
            snap.bin = options.bin;
            snap.type = 'Camera';
            snap.name = char(options.name);
            snap.timestamp = datetime(2026, 11, 6, 10, 15, 0);
            snap.ref2d = struct("ImageSize", size(image), ...
                "XWorldLimits", options.roi(1) + [0 options.roi(3)], ...
                "YWorldLimits", options.roi(2) + [0 options.roi(4)]);
            snap.tform = struct("name", {'DMD (shared)'}, "tform", {affinetform2d(options.transform)});
            snap.pixel_to_sample_um = options.pixel_to_sample_um;
            stem = fullfile(options.folder, options.stem + "_cam-" + regexprep(options.name, "[^A-Za-z0-9]", ""));
            file = stem + ".mat";
            save(file, "snap", "-v7.3");
            if options.tiff
                imwrite(image, stem + ".tiff");
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
