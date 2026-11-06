function patterns = manual_hilo_patterns(dmd, options)
%MANUAL_HILO_PATTERNS The HiLo tab's uniform (U) and structured (S) DMD patterns, to show by hand.
%
%   patterns = manual_hilo_patterns(dmd)
%   patterns = manual_hilo_patterns(dmd, blockSize=8, seed=0)
%   patterns = manual_hilo_patterns(dmd, camera=cam)        U = the camera's field, as the tab
%
%   On Firefly, in Luminos's MATLAB:
%       dmd = app.getDevice("ALP_DMD");                 % DMD (shared), the orange DMD
%       patterns = manual_hilo_patterns(dmd, blockSize=8, seed=0);
%       manual_hilo_display(dmd, patterns.uniform)      % then Snap with the camera controls
%       manual_hilo_display(dmd, patterns.structured)   % then Snap again
%       manual_hilo_display(dmd, "dark")
%
%   Nothing here touches a camera, the DAQ or a trigger: the patterns are
%   computed (and saved), and shown only by manual_hilo_display.
%
%   The patterns are Luminos's own (src/Experimental_Scripts/HiLo):
%     uniform     true on the whole DMD canvas; with camera=, the HiLo
%                 tab's illumination mask instead, hilo_fov_mask(dmd,
%                 camera, fovMargin): the camera's acquisition area grown by
%                 fovMargin, warped onto the DMD by the active calibration.
%     structured  generate_hilo_pattern(uniform, seed, substream,
%                 block_size = blockSize): uniform AND a random on/off
%                 pattern (P(on) = 0.5) in blockSize x blockSize mirror
%                 blocks, tiled from the canvas's top-left mirror, from its
%                 own mrg32k3a stream (MATLAB's global rng is untouched).
%   Both are logical, [rows columns] = dmd.Pattern_Canvas_Size(), true =
%   mirror on: exactly what DMD.Target takes and Write_Static projects, as
%   the HiLo tab shows them. The tab's acquisition draws plane k's S from
%   substream k + 1 (substream 1 is its calibration), so the default
%   substream 2 with the same seed, blockSize 1 and camera gives the S the
%   tab shows at its first plane. The tab itself uses blockSize 1.
%
%   Options:
%     blockSize  mirrors per block side (default 1, the tab's pattern)
%     seed       generator seed (default 0)
%     substream  generator substream (default 2)
%     camera     a Luminos camera (app.getDevice("Camera", "name", ...)):
%                U is its field of view; [] (default) for the whole canvas
%     fovMargin  with camera: fraction the lit area exceeds the camera's
%                (default 0.05, the tab's)
%     output     the .mat to write (default <current folder>/<HHMMSS>_hilo_patterns.mat);
%                "none" to write nothing
%
%   patterns: uniform, structured, params (everything needed to rebuild
%   them, with each pattern's SHA-256), file. The .mat holds "patterns".
arguments
    dmd
    options.blockSize (1, 1) double {mustBeInteger, mustBePositive} = 1
    options.seed (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
    options.substream (1, 1) double {mustBeInteger, mustBePositive} = 2
    options.camera = []
    options.fovMargin (1, 1) double {mustBeNonnegative} = 0.05
    options.output (1, 1) string = ""
end
needed = "generate_hilo_pattern";
if ~isempty(options.camera)
    needed(end+1) = "hilo_fov_mask";
end
hadamard_stim.manual.require_luminos_hilo(needed);

canvas = double(dmd.Pattern_Canvas_Size());
fov = struct("method", "whole canvas");
if isempty(options.camera)
    uniform = true(canvas);
else
    cam = options.camera;
    camera = struct("name", string(cam.name), "roi", double(cam.getROIForAcquisition()), ...
        "bin", double(cam.bin));
    [uniform, fov] = hilo_fov_mask(dmd, camera, options.fovMargin);
end
structured = generate_hilo_pattern(uniform, options.seed, options.substream, ...
    block_size=options.blockSize);
if ~isequal(size(uniform), canvas) || ~isequal(size(structured), canvas)
    error("hadamard_stim:PatternSize", "The patterns are %s, not the DMD canvas %s.", ...
        mat2str(size(structured)), mat2str(canvas));
end

params = struct();
params.dmd = string(dmd.name);
params.canvas_size = canvas;
params.block_size = options.blockSize;
params.seed = options.seed;
params.substream = options.substream;
params.rng = "mrg32k3a";
params.generator = "generate_hilo_pattern(uniform, seed, substream, block_size = blockSize)";
params.generator_file = string(which("generate_hilo_pattern"));
params.uniform = fov;
params.fov_margin = options.fovMargin;
params.uniform_sha256 = hadamard_stim.metadata.sha256(uniform);
params.structured_sha256 = hadamard_stim.metadata.sha256(structured);
params.uniform_on = nnz(uniform);
params.structured_on = nnz(structured);
params.created_utc = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));

patterns = struct("uniform", uniform, "structured", structured, "params", params, "file", "");
file = options.output;
if strlength(file) == 0
    file = fullfile(pwd, string(datetime("now", "Format", "HHmmss")) + "_hilo_patterns.mat");
end
if file ~= "none"
    folder = fileparts(file);
    if strlength(folder) > 0 && ~isfolder(folder)
        mkdir(folder);
    end
    patterns.file = file;
    save(file, "patterns", "-v7");
    fprintf("HiLo patterns (block %d, seed %d, substream %d, %d of %d mirrors in U) saved to %s\n", ...
        options.blockSize, options.seed, options.substream, nnz(uniform), numel(uniform), file);
end
end
