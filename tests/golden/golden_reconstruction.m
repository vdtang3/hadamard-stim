function data = golden_reconstruction(ctx)
%GOLDEN_RECONSTRUCTION Yitong's digital-pinhole Hadamard reconstruction.
%
%   dmd_hadamard_reconstruct (reference image and drift scans) and
%   hadamard_reconstruct (z-stack) run unmodified on synthetic movies that
%   are written to disk in the Sq_camera.bin format his vm class reads.
%   The camera is 32 x 700 pixels so his x(4096/width) upsampling stays
%   small (factor 4); at his real 448-pixel width the factor is 8 and the
%   intermediate array is several GB.
%
%   Shims: memory() (Windows-only) and ls() (Windows returns one row per
%   file; Linux one row for all, which would silently drop files).
golden_use_path(ctx, "reconstruction", lab_image_processing=true);
patterns = alp_btd_to_logical(hadamard_patterns_scramble_nopermutation([63 14], 1));
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

folder = fullfile(ctx.tmp, "reconstruction") + filesep;
mkdir(folder);
movies = struct( ...
    "name", {"120000_had_cal_synth_1", "120100_had_cal_synth_2", ...
             "121000_synth_ref_z01_rpt01", "121100_synth_ref_z02_rpt01"}, ...
    "sample", {uniform, uniform, sample, 0.6 * sample}, ...
    "seed", {1, 2, 3, 4});
data.camera_size = [rows cols];
data.n_repeats = 2;
data.movie_names = [movies.name];
data.movie_seeds = [movies.seed];
data.sample_sha256 = string(golden_sha256(sample));
data.movie_sha256 = strings(1, numel(movies));
for k = 1:numel(movies)
    m = synthetic_hadamard_movie(patterns, movies(k).sample, data.n_repeats, movies(k).seed);
    data.movie_sha256(k) = string(golden_sha256(m));
    write_movie(fullfile(folder, movies(k).name), m);
end

% dmd_hadamard_reconstruct: calibrate from both cal movies, reconstruct z01.
app = MockDmdApp(MockVialuxDMD(MockAlpDevice()));
im = dmd_hadamard_reconstruct(app, [63 14], char(folder), 'had_cal_synth', 'synth_ref_z01_rpt01');
data.dmd.image = im;
% The full calibration (32 x 700 x 64 doubles) is 11 MB; keep its hash and
% a crop for diagnosing a port mismatch.
calibration = app.function_data.hadamard_cal.data;
data.dmd.calibration_size = size(calibration);
data.dmd.calibration_sha256 = string(golden_sha256(calibration));
data.dmd.calibration_crop = calibration(:, 1:16, :);
% Sanity, not parity: the in-focus reconstruction should resemble the sample.
data.dmd.correlation_with_sample = corr(im(:), sample(:));
data.dmd.hadamard_ref_set = isequal(app.function_data.hadamard_ref, im);
% Second call with an empty calibration prefix reuses the cached calibration,
% as drift correction does.
data.dmd.image_cached_calibration = dmd_hadamard_reconstruct(app, [63 14], char(folder), [], 'synth_ref_z02_rpt01');
delete(app);

% hadamard_reconstruct: z-stack of both reference planes.
[had_all, ref_all] = hadamard_reconstruct([63 14], char(folder), 'had_cal_synth', 'synth_ref_z*_rpt01');
data.z_stack.had_all = had_all;
data.z_stack.ref_all = ref_all;
close all force
end

function write_movie(dir_name, movie)
% Sq_camera.bin plus the parameters file, laid out the way vm reads them;
% checked by reading it back.
mkdir(dir_name);
[rows, cols, ~] = size(movie);
fid = fopen(fullfile(dir_name, "experimental_parameters.txt"), "w");
fprintf(fid, "Horizontal pixel:_____________\t %d\nVertical pixel:_______________\t %d", cols, rows);
fclose(fid);
fid = fopen(fullfile(dir_name, "Sq_camera.bin"), "w");
fwrite(fid, permute(movie, [2 1 3]), "uint16");
fclose(fid);
assert(isequal(vm(char(dir_name)).data, movie), "Movie did not round-trip through vm");
end
