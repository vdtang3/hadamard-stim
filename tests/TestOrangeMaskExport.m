classdef TestOrangeMaskExport < matlab.unittest.TestCase
    %TESTORANGEMASKEXPORT The approved cells' orange DMD mask, saved for Luminos's own tabs.
    %
    %   A fallback for when the run pipeline cannot be used: the exact
    %   Cells.illum_mask the orange preview shows (dmd_show_mask) and the
    %   trials use, written to .mat and .png with its provenance. Files
    %   only: no device is begun, claimed or written, and the session does
    %   not change. Luminos's DMD tab loads it with the pattern function
    %   pdHadamard_Stim_Orange_Mask, which must project the same array.

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
        function itNeedsApprovedCells(testCase)
            [c, ~, cfg] = tab_session(fullfile(testCase.Folder, "session"));
            act(c, "set_config", struct("config", cfg));
            act(c, "prepare_rig");
            use_parity_scans(c, testCase.Root);
            act(c, "acquire_reference_image");
            act(c, "propose_cells");
            testCase.verifyFalse(c.legalActions().export_orange_mask);
            r = hadamard_stim.apply_controller_action(c, "export_orange_mask", ...
                struct("file_stem", fullfile(testCase.Folder, "early")), c.Revision);
            testCase.verifyFalse(r.ok);
            testCase.verifyFalse(isfile(fullfile(testCase.Folder, "early.mat")));
            act(c, "approve_cells");
            testCase.verifyTrue(c.legalActions().export_orange_mask);
        end

        function theExportIsTheApprovedMaskExactlyAndTouchesNoHardware(testCase)
            [c, app] = testCase.approved();
            dmd = app.getDevice("ALP_DMD");
            before = snapshot(app);
            log_before = app.Log;
            n = numel(app.Acquisitions);
            state_before = c.LifecycleState;
            stem = fullfile(testCase.Folder, "export", "fov1_orange_mask");

            r = act(c, "export_orange_mask", struct("file_stem", stem));

            % The same array: class, size, orientation and every pixel.
            saved = load(stem + ".mat");
            testCase.verifyClass(saved.mask, "logical");
            testCase.verifyEqual(saved.mask, c.Cells.illum_mask);
            testCase.verifyEqual(size(saved.mask), dmd.Pattern_Canvas_Size());
            testCase.verifyEqual(saved.info.canvas_size, dmd.Pattern_Canvas_Size());
            testCase.verifyEqual(saved.info.mask_sha256, hadamard_stim.metadata.sha256(c.Cells.illum_mask));
            testCase.verifyEqual(saved.info.mask_on_pixels, nnz(c.Cells.illum_mask));
            % The PNG is the same pixels, one per mirror, not transposed.
            png = imread(stem + ".png");
            testCase.verifyEqual(logical(png), c.Cells.illum_mask);

            % Provenance.
            info = saved.info;
            testCase.verifyEqual(info.kind, "hadamard_stim_orange_mask");
            testCase.verifyEqual(info.cells.cell_coord_xy, c.Cells.cell_coord);
            testCase.verifyEqual(info.cells.cell_id, (1:size(c.Cells.cell_coord, 1))');
            testCase.verifyEqual(info.cells.illum_rois, c.Cells.illum_rois);
            testCase.verifyEqual(info.dmd_calibration, c.Env.geometry.identity);
            testCase.verifyEqual(info.camera_now.roi, [0 448 0 328]);
            testCase.verifyEqual(info.camera_now.bin, 1);
            testCase.verifyEqual(info.camera_now.format.mode_label, info.imaging_format_prepared.mode_label);
            testCase.verifyEqual(info.imaging_format_prepared.storage_bits, 16);
            testCase.verifyEqual(info.reference.image_size, size(c.ReferenceImage));
            testCase.verifyNotEmpty(info.created_utc);
            testCase.verifySubstring(info.how_to_load, "Hadamard Stim Orange Mask");

            % The tab is told where the files are.
            testCase.verifyEqual(r.state.orange_mask_export.mat, stem + ".mat");
            testCase.verifyEqual(r.state.orange_mask_export.png, stem + ".png");
            testCase.verifyEqual(r.state.orange_mask_export.mask_sha256, info.mask_sha256);

            % Nothing on the rig moved and nothing was asked of it.
            testCase.verifyEqual(snapshot(app), before);
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyEqual(numel(app.Acquisitions), n);
            new_calls = setdiff(app.Log, log_before);
            testCase.verifyFalse(any(contains(new_calls, ["DMD" "LED" "Ownership" "Write" "set_level"])), ...
                strjoin(new_calls, ", "));
            testCase.verifyEqual(c.LifecycleState, state_before);
            testCase.verifyEmpty(c.OrangePreview);
        end

        function itIsTheMaskThePreviewShowsAndAPreviewStaysOn(testCase)
            [c, app] = testCase.approved();
            dmd = app.getDevice("ALP_DMD");
            act(c, "start_orange_preview");
            shown = logical(dmd.Target);
            owner = dmd.pattern_owner;
            stem = fullfile(testCase.Folder, "during_preview");
            act(c, "export_orange_mask", struct("file_stem", stem));
            saved = load(stem + ".mat", "mask");
            testCase.verifyEqual(saved.mask, shown);
            testCase.verifyEqual(c.OrangePreview.mask_sha256, hadamard_stim.metadata.sha256(saved.mask));
            % The preview is as it was: still shown, still owned.
            testCase.verifyEqual(logical(dmd.Target), shown);
            testCase.verifyEqual(dmd.pattern_owner, owner);
            testCase.verifyNotEmpty(c.OrangePreview);
            act(c, "stop_orange_preview");
        end

        function withoutAStemItGoesBesideTheRuns(testCase)
            [c, app] = testCase.approved();
            r = act(c, "export_orange_mask");
            mat = r.state.orange_mask_export.mat;
            testCase.verifyTrue(isfile(mat));
            testCase.verifyTrue(isfile(r.state.orange_mask_export.png));
            testCase.verifyEqual(string(fileparts(mat)), string(fileparts(c.Backend.default_run_folder(c.Config))));
            testCase.verifyMatches(mat, "\d{6}_" + regexptranslate("escape", c.Config.naming.prefix) + "_orange_mask\.mat$");
            testCase.verifyTrue(startsWith(mat, string(app.datafolder)));
        end

        function luminosProjectsTheSameArray(testCase)
            % Luminos's DMD tab: pattern function "Hadamard Stim Orange
            % Mask" (a pd- function: DMD space, Target then Write_Static),
            % given the exported .mat.
            presets = fullfile(fileparts(testCase.Root), "luminos-private", "src", "Devices", ...
                "Patterning", "DMD", "Preset_pattern");
            testCase.assumeTrue(isfile(fullfile(presets, "pdHadamard_Stim_Orange_Mask.m")), ...
                "luminos-private is not checked out beside hadamard-stim.");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(presets));
            [c, app] = testCase.approved();
            dmd = app.getDevice("ALP_DMD");
            stem = fullfile(testCase.Folder, "for_luminos");
            act(c, "export_orange_mask", struct("file_stem", stem));
            act(c, "start_orange_preview");
            previewed = logical(dmd.Target);
            act(c, "stop_orange_preview");
            loaded = pdHadamard_Stim_Orange_Mask(dmd, struct("maskFile", stem + ".mat"));
            testCase.verifyEqual(loaded, previewed);
            testCase.verifyEqual(loaded, c.Cells.illum_mask);
            % Another canvas, or a file that is not an export, is refused.
            other = fullfile(testCase.Folder, "other.mat");
            mask = false(10, 20); %#ok<NASGU>
            save(other, "mask");
            testCase.verifyError(@() pdHadamard_Stim_Orange_Mask(dmd, struct("maskFile", other)), ...
                "pdHadamard_Stim_Orange_Mask:CanvasSize");
            testCase.verifyError(@() pdHadamard_Stim_Orange_Mask(dmd, struct("maskFile", stem + ".png")), ...
                "pdHadamard_Stim_Orange_Mask:NotAMask");
        end
    end

    methods
        function [c, app] = approved(testCase)
            % A tab session with cells approved and the z-reference taken.
            folder = fullfile(testCase.Folder, string(java.util.UUID.randomUUID()));
            [c, app, cfg] = tab_session(folder);
            cfg.stimulation.orange_start_v = 1.2;
            act(c, "set_config", struct("config", cfg));
            act(c, "prepare_rig");
            use_parity_scans(c, testCase.Root);
            for step = ["acquire_reference_image" "propose_cells" "approve_cells" "acquire_z_reference"]
                act(c, step);
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
