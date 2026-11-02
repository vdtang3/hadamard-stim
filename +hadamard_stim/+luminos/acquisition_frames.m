function mov = acquisition_frames(acq, frames)
%ACQUISITION_FRAMES An acquisition's imaging movie, in the format it was recorded in.
%
%   mov = hadamard_stim.luminos.acquisition_frames(acq)
%   mov = hadamard_stim.luminos.acquisition_frames(acq, frames)
%
%   acq.imaging.file, .frame_size and .format (camera_format, recorded by
%   LuminosRig.acquire when the movie was taken). An acquisition recorded
%   without .format is 16-bit: until 8-bit support, preflight refused
%   every other storage depth.
arguments
    acq struct
    frames double = []
end
format = hadamard_stim.luminos.camera_format(16);
if isfield(acq.imaging, "format") && ~isempty(acq.imaging.format)
    format = hadamard_stim.luminos.camera_format(acq.imaging.format);
end
mov = hadamard_stim.luminos.read_frames(acq.imaging.file, acq.imaging.frame_size, frames, ...
    format=format);
end
