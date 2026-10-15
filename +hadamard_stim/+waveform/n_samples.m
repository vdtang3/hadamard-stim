function n = n_samples(waveform)
%N_SAMPLES Samples in a waveform, dense or repeated.
%
%   n = hadamard_stim.waveform.n_samples(waveform)
if isfield(waveform, "form") && waveform.form == "repeated"
    n = waveform.n_samples;
else
    n = size(waveform.amplitude, 2);
end
end
