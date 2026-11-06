function cells = draw_cells(cells, segmentation, geometry)
%DRAW_CELLS Spots and masks for given cells, as his DMD app drew them.
%
%   cells = hadamard_stim.protocol.draw_cells(cells, cfg.segmentation, geometry)
%
%   Fills illum_rois, stim_rois, illum_mask and stim_mask from
%   cells.cell_coord. The illumination pattern is drawn the "auto_square"
%   way and the stimulation pattern the "hidden" way, as his were.
%   With a rig geometry, cells.off_dmd lists the cells mapped off the DMD.
illum_spots = hadamard_stim.yitong.auto_square_rois(cells.cell_coord, segmentation.illum_spot_size);
cells.illum_rois = hadamard_stim.yitong.join_rois(illum_spots);
stim_spots = hadamard_stim.yitong.reduce_spot_size(cells.illum_rois, segmentation.stim_spot_size);
cells.stim_rois = hadamard_stim.yitong.join_rois(stim_spots);
cells.illum_mask = geometry.rasterize(illum_spots, "auto_square");
cells.stim_mask = geometry.rasterize(stim_spots, "hidden");
if isfield(geometry, "off_dmd")
    % Cells whose centre the calibration maps off the DMD canvas: their
    % spots are clipped by it (rig geometry only).
    cells.off_dmd = reshape(find(geometry.off_dmd(cells.cell_coord)), 1, []);
end
end
