function [device_rows, device_cols, active_rows, active_cols, ...
    active_row_offset, active_col_offset] = pixel_configuration
%PIXEL_CONFIGURATION Geometry Yitong's Hadamard pattern code assumes.
%
%   Rows here are columns in the ALP API: a 1024-mirror DMD line is one
%   MATLAB column of 1024 rows, and there are 768 of them. The whole DMD is
%   active.
%
%   Port of tests/yitong_reference/dragonfly/Hadamard/pixel_configuration.m
%   SHA-256 1f835431acdbf20e96a12a3d2f61748cedc1c198b147439804bb31e5e2a5b15a
%   Changes: none in behaviour; the offset fallbacks his file computes for
%   empty or negative offsets never apply to these constants and are kept.
device_rows = 1024;
device_cols = 768;
active_rows = 1024;
active_cols = 768;
active_row_offset = 0;
active_col_offset = 0;
if isempty(active_row_offset) || active_row_offset < 0
    active_row_offset = floor((device_rows-active_rows)/2);
end
if isempty(active_col_offset) || active_col_offset < 0
    active_col_offset = floor((device_cols-active_cols)/2);
end
active_rows = min(active_rows,device_rows-active_row_offset);
active_cols = min(active_cols,device_cols-active_col_offset);
end
