function [x_out, y_out] = static_image_seg_v5(~, ~)
%STATIC_IMAGE_SEG_V5 Shim: return given cell centres, so dmd_draw's
%'Auto Square' ROI construction can be checked against a session whose
%reference image was not saved. Set with
%setappdata(0, "hadamard_stim_golden_cells", [x y]).
cells = getappdata(0, "hadamard_stim_golden_cells");
x_out = cells(:, 1);
y_out = cells(:, 2);
end
