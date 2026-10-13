function spots = spot_select(rois, c_idx)
%SPOT_SELECT The spots of the selected cells, in cell order.
%
%   spots = hadamard_stim.yitong.spot_select(rois, c_idx)
%
%   rois are NaN-separated, one spot per cell; c_idx is logical, one per
%   cell. The protocol passes the stimulation spots, so this is the blue
%   picture of one code or one sparse pulse.
%
%   Port of tests/yitong_reference/dragonfly/dmd_control/quick_functions/spot_select_sequence.m
%   SHA-256 768383c1966e3aeb0e4a03ba8f9f851b670579c09a468df9d0feb6a3378e24bf
%   Changes: works on ROIs instead of the DMD app; rasterising is separate.
arguments
    rois (:, 2) double
    c_idx logical
end
spot_rois_new = hadamard_stim.yitong.split_rois(rois);
spot_rois_new(~c_idx) = [];
spots = spot_rois_new;
end
