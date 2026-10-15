function n = rising_edges(waveform, channel)
%RISING_EDGES How many times a waveform row goes from zero to positive.
%
%   n = hadamard_stim.waveform.rising_edges(waveform, channel)
%
%   The count a camera triggered by that row takes frames for. The row
%   starts from zero (a rising first sample counts). A repeated row is
%   counted without expanding it. A row the waveform does not drive has
%   none.
channel = string(channel);
k = find(string(waveform.channels) == channel, 1);
if isempty(k)
    n = 0;
    return
end
if ~(isfield(waveform, "form") && waveform.form == "repeated")
    x = waveform.amplitude(k, :) > 0;
    n = nnz(diff([false x]) > 0);
    return
end
r = waveform.rows(k);
head = r.head_samples > 0 && r.head_value > 0;   % the head is constant
unit = r.unit > 0;
n = double(head);
if r.n_repeat < 1 || isempty(unit)
    return
end
before = head;
inside = nnz(diff(unit) > 0);
n = n + (~before && unit(1)) ...                       % head into the first unit
    + r.n_repeat * inside ...                          % within each unit
    + (r.n_repeat - 1) * (~unit(end) && unit(1));      % one unit into the next
end
