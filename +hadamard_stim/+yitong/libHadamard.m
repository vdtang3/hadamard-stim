function h = libHadamard(n,testOnly)
%LIBHADAMARD Hadamard matrix of order n, if one is known.
%
%   h = hadamard_stim.yitong.libHadamard(n)
%
%   Port of tests/yitong_reference/external/lab/General Matlab/VIALUX control/Patterns/libHadamard.m
%   SHA-256 ebcaa873a6e865e044f28f29b42235a423dc91f023d2fc25ebaae17b797f6408
%   Changes: the orders his version reads from text files in a "hadlib"
%   folder (28, 36, 44, ...) raise an error instead, because that library
%   is not part of the port. The protocol's 63-code scan needs order 64,
%   which is hadamard(64) and never reaches that branch. pickFactors and
%   the recursion are package-qualified.
if ~exist('testOnly','var')
    testOnly = false;
end
factors = hadamard_stim.yitong.pickFactors(n);
if testOnly
    h = ~isempty(factors);
else
    hlib = [ % list of some stored hadamard matrices
        28 36 44 52 56 60 68 72 76 84 88 92 100 104 108 112 116 120 ...
        124 132 136 140 144 148 152 156 164 168 172 176 180 184 188 ...
        196 200 204 208 212 216 220 224 228 232 236 240 244 248 252];
    if ismember(n,hlib)
        error('hadamard_stim:HadamardLibrary', ...
            ['A Hadamard matrix of order %d comes from the lab''s hadlib text ' ...
             'files, which are not part of this port.'], n);
    elseif (...
            (~mod(log2(n),1) && log2(n)>=0) || ...
            (~mod(log2(n/12),1) && log2(n/12)>=0) || ...
            (~mod(log2(n/20),1)) && log2(n/20)>=0)
        h = hadamard(n);
    elseif ~isempty(factors)
        h = 1;
        for it = 1:numel(factors)
           h = kron(h,hadamard_stim.yitong.libHadamard(factors(it)));
        end
    else
        h = [];
    end
end
end
