function m = affine_matrix(t)
%AFFINE_MATRIX A 2-D geometric transform's 3 x 3 matrix, in affinetform2d's A convention.
%
%   m = hadamard_stim.luminos.affine_matrix(t)
%
%   affinetform2d / projtform2d (and structs with A) give A; the older
%   affine2d / projective2d (and structs with T) give T', which is the same
%   matrix in A's convention. [] for a transform with no matrix (e.g. a
%   polynomial fit), so two of those are never taken to be the same.
m = [];
if isempty(t)
    return
end
if (isobject(t) && isprop(t, "A")) || (isstruct(t) && isfield(t, "A"))
    m = double(t.A);
elseif (isobject(t) && isprop(t, "T")) || (isstruct(t) && isfield(t, "T"))
    m = double(t.T)';
end
end
