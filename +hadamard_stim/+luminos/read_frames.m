function mov = read_frames(file, frame_size, frames)
%READ_FRAMES Some frames of a Luminos camera recording, without reading the rest.
%
%   mov = hadamard_stim.luminos.read_frames(file, [rows cols])
%   mov = hadamard_stim.luminos.read_frames(file, [rows cols], frames)
%
%   file  frames<k>.bin, uncompressed 16-bit (preflight refuses compression)
%   mov   uint16 [rows x cols x numel(frames)], all frames if none given
%
%   Luminos writes each frame rows first (readBinMovFast, frame_layout
%   "rows_first"; Adaptive Optopatch's extract_roi_traces reads it the same
%   way). A stimulation movie is 8000 frames, about 2.3 GB, and the
%   protocol reads 500 of them, so only those are read.
arguments
    file (1, 1) string
    frame_size (1, 2) double {mustBeInteger, mustBePositive}
    frames double {mustBeInteger, mustBePositive} = []
end
rows = frame_size(1);
cols = frame_size(2);
frame_bytes = rows * cols * 2;
info = dir(file);
if isempty(info)
    error("hadamard_stim:NoMovie", "No camera recording at %s.", file);
end
n_available = floor(info.bytes / frame_bytes);
if isempty(frames)
    frames = 1:n_available;
end
if any(frames > n_available)
    error("hadamard_stim:MissingFrames", ...
        "%s holds %d frames of %d x %d; frame %d was asked for.", ...
        file, n_available, rows, cols, max(frames));
end
fid = fopen(file, "r", "ieee-le");
closer = onCleanup(@() fclose(fid));
mov = zeros(rows, cols, numel(frames), "uint16");
% Read each run of consecutive frames in one go.
starts = [1, find(diff(frames(:)') ~= 1) + 1];
stops = [starts(2:end) - 1, numel(frames)];
for r = 1:numel(starts)
    first = frames(starts(r));
    n = stops(r) - starts(r) + 1;
    fseek(fid, (first - 1) * frame_bytes, "bof");
    raw = fread(fid, rows * cols * n, "*uint16");
    mov(:, :, starts(r):stops(r)) = permute(reshape(raw, cols, rows, n), [2 1 3]);
end
end
