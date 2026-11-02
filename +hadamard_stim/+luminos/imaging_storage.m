function [bytes, largest, detail] = imaging_storage(cfg, frame_size, format)
%IMAGING_STORAGE What a session's imaging movies take on disk.
%
%   [bytes, largest, detail] = hadamard_stim.luminos.imaging_storage(cfg, frame_size, format)
%
%   frame_size  [rows cols] as recorded (the Camera tab's area, binned)
%   format      camera_format: bytes_per_pixel is what each pixel takes
%   bytes       the trials' (or blocks') movies together
%   largest     the largest single movie
%
%   Only the movies that dominate: a connectivity session's trials
%   (trials.n_trial of stimulation.n_frames) or a spontaneous session's
%   blocks (spontaneous.n_blocks of block_frames). The scans (reference,
%   z-stack, drift) add a few GB at most and are left out. Luminos writes
%   frames to disk as they arrive, so this is disk, not memory: the
%   memory a block holds is the DAQ's (block_memory).
frame_bytes = prod(frame_size) * format.bytes_per_pixel;
if hadamard_stim.metadata.session_mode(cfg) == "spontaneous"
    n = cfg.spontaneous.n_blocks;
    frames = cfg.spontaneous.block_frames;
    what = "blocks";
else
    n = cfg.trials.n_trial;
    frames = cfg.stimulation.n_frames;
    what = "trials";
end
largest = frames * frame_bytes;
bytes = n * largest;
detail = sprintf("%d %s of %d frames, %d x %d px, %d byte%s/pixel", n, what, frames, ...
    frame_size(2), frame_size(1), format.bytes_per_pixel, plural(format.bytes_per_pixel));
end

function s = plural(n)
s = "s";
if n == 1
    s = "";
end
end
