function btd = alp_logical_to_btd(bin)
%ALP_LOGICAL_TO_BTD Pack logical DMD pictures into ALP binary top-down bytes.
%
%   btd = hadamard_stim.yitong.alp_logical_to_btd(bin)
%
%   bin is [768 x 1024 x n] (his mask_sequence permuted [2 1 3]); btd is
%   uint8 [128 x 768 x n], eight mirrors per byte, the first in the most
%   significant bit. Copyright 2016-2017 Vicente Parot (MIT licence, as in
%   the frozen file).
%
%   Port of tests/yitong_reference/dragonfly/Hadamard/alp_logical_to_btd.m
%   SHA-256 2fcecf41c0d67e0c35c65a2cad8a54dee009c866912ca65c66d440539ff43820
%   Changes: pixel_configuration is package-qualified.
[device_rows, device_cols] = hadamard_stim.yitong.pixel_configuration;
bit_depth = uint8(8);
stride = device_rows/bit_depth;
logical_btd = reshape(permute(uint8(bin),[2 1 3]),bit_depth,stride,device_cols,[]);
btd = reshape(sum(bsxfun(@times,logical_btd,2.^(bit_depth-1:-1:0)'),'native'),stride,device_cols,[]);
end
