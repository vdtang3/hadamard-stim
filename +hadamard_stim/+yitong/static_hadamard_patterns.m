function mask_sequence = static_hadamard_patterns(dmd_pat)
%STATIC_HADAMARD_PATTERNS The 64 DMD masks of his 63x14 Hadamard scan.
%
%   mask_sequence = hadamard_stim.yitong.static_hadamard_patterns(dmd_pat)
%
%   Returns logical [1024 x 768 x 64] in his mask_sequence orientation,
%   each pattern ANDed with dmd_pat (default all true; drift correction
%   passes the DMD app's saved_mask when one is set).
%
%   Quirk kept for parity: generating the patterns seeds the GLOBAL random
%   generator with rng(142857, 'twister') and does not restore it (inside
%   hadamard_patterns_scramble_nopermutation). Callers that care about the
%   global stream must save and restore it themselves.
%
%   Port of tests/yitong_reference/dragonfly/dmd_control/quick_functions/static_Hadamard_patterns.m
%   SHA-256 cba148f99c0e2d9e14ae92f7d7343110bbe879142820a6969c9e1be41153d627
%   Changes: returns the masks instead of writing app.mask_sequence; the
%   preview figure is not drawn; helpers are package-qualified.
if nargin < 1
    dmd_pat = true(1024,768);
end
m_q = [63 14];
blocksize = m_q;
elementsize = 1;
alp_patterns = hadamard_stim.yitong.alp_btd_to_logical( ...
    hadamard_stim.yitong.hadamard_patterns_scramble_nopermutation(blocksize,elementsize)); %theoretical pattern
mask_sequence = bsxfun(@and,alp_patterns,dmd_pat);
end
