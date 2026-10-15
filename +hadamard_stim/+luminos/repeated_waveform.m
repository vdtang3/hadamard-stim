function y = repeated_waveform(t, head_value, head_samples, unit, n_repeat)
%REPEATED_WAVEFORM Luminos waveform function for a constant head, a repeated unit, then zeros.
%
%   y = hadamard_stim.luminos.repeated_waveform(t, head_value, head_samples, unit, n_repeat)
%
%   Luminos evaluates each wfm_data record as feval(wavefile, tvec,
%   params{:}). daq_records gives this function a row of a repeated
%   waveform (hadamard_stim.protocol.spontaneous_waveform), so the record
%   carries a few kilobytes and Luminos builds the long row only once, in
%   its own buffer: one sample per DAQ tick, as waveform.expand_row
%   defines it.
y = hadamard_stim.waveform.expand_row(numel(t), head_value, head_samples, unit, n_repeat);
end
