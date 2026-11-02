function files = write_orange_mask(file_stem, mask, info)
%WRITE_ORANGE_MASK Save the approved cells' orange DMD mask for use outside the package.
%
%   files = hadamard_stim.metadata.write_orange_mask(file_stem, mask, info)
%
%   file_stem  path without extension; <stem>.mat and <stem>.png are written
%              (its folder is made if needed)
%   mask       the controller's Cells.illum_mask: logical, the DMD canvas
%              (dmd.Pattern_Canvas_Size(), rows x cols, as DMD.Target),
%              exactly what orange_preview hands dmd_show_mask
%   info       provenance (HadamardStimController.exportOrangeMask)
%
%   <stem>.mat  mask   the array itself, unchanged (no resampling, flip or
%                      cast)
%               info   provenance, with info.mask_sha256 (the hash the
%                      orange preview and run recipe record) and
%                      info.canvas_size
%   <stem>.png  the same mask, one PNG pixel per mirror (white = on), in
%               the same orientation
%
%   Files only: no device is touched. In Luminos, the DMD tab's pattern
%   function "Hadamard Stim Orange Mask" (Preset_pattern/
%   pdHadamard_Stim_Orange_Mask.m) loads <stem>.mat and projects it
%   through Target and Write_Static, as dmd_show_mask does.
arguments
    file_stem (1, 1) string
    mask logical
    info struct
end
if ~ismatrix(mask) || isempty(mask)
    error("hadamard_stim:PatternSize", "The orange mask must be one non-empty picture, not %s.", ...
        mat2str(size(mask)));
end
folder = fileparts(file_stem);
if strlength(folder) > 0 && ~isfolder(folder)
    mkdir(folder);
end
info.mask_sha256 = hadamard_stim.metadata.sha256(mask);
info.canvas_size = size(mask);
info.mask_on_pixels = nnz(mask);
files = struct("mat", file_stem + ".mat", "png", file_stem + ".png");
save(files.mat, "mask", "info", "-v7");
imwrite(mask, files.png);
end
