function alp_logical_patterns = alp_btd_to_logical(btd)
%ALP_BTD_TO_LOGICAL Unpack ALP binary top-down bytes into logical pictures.
%
%   alp_logical_patterns = hadamard_stim.yitong.alp_btd_to_logical(btd)
%
%   btd is uint8 [128 x 768 x n]; the result is logical [1024 x 768 x n],
%   his mask_sequence orientation. Vicente Parot, 2016.
%
%   Port of tests/yitong_reference/dragonfly/Hadamard/alp_btd_to_logical.m
%   SHA-256 b0b976cd35b13ccb707081e552fe5e251be4c8f6fece22a9be1c03c3c130b2e6
%   Changes: pixel_configuration is package-qualified.
[device_rows, device_cols] = hadamard_stim.yitong.pixel_configuration;
alp_logical_patterns = false(device_rows,device_cols,size(btd,3));
for patidx = 1:size(alp_logical_patterns,3)
    alp_logical_patterns(:,:,patidx) = ~~reshape(permute(cell2mat(arrayfun(@(n)~~bitget(btd(:,:,patidx),n),permute(8:-1:1,[1 4 3 2]),'uni',false)),[4 1 2 3]),device_rows,device_cols,[]);
end
end
