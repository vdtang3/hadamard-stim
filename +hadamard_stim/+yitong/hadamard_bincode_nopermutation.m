function bincode = hadamard_bincode_nopermutation(length)
%HADAMARD_BINCODE_NOPERMUTATION Binary Hadamard code without row permutation.
%
%   bincode = hadamard_stim.yitong.hadamard_bincode_nopermutation(length)
%
%   The last LENGTH rows of the next Hadamard matrix, as logicals. For
%   length 63 that is hadamard(64) without its first row.
%
%   Port of tests/yitong_reference/dragonfly/Hadamard/hadamard_bincode_nopermutation.m
%   SHA-256 226512dbe0533a67903d7ee43ece9653554f60e6b602471ee8e7d19e35248ca6
%   Changes: nextHadamard is package-qualified.
bincode = ~~(hadamard_stim.yitong.nextHadamard(length)/2+.5);
bincode = bincode(end-length+1:end,:);
end
