function factors = pickFactors(product,possibleFactors)
%PICKFACTORS Factor PRODUCT into orders with known Hadamard matrices.
%
%   factors = hadamard_stim.yitong.pickFactors(product)
%
%   Port of tests/yitong_reference/external/lab/General Matlab/VIALUX control/Patterns/pickFactors.m
%   SHA-256 fb0d7f28c9b367c15cfc0cc15888fef3e73ccd2b596c5630aa237e4c5e09b797
%   Changes: the recursion is package-qualified.
if ~exist('possibleFactors','var')
    possibleFactors = [2 4:4:2^8];
end
possibleFactors(possibleFactors==1) = [];
divIdx = find(~rem(product,possibleFactors));
if isempty(divIdx)
    factors = [];
else
    for it = numel(divIdx):-1:1
        lowerFactors = hadamard_stim.yitong.pickFactors(product./possibleFactors(divIdx(it)),possibleFactors);
        factors = [lowerFactors possibleFactors(divIdx(it))];
        if product == prod(factors)
            break
        else
            factors = [];
        end
    end
end
end
