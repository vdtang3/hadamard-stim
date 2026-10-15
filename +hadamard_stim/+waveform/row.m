function samples = row(waveform, channel)
%ROW One row of a waveform as samples, whichever form it is in.
%
%   samples = hadamard_stim.waveform.row(waveform, channel)
%
%   A dense waveform (scan_waveform, stimulation_waveform) holds its
%   samples in amplitude; a repeated one (spontaneous_waveform) is
%   expanded here. A row the waveform does not drive is all zeros. Meant
%   for tests and short waveforms: a spontaneous block's row is ~36 M
%   samples.
n = hadamard_stim.waveform.n_samples(waveform);
channel = string(channel);
k = find(string(waveform.channels) == channel, 1);
if isempty(k)
    samples = zeros(1, n);
elseif isfield(waveform, "form") && waveform.form == "repeated"
    r = waveform.rows(k);
    samples = hadamard_stim.waveform.expand_row(n, r.head_value, r.head_samples, ...
        r.unit, r.n_repeat);
else
    samples = waveform.amplitude(k, :);
end
end
