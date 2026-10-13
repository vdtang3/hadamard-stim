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

        function tiedMaximaStillFail(testCase)
            % P4: reproduced, not fixed.
            try
                hadamard_stim.yitong.static_image_seg_v5(round(synthetic_reference_image()), 320, 0);
                testCase.verifyFail("A tied maximum no longer errors.");
            catch err
                testCase.verifyEqual(string(err.message), testCase.Segmentation.integer_image_error);
            end
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
