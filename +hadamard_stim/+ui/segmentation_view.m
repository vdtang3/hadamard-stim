function view = segmentation_view(controller)
%SEGMENTATION_VIEW The reference image with the cells the package found, numbered.
%
%   view = hadamard_stim.ui.segmentation_view(controller)
%
%   Shows the approved cells when there are any, otherwise the proposal,
%   otherwise just the reference image. Cell k is row k of cell_coord,
%   which is row k of the stimulation matrix: the numbering is the
%   package's order, never re-sorted here. Spots are the camera-space
%   polygons the masks were drawn from (illum_rois, stim_rois). The
%   excluded candidates are the n_exclude skipped ones, for display.
%   Coordinates are camera pixels (x = column, y = row).
view = struct("source", "none", "reference_revision", controller.ReferenceRevision, ...
    "image", [], "n_cells", 0, "cells", [], "excluded", zeros(0, 2), ...
    "min_val", [], "n_exclude", [], "threshold", []);
if ~isempty(controller.ReferenceImage)
    view.image = hadamard_stim.ui.display_image(controller.ReferenceImage);
end
cells = controller.Cells;
view.source = "approved";
if isempty(cells)
    cells = controller.Proposal;
    view.source = "proposal";
end
if isempty(cells)
    view.source = "none";
    return
end
n = size(cells.cell_coord, 1);
illum = hadamard_stim.yitong.split_rois(cells.illum_rois);
stim = hadamard_stim.yitong.split_rois(cells.stim_rois);
view.n_cells = n;
view.cells = struct("number", num2cell(1:n)', ...
    "x", num2cell(round(cells.cell_coord(:, 1), 3)), ...
    "y", num2cell(round(cells.cell_coord(:, 2), 3)), ...
    "illum", reshape(cellfun(@(p) round(p, 3), illum, "UniformOutput", false), [], 1), ...
    "stim", reshape(cellfun(@(p) round(p, 3), stim, "UniformOutput", false), [], 1));
if isfield(cells, "excluded_coord")
    view.excluded = round(cells.excluded_coord, 3);
end
if isfield(cells, "min_val")
    view.min_val = cells.min_val;
end
if isfield(cells, "n_exclude")
    view.n_exclude = cells.n_exclude;
    view.threshold = cells.threshold;
end
end
