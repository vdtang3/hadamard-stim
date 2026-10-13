function rois = join_rois(spots)
%JOIN_ROIS Spots as one NaN-separated vertex list, as the DMD app stored them.
%
%   rois = hadamard_stim.yitong.join_rois(spots)
%
%   Each spot's vertices followed by a [NaN NaN] row. This is the form of
%   his mask_sequence_rois entries, which the protocol and its parity
%   fixtures carry around.
%
%   Port of tests/yitong_reference/dragonfly/dmd_control/dmd_draw_hidden.m
%   SHA-256 316fa4ae4113105c5f26fccc98f61c2f443f8daa6c1d0c72fb341bac74b86e52
%   Changes: the roi_points_out expression only.
arguments
    spots cell
end
rois = cell2mat(cellfun(@(x) [x;nan nan],spots(:),'uniformoutput',false));
end
