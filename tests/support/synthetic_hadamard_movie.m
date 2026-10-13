function movie = synthetic_hadamard_movie(patterns, sample, n_repeats, seed)
%SYNTHETIC_HADAMARD_MOVIE Camera movie of SAMPLE under DMD PATTERNS.
%   patterns: DMD frames (1024 x 768 x n, logical), in Yitong's orientation.
%   sample:   in-focus brightness per camera pixel (rows x cols).
%   Camera pixel (r, c) images DMD pixel (200 + r, 30 + c) through a 3x3
%   box PSF. Each frame is 100 (camera offset) + 30% unmodulated
%   background + 70% patterned signal + small deterministic noise, as
%   uint16. The pattern sequence repeats N_REPEATS times.
[rows, cols] = size(sample);
n = size(patterns, 3);
psf = ones(3) / 9;
modulation = zeros(rows, cols, n);
for k = 1:n
    blurred = conv2(double(patterns(:, :, k)), psf, "same");
    modulation(:, :, k) = blurred(200 + (1:rows), 30 + (1:cols));
end
stream = RandStream("mt19937ar", "Seed", seed);
frames = repmat(sample .* (0.3 + 0.7 * modulation), 1, 1, n_repeats);
movie = uint16(round(100 + frames + 3 * randn(stream, size(frames))));
end
