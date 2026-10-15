function [bytes, detail] = block_memory(cfg, face_camera, encoder)
%BLOCK_MEMORY What Luminos holds in memory while one spontaneous block runs.
%
%   [bytes, detail] = hadamard_stim.luminos.block_memory(cfg, face_camera, encoder)
%
%   Luminos builds each driven row and each recorded line as a double for
%   the whole acquisition (DQ_Channel.data), plus the time vector it
%   evaluates the rows on. The package itself holds only the waveform's
%   description (spontaneous_waveform). His app held all twelve output
%   rows and three inputs the same way on the same PC: ~4.5 GB for a
%   288,000-frame block.
period_ms = cfg.stimulation.waveform_period_ms;
n_samples = (cfg.stimulation.wait_frames + cfg.spontaneous.block_frames) * ...
    round(period_ms * 1e-3 * cfg.daq.rate);
rows = 2;                      % camera trigger, orange
if face_camera
    rows = rows + 2;           % Grasshopper trigger, IR
end
lines = 2 * logical(encoder);  % encoder A and B
vectors = rows + lines + 1;    % + the time vector
bytes = vectors * n_samples * 8;
detail = sprintf("%d output rows, %d encoder lines, %.1f M samples each", rows, lines, n_samples / 1e6);
end
