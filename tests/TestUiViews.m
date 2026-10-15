classdef TestUiViews < matlab.unittest.TestCase
    %TESTUIVIEWS The display products are the package's own results, unchanged.
    %
    %   The tab draws what controller_view returns, so each view must be
    %   exactly what the protocol holds: cells in cell_coord order (the
    %   stimulation matrix's rows), their spots as drawn, the excluded
    %   candidates segmentation skipped, a pattern's cells as the matrix or
    %   the trial has them. Views never change the session.

    properties
        Root
        Cfg
        Env
        Ref
        Controller
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
            [cfg, env, ~, inputs] = parity_environment(fullfile(testCase.Root, "tests", "fixtures"));
            cfg.trials.last = 2;
            env.context = struct("luminos", struct("commit", "not_applicable"), ...
                "geometry_identity", env.geometry.identity, ...
                "blue_calibration", struct("identity", "blueCal.mat", "source", "testing"), ...
                "standing_deviations", "simulation: no hardware", "simulated", true);
            testCase.Cfg = cfg;
            testCase.Env = env;
            testCase.Ref = inputs.ref_im;
            % One session run to the end of trial 2, shared by the tests.
            testCase.Folder = string(tempname);
            testCase.addTeardown(@() rmdir(testCase.Folder, "s"));
            c = hadamard_stim.HadamardStimController(env);
            c.setConfig(cfg);
            c.setReferenceImage(inputs.ref_im);
            c.proposeCells();
            c.approveCells();
            c.acquireZReference();
            c.startRun(testCase.Folder);
            testCase.Controller = c;
        end
    end

    methods (Test)
        function cellsAreNumberedInThePackagesOrder(testCase)
            c = testCase.Controller;
            v = hadamard_stim.controller_view(c, "segmentation");
            testCase.assertTrue(v.ok, v.message);
            d = v.data;
            cells = c.Cells;
            testCase.verifyEqual(d.source, "approved");
            testCase.verifyEqual([d.cells.number]', (1:320)');
            testCase.verifyEqual([[d.cells.x]' [d.cells.y]'], round(cells.cell_coord, 3));
            % Each cell's spots are the ones its masks were drawn from.
            illum = hadamard_stim.yitong.split_rois(cells.illum_rois);
            stim = hadamard_stim.yitong.split_rois(cells.stim_rois);
            for k = [1 2 160 319 320]
                testCase.verifyEqual(d.cells(k).illum, round(illum{k}, 3));
                testCase.verifyEqual(d.cells(k).stim, round(stim{k}, 3));
            end
            testCase.verifyEqual(d.min_val, cells.min_val);
            testCase.verifyEqual(d.n_exclude, 5);
        end

        function theExcludedAreTheSkippedTopCandidates(testCase)
            % Segmenting for threshold + n_exclude with nothing skipped
            % gives his cells followed by the ones he excluded.
            s = testCase.Cfg.segmentation;
            [x, y, ~, excluded] = hadamard_stim.yitong.static_image_seg_v5(testCase.Ref, s.threshold, s.n_exclude);
            [x0, y0] = hadamard_stim.yitong.static_image_seg_v5(testCase.Ref, s.threshold + s.n_exclude, 0);
            testCase.verifyEqual([x y], [x0(1:end-5) y0(1:end-5)]);
            testCase.verifyEqual(excluded, [x0(end-4:end) y0(end-4:end)]);
            v = hadamard_stim.controller_view(testCase.Controller, "segmentation");
            testCase.verifyEqual(v.data.excluded, round(excluded, 3));
        end

        function aPatternIsTheMatrixColumnOrTheTrialAsPlayed(testCase)
            c = testCase.Controller;
            had_mat = hadamard_stim.yitong.stim_matrix(320);
            for k = [1 8 320]
                v = hadamard_stim.controller_view(c, "pattern", struct("source", "matrix", "index", k));
                testCase.verifyEqual(v.data.on, find(had_mat(:, k)));
                testCase.verifyEqual(v.data.n_patterns, 320);
            end
            record = c.LastRecord;
            v = hadamard_stim.controller_view(c, "pattern", struct("source", "last_trial", "index", 3));
            testCase.verifyEqual(v.data.on, find(record.c_idx_all_it(:, 3)));
            testCase.verifyEqual(v.data.trial, 2);
            testCase.verifyEqual(v.data.kind, "sparse");
            v = hadamard_stim.controller_view(c, "pattern", struct("source", "matrix", "index", 321));
            testCase.verifyFalse(v.ok);
        end

        function theImageIsAPngOfTheReference(testCase)
            out = hadamard_stim.ui.display_image(testCase.Ref);
            testCase.verifyEqual([out.rows out.columns], size(testCase.Ref));
            file = string(tempname) + ".png";
            testCase.addTeardown(@() delete(file));
            fid = fopen(file, "w");
            fwrite(fid, matlab.net.base64decode(out.pixels));
            fclose(fid);
            im = imread(file);
            testCase.verifyClass(im, "uint8");
            testCase.verifySize(im, size(testCase.Ref));
            % Brighter stays brighter.
            [~, hi] = max(testCase.Ref(:));
            [~, lo] = min(testCase.Ref(:));
            testCase.verifyEqual(im(hi), uint8(255));
            testCase.verifyEqual(im(lo), uint8(0));
        end

        function viewsChangeNothing(testCase)
            c = testCase.Controller;
            before = c.Revision;
            for name = ["config_fields" "segmentation" "pattern" "summary" "recipe" "checkpoint"]
                v = hadamard_stim.controller_view(c, name);
                testCase.verifyTrue(v.ok, name + ": " + v.message);
                testCase.verifyNotEmpty(jsonencode(v), name);
            end
            testCase.verifyEqual(c.Revision, before);
            v = hadamard_stim.controller_view(c, "anything");
            testCase.verifyFalse(v.ok);
        end

        function theSummaryAndRecipeAreWhatWillBeOrWasRun(testCase)
            c = testCase.Controller;
            s = hadamard_stim.controller_view(c, "summary").data;
            testCase.verifyEqual(s.mode, "yitong_compatible");
            testCase.verifyEqual(s.n_cells, 320);
            testCase.verifyEqual([s.trials.first s.trials.last], [1 2]);
            testCase.verifyEqual(s.switches, struct("run_sparse", true, "z_reference", true, ...
                "drift_correction", true, "bleaching_correction", true));
            testCase.verifyEqual(s.standing_deviations, "simulation: no hardware");
            r = hadamard_stim.controller_view(c, "recipe").data;
            saved = jsondecode(fileread(fullfile(testCase.Folder, "run_recipe.json")));
            testCase.verifyEqual(r.recipe_hash, saved.recipe_hash);
            testCase.verifyEqual(r.cells.n_cells, 320);
            testCase.verifyFalse(isfield(r.cells, "cell_coord"));
        end

        function everyConfigFieldIsInTheConfiguration(testCase)
            cfg = hadamard_stim.default_config();
            fields = hadamard_stim.ui.config_fields();
            testCase.verifyEqual(numel(unique([fields.path])), numel(fields));
            for f = fields'
                parts = split(f.path, ".");
                v = cfg;
                for p = parts'
                    testCase.assertTrue(isfield(v, p), f.path);
                    v = v.(p);
                end
            end
            % The required settings are the ones validate_config requires.
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyEqual(sort(reshape(extractBefore(report.errors, " is not set."), [], 1)), ...
                sort(reshape([fields([fields.required]).path], [], 1)));
        end

        function aCheckpointIsReadAsResumeReadsIt(testCase)
            c = testCase.Controller;
            v = hadamard_stim.controller_view(c, "checkpoint");
            state = hadamard_stim.metadata.load_checkpoint(testCase.Folder);
            testCase.verifyEqual(v.data.next_trial, state.next_trial);
            testCase.verifyEqual(v.data.cnt, state.cnt);
            testCase.verifyEqual(v.data.cnt_had, state.cnt_had);
            testCase.verifyEqual(v.data.b0, state.b0);
            testCase.verifyEqual(v.data.n_trial_records, 2);
            testCase.verifyTrue(v.data.calibration_matches);
            % A folder resume would refuse is refused here with its reason.
            copy = string(tempname);
            copyfile(testCase.Folder, copy);
            testCase.addTeardown(@() rmdir(copy, "s"));
            checkpoint = load(fullfile(copy, "run_checkpoint.mat"));
            checkpoint.checkpoint.recipe_hash = "0000";
            save(fullfile(copy, "run_checkpoint.mat"), "-struct", "checkpoint");
            v = hadamard_stim.controller_view(c, "checkpoint", struct("run_folder", copy));
            testCase.verifyTrue(v.ok);
            testCase.verifyFalse(v.data.ok);
            testCase.verifySubstring(v.data.message, "belongs to recipe 0000");
        end
    end
end
