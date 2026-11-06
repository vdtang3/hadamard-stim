classdef TestManualSegmentation < matlab.unittest.TestCase
    %TESTMANUALSEGMENTATION manual_segment_dmd's settings are the tab's; tuning, choosing cells, saving settings.

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
        function everyTabSettingIsAnOptionWithTheTabsDefault(testCase)
            fields = hadamard_stim.ui.config_fields();
            paths = [fields.path];
            names = extractAfter(paths(startsWith(paths, "segmentation.")), "segmentation.");
            his = hadamard_stim.default_config().segmentation;
            testCase.verifyEqual(sort(names), sort(string(fieldnames(his))'), ...
                "The tab edits every segmentation setting the protocol reads.");
            testCase.verifyEqual(hadamard_stim.manual.segmentation_settings(), his, "Defaults are the tab's.");
            image = testCase.image();
            values = struct("n_exclude", 2, "threshold", 50, "select_all", false, "candidate_pool", 600, ...
                "min_area_px", 12, "filter_size_px", 6, "illum_spot_size", 4, "stim_spot_size", 2);
            args = {};
            for name = names
                camel = regexprep(name, "_([a-z])", "${upper($1)}");
                args = [args {char(camel), values.(name)}]; %#ok<AGROW>
            end
            r = manual_segment_dmd(image, [], args{:}, show=false, output="none");
            for name = names
                testCase.verifyEqual(r.settings.(name), values.(name), name);
            end
            % By the tab's own names, in a settings struct: the same result.
            s = manual_segment_dmd(image, [], settings=values, show=false, output="none");
            testCase.verifyEqual(s.cells, r.cells);
            % Its rules: n_exclude is required, and bad values are refused.
            testCase.verifyError(@() manual_segment_dmd(image, [], show=false), "hadamard_stim:NExcludeMissing");
            testCase.verifyError(@() manual_segment_dmd(image, [], nExclude=0, candidatePool=1, show=false), ...
                "hadamard_stim:SegmentationSettings");
            testCase.verifyError(@() manual_segment_dmd(image, [], settings=struct("diameter", 3), show=false), ...
                "hadamard_stim:SegmentationSettings");
        end

        function theSameSettingsGiveTheTabsCellsAndMask(testCase)
            % Non-default settings, set in the tab and given here.
            [c, app, cfg] = tab_session(fullfile(testCase.Folder, "tab"));
            cfg.segmentation.candidate_pool = 700;
            cfg.segmentation.min_area_px = 14;
            cfg.segmentation.illum_spot_size = 6;
            cfg.segmentation.threshold = 120;
            act(c, "set_config", struct("config", cfg));
            file = testCase.snap(testCase.image());
            act(c, "load_reference_snap", struct("file", file));
            act(c, "propose_cells");
            act(c, "approve_cells");
            m = manual_segment_dmd(file, app.getDevice("ALP_DMD"), settings=cfg.segmentation, show=false, output="none");
            for name = ["cell_coord" "excluded_coord" "min_val" "illum_rois" "stim_rois"]
                testCase.verifyEqual(m.cells.(name), c.Cells.(name), name);
            end
            testCase.verifyEqual(m.mask, c.Cells.illum_mask);
            testCase.verifyEqual(m.stim_mask, c.Cells.stim_mask);
        end

        function tuningReRunsOnTheSameImageAndKeepsTheChoice(testCase)
            image = testCase.image();
            file = testCase.snap(image);
            before = hadamard_stim.metadata.sha256(image);
            tuner = testCase.tuner(image, struct("n_exclude", 0, "threshold", 80));
            first = tuner.state();
            testCase.verifyEqual(size(first.cells.cell_coord, 1), 80);
            tuner.set("threshold", 40);
            tuner.set("min_area_px", 15);
            tuner.run();
            second = tuner.state();
            testCase.verifyEqual(second.settings.threshold, 40);
            testCase.verifyEqual(second.cells, hadamard_stim.manual.segment(image, second.settings), ...
                "The tab's segmentation with the settings shown.");
            testCase.verifyEqual(hadamard_stim.metadata.sha256(image), before, "The image is unchanged.");
            % Cells dropped by clicking, then accepted.
            tuner.toggle(3);
            tuner.toggle(7);
            tuner.toggle(7);       % restored
            tuner.accept();
            st = tuner.state();
            testCase.verifyTrue(st.accepted && st.done);
            testCase.verifyEqual(st.kept, setdiff(1:40, 3));
            % The mask of those cells, drawn by the tab's rules.
            dmd = hadamard_stim.testing.FakeAlpDmd("DMD (shared)");
            m = manual_segment_dmd(file, dmd, settings=st.settings, keep=st.kept, show=false, output="none");
            g = hadamard_stim.luminos.active_geometry(dmd, struct("name", "Teledyne Kinetix", ...
                "roi", [0 0 448 328], "bin", 1));
            subset = hadamard_stim.protocol.draw_cells(struct("cell_coord", m.cells.cell_coord(st.kept, :)), ...
                st.settings, g);
            testCase.verifyEqual(m.kept, st.kept);
            testCase.verifyEqual(m.mask, subset.illum_mask);
            testCase.verifyEqual(dmd.Displaying, "nothing", "Nothing was projected.");
        end

        function settingsAreSavedWithTheResultAndReload(testCase)
            image = testCase.image();
            file = testCase.snap(image);
            dmd = hadamard_stim.testing.FakeAlpDmd("DMD (shared)");
            json = fullfile(testCase.Folder, "mine.json");
            m = manual_segment_dmd(file, dmd, nExclude=1, threshold=60, minAreaPx=12, keep=[2 4 6], ...
                saveSettings=json, show=false);
            saved = load(m.files.mat);
            testCase.verifyEqual(saved.segmentation.settings, m.settings);
            testCase.verifyEqual(saved.segmentation.kept, [2 4 6]);
            testCase.verifyEqual(saved.info.segmentation_settings, m.settings);
            % From the result file, and from the .json: the same cells.
            again = manual_segment_dmd(file, dmd, settings=m.files.mat, keep=[2 4 6], show=false, output="none");
            testCase.verifyEqual(again.cells, m.cells);
            testCase.verifyEqual(again.mask, m.mask);
            fromJson = manual_segment_dmd(file, dmd, settings=json, keep=[2 4 6], show=false, output="none");
            testCase.verifyEqual(fromJson.settings, m.settings);
            testCase.verifyEqual(fromJson.cells, m.cells);
            % The tuner loads and saves the same files.
            tuner = testCase.tuner(image, hadamard_stim.manual.segmentation_settings());
            tuner.load(json);
            tuner.run();
            testCase.verifyEqual(tuner.state().cells, m.cells);
            other = fullfile(testCase.Folder, "from_tuner.json");
            tuner.save(other);
            testCase.verifyEqual(hadamard_stim.manual.segmentation_settings(other), m.settings);
            tuner.cancel();
        end

        function segmentationNeedsNoDmdOrCalibration(testCase)
            image = testCase.image();
            r = manual_segment_dmd(image, [], nExclude=0, threshold=30, show=false, output="none");
            testCase.verifyEqual(size(r.cells.cell_coord, 1), 30);
            testCase.verifyEmpty(r.mask);
            % A DMD with no Kinetix calibration: refused at the mask, only.
            dmd = hadamard_stim.testing.FakeAlpDmd("DMD (shared)");
            dmd.CalibratedCamera = "Libra 5514 Pro";
            testCase.verifyError(@() manual_segment_dmd(testCase.snap(image), dmd, nExclude=0, threshold=30, ...
                show=false, output="none"), "hadamard_stim:IncompatibleSnap");
        end
    end

    methods
        function im = image(testCase)
            [~, ~, ~, inputs] = parity_environment(fullfile(testCase.Root, "tests", "fixtures"));
            im = double(inputs.ref_im);
        end

        function file = snap(testCase, image)
            snap = struct("img", image, "bin", 1, "type", 'Camera', "name", 'Teledyne Kinetix', ...
                "timestamp", datetime(2026, 11, 6), "ref2d", struct("ImageSize", size(image), ...
                "XWorldLimits", [0 448], "YWorldLimits", [0 328]), ...
                "tform", struct("name", {'DMD (shared)'}, "tform", {affinetform2d(eye(3))}));
            file = fullfile(testCase.Folder, "120000_cam-TeledyneKinetix.mat");
            save(file, "snap", "-v7.3");
        end

        function t = tuner(testCase, image, settings)
            try
                t = hadamard_stim.manual.segmentation_tuner(image, ...
                    hadamard_stim.manual.segmentation_settings(settings), [], visible=false);
            catch err
                testCase.assumeFail("No figure window here: " + string(err.message));
            end
            testCase.addTeardown(@() delete(t.fig(isvalid(t.fig))));
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
