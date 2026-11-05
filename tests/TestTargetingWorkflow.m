classdef TestTargetingWorkflow < matlab.unittest.TestCase
    %TESTTARGETINGWORKFLOW Reference -> segment -> approve -> preview/export, at any cell count.
    %
    %   2026-11-04 (docs/notebook.md): segmentation's settings are
    %   configurable (cells to keep or all, the candidate pool, the region
    %   size, the filter size) with his values as defaults; targeting (the
    %   orange preview and the mask export) needs no prepared rig and no
    %   stimulation matrix; preparing keeps the reference image and the
    %   cells unless the DMD calibration changed; changing a segmentation
    %   setting discards the cells explicitly. A run still needs exactly
    %   matrix.order approved cells, and a matrix order MATLAB's hadamard
    %   can build.

    properties
        Root
        Folder
        Dense      % a reference image with about 1,400 cell-like spots
    end

    methods (TestClassSetup)
        function setUp(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
            incoming = rng;
            testCase.addTeardown(@() rng(incoming));
            testCase.Dense = dense_cells_image();
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
        % ---- Segmentation ---------------------------------------------------

        function hisDefaultsAreHisSegmentation(testCase)
            % default_config's new settings are his constants: segment_cells
            % gives exactly what static_image_seg_v5 gives with none.
            fixtures = fullfile(testCase.Root, "tests", "fixtures");
            inputs = load(fullfile(fixtures, "yitong_session_inputs.mat"));
            expected = load(fullfile(fixtures, "yitong_segmentation.mat"));
            cfg = hadamard_stim.default_config();
            cfg.segmentation.n_exclude = expected.real.n_exclude;
            [x, y, min_val] = hadamard_stim.yitong.static_image_seg_v5(inputs.session_2025.ref_im, ...
                cfg.segmentation.threshold, cfg.segmentation.n_exclude);
            testCase.verifyEqual([x y], expected.real.cells);
            geometry = identity_geometry();
            cells = hadamard_stim.protocol.segment_cells(cfg, inputs.session_2025.ref_im, geometry);
            testCase.verifyEqual(cells.cell_coord, expected.real.cells);
            testCase.verifyEqual(cells.min_val, min_val);
            info = cells.segmentation;
            testCase.verifyEqual([info.candidate_pool info.min_area_px info.filter_size_px], [1000 10 7]);
            testCase.verifyFalse(info.select_all);
            testCase.verifyEqual(info.n_selected, 320);
            testCase.verifyFalse(info.limited);
        end

        function moreThan320AndMoreThan1000Cells(testCase)
            im = testCase.Dense;
            % His pool admits at most 999 candidates.
            [~, ~, ~, ~, his] = hadamard_stim.yitong.static_image_seg_v5(im, 1024, 0);
            testCase.verifyLessThan(his.n_candidates, 1000);
            testCase.verifyTrue(his.limited);
            testCase.verifyEqual(his.n_selected, his.n_candidates);
            % More than 320 within it.
            [x, ~] = hadamard_stim.yitong.static_image_seg_v5(im, 640, 0);
            testCase.verifySize(x, [640 1]);
            % A larger pool: 1024 and more.
            [x, y, ~, ~, info] = hadamard_stim.yitong.static_image_seg_v5(im, 1024, 0, candidate_pool=4000);
            testCase.verifySize(x, [1024 1]);
            testCase.verifyGreaterThan(info.n_candidates, 1024);
            testCase.verifyFalse(info.limited);
            testCase.verifyEqual(size(unique([x y], "rows"), 1), 1024, "one pixel per cell");
            % Every candidate.
            [xa, ya, ~, ~, all_] = hadamard_stim.yitong.static_image_seg_v5(im, 1024, 0, ...
                candidate_pool=4000, select_all=true);
            testCase.verifyEqual(all_.n_selected, all_.n_candidates);
            testCase.verifyTrue(isnan(all_.n_requested));
            testCase.verifyFalse(all_.limited);
            testCase.verifyGreaterThan(numel(xa), 1200);
            % One ranking: the 1024 are the top of "all", in the same order.
            testCase.verifyEqual([xa(end-1023:end) ya(end-1023:end)], [x y]);
        end

        function theSameImageAlwaysGivesTheSameCellsInTheSameOrder(testCase)
            im = testCase.Dense;
            [x1, y1] = hadamard_stim.yitong.static_image_seg_v5(im, 1024, 3, candidate_pool=4000);
            [x2, y2] = hadamard_stim.yitong.static_image_seg_v5(im, 1024, 3, candidate_pool=4000);
            testCase.verifyEqual([x2 y2], [x1 y1]);
        end

        function sensitivityAndRegionSizeChangeTheCandidates(testCase)
            im = testCase.Dense;
            n = @(varargin) candidates(im, varargin{:});
            % The pool is the sensitivity: more regions ranked, more candidates.
            testCase.verifyLessThan(n(candidate_pool=500), n(candidate_pool=1000));
            testCase.verifyLessThan(n(candidate_pool=1000), n(candidate_pool=4000));
            % A larger minimum size rejects small regions.
            testCase.verifyGreaterThan(n(candidate_pool=4000, min_area_px=10), ...
                n(candidate_pool=4000, min_area_px=60));
            % The filter size is a different detection scale, not a resampling:
            % the cells are still pixels of the image.
            [x, y] = hadamard_stim.yitong.static_image_seg_v5(im, 300, 0, filter_size_px=9);
            testCase.verifyEqual([x y], round([x y]));
            testCase.verifyTrue(all(x >= 1 & x <= size(im, 2) & y >= 1 & y <= size(im, 1)));
        end

        function gainDoesNotChangeTheCellsAndAnOffsetHardly(testCase)
            % Why one pipeline serves Hadamard, HiLo and camera references:
            % both rankings are of intensity differences, on regions found
            % with a zero-mean filter. A gain changes nothing. An offset
            % changes only the regions within a filter's width of the border
            % (the filter pads with zeros), which can move a few candidates
            % across the ranking's cutoff.
            im = testCase.Dense;
            [x, y] = hadamard_stim.yitong.static_image_seg_v5(im, 640, 0);
            [x2, y2] = hadamard_stim.yitong.static_image_seg_v5(3 * im, 640, 0);
            testCase.verifyEqual([x2 y2], [x y]);
            [x3, y3] = hadamard_stim.yitong.static_image_seg_v5(im + 500, 640, 0);
            same = size(intersect([x y], [x3 y3], "rows"), 1);
            testCase.verifyGreaterThanOrEqual(same, 0.99 * 640);
        end

        function badSettingsAreRefusedWithAReason(testCase)
            cfg = hadamard_stim.default_config();
            cfg.segmentation.n_exclude = 0;
            cfg.segmentation.candidate_pool = 1.5;
            testCase.verifyError(@() hadamard_stim.protocol.segment_cells(cfg, testCase.Dense, ...
                identity_geometry()), "hadamard_stim:SegmentationSettings");
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyTrue(any(contains(report.errors, "candidate_pool")));
        end

        % ---- The controller -------------------------------------------------

        function resegmentingNeedsNoNewReferenceNoPrepareNoHardware(testCase)
            [c, app] = testCase.unprepared();
            revision = c.ReferenceRevision;
            log_before = app.Log;
            act(c, "propose_cells");
            testCase.verifyEqual(c.getState().proposal.segmentation.n_selected, 320);
            act(c, "update_config", struct("changes", [ ...
                struct("path", "segmentation.threshold", "value", 1024), ...
                struct("path", "segmentation.candidate_pool", "value", 4000)]));
            testCase.verifyEmpty(c.Proposal);
            testCase.verifySubstring(c.getState().setup_notice, "Segmentation settings changed");
            act(c, "propose_cells");
            s = c.getState();
            testCase.verifyEqual(s.proposal.n_cells, 1024);
            testCase.verifyEqual(s.proposal.segmentation.n_requested, 1024);
            testCase.verifyEqual(s.setup_notice, "");
            testCase.verifyEqual(c.ReferenceRevision, revision, "the same reference image");
            testCase.verifyFalse(c.hasEnvironment());
            new_calls = setdiff(app.Log, log_before);
            testCase.verifyFalse(any(contains(new_calls, ["Write" "Ownership" "set_level" "acquisition"])), ...
                strjoin(new_calls, ", "));
            % The view a frontend draws the overlay from has every cell.
            view = hadamard_stim.controller_view(c, "segmentation").data;
            testCase.verifyEqual(view.n_cells, 1024);
            testCase.verifyNumElements(view.cells, 1024);
        end

        function changingSegmentationDiscardsApprovedCellsExplicitly(testCase)
            [c, app] = testCase.unprepared();
            act(c, "propose_cells");
            act(c, "approve_cells");
            mask = c.Cells.illum_mask;
            % A setting that is not segmentation's keeps them.
            act(c, "update_config", struct("changes", struct("path", "stimulation.orange_start_v", "value", 1.1)));
            testCase.verifyEqual(c.LifecycleState, "CELLS_APPROVED");
            testCase.verifyEqual(c.Cells.illum_mask, mask);
            % A preview that is on is ended with them.
            act(c, "start_orange_preview");
            act(c, "update_config", struct("changes", struct("path", "segmentation.min_area_px", "value", 20)));
            testCase.verifyEmpty(c.Cells);
            testCase.verifyEmpty(c.OrangePreview);
            testCase.verifyEqual(app.getDevice("ALP_DMD").pattern_owner, "");
            testCase.verifyEqual(c.LifecycleState, "CONFIGURING");
            testCase.verifySubstring(c.SetupNotice, "approved cells and their masks were discarded");
            testCase.verifyNotEmpty(c.ReferenceImage);
            testCase.verifyFalse(c.legalActions().export_orange_mask);
            act(c, "propose_cells");
            act(c, "approve_cells");
            testCase.verifyEqual(c.getState().approved_segmentation.min_area_px, 20);
        end

        function aZReferenceSurvivesResegmenting(testCase)
            % A z-stack is of the field of view, not of the cells: approving
            % again after a settings change is READY again.
            [c, ~, cfg] = tab_session(fullfile(testCase.Folder, "z"));
            act(c, "set_config", struct("config", cfg));
            act(c, "prepare_rig");
            use_parity_scans(c, testCase.Root);
            for step = ["acquire_reference_image" "propose_cells" "approve_cells" "acquire_z_reference"]
                act(c, step);
            end
            z = c.Reference.had_z_stack;
            act(c, "update_config", struct("changes", struct("path", "segmentation.n_exclude", "value", 4)));
            testCase.verifyEqual(c.LifecycleState, "CONFIGURING");
            act(c, "propose_cells");
            act(c, "approve_cells");
            testCase.verifyEqual(c.LifecycleState, "READY");
            testCase.verifyEqual(c.Reference.had_z_stack, z);
            testCase.verifyEqual(c.Reference.had_ref, c.ReferenceImage);
        end

        function prepareKeepsTheReferenceAndTheCells(testCase)
            [c, ~] = testCase.unprepared();
            act(c, "propose_cells");
            proposal = c.Proposal;
            act(c, "prepare_rig");
            testCase.verifyEqual(c.Proposal, proposal);
            testCase.verifyEqual(c.LifecycleState, "CELLS_PROPOSED");
            act(c, "approve_cells");
            cells = c.Cells;
            revision = c.ReferenceRevision;
            % Prepared again, in any setup state: nothing is lost.
            testCase.verifyTrue(c.legalActions().prepare_rig);
            act(c, "prepare_rig");
            act(c, "prepare_rig");
            testCase.verifyEqual(c.Cells, cells);
            testCase.verifyEqual(c.ReferenceRevision, revision);
            testCase.verifyEqual(c.LifecycleState, "CELLS_APPROVED");
            testCase.verifyEqual(c.SetupNotice, "");
        end

        function prepareOnAnotherDmdCalibrationDiscardsTheCellsAndSaysWhy(testCase)
            [c, app] = testCase.unprepared();
            act(c, "propose_cells");
            act(c, "approve_cells");
            dmd = app.getDevice("ALP_DMD");
            moved = dmd.PairTransform;
            moved.A(1, 3) = moved.A(1, 3) + 5;
            dmd.PairTransform = moved;
            act(c, "prepare_rig");
            testCase.verifyEmpty(c.Cells);
            testCase.verifyEqual(c.LifecycleState, "CONFIGURING");
            testCase.verifySubstring(c.SetupNotice, "another DMD calibration");
            testCase.verifyNotEmpty(c.ReferenceImage);
        end

        function previewWithoutPrepareClaimsOnlyWhatItUsesAndReleasesIt(testCase)
            [c, app] = testCase.unprepared();
            act(c, "propose_cells");
            act(c, "approve_cells");
            dmd = app.getDevice("ALP_DMD");
            orange = app.getDevice("NI_DAQ_Modulator", "name", "Red LED 615");
            n = numel(app.Acquisitions);
            testCase.verifyFalse(c.hasEnvironment());
            testCase.verifyTrue(c.legalActions().start_orange_preview);
            act(c, "start_orange_preview");
            testCase.verifyEqual(logical(dmd.Target), logical(c.Cells.illum_mask));
            testCase.verifyEqual(dmd.pattern_owner, "hadamard_stim");
            testCase.verifyEqual(orange.level, c.Config.stimulation.orange_start_v);
            testCase.verifyEqual(numel(app.Acquisitions), n);
            % The export is the mask shown.
            stem = fullfile(testCase.Folder, "mask");
            act(c, "export_orange_mask", struct("file_stem", stem));
            testCase.verifyEqual(load(stem + ".mat").mask, logical(dmd.Target));
            % Stop: LED off, DMD dark, released; the cells stay.
            act(c, "stop_orange_preview");
            testCase.verifyEqual(orange.level, 0);
            testCase.verifyEqual(dmd.Displaying, "dark");
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyEqual(c.LifecycleState, "CELLS_APPROVED");
            testCase.verifyTrue(c.getState().cleanup.ok);
            % Abort ends it the same way.
            act(c, "start_orange_preview");
            act(c, "abort");
            testCase.verifyEmpty(c.OrangePreview);
            testCase.verifyEqual(orange.level, 0);
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyNotEmpty(c.Cells);
        end

        function previewFailuresLeaveNothingOn(testCase)
            [c, app] = testCase.unprepared();
            act(c, "propose_cells");
            act(c, "approve_cells");
            dmd = app.getDevice("ALP_DMD");
            orange = app.getDevice("NI_DAQ_Modulator", "name", "Red LED 615");
            % A fault while starting.
            orange.FailOn = "set_level=" + string(c.Config.stimulation.orange_start_v);
            r = hadamard_stim.apply_controller_action(c, "start_orange_preview", struct(), c.Revision);
            testCase.verifyFalse(r.ok);
            testCase.verifyEmpty(c.OrangePreview);
            testCase.verifyEqual(dmd.Displaying, "dark");
            testCase.verifyEqual(dmd.pattern_owner, "");
            orange.FailOn = "";
            % Another owner: refused, nothing touched.
            dmd.pattern_owner = "adaptive_optopatch";
            r = hadamard_stim.apply_controller_action(c, "start_orange_preview", struct(), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:HardwareNotReady");
            testCase.verifySubstring(r.message, "adaptive_optopatch");
            testCase.verifyEqual(dmd.pattern_owner, "adaptive_optopatch");
            dmd.pattern_owner = "";
            % The DMD calibration changed since the cells were drawn: refused.
            moved = dmd.PairTransform;
            moved.A(2, 3) = moved.A(2, 3) + 3;
            dmd.PairTransform = moved;
            r = hadamard_stim.apply_controller_action(c, "start_orange_preview", struct(), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:GeometryChanged");
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyNotEmpty(c.Cells, "a refused preview discards nothing");
        end

        function aLargePopulationIsExportedAndRefusedOnlyForARun(testCase)
            % 1,000 approved cells: the mask is drawn and exported, the
            % preview shows it; a connectivity run is refused explicitly,
            % because matrix.order (320) is not 1,000 and hadamard(1000)
            % does not exist.
            [c, app] = testCase.unprepared();
            act(c, "update_config", struct("changes", [ ...
                struct("path", "segmentation.threshold", "value", 1000), ...
                struct("path", "segmentation.candidate_pool", "value", 4000)]));
            act(c, "propose_cells");
            act(c, "approve_cells");
            testCase.verifyEqual(size(c.Cells.cell_coord, 1), 1000);
            stem = fullfile(testCase.Folder, "large");
            act(c, "export_orange_mask", struct("file_stem", stem));
            saved = load(stem + ".mat");
            testCase.verifyEqual(saved.mask, c.Cells.illum_mask);
            testCase.verifySize(saved.info.cells.cell_coord_xy, [1000 2]);
            presets = fullfile(fileparts(testCase.Root), "luminos-private", "src", "Devices", ...
                "Patterning", "DMD", "Preset_pattern");
            if isfile(fullfile(presets, "pdHadamard_Stim_Orange_Mask.m"))
                testCase.applyFixture(matlab.unittest.fixtures.PathFixture(presets));
                loaded = pdHadamard_Stim_Orange_Mask(app.getDevice("ALP_DMD"), struct("maskFile", stem + ".mat"));
                testCase.verifyEqual(loaded, c.Cells.illum_mask);
            end
            act(c, "start_orange_preview");
            testCase.verifyEqual(logical(app.getDevice("ALP_DMD").Target), c.Cells.illum_mask);
            act(c, "stop_orange_preview");

            readiness = c.getState().readiness;
            item = readiness.checks(string({readiness.checks.id}) == "cells_matrix");
            testCase.verifyEqual(item.status, "blocker");
            testCase.verifySubstring(item.message, "1000 cells are approved");
            testCase.verifySubstring(item.consequence, "preview and export are not affected");
            cfg = c.Config;
            cfg.matrix.order = 1000;
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyTrue(any(contains(report.errors, "no Hadamard matrix")));
            cfg.matrix.order = 1024;
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyFalse(any(contains(report.errors, "matrix.order")));
            testCase.verifyTrue(any(contains(report.warnings, "1.25 passes")));
        end

        function aSupportedLargerOrderBuildsItsMatrixAndRunState(testCase)
            % 640 cells and matrix.order 640: the run's state is built (one
            % matrix row per cell), the configuration is valid, and his 160
            % Hadamard trials cover the matrix exactly twice.
            cfg = hadamard_stim.default_config();
            cfg.segmentation.n_exclude = 0;
            cfg.segmentation.threshold = 640;
            cfg.matrix.order = 640;
            cfg.naming.prefix = "test";
            cfg.stimulation.orange_start_v = 1;
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyTrue(report.ok, strjoin(report.errors, " "));
            testCase.verifyFalse(any(contains(report.warnings, "passes")));
            cells = hadamard_stim.protocol.segment_cells(cfg, testCase.Dense, identity_geometry());
            state = hadamard_stim.protocol.new_run_state(cfg, cells, struct());
            testCase.verifySize(state.had_mat, [640 640]);
            testCase.verifySize(state.picked, [640 cfg.trials.n_trial]);
        end
    end

    methods
        function [c, app] = unprepared(testCase)
            % A tab session on the fake Firefly with the dense reference
            % set, nothing prepared and no hardware claimed.
            folder = fullfile(testCase.Folder, string(java.util.UUID.randomUUID()));
            [c, app, cfg] = tab_session(folder);
            cfg.stimulation.orange_start_v = 1.2;
            cfg.segmentation.n_exclude = 0;
            act(c, "set_config", struct("config", cfg));
            c.setReferenceImage(testCase.Dense);
        end
    end
end

function n = candidates(im, varargin)
[~, ~, ~, ~, info] = hadamard_stim.yitong.static_image_seg_v5(im, 10, 0, varargin{:});
n = info.n_candidates;
end

function im = dense_cells_image()
% 328 x 448 (his area), about 1,400 soma-like spots on a 10-px lattice
% with jitter, of varied brightness, on a background with shot-like noise.
rng(11, "twister");
[cols, rows] = meshgrid(6:10:443, 6:10:323);
centres = [cols(:) rows(:)] + 1.5 * randn(numel(cols), 2);
amplitude = 60 + 240 * rand(numel(cols), 1);
[x, y] = meshgrid(1:448, 1:328);
im = 100 * ones(328, 448);
for k = 1:size(centres, 1)
    im = im + amplitude(k) * exp(-((x - centres(k, 1)) .^ 2 + (y - centres(k, 2)) .^ 2) / (2 * 1.8 ^ 2));
end
im = im + sqrt(im) .* randn(size(im));
end

function geometry = identity_geometry()
% Camera pixels straight onto his DMD canvas, for tests that only segment.
canvas = [768 1024];
geometry.identity = struct("source", "test");
geometry.rasterize = @(spots, how) rasterize(spots, canvas);
end

function mask = rasterize(spots, canvas)
mask = false(canvas);
for k = 1:numel(spots)
    p = spots{k};
    mask = mask | poly2mask(p(:, 1), p(:, 2), canvas(1), canvas(2));
end
end

function r = act(c, action, payload)
if nargin < 3
    payload = struct();
end
r = hadamard_stim.apply_controller_action(c, action, payload, c.Revision);
assert(r.ok, "%s: %s", action, r.message);
end
