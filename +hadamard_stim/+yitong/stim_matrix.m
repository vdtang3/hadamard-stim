function had_mat = stim_matrix(had_order)
%STIM_MATRIX The cell-by-code stimulation matrix of Yitong's protocol.
%
%   had_mat = hadamard_stim.yitong.stim_matrix(had_order)
%
%   had_mat(c, j) is true when cell c is stimulated by code j. The script
%   starts from hadamard(had_order), but every element of that is +-1 and
%   the two randperm lines only write -1, so the xor with a seeded uniform
%   draw leaves rand(had_order) <= .5 under rng(0, 'twister'): the Hadamard
%   structure is discarded (notebook, finding 1). The lines are kept as he
%   wrote them so the result is his by construction, not by that argument.
%
%   The global generator is restored to its state on entry. His script
%   reset it with rng('default') instead, which the parity runner reproduces
%   (hadamard_stim.protocol), not this function.
%
%   Port of tests/yitong_reference/dragonfly/Auto Scripts/RunSynchronizedAQMulti_sparse_pulse_hadamard_behavior_v1.m
%   SHA-256 54dd37dcdfc4d46779b51997335076bc5e0b945fd04dd6a0d3e14c4b0c507b1c
%   Lines 51-57. Changes: had_order is an argument; global RNG restored.
arguments
    had_order (1, 1) double {mustBeInteger, mustBePositive} = 320
end
incoming = rng;
restore = onCleanup(@() rng(incoming));

hadMat = hadamard(had_order);
hadMat(1, randperm(had_order, had_order / 2)) = -1;
hadMat(randperm(had_order, had_order / 2), 1) = -1;
rng(0, 'twister')
had_mat = xor(hadMat, rand(had_order) > .5);
end
