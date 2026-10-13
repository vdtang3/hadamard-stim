function out = tovec(mov)
%TOVEC A movie [rows x cols x frames] as [rows*cols x frames].
%
%   out = hadamard_stim.yitong.tovec(mov)
%
%   Port of tests/yitong_reference/external/lab/Image Processing/NeuroSegmentation/tovec.m
%   SHA-256 5632d67074160e2cb6cf354805be30323d77449d054f9e8aa315f36cc7cbc1ff
%   Changes: none.
[nr, nc, ~] = size(mov);
out = reshape(mov,nr*nc,[]);
end
