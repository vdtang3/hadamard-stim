classdef TestLuminosPieces < matlab.unittest.TestCase
    %TESTLUMINOSPIECES The adapter's parts that need no session: translation only.

    properties
        Root
        Cfg
        Folder
    end

    methods (TestClassSetup)
        function setUp(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(testCase.Root, "tests", "support")));
            testCase.Cfg = parity_environment(fullfile(testCase.Root, "tests", "fixtures"));
            incoming = rng;
            testCase.addTeardown(@() rng(incoming));
        end
    end

    methods (TestMethodSetup)
        function makeFolder(testCase)
            testCase.Folder = string(tempname);
            mkdir(testCase.Folder);
            testCase.addTeardown(@() rmdir(testCase.Folder, "s"));
        end
    end

    methods (Test)
        % ---- Blue calibration (P2) ---------------------------------------

        function hisCurveAtHisThresholdGivesHisVoltages(testCase)
            % With his blueCal.mat as the Luminos curve and blue_threshold 15,
            % the protocol's blue voltages are exactly the parity ones.
            blue = load(fullfile(testCase.Root, "tests", "yitong_reference", "dragonfly", ...
                "Utilities", "blueCal.mat"));
            his = struct("v_blue", blue.vBlue, "blue_intens_c", blue.blueIntensC);
            ours = hadamard_stim.luminos.active_blue_calibration( ...
                modulator([blue.vBlue(:)'; blue.blueIntensC(:)']), 15);
            v = 0:0.01:5;
            testCase.verifyEqual(hadamard_stim.yitong.linearize_blue_voltage(v, ours), ...
                hadamard_stim.yitong.linearize_blue_voltage(v, his));
        end

        function theThresholdIsInTheCalibrationsUnits(testCase)
            % Dropping power <= T is the same whatever the power scale, so a
            % curve in mW with T in mW gives the result of the same curve in
            % W with T in W.
            v = linspace(0, 5, 200);
            power_mw = 40 * max(v - 0.8, 0).^1.3;
            in_mw = hadamard_stim.luminos.active_blue_calibration(modulator([v; power_mw]), 2);
            in_w = hadamard_stim.luminos.active_blue_calibration(modulator([v; power_mw / 1000]), 0.002);
            x = 0:0.05:5;
            testCase.verifyEqual(hadamard_stim.yitong.linearize_blue_voltage(x, in_mw), ...
                hadamard_stim.yitong.linearize_blue_voltage(x, in_w), "AbsTol", 1e-12);
            % ... and differs from a different threshold.
            other = hadamard_stim.luminos.active_blue_calibration(modulator([v; power_mw]), 20);
            testCase.verifyNotEqual(hadamard_stim.yitong.linearize_blue_voltage(x, other), ...
                hadamard_stim.yitong.linearize_blue_voltage(x, in_mw));
        end

        function theCalibrationIsIdentified(testCase)
            v = linspace(0, 5, 50);
            c = hadamard_stim.luminos.active_blue_calibration(modulator([v; v.^2]), 0.5);
            testCase.verifyEqual(c.source, "luminos_modulator_calibration");
            testCase.verifyEqual(c.identity.device, "Blue LED 488");
            testCase.verifyEqual(c.identity.blue_threshold, 0.5);
            testCase.verifyEqual(c.identity.curve_sha256, hadamard_stim.metadata.sha256([v; v.^2]));
            testCase.verifyNotEmpty(jsonencode(c.identity));
        end

        function anUnusableCalibrationIsRefused(testCase)
            v = linspace(0, 5, 50);
            testCase.verifyError(@() hadamard_stim.luminos.active_blue_calibration( ...
                modulator([v; v.^2]), 1e6), "hadamard_stim:BlueCalibrationUnusable");
            testCase.verifyError(@() hadamard_stim.luminos.active_blue_calibration( ...
                modulator([v; v.^2; v]), 1), "hadamard_stim:BlueCalibrationUnusable");
            testCase.verifyError(@() hadamard_stim.luminos.active_blue_calibration( ...
                modulator([]), 1), "hadamard_stim:NoBlueCalibration");
        end

        % ---- DAQ --------------------------------------------------------

        function onlyRowsThatAreUsedAreDriven(testCase)
            profile = hadamard_stim.luminos.firefly_profile();
            waveform.channels = testCase.Cfg.daq.channels;
            waveform.amplitude = zeros(numel(waveform.channels), 10);
            waveform.amplitude(1, 2:3) = 1;      % cameraTrigger
            waveform.amplitude(5, :) = 0.47;     % orangeIntensity
            [records, driven] = hadamard_stim.luminos.daq_records(waveform, profile);
            testCase.verifyEqual(string({records.do.port}), "Dev1/port0/line26");
            testCase.verifyEqual(string({records.ao.port}), "Dev1/ao0");
            testCase.verifyEqual(records.ao.params{1}, waveform.amplitude(5, :));
            testCase.verifyEqual(string({records.ao.script_owner}), "hadamard_stim");
            testCase.verifyEqual(driven.channel, ["cameraTrigger"; "orangeIntensity"]);
        end

        function aDrivenRowWithoutAPortIsRefused(testCase)
            waveform.channels = "laser";
            waveform.amplitude = ones(1, 5);
            testCase.verifyError(@() hadamard_stim.luminos.daq_records(waveform, ...
                hadamard_stim.luminos.firefly_profile()), "hadamard_stim:UnknownChannel");
        end

        function samplesArePlayedOnlyAtTheirOwnLength(testCase)
            testCase.verifyEqual(hadamard_stim.luminos.sampled_waveform(0:3, [1; 2; 3; 4]), [1 2 3 4]);
            testCase.verifyError(@() hadamard_stim.luminos.sampled_waveform(0:4, 1:4), ...
                "hadamard_stim:SampleCountMismatch");
        end

        % ---- Cameras ----------------------------------------------------

        function framesFollowTheTriggerRows(testCase)
            cfg = testCase.Cfg;
            waveform = hadamard_stim.protocol.scan_waveform(cfg, 2.52, 0.47, 64, camera_rows=328);
            spec = hadamard_stim.protocol.acquisition_spec("z_stack_plane", "f", waveform, ...
                camera_exposure_ms=2.5);
            plan = hadamard_stim.luminos.camera_plan(spec, ["Teledyne Kinetix" "Grasshopper3"], ...
                hadamard_stim.luminos.firefly_profile());
            testCase.verifyEqual([plan.frames_requested], [640 1]);
            testCase.verifyEqual([plan.frametrigger_source], ["External" "Off"]);
            testCase.verifyEqual(plan(1).acquisition_exposure_s, 0.0025);
            testCase.verifyEqual([plan.file], ["frames1.bin" "frames2.bin"]);
            spec.n_frames = 641;
            testCase.verifyError(@() hadamard_stim.luminos.camera_plan(spec, "Teledyne Kinetix", ...
                hadamard_stim.luminos.firefly_profile()), "hadamard_stim:CameraFrameMismatch");
        end

        % ---- Movies -----------------------------------------------------

        function framesAreReadRowsFirstAndOnlyThoseAsked(testCase)
            mov = uint16(reshape(1:5*7*9, 5, 7, 9));
            file = fullfile(testCase.Folder, "frames1.bin");
            write_luminos_movie(file, mov);
            testCase.verifyEqual(hadamard_stim.luminos.read_frames(file, [5 7]), mov);
            testCase.verifyEqual(hadamard_stim.luminos.read_frames(file, [5 7], [2 3 4 8]), mov(:, :, [2 3 4 8]));
            testCase.verifyError(@() hadamard_stim.luminos.read_frames(file, [5 7], 10), ...
                "hadamard_stim:MissingFrames");
        end

        function scansAreReconstructedFromLuminosFilesAsHisCoresDo(testCase)
            m_q = testCase.Cfg.scan.m_q;
            % Wide and short, like TestParityReconstruction: his calibration
            % upsamples to ~4096 px along the longest side, so a small square
            % image would need gigabytes.
            rng(7, "twister");
            cal = uint16(100 + randi(500, 16, 600, 128));
            scan = uint16(100 + randi(500, 16, 600, 128));
            planes = {uint16(100 + randi(500, 16, 600, 64)), uint16(100 + randi(500, 16, 600, 64))};
            [reconstruct_scan, reconstruct_z_stack, scorr] = ...
                hadamard_stim.luminos.scan_reconstruction(m_q, {cal});
            testCase.verifyEqual(scorr, hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, {cal}));

            acq = luminos_acquisition(testCase.Folder, "scan", scan);
            testCase.verifyEqual(reconstruct_scan(acq), ...
                hadamard_stim.yitong.dmd_hadamard_reconstruct_core(m_q, {scan}, scorr));

            acqs = [luminos_acquisition(testCase.Folder, "z1", planes{1}), ...
                luminos_acquisition(testCase.Folder, "z2", planes{2})];
            testCase.verifyEqual(reconstruct_z_stack(acqs), ...
                hadamard_stim.yitong.hadamard_reconstruct_core(m_q, planes, scorr));
        end

        % ---- Geometry ---------------------------------------------------

        function spotsAreDrawnThroughTheLuminosCalibration(testCase)
            dmd = hadamard_stim.testing.FakeAlpDmd("DMD (shared)");
            camera = hadamard_stim.testing.FakeLuminosCamera("Teledyne Kinetix");
            geometry = hadamard_stim.luminos.active_geometry(dmd, camera);
            square = {[10 20; 14 20; 14 24; 10 24; 10 20]};
            mask = geometry.rasterize(square, "hidden");
            testCase.verifyClass(mask, "logical");
            testCase.verifySize(mask, [768 1024]);
            % The fake calibration transposes camera onto DMD.
            testCase.verifyEqual(mask, geometry.rasterize(square, "auto_square"));
            % Camera x 10-14, y 20-24 lands at DMD rows 10-14, columns 20-24.
            testCase.verifyTrue(all(mask(11:13, 21:23), "all"));
            testCase.verifyEqual(nnz(mask), nnz(poly2mask(square{1}(:, 1), square{1}(:, 2), 328, 448)));
            testCase.verifySize(geometry.scan_area, [1024 768]);
            testCase.verifyEqual(geometry.identity.source, "luminos_dmd_calibration");
            testCase.verifyNotEmpty(jsonencode(geometry.identity));
        end
    end
end

function m = modulator(curve)
m = hadamard_stim.testing.FakeModulator("Blue LED 488");
m.iscalibrated = ~isempty(curve);
m.calibration_curve = curve;
end

function write_luminos_movie(file, mov)
% Rows first, as Luminos writes frames<k>.bin.
fid = fopen(file, "w", "ieee-le");
fwrite(fid, permute(mov, [2 1 3]), "uint16");
fclose(fid);
end

function acq = luminos_acquisition(folder, name, mov)
file = fullfile(folder, name + ".bin");
write_luminos_movie(file, mov);
acq.imaging = struct("file", file, "frame_size", [size(mov, 1) size(mov, 2)]);
end
