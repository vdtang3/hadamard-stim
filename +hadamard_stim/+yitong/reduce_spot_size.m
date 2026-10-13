function spots = reduce_spot_size(rois, newR)
%REDUCE_SPOT_SIZE Shrink every spot to diameter newR about its vertex mean.
%
%   spots = hadamard_stim.yitong.reduce_spot_size(rois, newR)
%
%   rois are NaN-separated (join_rois); returns 1 x n spots. "Diameter" is
%   twice the distance from the vertex mean to the first vertex. With the
%   closing vertex counted twice, Auto Square spots of size 5 reduced to 3
%   come out at radius 1.636, 0.072 px right of the cell (finding 3).
%
%   Port of tests/yitong_reference/dragonfly/dmd_control/quick_functions/reduce_spot_size_sequence.m
%   SHA-256 b2c15f8b5ef20b689bfe7fd65cffe7706b825b05fdd183e719fce99b255a1217
%   Changes: works on ROIs instead of the DMD app; rasterising is separate.
arguments
    rois (:, 2) double
    newR (1, 1) double
end
spot_rois_new = hadamard_stim.yitong.split_rois(rois);
for ii = 1:numel(spot_rois_new)
    % calculate original spot size
    ptCtr = nanmean(spot_rois_new{ii},1); %#ok<NANMEAN> his call, kept for parity
    oldR = sqrt(sum((spot_rois_new{ii}(1,:) - ptCtr).^2))*2;
    spot_rois_new{ii} = (spot_rois_new{ii} - ptCtr)*newR/oldR + ptCtr;
end
spots = spot_rois_new;
end
