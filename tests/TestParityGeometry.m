classdef TestParityGeometry < matlab.unittest.TestCase
    %TESTPARITYGEOMETRY Segmentation, spots and DMD masks equal his.
    %
    %   Inputs are his 2025-03-08 reference image and registration
    %   (yitong_session_inputs); the expected outputs are what his own code
    %   produced from them (yitong_segmentation, yitong_masks).

    properties
        Inputs
        Segmentation
        Masks
        Matrix
    end

    methods (TestClassSetup)
        function load_(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "support")));
            testCase.Inputs = load(fixture("session_inputs"));
            testCase.Segmentation = load(fixture("segmentation"));
            testCase.Masks = load(fixture("masks"));
            testCase.Matrix = load(fixture("matrix"), "had_mat");
        end
    end

    methods (Test)
        function segmentationOfHisImage(testCase)
            s = testCase.Segmentation.real;
            ref = testCase.Inputs.session_2025.ref_im;
            [x, y, min_val] = hadamard_stim.yitong.static_image_seg_v5(ref, s.threshold, s.n_exclude);
            testCase.verifyEqual([x y], s.cells);
            testCase.verifyEqual(min_val, s.min_val);
            [x0, y0] = hadamard_stim.yitong.static_image_seg_v5(ref, s.threshold, 0);
            testCase.verifyEqual([x0 y0], s.cells_n_exclude_0);
        end

        function segmentationOfTheSyntheticImage(testCase)
            s = testCase.Segmentation.synthetic;
            im = synthetic_reference_image();
            for n = [0 5]
                c = s.("n_exclude_" + n);
                [x, y, min_val] = hadamard_stim.yitong.static_image_seg_v5(im, c.threshold, n);
                testCase.verifyEqual([x y], c.cells);
                testCase.verifyEqual(min_val, c.min_val);
            end
        end

        function aMaximumValueElsewhereInTheImageIsIgnored(testCase)
            % P4, Firefly 2026-10-30: region 366's maximum also occurred at
            % a pixel 190 rows away, and his whole-image search returned two
            % pixels for one cell. Copy a kept cell's maximum value onto the
            % nearest-valued pixel far from it that is not a peak itself:
            % the cells are unchanged.
            im = synthetic_reference_image();
            [x, y] = hadamard_stim.yitong.static_image_seg_v5(im, 320, 5);
            v = im(y(1), x(1));
            [rr, cc] = ndgrid(1:size(im, 1), 1:size(im, 2));
            far = hypot(rr - y(1), cc - x(1)) > 50 & im < imdilate(im, ones(3));
            gap = abs(im - v);
            gap(~far) = Inf;
            [~, k] = min(gap(:));
            tied = im;
            tied(k) = v;
            testCase.assertEqual(nnz(tied == v), 2, "the value now occurs twice");
            [x2, y2] = hadamard_stim.yitong.static_image_seg_v5(tied, 320, 5);
            testCase.verifyEqual([x2 y2], [x y]);
        end

        function integerImagesSegment(testCase)
            % P4: the integer image his code failed on (the fixture records
            % his error) now segments, each cell at its own region's maximum.
            testCase.verifySubstring(testCase.Segmentation.integer_image_error, "different number of elements");
            im = round(synthetic_reference_image());
            [x, y] = hadamard_stim.yitong.static_image_seg_v5(im, 320, 0);
            testCase.verifySize(x, [320 1]);
            testCase.verifyEqual(size(unique([x y], "rows"), 1), 320, "one pixel per cell");
            testCase.verifyEqual([x y], round([x y]));
        end

        function aBlankImageSaysNoCellsWereDetected(testCase)
            % A slide with nothing on it: too few regions to rank.
            testCase.verifyError(@() hadamard_stim.yitong.static_image_seg_v5( ...
                100 * ones(328, 448), 320, 0), "hadamard_stim:TooFewRegions");
            % Enough regions, too few candidates for the cells asked for.
            im = synthetic_reference_image();
            try
                hadamard_stim.yitong.static_image_seg_v5(im, 5000, 0);
                testCase.verifyFail("Asking for more cells than candidates did not error.");
            catch err
                testCase.verifyEqual(string(err.identifier), "hadamard_stim:TooFewCandidates");
                testCase.verifySubstring(string(err.message), "No cells detected");
            end
            % thres + n_exclude is exactly what it needs, and min_val thres + 99.
            [~, ~, ~] = hadamard_stim.yitong.static_image_seg_v5(im, 50, 5);
        end

        function spotsReproduceHisSavedRois(testCase)
            % 2024-08-23: his saved camera-space ROIs, from his saved cells.
            s = testCase.Inputs.session_2024;
            illum = hadamard_stim.yitong.join_rois(hadamard_stim.yitong.auto_square_rois(s.cell_coord, 5));
            stim = hadamard_stim.yitong.join_rois(hadamard_stim.yitong.reduce_spot_size(illum, 3));
            testCase.verifyEqual(illum, s.mask_sequence_rois{1});
            testCase.verifyEqual(stim, s.mask_sequence_rois{2});
        end

        function canonicalPatternsAreHis(testCase)
            c = testCase.Masks.canonical;
            illum_spots = hadamard_stim.yitong.auto_square_rois(c.cell_coord, 5);
            illum = hadamard_stim.yitong.join_rois(illum_spots);
            stim_spots = hadamard_stim.yitong.reduce_spot_size(illum, 3);
            testCase.verifyEqual(illum, c.mask_sequence_rois{1});
            testCase.verifyEqual(hadamard_stim.yitong.join_rois(stim_spots), c.mask_sequence_rois{2});

            mask1 = hadamard_stim.yitong.dmd_draw_rasterize(illum_spots, c.registration_data, c.camera_offset);
            mask2 = hadamard_stim.yitong.dmd_draw_hidden(stim_spots, c.registration_data, c.camera_offset);
            testCase.verifyEqual(double(mask1), c.mask_sequence(:, :, 1));
            testCase.verifyEqual(double(mask2), c.mask_sequence(:, :, 2));
            % Without a saved_mask the two rasterisers agree, which is what
            % lets the port use one geometry for both.
            testCase.verifyEqual(hadamard_stim.yitong.dmd_draw_hidden(illum_spots, ...
                c.registration_data, c.camera_offset), mask1);
        end

        function spotSelectionIsHis(testCase)
            c = testCase.Masks.canonical;
            for name = ["hadamard_code_1" "sparse_first"]
                g = testCase.Masks.spot_select.(name);
                spots = hadamard_stim.yitong.spot_select(c.mask_sequence_rois{2}, g.c_idx);
                testCase.verifyEqual(hadamard_stim.yitong.join_rois(spots), g.rois{2}, name);
                mask2 = hadamard_stim.yitong.dmd_draw_hidden(spots, c.registration_data, c.camera_offset);
                testCase.verifyEqual(double(mask2), g.mask_sequence(:, :, 2), name);
            end
            testCase.verifyEqual(testCase.Masks.spot_select.hadamard_code_1.c_idx, ...
                testCase.Matrix.had_mat(:, 1) > 0);
        end

        function firstSparsePulseIsHis(testCase)
            c = testCase.Masks.canonical;
            n = size(c.cell_coord, 1);
            c_idx = hadamard_stim.yitong.quasi_equidist_hardsphere_v2(c.cell_coord, 123, [], zeros(n, 640));
            testCase.verifyEqual(c_idx, testCase.Masks.spot_select.sparse_first.c_idx);
        end
    end
end

function file = fixture(name)
file = fullfile(fileparts(mfilename("fullpath")), "fixtures", "yitong_" + name + ".mat");
end
