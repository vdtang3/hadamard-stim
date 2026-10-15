function y = expand_row(n, head_value, head_samples, unit, n_repeat)
%EXPAND_ROW Samples of one row of a repeated waveform: a constant head, unit x n_repeat, zeros.
%
%   y = hadamard_stim.waveform.expand_row(n, head_value, head_samples, unit, n_repeat)
%
%   n is the number of samples wanted. A row longer than n is an error: the
%   caller's timing is not the waveform's.
body = head_samples + numel(unit) * n_repeat;
if body > n
    error("hadamard_stim:SampleCountMismatch", ...
        ['The DAQ asked for %d samples but the protocol''s waveform has %d. ' ...
         'The DAQ rate or total time is not the one the waveform was made for.'], n, body);
end
y = zeros(1, n);
y(1:head_samples) = head_value;
if n_repeat > 0 && ~isempty(unit)
    if isscalar(unit)
        y(head_samples + (1:n_repeat)) = unit;
    else
        y(head_samples + (1:numel(unit) * n_repeat)) = repmat(reshape(double(unit), 1, []), 1, n_repeat);
    end
end
end
