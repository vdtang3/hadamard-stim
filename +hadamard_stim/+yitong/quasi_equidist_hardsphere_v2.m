function cIdx = quasi_equidist_hardsphere_v2(xy,distCutoff,idxNull,picked)
%QUASI_EQUIDIST_HARDSPHERE_V2 One sparse pulse: cells all > distCutoff apart.
%
%   cIdx = hadamard_stim.yitong.quasi_equidist_hardsphere_v2(xy, distCutoff, idxNull, picked)
%
%   Greedy: start from the unused cell picked least often in earlier trials
%   (ties to the lowest index), then keep adding the least-picked cell
%   farther than distCutoff from every cell chosen so far. idxNull lists
%   cells already pulsed in this trial; picked is cells x trials.
%
%   Port of tests/yitong_reference/dragonfly/Utilities/quasi_equidist_hardsphere_v2.m
%   SHA-256 38a23be9419dd464706152b0c0bc70b6a1452ca77b3223df9f92fca3eb16312c
%   Changes: none beyond the help text.
nCells = length(xy);
distMat = squareform(pdist(xy));
distBinMat = distMat>distCutoff;
nPicked = sum(picked,2);

idxUse = setdiff(1:nCells,idxNull);

[~,nPickedSortIdx] = sort(nPicked(idxUse));
idxCur = idxUse(nPickedSortIdx(1));

idxItCum = [];
idxItCum = [idxItCum idxCur];
itMask = distBinMat(idxCur,:);
itMask(idxNull) = false;

while any(itMask)
    idxItMask = find(itMask);

    [~,nPickedSortIdx] = sort(nPicked(idxItMask));
    idxCur = idxItMask(nPickedSortIdx(1));

    idxItCum = [idxItCum idxCur]; %#ok<AGROW>

    itMask = itMask & distBinMat(idxCur,:);
end

cIdx = false(nCells,1);
cIdx(idxItCum) = true;
end
