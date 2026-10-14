classdef TestLuminosAdapterActions < matlab.unittest.TestCase
    %TESTLUMINOSADAPTERACTIONS The Luminos adapter asks the rig for what the protocol asked.
    %
    %   The same protocol (reference z-stack, then trials 1 to 4: three
    %   sparse trials, a Hadamard trial and the trial-1 drift scan) runs
    %   twice in the parity world: on SimulatedRig, whose actions are the
    %   golden-checked ones, and through LuminosRig on fake Luminos devices.
    %   Each acquisition must then have played the same DAQ samples on his
    %   ports, the same DMD queue or scan stack, the same stage moves and
    %   the same camera frame counts. Only how they are executed differs.

    properties
        Root
        Cfg
        Sim          % SimulatedRig after the run
        SimState
        Rig          % LuminosRig after the run
        App          % fake Luminos session
        LumState
        Release
    end

    methods (TestClassSetup)
        function runBoth(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
            incoming = rng;
            testCase.addTeardown(@() rng(incoming));
            fixtures = fullfile(testCase.Root, "tests", "fixtures");

            [cfg, env, ~, inputs] = parity_environment(fixtures);
            cfg.trials.last = 4;
            testCase.Cfg = cfg;
            cells = hadamard_stim.protocol.segment_cells(cfg, inputs.ref_im, env.geometry);

            % The simulated rig, as in the parity tests.
            sim_ref = hadamard_stim.protocol.run_z_reference(cfg, env);
            sim_ref.had_ref = inputs.ref_im;
            [testCase.SimState, ~] = hadamard_stim.protocol.run_protocol(cfg, env, ...
                hadamard_stim.protocol.new_run_state(cfg, cells, sim_ref));
            testCase.Sim = env.hw;

            % The Luminos adapter on fake devices, in the same world: same
            % geometry and calibration, and the drift scans reconstruct to
            % the images the simulated rig's world gives.
            folder = string(tempname);
            mkdir(folder);
            testCase.addTeardown(@() rmdir(folder, "s"));
            app = hadamard_stim.testing.make_fake_luminos(folder, ...
                z_start=inputs.z_position, blue_curve=blue_curve(testCase.Root));
            [~, lum_env] = parity_environment(fixtures);
            world = lum_env.hw.world;
            lum_env.hw = hadamard_stim.luminos.LuminosRig(app, blue_threshold=15, ...
                acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition);
            n_scans = 0;
            lum_env.reconstruct_scan = @drift_image;
            report = lum_env.hw.begin(cfg);
            testCase.assertTrue(report.ok, strjoin(report.failures, newline));
            lum_ref = hadamard_stim.protocol.run_z_reference(cfg, lum_env);
            lum_ref.had_ref = inputs.ref_im;
            [testCase.LumState, ~] = hadamard_stim.protocol.run_protocol(cfg, lum_env, ...
                hadamard_stim.protocol.new_run_state(cfg, cells, lum_ref));
            testCase.Release = lum_env.hw.release();
            testCase.Rig = lum_env.hw;
            testCase.App = app;

            function im = drift_image(acq)
                n_scans = n_scans + 1;
                im = world.scan_image([], struct("kind", acq.kind, ...
                    "drift_scan_number", n_scans, "motor_z", acq.motor_z));
            end
        end
    end

    methods (Test)
        function sameAcquisitionsInTheSameOrder(testCase)
            sim = testCase.Sim.acquisitions;
            lum = testCase.Rig.acquisitions;
            testCase.assertEqual(numel(lum), numel(sim));
            testCase.verifyEqual([lum.kind]', [sim.kind]');
            testCase.verifyEqual([lum.folder]', [sim.folder]');
            testCase.verifyEqual(numel(testCase.App.Acquisitions), numel(sim));
            % Luminos names each folder with the protocol's folder as tag.
            tags = [testCase.App.Acquisitions.tag]';
            testCase.verifyEqual(tags, "_" + [sim.folder]');
        end

        function sameStageMoves(testCase)
            testCase.verifyEqual(testCase.Rig.moves(:, 1:2), testCase.Sim.moves);
            testCase.verifyEqual(testCase.Rig.moves(:, 3), testCase.Rig.moves(:, 2));
            testCase.verifyEqual([testCase.Rig.acquisitions.motor_z]', ...
                [testCase.Sim.acquisitions.motor_z]');
        end

        function sameDmdQueuesAndStacks(testCase)
            sim = testCase.Sim.acquisitions;
            played = testCase.App.Acquisitions;
            for k = 1:numel(sim)
                if sim(k).kind == "stimulation"
                    testCase.verifyEqual(played(k).queue.combined_sha256, sim(k).queue.combined_sha256);
                    testCase.verifyEqual(played(k).queue.repeat, sim(k).queue.repeat);
                    testCase.verifyEqual(played(k).queue_settings, ...
                        struct("picture_time_us", 44, "trigger_edge", testCase.Cfg.dmd.trigger_edge));
                else
                    testCase.verifyEqual(played(k).stack.sha256, sim(k).dmd_stack.sha256);
                    testCase.verifyEmpty(played(k).queue);
                end
                testCase.verifyEqual(played(k).dmd_owner, "hadamard_stim");
            end
        end

        function sameSamplesOnHisPorts(testCase)
            % Every row the protocol drives is played on his port, sample for
            % sample, apart from the last sample Luminos sets to 0; every
            % other row is zero throughout and is not driven.
            cfg = testCase.Cfg;
            profile = hadamard_stim.luminos.firefly_profile();
            lum = testCase.Rig.acquisitions;
            played = testCase.App.Acquisitions;
            for k = 1:numel(lum)
                waveform = regenerate(cfg, lum(k));
                testCase.verifyEqual(hadamard_stim.metadata.sha256(waveform.amplitude), ...
                    lum(k).waveform_sha256, "regenerated waveform is not the one used");
                testCase.verifyEqual(played(k).n_samples, size(waveform.amplitude, 2));
                testCase.verifyEqual(played(k).rate, cfg.daq.rate);
                ports = played(k).ports;
                for row = 1:numel(waveform.channels)
                    c = profile.channels([profile.channels.name] == waveform.channels(row));
                    samples = waveform.amplitude(row, :);
                    p = ports([ports.port] == c.port);
                    if ~any(samples)
                        testCase.verifyEmpty(p, c.name + " is zero but was driven");
                        continue
                    end
                    testCase.assertNumElements(p, 1, c.name + " was not driven");
                    testCase.verifyEqual(p.kind, c.kind);
                    samples(end) = 0;
                    testCase.verifyEqual(p.sha256, hadamard_stim.metadata.sha256(samples), ...
                        lum(k).folder + "/" + c.name);
                end
            end
        end

        function camerasTakeTheProtocolsFrames(testCase)
            lum = testCase.Rig.acquisitions;
            played = testCase.App.Acquisitions;
            for k = 1:numel(lum)
                cams = played(k).cameras;
                kinetix = cams([cams.name] == "Teledyne Kinetix");
                testCase.verifyEqual(kinetix.frametrigger_source, "External");
                testCase.verifyEqual(kinetix.frames, lum(k).n_frames);
                testCase.verifyEqual(kinetix.exposure_s, lum(k).camera_exposure_ms / 1000);
                grasshopper = cams([cams.name] == "Grasshopper3");
                if lum(k).kind == "stimulation"
                    % One frame per Grasshopper trigger his waveform sends.
                    testCase.verifyEqual(grasshopper.frametrigger_source, "External");
                    testCase.verifyEqual(grasshopper.frames, lum(k).behavior.frames);
                    testCase.verifyGreaterThan(grasshopper.frames, 0);
                else
                    testCase.verifyEqual(grasshopper.frametrigger_source, "Off");
                end
                blackfly = cams([cams.name] == "Blackfly");
                testCase.verifyEqual([blackfly.frametrigger_source blackfly.frames], ["Off" "1"]);
            end
        end

        function theProtocolStateIsTheSame(testCase)
            s = testCase.SimState;
            l = testCase.LumState;
            testCase.verifyEqual(l.next_trial, s.next_trial);
            testCase.verifyEqual(l.cnt, s.cnt);
            testCase.verifyEqual(l.cnt_had, s.cnt_had);
            testCase.verifyEqual(l.picked, s.picked);
            testCase.verifyEqual(l.cells.current, s.cells.current);
            testCase.verifyEqual(l.exposure_waveform_ms, s.exposure_waveform_ms);
            testCase.verifyEqual(l.reference.had_z_stack, s.reference.had_z_stack);
        end

        function eachAcquisitionCarriesThePackagesRecord(testCase)
            for acq = testCase.Rig.acquisitions'
                saved = load(fullfile(acq.luminos_folder, "output_data.mat"), "hadamard_stim_acquisition");
                r = saved.hadamard_stim_acquisition;
                testCase.verifyEqual(r.folder, acq.folder);
                testCase.verifyEqual(r.waveform_sha256, acq.waveform_sha256);
                testCase.verifyFalse(isfield(r, "waveform"), "samples must not be stored in the record");
            end
        end

        function releaseLeavesTheRigAsFound(testCase)
            app = testCase.App;
            dmd = app.getDevice("ALP_DMD");
            testCase.verifyTrue(testCase.Release.ok);
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyTrue(dmd.auto_write_stack);
            testCase.verifyEqual(dmd.Displaying, "dark");
            testCase.verifyEmpty(dmd.pattern_stack);
            daq = app.getDevice("DAQ");
            testCase.verifyEmpty(daq.wfm_data.ao);
            testCase.verifyEmpty(daq.wfm_data.do);
            testCase.verifyEqual(daq.global_props.total_time, 1);
            for cam = app.getDevice("Camera")
                testCase.verifyEqual([cam.frametrigger_source string(cam.frames_requested)], ["Off" "1"]);
                testCase.verifyEqual(cam.acquisition_exposuretime, 0.15);
            end
            % Ownership goes last.
            testCase.verifyEqual(app.Log(end), "DMD (shared):Release_Pattern_Ownership");
        end
    end
end

function curve = blue_curve(root)
blue = load(fullfile(root, "tests", "yitong_reference", "dragonfly", "Utilities", "blueCal.mat"));
curve = [blue.vBlue(:)'; blue.blueIntensC(:)'];
end

function waveform = regenerate(cfg, acq)
% The waveform an acquisition used, rebuilt from its recorded settings by
% the protocol's own builders.
s = acq.waveform_settings;
if acq.kind == "stimulation"
    env.blue_calibration = blue_calibration_of(cfg);
    waveform = hadamard_stim.protocol.stimulation_waveform(cfg, env, ...
        s.exposure_ms, s.orange_v, s.blue_v, s.params);
else
    waveform = hadamard_stim.protocol.scan_waveform(cfg, s.exposure_ms, s.orange_v, s.n_pat);
end
end

function c = blue_calibration_of(~)
root = fileparts(fileparts(mfilename("fullpath")));
blue = load(fullfile(root, "tests", "yitong_reference", "dragonfly", "Utilities", "blueCal.mat"));
c = struct("v_blue", blue.vBlue, "blue_intens_c", blue.blueIntensC);
end
