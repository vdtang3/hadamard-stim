classdef TestParityWaveforms < matlab.unittest.TestCase
    %TESTPARITYWAVEFORMS The DAQ waveform ports reproduce his samples
    %exactly, row by row, for every waveform case in the fixture.
    properties (TestParameter)
        StimCase = {"stim_sparse", "stim_hadamard", "stim_small_sparse", "stim_small_hadamard"}
        ScanCase = {"scan_drift", "scan_small"}
    end
    properties
        Golden
    end
    methods (TestClassSetup)
        function setup(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fileparts(fileparts(mfilename("fullpath")))));
            testCase.Golden = load(fullfile(fileparts(mfilename("fullpath")), ...
                "fixtures", "yitong_waveforms.mat"));
        end
    end
    methods (Test)
        function stimulationSamplesAreHis(testCase, StimCase)
            g = testCase.Golden.(StimCase);
            cal = load(fullfile(fileparts(mfilename("fullpath")), "yitong_reference", ...
                "dragonfly", "Utilities", "blueCal.mat"));
            p = struct("daq_rate", 1e5, "channels", testCase.Golden.channels, ...
                "exposure_ms", g.settings.base.exposure_ms, ...
                "gs_ms", g.settings.base.gs_ms, ...
                "n_frames", g.settings.base.n_frames, "n_pat", 2, ...
                "params", g.settings.trial.params, ...
                "blue_v", g.settings.trial.blue_v, ...
                "ir_v", g.settings.base.ir_v, ...
                "orange_v", g.settings.base.orange_v, ...
                "blue_calibration", struct("v_blue", cal.vBlue, "blue_intens_c", cal.blueIntensC));
            waves = hadamard_stim.yitong.multipat_periodic_pulse_v2_waveform(p);
            testCase.verifyRows(waves, g);
        end
        function scanSamplesAreHis(testCase, ScanCase)
            g = testCase.Golden.(ScanCase);
            s = g.settings;
            p = struct("daq_rate", 1e5, "channels", testCase.Golden.channels, ...
                "exposure_ms", s.exposure_ms, "n_pat", s.n_pat, "repeat", s.repeat, ...
                "n_rows", s.n_rows, "orange_v", s.orange_v, "blue_v", s.blue_v);
            waves = hadamard_stim.yitong.static_hadamard_waveform(p);
            testCase.verifyRows(waves, g);
        end
    end
    methods
        function verifyRows(testCase, waves, g)
            testCase.verifyEqual(waves.channels, g.rows);
            testCase.verifyEqual(size(waves.amplitude), [numel(g.rows) g.n_samples]);
            for r = 1:numel(g.rows)
                [values, lengths] = run_length_encode(waves.amplitude(r, :));
                testCase.verifyTrue(isequaln(values, g.values{r}), g.rows(r) + ": values");
                testCase.verifyEqual(lengths, g.run_lengths{r}, g.rows(r) + ": run lengths");
            end
        end
    end
end

function [values, lengths] = run_length_encode(x)
% As the fixture generator encoded the rows (tests/golden/golden_waveforms.m).
starts = [true, x(2:end) ~= x(1:end-1) & ~(isnan(x(2:end)) & isnan(x(1:end-1)))];
values = x(starts);
lengths = diff([find(starts), numel(x) + 1]);
end
