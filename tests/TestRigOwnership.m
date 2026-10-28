classdef TestRigOwnership < matlab.unittest.TestCase
    %TESTRIGOWNERSHIP What Hadamard Stim sets for each acquisition, and what it inherits.
    %
    %   The package owns the acquisition's timing: the DAQ's rate, clock,
    %   triggering and waveforms (no Waveforms tab needed), the imaging
    %   camera's external trigger, frame count and exposure, and puts all of
    %   it back afterwards. It inherits the field of view: the camera's
    %   acquisition area as the Camera tab left it, which also sets the
    %   scan's rolling-shutter blanking (his camApp.liveArea(1)).

    properties
        Root
        Folder
    end

    methods (TestClassSetup)
        function setUp(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
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
        % ---- DAQ ---------------------------------------------------------

        function noWaveformsTabIsNeeded(testCase)
            % Luminos started, the Waveforms tab never opened: preparing,
            % the reference scan, the z-reference and a trial all run, each
            % acquisition installs the protocol's DAQ settings, and the DAQ
            % is left as it was found (nothing set).
            [c, app, cfg] = tab_session(testCase.Folder);
            daq = app.getDevice("DAQ");
            daq.never_configured();
            cfg.trials.last = 1;
            c.setConfig(cfg);
            c.runPreflight();
            item = c.Preflight.checks(string({c.Preflight.checks.id}) == "daq_rate");
            testCase.verifyEqual(item.status, "pass");
            testCase.verifySubstring(item.message, "No Waveforms-tab settings");
            n = numel(app.Acquisitions);
            run_on_tab(c, cfg, testCase.Root);
            a = app.Acquisitions(n + 1:end);
            testCase.assertNotEmpty(a);
            gp = [a.global_props];
            testCase.verifyEqual(unique([gp.rate]), 1e5);
            testCase.verifyEqual(unique(string({gp.clock_source})), "Internal Dev1");
            testCase.verifyTrue(all([gp.daq_master]));
            testCase.verifyEqual(unique(string({gp.completion_trigger})), "None");
            % The rest of the tab's defaults (Luminos DAQ.Default_Global_Props).
            testCase.verifyEqual(unique(string({gp.trigger_source})), "/Dev1/PFI0");
            testCase.verifyTrue(all(arrayfun(@(x) isempty(x.external_clock_rate), a)));
            testCase.verifyEmpty(daq.global_props);
            testCase.verifyEmpty(daq.wfm_data);
        end

        function aWaveformsTabClockIsSetAsideAndPutBack(testCase)
            % Whatever the tab chose (another rate, a camera's clock, a rate
            % override) is only noted: each acquisition uses the DAQ's own
            % 100 kHz clock and restores the tab's settings afterwards.
            [c, app, cfg] = tab_session(testCase.Folder);
            daq = app.getDevice("DAQ");
            gp = daq.global_props;
            gp.rate = 2e5;
            gp.clock_source = "/Dev1/PFI1";
            daq.global_props_ = gp;
            daq.external_clock_rate = 2e5;
            c.setConfig(cfg);
            c.runPreflight();
            item = c.Preflight.checks(string({c.Preflight.checks.id}) == "daq_rate");
            testCase.verifyEqual(item.status, "info");
            testCase.verifySubstring(item.message, "/Dev1/PFI1");
            testCase.verifyTrue(c.Preflight.can_run);
            [rig, spec] = scan_rig(app, cfg);
            rig.acquire(spec);
            a = app.Acquisitions(end);
            testCase.verifyEqual(a.global_props.rate, 1e5);
            testCase.verifyEqual(string(a.global_props.clock_source), "Internal Dev1");
            testCase.verifyEmpty(a.external_clock_rate);
            rig.release();
            testCase.verifyEqual(daq.global_props, gp);
            testCase.verifyEqual(daq.external_clock_rate, 2e5);
        end

        % ---- Camera ------------------------------------------------------

        function theCameraIsExternallyTriggeredFramePerEdgeAndRestored(testCase)
            [app, cfg] = fake_firefly(testCase.Folder);
            kinetix = app.getDevice("Camera", "name", "Teledyne Kinetix");
            before = {kinetix.frametrigger_source, kinetix.frames_requested, kinetix.acquisition_exposuretime};
            [rig, spec] = scan_rig(app, cfg);
            rig.acquire(spec);
            a = app.Acquisitions(end);
            cam = a.cameras([a.cameras.name] == "Teledyne Kinetix");
            testCase.verifyEqual(string(cam.frametrigger_source), "External");
            edges = hadamard_stim.waveform.rising_edges(spec.waveform, "cameraTrigger");
            testCase.verifyEqual(cam.frames, edges);
            testCase.verifyEqual(cam.frames, spec.n_frames);
            testCase.verifyEqual(cam.exposure_s, spec.camera_exposure_ms / 1000, "AbsTol", 1e-12);
            rig.release();
            testCase.verifyEqual({kinetix.frametrigger_source, kinetix.frames_requested, ...
                kinetix.acquisition_exposuretime}, before);
        end

        function aFailedAcquisitionStillRestoresTheCamera(testCase)
            [app, cfg] = fake_firefly(testCase.Folder);
            kinetix = app.getDevice("Camera", "name", "Teledyne Kinetix");
            before = {kinetix.frametrigger_source, kinetix.frames_requested, kinetix.acquisition_exposuretime};
            [rig, spec] = scan_rig(app, cfg);
            app.FailOnAcquisition = numel(app.Acquisitions) + 1;
            testCase.verifyError(@() rig.acquire(spec), "fake:AcquisitionFailed");
            report = rig.release();
            testCase.verifyTrue(report.ok);
            testCase.verifyEqual({kinetix.frametrigger_source, kinetix.frames_requested, ...
                kinetix.acquisition_exposuretime}, before);
        end

        function anEightBitCameraModeBlocks(testCase)
            [app, cfg, ~, rig] = fake_firefly(testCase.Folder);
            kinetix = app.getDevice("Camera", "name", "Teledyne Kinetix");
            kinetix.bit_depth = 8;
            kinetix.bit_mode_label = '8-bit (Speed)';
            report = rig.begin(cfg);
            testCase.verifyFalse(report.can_run);
            item = report.checks(string({report.checks.id}) == "camera_settings");
            testCase.verifyEqual(item.status, "blocker");
            testCase.verifySubstring(item.message, "8-bit");
        end

        % ---- Field of view -----------------------------------------------

        function theCameraTabsAreaIsUsedAndShown(testCase)
            [c, app, cfg] = tab_session(testCase.Folder);
            kinetix = app.getDevice("Camera", "name", "Teledyne Kinetix");
            state = c.getState();
            testCase.verifyEqual(state.imaging_camera.roi, [0 448 0 328]);
            testCase.verifyEqual(state.imaging_camera.frame_size, [328 448]);
            kinetix.ROI = [64 256 32 200];
            state = c.getState();
            testCase.verifyEqual([state.imaging_camera.width state.imaging_camera.height], [256 200]);
            testCase.verifyEqual(state.imaging_camera.frame_size, [200 256]);
            % The acquisition records that area, and its scan blanks for 200 rows.
            [rig, spec] = scan_rig(app, cfg);
            acq = rig.acquire(spec);
            a = app.Acquisitions(end);
            cam = a.cameras([a.cameras.name] == "Teledyne Kinetix");
            testCase.verifyEqual(cam.roi, [64 256 32 200]);
            testCase.verifyEqual(acq.waveform_settings.n_rows, 200);
            rig.release();
            c.setConfig(cfg);
            c.runPreflight();
            % The DMD calibration's area is compared with this one.
            geometry = c.Preflight.checks(string({c.Preflight.checks.id}) == "dmd_calibration");
            testCase.verifyEqual(geometry.status, "warning");
        end

        % ---- Rolling shutter ---------------------------------------------

        function hisRowCountKeepsHisScanSamples(testCase)
            % 328 rows (his area) gives exactly his scan waveform.
            g = load(fullfile(testCase.Root, "tests", "fixtures", "yitong_waveforms.mat")).scan_small;
            s = g.settings;
            cfg = hadamard_stim.default_config();
            w = hadamard_stim.protocol.scan_waveform(cfg, s.exposure_ms, s.orange_v, s.n_pat, s.repeat, ...
                camera_rows=328);
            testCase.verifyEqual(s.n_rows, 328);
            for r = 1:numel(g.rows)
                expected = repelem(g.values{r}(:)', g.run_lengths{r}(:)');
                testCase.verifyEqual(w.amplitude(r, :), expected, g.rows(r));
            end
            testCase.verifyEqual(w.settings.n_rows, 328);
        end

        function anotherAreaShiftsTheBlankingByItsRows(testCase)
            % 3.75 us per row at 100 kHz: 128 fewer rows light 48 samples
            % earlier in every frame; nothing else changes.
            cfg = hadamard_stim.default_config();
            full = hadamard_stim.protocol.scan_waveform(cfg, 2.52, 0.47, 4, 2, camera_rows=328);
            small = hadamard_stim.protocol.scan_waveform(cfg, 2.52, 0.47, 4, 2, camera_rows=200);
            orange = cfg.daq.channels == "orangeIntensity";
            on = @(w) find(diff([0 w.amplitude(orange, :)]) > 0);
            testCase.verifyEqual(numel(on(full)), numel(on(small)));
            testCase.verifyEqual(on(full) - on(small), repmat(48, 1, numel(on(full))));
            others = ~ismember(cfg.daq.channels, ["orangeIntensity" "blueIntensity"]);
            testCase.verifyEqual(full.amplitude(others, :), small.amplitude(others, :));
            testCase.verifyEqual(small.settings.n_rows, 200);
            testCase.verifyError(@() hadamard_stim.protocol.scan_waveform(cfg, 2.52, 0.47, 4), ...
                "hadamard_stim:NoCameraRows");
        end
    end
end

function [rig, spec] = scan_rig(app, cfg)
% A begun LuminosRig and a short scan acquisition on the current area.
rig = hadamard_stim.luminos.LuminosRig(app, blue_threshold=15, ...
    acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition);
report = rig.begin(cfg);
assert(report.can_run, strjoin(report.failures, " "));
waveform = hadamard_stim.protocol.scan_waveform(cfg, cfg.scan.waveform_period_ms, ...
    cfg.scan.orange_v, 4, 1, camera_rows=rig.camera_rows());
spec = hadamard_stim.protocol.acquisition_spec("z_stack_plane", "ownership_test", ...
    waveform, camera_exposure_ms=cfg.scan.camera_exposure_ms);
end

function run_on_tab(c, cfg, root)
% Prepare, a reference scan, cells, z-reference and one trial, as the tab does.
for step = {{"set_config", struct("config", cfg)}, {"prepare_rig", struct()}}
    r = hadamard_stim.apply_controller_action(c, step{1}{1}, step{1}{2}, c.Revision);
    assert(r.ok, r.message);
end
use_parity_scans(c, root);
for step = {{"acquire_reference_image", struct()}, {"propose_cells", struct()}, ...
        {"approve_cells", struct()}, {"acquire_z_reference", struct()}}
    r = hadamard_stim.apply_controller_action(c, step{1}{1}, step{1}{2}, c.Revision);
    assert(r.ok, r.message);
end
warnings = c.getState().readiness.warnings;
r = hadamard_stim.apply_controller_action(c, "start_run", struct("run_folder", ...
    string(tempname), "acknowledged_warnings", string({warnings.id})), c.Revision);
assert(r.ok, r.message);
end
