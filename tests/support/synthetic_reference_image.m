function im = synthetic_reference_image(options)
%SYNTHETIC_REFERENCE_IMAGE Deterministic camera-like image with bright cells.
%   Full double precision, deliberately: Yitong's static_image_seg_v5
%   locates each cell's maximum by value over the whole image and fails when
%   two pixels tie, which integer or even single-precision images make
%   likely. Fixtures store a SHA-256 of the image rather than the image.
%   Background noise guarantees the >= 1000 watershed regions it requires.
arguments
    options.size (1,2) double = [328 448]
    options.n_cells (1,1) double = 400
    options.seed (1,1) double = 20261013
end
stream = RandStream("mt19937ar", "Seed", options.seed);
nr = options.size(1);
nc = options.size(2);
[x, y] = meshgrid(1:nc, 1:nr);
signal = zeros(nr, nc);
cx = 4 + rand(stream, options.n_cells, 1) * (nc - 8);
cy = 4 + rand(stream, options.n_cells, 1) * (nr - 8);
amp = 150 + 450 * rand(stream, options.n_cells, 1);
sigma = 1.2 + 0.8 * rand(stream, options.n_cells, 1);
for k = 1:options.n_cells
    signal = signal + amp(k) * exp(-((x - cx(k)).^2 + (y - cy(k)).^2) / (2 * sigma(k)^2));
end
background = 100 + 20 * (x / nc) + 10 * (y / nr);
noise = 6 * randn(stream, nr, nc);
im = background + signal + noise;
end
