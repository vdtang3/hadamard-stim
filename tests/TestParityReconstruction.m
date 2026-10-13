classdef TestParityReconstruction < matlab.unittest.TestCase
    %TESTPARITYRECONSTRUCTION The reconstruction ports give his numbers.
    %
    %   Rebuilds the synthetic movies of tests/golden/golden_reconstruction.m
    %   (same patterns, sample, seeds, file layout) in a temporary folder,
    %   checks they are byte-identical to the ones his code was run on, and
    %   compares the ports' calibration and images with the fixture exactly.

    properties
        Golden
        Folder
        Sample
        Movies      % the regenerated movies, uint16, by name
    end

    methods (TestClassSetup)
        function buildMovies(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(root, "tests", "support")));
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Folder = fullfile(temp.Folder, "reconstruction");
            mkdir(testCase.Folder);
            testCase.Golden = load(fullfile(root, "tests", "fixtures", "yitong_reconstruction.mat"));

            % Exactly as golden_reconstruction.m.
            patterns = hadamard_stim.yitong.alp_btd_to_logical( ...
                hadamard_stim.yitong.hadamard_patterns_scramble_nopermutation([63 14], 1));
            rows = 32;
            cols = 700;
            uniform = 2000 * ones(rows, cols);
            stream = RandStream("mt19937ar", "Seed", 7);
            [x, y] = meshgrid(1:cols, 1:rows);
            sample = 200 * ones(rows, cols);
            for k = 1:120
                cx = 1 + rand(stream) * (cols - 1);
                cy = 1 + rand(stream) * (rows - 1);
                sample = sample + 1500 * exp(-((x - cx).^2 + (y - cy).^2) / (2 * 1.5^2));
            end
            testCase.Sample = sample;
            g = testCase.Golden;
            testCase.assertEqual(string(sha256_of(sample)), g.sample_sha256, ...
                "The synthetic sample no longer matches the fixture's");
            samples = {uniform, uniform, sample, 0.6 * sample};
            testCase.Movies = struct();
            for k = 1:numel(samples)
                m = synthetic_hadamard_movie(patterns, samples{k}, g.n_repeats, g.movie_seeds(k));
                testCase.assertEqual(string(sha256_of(m)), g.movie_sha256(k), ...
                    "Movie " + g.movie_names(k) + " differs from the one his code read");
                write_movie(fullfile(testCase.Folder, g.movie_names(k)), m);
                testCase.Movies.(matlab.lang.makeValidName(g.movie_names(k))) = m;
            end
        end
    end

    methods (Test)
        function coresOnInMemoryMoviesMatchTheFileWrappers(testCase)
            % Luminos hands movies over in memory. The cores given the very
            % arrays the wrappers read from disk must give the same numbers.
            g = testCase.Golden;
            [cal1, cal2, z1, z2] = testCase.moviesNamed(g.movie_names);
            scorr = hadamard_stim.yitong.hadamard_pinhole_calibration([63 14], {cal1, cal2});
            testCase.verifyEqual(string(sha256_of(scorr)), g.dmd.calibration_sha256);
            testCase.verifyEqual(hadamard_stim.yitong.dmd_hadamard_reconstruct_core( ...
                [63 14], {z1}, scorr), g.dmd.image);
            testCase.verifyEqual(hadamard_stim.yitong.dmd_hadamard_reconstruct_core( ...
                [63 14], {z2}, scorr), g.dmd.image_cached_calibration);
            [had_all, ref_all] = hadamard_stim.yitong.hadamard_reconstruct_core( ...
                [63 14], {z1, z2}, scorr);
            testCase.verifyEqual(had_all, g.z_stack.had_all);
            testCase.verifyEqual(ref_all, g.z_stack.ref_all);
        end

        function dmdReconstructionIsHis(testCase)
            g = testCase.Golden.dmd;
            [im, scorr] = hadamard_stim.yitong.dmd_hadamard_reconstruct( ...
                [63 14], testCase.Folder, 'had_cal_synth', 'synth_ref_z01_rpt01');
            testCase.verifySize(scorr, g.calibration_size);
            testCase.verifyEqual(scorr(:, 1:16, :), g.calibration_crop);
            testCase.verifyEqual(string(sha256_of(scorr)), g.calibration_sha256);
            testCase.verifyEqual(im, g.image);
            testCase.verifyEqual(corr(im(:), testCase.Sample(:)), g.correlation_with_sample, ...
                "AbsTol", 1e-12);
        end

        function cachedCalibrationIsReusedAsHisWas(testCase)
            g = testCase.Golden.dmd;
            [~, scorr] = hadamard_stim.yitong.dmd_hadamard_reconstruct( ...
                [63 14], testCase.Folder, 'had_cal_synth', 'synth_ref_z01_rpt01');
            im = hadamard_stim.yitong.dmd_hadamard_reconstruct( ...
                [63 14], testCase.Folder, [], 'synth_ref_z02_rpt01', scorr);
            testCase.verifyEqual(im, g.image_cached_calibration);
        end

        function zStackReconstructionIsHis(testCase)
            g = testCase.Golden.z_stack;
            [had_all, ref_all] = hadamard_stim.yitong.hadamard_reconstruct( ...
                [63 14], testCase.Folder, 'had_cal_synth', 'synth_ref_z*_rpt01');
            testCase.verifyEqual(had_all, g.had_all);
            testCase.verifyEqual(ref_all, g.ref_all);
        end
    end

    methods
        function varargout = moviesNamed(testCase, names)
            varargout = arrayfun(@(n) testCase.Movies.(matlab.lang.makeValidName(n)), ...
                names, "UniformOutput", false);
        end
    end
end

function write_movie(dir_name, movie)
% Sq_camera.bin plus the parameters file, as golden_reconstruction.m wrote them.
mkdir(dir_name);
[rows, cols, ~] = size(movie);
fid = fopen(fullfile(dir_name, "experimental_parameters.txt"), "w");
fprintf(fid, "Horizontal pixel:_____________\t %d\nVertical pixel:_______________\t %d", cols, rows);
fclose(fid);
fid = fopen(fullfile(dir_name, "Sq_camera.bin"), "w");
fwrite(fid, permute(movie, [2 1 3]), "uint16");
fclose(fid);
assert(isequal(hadamard_stim.yitong.read_vm_movie(dir_name), movie), "Movie did not round-trip");
end

function hex = sha256_of(value)
% As tests/golden/mocks/golden_sha256: column-major bytes, logical as uint8.
if islogical(value)
    value = uint8(value);
end
md = java.security.MessageDigest.getInstance("SHA-256");
md.update(typecast(reshape(value, [], 1), "int8"));
hex = lower(reshape(dec2hex(typecast(md.digest(), "uint8"), 2).', 1, []));
end
