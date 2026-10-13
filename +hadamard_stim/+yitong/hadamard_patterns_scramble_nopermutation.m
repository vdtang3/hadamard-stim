function [alp_pattern_data, bincode] = ...
    hadamard_patterns_scramble_nopermutation(nblock_and_step,...
    projection_element,super_mask)
%HADAMARD_PATTERNS_SCRAMBLE_NOPERMUTATION Scrambled Hadamard scan patterns.
%
%   [btd, bincode] = hadamard_stim.yitong.hadamard_patterns_scramble_nopermutation([m q], element)
%
%   The structured-illumination patterns of an m-code Hadamard scan with
%   block step q, as packed ALP bytes [128 x 768 x m+1]. The scramble mask
%   comes from the global generator after rng(142857, 'twister'), which is
%   left in that state on return, exactly as in his code.
%
%   Port of tests/yitong_reference/dragonfly/Hadamard/hadamard_patterns_scramble_nopermutation.m
%   SHA-256 f9f89a8daf49bb36c3a55115270b8f8f1404c3a66e4c0ea0a64d68361e0100f1
%   Changes: pixel_configuration, hadamard_bincode_nopermutation and
%   alp_logical_to_btd are package-qualified.
[device_rows, device_cols, active_rows, active_cols, ...
    active_row_offset, active_col_offset] = hadamard_stim.yitong.pixel_configuration; %#ok<ASGLU>
if nargin < 3
    super_mask = ones(device_rows,device_cols);
end
if nargin < 2
    projection_element = 1;
end
projection_element = max(round(projection_element),1);
nblock = nblock_and_step(1);
blockstep = nblock_and_step(2);
bincode = hadamard_stim.yitong.hadamard_bincode_nopermutation(nblock);
bitplanes = size(bincode,2);
plind = mod(bsxfun(@plus,blockstep*(0:nblock-1)',0:nblock-1),nblock)+1;
[rr, cc] = find(plind);
xs = false(nblock*[1 1 1]);
xs(sub2ind(nblock*[1 1 1],rr,cc,plind(:))) = true;
xs = reshape(xs,[nblock*nblock nblock]);
xs = ~~(double(xs)*double(bincode));
xs = reshape(xs,[nblock nblock bitplanes]);
xs = bsxfun(@times,xs*2-1,mod(1:nblock,2)'*2-1)/2+.5; % works fine with 11,3; 63,14; 19,5;
xs = ~[xs; ~xs];
xspat = repmat(...
    imresize(xs,projection_element,'nearest'),...
    ceil([device_rows/nblock/2 device_cols/nblock]./projection_element));
rng(142857,'twister')
xsrand = sign(randn(nblock*[2 1].*ceil([device_rows/nblock/2 device_cols/nblock]./projection_element)));
xsfullrand = imresize(xsrand,projection_element,'nearest');
xspat = bsxfun(@xor,xspat,xsfullrand>0);
alp_pattern_data = bsxfun(@times,xspat(1:active_rows,1:active_cols,:),logical(super_mask));
alp_pattern_data = hadamard_stim.yitong.alp_logical_to_btd(permute(alp_pattern_data,[2 1 3]));
end
