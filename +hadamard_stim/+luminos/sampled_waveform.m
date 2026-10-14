function y = sampled_waveform(t, samples)
%SAMPLED_WAVEFORM Luminos waveform function that plays given samples as they are.
%
%   y = hadamard_stim.luminos.sampled_waveform(t, samples)
%
%   Luminos evaluates each wfm_data record as feval(wavefile, tvec,
%   params{:}); daq_records gives this function the protocol's samples, so
%   Luminos plays exactly what +protocol computed, one sample per DAQ tick.
%   There is no resampling: a length that does not match the DAQ's sample
%   count is an error, because it means the DAQ timing is not the
%   protocol's (rate or total_time changed).
if numel(t) ~= numel(samples)
    error("hadamard_stim:SampleCountMismatch", ...
        ['The DAQ asked for %d samples but the protocol''s waveform has %d. ' ...
         'The DAQ rate or total time is not the one the waveform was made for.'], ...
        numel(t), numel(samples));
end
y = reshape(double(samples), 1, []);
end
