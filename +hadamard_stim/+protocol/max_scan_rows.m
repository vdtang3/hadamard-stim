function n = max_scan_rows(period_ms, daq_rate)
%MAX_SCAN_ROWS The tallest camera area whose rolling shutter fits a scan frame.
%
%   n = hadamard_stim.protocol.max_scan_rows(period_ms, daq_rate)
%
%   His scan waveform (static_hadamard_waveform) holds the illumination off
%   for the rolling shutter, 3.75 us per row of the acquisition area, then
%   lights the rest of the frame, floor(period / dt) * dt long. An area of
%   more than n rows leaves no time to light: the waveform cannot be built
%   (his code then asks for a negative duration). 671 rows for the 2.52 ms
%   scans, 2930 for the 11 ms calibration scans; his area was 328.
t_frame = period_ms * 1e-3;
dt = 1 / daq_rate;
t_illum = floor(t_frame / dt) * dt;      % as static_hadamard_waveform
n = ceil(t_illum / 3.75e-6) - 1;
end
