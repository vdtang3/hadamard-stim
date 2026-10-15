function out = display_image(im, max_side)
%DISPLAY_IMAGE An image as eight-bit pixels a browser can paint.
%
%   out = hadamard_stim.ui.display_image(im, max_side)
%
%   out.rows, out.columns (of the image, not the display), out.encoding
%   ("png_base64"), out.pixels (a grayscale PNG, base64), out.scale
%   (display pixels per image pixel, at most 1), out.range ([low high]
%   intensities mapped to 0 and 255).
%   Contrast is stretched between the 0.5th and 99.5th percentiles; images
%   larger than max_side (default 1024) are shrunk by whole-pixel
%   decimation. For display only: nothing is measured from it.
arguments
    im {mustBeNumeric}
    max_side (1, 1) double = 1024
end
im = double(im);
step = max(1, ceil(max(size(im)) / max_side));
small = im(1:step:end, 1:step:end);
values = sort(small(isfinite(small)));
if isempty(values)
    range = [0 1];
else
    range = values(max(1, round([0.005 0.995] * numel(values))))';
end
if range(2) <= range(1)
    range(2) = range(1) + 1;
end
pixels = uint8(255 * min(max((small - range(1)) / (range(2) - range(1)), 0), 1));
out = struct("rows", size(im, 1), "columns", size(im, 2), "encoding", "png_base64", ...
    "pixels", string(matlab.net.base64encode(png_bytes(pixels))), ...
    "scale", 1 / step, "range", range);
end

function bytes = png_bytes(pixels)
file = string(tempname) + ".png";
cleanup = onCleanup(@() delete(file));
imwrite(pixels, file);
fid = fopen(file, "r");
bytes = fread(fid, inf, "*uint8")';
fclose(fid);
end
