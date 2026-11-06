classdef TestCalibrationAnyFov < matlab.unittest.TestCase
    %TESTCALIBRATIONANYFOV The Kinetix's DMD calibration serves any field of view, area and binning.
    %
    %   The calibration maps unbinned sensor pixels to DMD mirrors and belongs
    %   to the camera and light path: a new stage position, camera area or
    %   binning, an area beyond the calibrated one (extrapolated, said), a
    %   calibration read back from disk after a restart and no reference
    %   image loaded in the DMD tab all draw through it. Refused only: no
    %   calibration for the camera (another camera's is never used), or a
    %   transform that is not finite or not invertible. Cells mapped off the
    %   DMD are listed and their spots clipped to the canvas.

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
        function aCalibrationMeasuredOnACropServesOtherAreasAndBinnings(testCase)
            % Measured on a 200 x 150 crop at (100, 80); used on the full
            % frame, binned, and an area entirely outside the crop.
            dmd = TestCalibrationAnyFov.dmd();
            dmd.ReferenceRoi = [100 80 200 150];
            dmd.refimage = struct("img", zeros(150, 200), "bin", 1);
            sensor = [380 290];                       % outside the crop
            for area = {{[0 0 448 328], 1}, {[0 0 448 328], 2}, {[300 200 120 100], 1}, {[100 80 200 150], 1}}
                roi = area{1}{1};
                bin = area{1}{2};
                label = sprintf("area %s bin %d", mat2str(roi), bin);
                g = hadamard_stim.luminos.active_geometry(dmd, struct("name", "Teledyne Kinetix", "roi", roi, "bin", bin));
                inside = isequal(roi, [100 80 200 150]);
                testCase.verifyEqual(g.identity.extrapolated, ~inside, label);
                testCase.verifyEqual(g.identity.calibrated_roi, [100 80 200 150], label);
                if inside, continue, end
                local = (sensor - roi(1:2) - 0.5) / bin + 0.5;    % the pixel holding that sensor point
                uv = g.to_dmd(local);
                expected = dmd.PairTransform.A * [sensor 1]';
                testCase.verifyLessThan(norm(uv - expected(1:2)'), 1e-9, label + ": the stored transform, applied");
                testCase.verifyFalse(g.off_dmd(local), label);
                mask = g.rasterize({circle(local, 8 / bin)}, "auto_square");
                testCase.verifySize(mask, dmd.Pattern_Canvas_Size(), label);
                testCase.verifyLessThan(norm(centroid(mask) - uv), 1.5, label + ": the spot lands there");
            end
        end

        function aCalibrationReadFromDiskWithNoReferenceImageIsUsed(testCase)
            % After a restart: status "file", and the DMD tab shows no image.
            dmd = TestCalibrationAnyFov.dmd();
            camera = struct("name", "Teledyne Kinetix", "roi", [0 0 448 328], "bin", 1);
            before = hadamard_stim.luminos.active_geometry(dmd, camera);
            reference = before.rasterize({circle([200 150], 10)}, "auto_square");
            dmd.refimage = [];
            dmd.CalibrationStatus = "file";
            after = hadamard_stim.luminos.active_geometry(dmd, camera);
            testCase.verifyEqual(after.identity.status, "file");
            testCase.verifyNotEqual(after.identity.drawn_by, "setPatterningROI");
            mask = after.rasterize({circle([200 150], 10)}, "auto_square");
            testCase.verifyLessThan(norm(centroid(mask) - centroid(reference)), 1e-6);
            testCase.verifyEqual(nnz(mask), nnz(reference));
        end

        function theTabUsesItAfterARestartAndAtANewStagePosition(testCase)
            [c, app, cfg] = tab_session(fullfile(testCase.Folder, "tab"));
            hadamard_stim.apply_controller_action(c, "set_config", struct("config", cfg), c.Revision);
            dmd = app.getDevice("ALP_DMD");
            dmd.refimage = [];
            dmd.CalibrationStatus = "file";
            [~, ~, ~, inputs] = parity_environment(fullfile(testCase.Root, "tests", "fixtures"));
            first = double(inputs.ref_im);
            act(c, "load_reference_snap", struct("file", testCase.snap(first, "fov1")));
            act(c, "propose_cells");
            act(c, "approve_cells");
            calibration = c.CellsGeometry;
            % The stage moved: another field, the same camera area.
            second = circshift(first, [17 -23]);
            act(c, "new_session");
            act(c, "set_config", struct("config", cfg));
            act(c, "load_reference_snap", struct("file", testCase.snap(second, "fov2")));
            testCase.verifyEqual(c.SetupNotice, "", "Nothing to say about a new field of view.");
            act(c, "propose_cells");
            act(c, "approve_cells");
            testCase.verifyEqual(c.CellsGeometry, calibration, "The same calibration, the same area.");
        end

        function cellsOffTheDmdAreListedAndClipped(testCase)
            dmd = TestCalibrationAnyFov.dmd();
            dmd.PairTransform = struct("A", [1.6 0 700; 0 1.6 25; 0 0 1]);   % x beyond ~200 px leaves the DMD
            g = hadamard_stim.luminos.active_geometry(dmd, struct("name", "Teledyne Kinetix", ...
                "roi", [0 0 448 328], "bin", 1));
            cells = struct("cell_coord", [50 100; 150 100; 300 100; 420 300]);
            drawn = hadamard_stim.protocol.draw_cells(cells, hadamard_stim.default_config().segmentation, g);
            testCase.verifyEqual(drawn.off_dmd, [3 4]);
            testCase.verifySize(drawn.illum_mask, dmd.Pattern_Canvas_Size());
            testCase.verifyGreaterThan(nnz(drawn.illum_mask), 0, "The cells on the DMD are drawn.");
        end

        function noUsableTransformIsRefused(testCase)
            for A = {[NaN 0 0; 0 1 0; 0 0 1], [1 2 0; 2 4 0; 0 0 1]}
                dmd = TestCalibrationAnyFov.dmd();
                dmd.PairTransform = struct("A", A{1});
                testCase.verifyError(@() hadamard_stim.luminos.active_geometry(dmd, ...
                    struct("name", "Teledyne Kinetix", "roi", [0 0 448 328], "bin", 1)), ...
                    "hadamard_stim:NoDmdCalibration");
            end
        end

        function anotherCamerasCalibrationIsNeverUsed(testCase)
            dmd = TestCalibrationAnyFov.dmd();
            dmd.CalibratedCamera = "Libra 5514 Pro";
            testCase.verifyError(@() hadamard_stim.luminos.active_geometry(dmd, ...
                struct("name", "Teledyne Kinetix", "roi", [0 0 448 328], "bin", 1)), ...
                "hadamard_stim:NoDmdCalibration");
            testCase.verifyEqual(dmd.SelectedCamera, "");
        end
    end

    methods
        function file = snap(testCase, image, stem)
            snap = struct("img", image, "bin", 1, "type", 'Camera', "name", 'Teledyne Kinetix', ...
                "timestamp", datetime(2026, 11, 6), "ref2d", struct("ImageSize", size(image), ...
                "XWorldLimits", [0 448], "YWorldLimits", [0 328]), ...
                "tform", struct("name", {'DMD (shared)'}, "tform", {affinetform2d(eye(3))}));
            file = fullfile(testCase.Folder, stem + "_cam-TeledyneKinetix.mat");
            save(file, "snap", "-v7.3");
        end
    end

    methods (Static)
        function dmd = dmd()
            dmd = LuminosWarpDmd("DMD (shared)");
            theta = deg2rad(7);
            dmd.PairTransform = struct("A", [1.6 * cos(theta), -1.6 * sin(theta), 40; ...
                1.6 * sin(theta), 1.6 * cos(theta), 25; 0 0 1]);
        end
    end
end

function xy = circle(centre, radius)
t = linspace(0, 2 * pi, 49)';
xy = centre + radius * [cos(t) sin(t)];
end

function c = centroid(mask)
[r, col] = find(mask);
c = [mean(col) mean(r)];
end

function r = act(c, action, payload)
if nargin < 3
    payload = struct();
end
r = hadamard_stim.apply_controller_action(c, action, payload, c.Revision);
assert(r.ok, "%s: %s", action, r.message);
end
