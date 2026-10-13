function spots = split_rois(rois)
%SPLIT_ROIS One cell per spot from a NaN-separated vertex list.
%
%   spots = hadamard_stim.yitong.split_rois(rois)
%
%   The parsing loop his quick functions start with. Returns a 1 x n cell.
%
%   Port of tests/yitong_reference/dragonfly/dmd_control/quick_functions/spot_select_sequence.m
%   SHA-256 768383c1966e3aeb0e4a03ba8f9f851b670579c09a468df9d0feb6a3378e24bf
%   Changes: the parsing loop only.
arguments
    rois (:, 2) double
end
spot_rois = rois;
spot_rois_idx = find(ismissing(spot_rois(:,1)));

spots = {};
for ii = 1:length(spot_rois_idx)
    if ii == 1
        spots{ii} = spot_rois(1:spot_rois_idx(1)-1,:); %#ok<AGROW>
    else
        spots{ii} = spot_rois(spot_rois_idx(ii-1)+1:spot_rois_idx(ii)-1,:); %#ok<AGROW>
    end
end
end
