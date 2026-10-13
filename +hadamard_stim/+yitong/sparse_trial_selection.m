function [cIdxAllIt, idxNull, skipped] = sparse_trial_selection(cell_coord, distCutoff, nIt, picked)
%SPARSE_TRIAL_SELECTION Which cells each of a sparse trial's pulses stimulates.
%
%   [c_idx_all_it, used, skipped] = hadamard_stim.yitong.sparse_trial_selection(cell_coord, dist_cutoff, n_it, picked)
%
%   c_idx_all_it  cells x n_it; column it is pulse it's cells
%   used          cells pulsed at least once in this trial; the caller
%                 marks them in picked(:, cnt), as his script does
%   skipped       pulses with no cell left to choose. His loop skips them
%                 with continue, which leaves that pulse's DMD picture as
%                 whatever the previous trial put there; the protocol
%                 reproduces that (hadamard_stim.protocol.plan_sparse_trial).
%
%   Port of tests/yitong_reference/dragonfly/Auto Scripts/RunSynchronizedAQMulti_sparse_pulse_hadamard_behavior_v1.m
%   SHA-256 54dd37dcdfc4d46779b51997335076bc5e0b945fd04dd6a0d3e14c4b0c507b1c
%   Lines 135-176. Changes: the selection only; the DMD pictures are built
%   by the caller, and progress is not printed.
nCells = size(cell_coord, 1);
idxNull = false(nCells,1);
cIdxAllIt = false(nCells,nIt);
skipped = false(1,nIt);

for it = 1:nIt
    if isempty(setdiff(1:nCells,find(idxNull))), skipped(it) = true; continue; end

    cIdx = hadamard_stim.yitong.quasi_equidist_hardsphere_v2(cell_coord,distCutoff,find(idxNull),picked);
    cIdxAllIt(:,it) = cIdx;
    idxNull = cIdx | idxNull;
end
end
