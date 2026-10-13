function cIdx = quasi_equidist_hardsphere_v2(xy,distCutoff,idxNull,picked)

nCells = length(xy);
distMat = squareform(pdist(xy));
distBinMat = distMat>distCutoff;
nPicked = sum(picked,2);

idxUse = setdiff(1:nCells,idxNull);

[~,nPickedSortIdx] = sort(nPicked(idxUse));
idxCur = idxUse(nPickedSortIdx(1));

% idxCur = idxUse(randperm(length(idxUse),1));
idxItCum = [];
idxItCum = [idxItCum idxCur];
itMask = distBinMat(idxCur,:);
itMask(idxNull) = false;

while any(itMask)
    idxItMask = find(itMask);

    [~,nPickedSortIdx] = sort(nPicked(idxItMask));
    idxCur = idxItMask(nPickedSortIdx(1));
    
    idxItCum = [idxItCum idxCur];

    itMask = itMask & distBinMat(idxCur,:);
end

cIdx = false(nCells,1);
cIdx(idxItCum) = true;