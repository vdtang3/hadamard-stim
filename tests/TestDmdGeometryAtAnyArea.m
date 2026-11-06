classdef TestDmdGeometryAtAnyArea < matlab.unittest.TestCase
    %TESTDMDGEOMETRYATANYAREA One DMD calibration serves every camera area.
    %
    %   Luminos's camera-to-DMD calibration is in unbinned sensor
    %   coordinates, so cells found at a new field of view (another camera
    %   area or binning than the calibration was measured at, e.g. once the
    %   animal is on) are drawn without recalibrating: active_geometry
    %   composes the calibration with the camera area's origin. A spot at one
    %   place on the sensor lands at one place on the DMD, whichever area it
    %   was found in; areas beyond the calibrated one are extrapolated and
    %   say so; the calibration's own area is drawn by setPatterningROI as
    %   before.

    properties
        Root
    end

    methods (TestClassSetup)
        function setUp(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
        end
    end

    methods (Test)
        function aSpotLandsInOnePlaceFromEveryArea(testCase)
            dmd = TestDmdGeometryAtAnyArea.dmd();
            sensor = [230 170];                 % spot centre, unbinned sensor pixels
            radius = 12;                        % sensor pixels
            reference = TestDmdGeometryAtAnyArea.drawn(dmd, [0 448 0 328], 1, sensor, radius);
            testCase.assertGreaterThan(nnz(reference.mask), 50);
            testCase.verifyEqual(reference.identity.drawn_by, "setPatterningROI", ...
                "The calibration's own area is drawn by Luminos as before.");
            testCase.verifyFalse(reference.identity.extrapolated);

            for area = {{[100 300 60 200], 1}, {[100 300 60 200], 2}, {[0 448 0 328], 2}, {[150 120 120 100], 1}}
                roi = area{1}{1};
                bin = area{1}{2};
                other = TestDmdGeometryAtAnyArea.drawn(dmd, roi, bin, sensor, radius);
                label = sprintf("area %s bin %d", mat2str(roi), bin);
                testCase.verifyNotEqual(other.identity.drawn_by, "setPatterningROI", label);
                testCase.verifyFalse(other.identity.extrapolated, label + " is inside the calibration.");
                testCase.verifyLessThan(norm(centroid(other.mask) - centroid(reference.mask)), 1.5, ...
                    label + ": the spot moved on the DMD.");
                testCase.verifyEqual(nnz(other.mask), nnz(reference.mask), "RelTol", 0.2, label);
                overlap = nnz(other.mask & reference.mask) / nnz(other.mask | reference.mask);
                testCase.verifyGreaterThan(overlap, 0.75, label);
            end
        end

        function anAreaBeyondTheCalibrationIsExtrapolatedAndSaysSo(testCase)
            dmd = TestDmdGeometryAtAnyArea.dmd();
            camera = hadamard_stim.testing.FakeLuminosCamera("Teledyne Kinetix");
            camera.ROI = [400 300 250 200];      % x 400..700, y 250..450: past 448 x 328
            [geometry, mismatch] = hadamard_stim.luminos.active_geometry(dmd, camera);
            testCase.verifyTrue(geometry.identity.extrapolated);
            testCase.verifySubstring(mismatch.message, "extrapolated");
            % Where the calibration's affine map puts the spot's sensor position.
            sensor = [600 380];
            spot = sensor - [400 250];          % in this area's pixels (bin 1)
            mask = geometry.rasterize({circle(spot, 10)}, "auto_square");
            expected = dmd.PairTransform.A * [sensor 1]';
            testCase.verifyLessThan(norm(centroid(mask) - expected(1:2)'), 1.5);
        end

        function aPolynomialCalibrationIsPaddedAsLuminosDoes(testCase)
            % No matrix to compose: the mask is placed on the sensor and the
            % calibration applied there, Luminos's fallback. Here the
            % "polynomial" is the same affine map given only as a function
            % (geometricTransform2d), which has no matrix to compose.
            dmd = TestDmdGeometryAtAnyArea.dmd();
            matrix = dmd.PairTransform.A;
            reference = TestDmdGeometryAtAnyArea.drawn(dmd, [0 448 0 328], 1, [230 170], 12);
            dmd.PairTransform = geometricTransform2d(@(uv) inverse_map(uv, matrix));
            camera = hadamard_stim.testing.FakeLuminosCamera("Teledyne Kinetix");
            camera.ROI = [100 300 60 200];
            geometry = hadamard_stim.luminos.active_geometry(dmd, camera);
            mask = geometry.rasterize({circle([230 170] - [100 60], 12)}, "auto_square");
            testCase.verifyLessThan(norm(centroid(mask) - centroid(reference.mask)), 1.5);
        end

        function aSnapAtANewAreaNeedsNoRecalibration(testCase)
            % The animal's field: a smaller area, binned, never calibrated at.
            dmd = TestDmdGeometryAtAnyArea.dmd();
            snap = struct("name", "Teledyne Kinetix", "roi", [100 60 300 200], "bin", 2, ...
                "image_size", [100 150], "transforms", struct("name", {}, "matrix", {}), "file", "x.mat");
            fit = hadamard_stim.luminos.check_reference_snap(snap, dmd, "Teledyne Kinetix", ...
                [100 60 300 200], 2);
            testCase.verifyEqual(fit.grid, [100 150]);
            testCase.verifyEqual(fit.roi, [100 60 300 200]);
            testCase.verifyEqual(fit.calibration_roi, [0 0 448 328]);
            % Its recorded transform is the calibration's: still accepted.
            snap.transforms = struct("name", "DMD (shared)", "matrix", dmd.PairTransform.A);
            hadamard_stim.luminos.check_reference_snap(snap, dmd, "Teledyne Kinetix", [100 60 300 200], 2);
            % The camera moved to another area since: the Snap's pixels are
            % not where the run's images are, so it is refused - without
            % asking for a DMD calibration.
            err = verifyThrows(@() hadamard_stim.luminos.check_reference_snap(snap, dmd, ...
                "Teledyne Kinetix", [0 0 448 328], 1));
            testCase.verifyEqual(err.identifier, 'hadamard_stim:IncompatibleSnap');
            testCase.verifySubstring(err.message, "no DMD recalibration is needed");
        end
    end

    methods (Static)
        function dmd = dmd()
            % Calibrated at 448 x 328 from the sensor origin, bin 1, with a
            % rotated, scaled, shifted camera->DMD map.
            dmd = LuminosWarpDmd("DMD (shared)");
            theta = deg2rad(7);
            scale = 1.6;
            A = [scale * cos(theta), -scale * sin(theta), 40; ...
                 scale * sin(theta),  scale * cos(theta), 25; 0 0 1];
            dmd.PairTransform = struct("A", A);
        end

        function out = drawn(dmd, roi, bin, sensor, radius)
            % A disc at a sensor position, found in a camera at roi
            % ([left width top height]) and bin, drawn on the DMD.
            camera = hadamard_stim.testing.FakeLuminosCamera("Teledyne Kinetix");
            camera.ROI = roi;
            camera.bin = bin;
            geometry = hadamard_stim.luminos.active_geometry(dmd, camera);
            local = (sensor - [roi(1) roi(3)]) / bin;
            out.mask = geometry.rasterize({circle(local, radius / bin)}, "auto_square");
            out.identity = geometry.identity;
        end
    end
end

function xy = circle(centre, radius)
t = linspace(0, 2 * pi, 49)';
xy = centre + radius * [cos(t) sin(t)];
end

function xy = inverse_map(uv, matrix)
% DMD -> sensor for imwarp (which maps output points back to the input).
p = matrix \ [uv ones(size(uv, 1), 1)]';
xy = p(1:2, :)';
end

function c = centroid(mask)
[r, col] = find(mask);
c = [mean(col) mean(r)];
end

function err = verifyThrows(f)
err = [];
try
    f();
catch err
end
assert(~isempty(err), "Expected an error.");
end
