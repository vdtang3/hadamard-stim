function h = nextHadamard(n)
%NEXTHADAMARD Smallest available Hadamard matrix of order above n.
%
%   h = hadamard_stim.yitong.nextHadamard(n)
%
%   Port of tests/yitong_reference/external/lab/General Matlab/VIALUX control/Patterns/nextHadamard.m
%   SHA-256 472ecd3801d382e5c322344bac527bef5478463478c8d5547c03e20261a8fa75
%   Changes: libHadamard is package-qualified.
if n < 2
    h = hadamard(n+1);
else
    h = [];
    n = floor(n/4)*4;
    while isempty(h)
        n = n + 4;
        h = hadamard_stim.yitong.libHadamard(n);
    end
end
end
