function b = bleaching_signal(movie_mean, nCells, nPixCell)
%BLEACHING_SIGNAL Yitong's brightness measure for the orange correction.
%
%   b = hadamard_stim.yitong.bleaching_signal(movie_mean, n_cells, n_pix_cell)
%
%   movie_mean is the mean of frames 501:1000 of a stimulation movie. b is
%   the median of the brightest n_cells * n_pix_cell pixels minus the
%   median pixel. The protocol keeps b0 from trial 1 and, at each retarget
%   trial after the first, scales orange by b0 / b1, where b1 is from the
%   trial before (notebook, P5).
%
%   Port of tests/yitong_reference/dragonfly/Auto Scripts/RunSynchronizedAQMulti_sparse_pulse_hadamard_behavior_v1.m
%   SHA-256 54dd37dcdfc4d46779b51997335076bc5e0b945fd04dd6a0d3e14c4b0c507b1c
%   Lines 250-259. Changes: the measure only, on a mean image passed in;
%   reading the movie is the caller's.
imVec = sort(hadamard_stim.yitong.tovec(movie_mean),'descend');
b = median(imVec(1:nCells*nPixCell)) - median(imVec);
end
