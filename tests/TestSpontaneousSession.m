classdef TestSpontaneousSession < matlab.unittest.TestCase
    %TESTSPONTANEOUSSESSION Spontaneous imaging in blocks, as his behaviour script ran it.
    %
    %   The block waveform is his stimulation waveform's camera, orange,
    %   Grasshopper and IR rows with nothing else (no blue, no DMD
    %   triggers), described without its samples. A session runs its
    %   blocks with or without a drift correction before each (his
    %   single_v1: no smoothing), applies the bleaching update between
    %   blocks, checkpoints at block boundaries, reruns an interrupted
    %   block in full on resume, and records what it did. A block of his
    %   full length passes through the Luminos adapter without the package
    %   holding any of its samples.

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
            testCase.addTeardown(@() rmdir_if(testCase.Folder));
        end
    end

    methods (Test)
        function aBlockIsHisWaveformWithoutStimulation(testCase)
            [cfg, env] = parity_environment(fullfile(testCase.Root, "tests", "fixtures"));
            for n_frames = [2600 3001]
                for period = [1.27 1.29]
                    p = struct("daq_rate", cfg.daq.rate, "channels", cfg.daq.channels, ...
                        "exposure_ms", period, "gs_ms", cfg.stimulation.grasshopper_period_ms, ...
                        "n_frames", n_frames, "n_pat", 2, ...
                        "params", [cfg.stimulation.wait_frames 16 160 3], "blue_v", 0, ...
                        "ir_v", cfg.stimulation.ir_v, "orange_v", 1.7, ...
                        "blue_calibration", env.blue_calibration);
                    his = hadamard_stim.yitong.multipat_periodic_pulse_v2_waveform(p);
                    w = hadamard_stim.protocol.spontaneous_waveform(cfg, period, 1.7, n_frames);
                    testCase.verifyEqual(w.n_samples, size(his.amplitude, 2));
                    for row = ["cameraTrigger" "orangeIntensity" "grashopperTrigger" "IRVoltage"]
                        mine = hadamard_stim.waveform.row(w, row);
                        testCase.verifyEqual(mine, his.amplitude(his.channels == row, :), row);
                        testCase.verifyEqual(hadamard_stim.waveform.rising_edges(w, row), ...
                            nnz(diff([false mine > 0]) > 0), row);
                    end
                    % Nothing else is driven: no blue, no DMD triggers.
                    testCase.verifyEqual(sort(w.channels)', ...
                        sort(["cameraTrigger" "orangeIntensity" "grashopperTrigger" "IRVoltage"]));
                    testCase.verifyFalse(any(hadamard_stim.waveform.row(w, "blueIntensity")));
                    testCase.verifyFalse(any(hadamard_stim.waveform.row(w, "dmdTrigger")));
                end
            end
            % His full block is described in kilobytes.
            w = hadamard_stim.protocol.spontaneous_waveform(cfg, 1.27, 1, 288000);
            info = whos("w");
            testCase.verifyLessThan(info.bytes, 50e3);
            testCase.verifyEqual(w.n_samples, (200 + 288000) * 127);
            testCase.verifyEqual(hadamard_stim.waveform.rising_edges(w, "cameraTrigger"), 288000);
        end

        function blocksRunWithDriftCorrectionAndBleachingAsHeRanThem(testCase)
            [c, env] = testCase.session(n_blocks=3);
            c.startRun(testCase.Folder, AcknowledgedWarnings="config_deviations");
            testCase.assertEqual(c.LifecycleState, "COMPLETED");
            a = env.hw.acquisitions;
            blocks = a([a.kind] == "spontaneous");
            testCase.verifyNumElements(blocks, 3);
            testCase.verifyEqual([blocks.n_frames], [1200 1200 1200]);
            testCase.verifyEqual([blocks.blue_v], [0 0 0]);
            testCase.verifyEqual([blocks.folder], "M-YQ0201-29_FOV1_behavior_mask5_DC_0" + (1:3));
            % A drift scan before every block.
            kinds = [a.kind];
            k = find(kinds == "spontaneous");
            testCase.verifyEqual(kinds(k - 1), repmat("drift_scan", 1, 3));
            testCase.verifyEqual([a(k - 1).folder], "M-YQ0201-29_FOV1_had_trial" + (1:3));
            % Bleaching: b0/b1 both from block 1 at block 2 (ratio 1), then
            % block 2's from block 3 on.
            records = block_records(testCase.Folder);
            testCase.verifyEqual(blocks(2).orange_v, blocks(1).orange_v);
            testCase.verifyEqual(blocks(3).orange_v, blocks(2).orange_v * records(2).b0 / records(2).b1, ...
                "RelTol", 1e-12);
            testCase.verifyGreaterThan(blocks(3).orange_v, blocks(2).orange_v);
            % The illumination mask, as corrected before the block, is what
            % the DMD shows: one static picture.
            testCase.verifyEqual(blocks(3).dmd_stack.size, [1024 768 1]);
            current = c.RunState.cells.current.illum_mask;
            testCase.verifyEqual(blocks(3).dmd_stack.sha256, ...
                hadamard_stim.metadata.sha256(permute(current, [2 1 3])));
            testCase.verifyEmpty(blocks(3).queue);
            % His single_v1 corrections: illumination only, each cell's own flow.
            corrections = c.RunState.cells.corrections;
            testCase.verifyNumElements(corrections, 3);
            testCase.verifyEqual([corrections.stim_mask_sha256], ["" "" ""]);
            last = corrections(end);
            testCase.verifyEqual(last.cell_shift, last.flow_at_cells);
        end

        function withoutDriftCorrectionThereIsNoZStackOrStageMove(testCase)
            [c, env] = testCase.session(n_blocks=2, drift=false, z_reference=false);
            testCase.verifyEqual(c.LifecycleState, "READY");
            c.startRun(testCase.Folder, AcknowledgedWarnings="config_deviations");
            testCase.assertEqual(c.LifecycleState, "COMPLETED");
            testCase.verifyEqual([env.hw.acquisitions.kind], ["spontaneous" "spontaneous"]);
            testCase.verifyEmpty(env.hw.moves);
            testCase.verifyEqual([env.hw.acquisitions.orange_v], [1 1]);
            recipe = jsondecode(fileread(fullfile(testCase.Folder, "run_recipe.json")));
            testCase.verifyFalse(recipe.streams.drift_correction.enabled);
            testCase.verifyTrue(any(contains(string(recipe.warnings), "Drift correction between blocks off")));
            testCase.verifyTrue(ismember("spontaneous.drift_correction", string({recipe.deviations.path})));
            testCase.verifyEmpty(recipe.matrix);
        end

        function aOneBlockTestNeedsNoParticularLength(testCase)
            [c, env] = testCase.session(n_blocks=1, block_frames=50);
            c.startRun(testCase.Folder, AcknowledgedWarnings="config_deviations");
            testCase.assertEqual(c.LifecycleState, "COMPLETED");
            block = env.hw.acquisitions(end);
            testCase.verifyEqual(block.n_frames, 50);
            % Longer runs need blocks long enough to measure bleaching.
            cfg = c.Config;
            cfg.spontaneous.n_blocks = 2;
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyFalse(report.ok);
            testCase.verifySubstring(report.errors(1), "bleaching");
            cfg.bleaching.enabled = false;
            testCase.verifyTrue(hadamard_stim.validate_config(cfg).ok);
        end

        function anAbortedBlockIsAcquiredAgainOnResume(testCase)
            [straight, ~] = testCase.session(n_blocks=3);
            straight.startRun(testCase.Folder + "_straight", AcknowledgedWarnings="config_deviations");
            testCase.addTeardown(@() rmdir_if(testCase.Folder + "_straight"));
            expected = block_records(testCase.Folder + "_straight");

            [c, env] = testCase.session(n_blocks=3);
            c.StatusChangedFcn = @(ctrl) abort_in_block(ctrl, 2);
            c.startRun(testCase.Folder, AcknowledgedWarnings="config_deviations");
            c.StatusChangedFcn = [];
            testCase.assertEqual(c.LifecycleState, "ABORTED");
            testCase.verifySubstring(c.LastError, "resumes at block 2");
            testCase.verifyEqual(c.RunState.next_block, 2);
            testCase.verifyNumElements(dir(fullfile(testCase.Folder, "blocks", "*.json")), 1);
            v = hadamard_stim.controller_view(c, "checkpoint").data;
            testCase.verifyEqual(v.session_mode, "spontaneous");
            testCase.verifyEqual([v.next_block v.n_blocks v.n_block_records], [2 3 1]);
            n_before = numel(env.hw.acquisitions);

            r = hadamard_stim.apply_controller_action(c, "resume_run", struct(), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyEqual(c.LifecycleState, "COMPLETED");
            % Block 2 again from its drift correction, then block 3. The
            % repeated correction starts from where the abandoned one left
            % the stage, so only the stage and the correction differ.
            again = env.hw.acquisitions(n_before + 1:end);
            testCase.verifyEqual([again.kind], ["drift_scan" "spontaneous" "drift_scan" "spontaneous"]);
            testCase.verifyEqual(without_stage(block_records(testCase.Folder)), without_stage(expected));
            resume = jsondecode(fileread(fullfile(testCase.Folder, "resumes", "resume_001.json")));
            testCase.verifyEqual(resume.next_block, 2);
            testCase.verifyFalse(isfield(resume, "next_trial"));
        end

        function theStateAndRecordsCarryNoBulkData(testCase)
            [c, env] = testCase.session(n_blocks=2);
            c.startRun(testCase.Folder, AcknowledgedWarnings="config_deviations");
            state = c.getState();
            testCase.verifyLessThan(strlength(jsonencode(state)), 64e3);
            testCase.verifyEqual(state.progress.unit, "block");
            testCase.verifyEqual([state.progress.next_block state.progress.n_blocks], [3 2]);
            testCase.verifyEqual(state.last_block.block, 2);
            testCase.verifyEqual(state.session_mode, "spontaneous");
            record = c.LastRecord;
            testCase.verifyFalse(isfield(record.acquisition, "waveform"));
            info = whos("record");
            testCase.verifyLessThan(info.bytes, 100e3);
            rig = env.hw.acquisitions; %#ok<NASGU>
            info = whos("rig");
            testCase.verifyLessThan(info.bytes, 2e6);
            saved = jsondecode(fileread(fullfile(testCase.Folder, "blocks", "block_02.json")));
            testCase.verifyEqual(saved.kind, 'hadamard_stim_block');
            testCase.verifyEqual(saved.blue_v, 0);
            testCase.verifyTrue(saved.streams.face_camera);
            testCase.verifyFalse(saved.streams.wheel_encoder);
            testCase.verifyEqual(saved.acquisition.waveform_function, 'spontaneous_block');
        end

        function validationFollowsTheSessionMode(testCase)
            cfg = hadamard_stim.default_config();
            cfg.naming.prefix = "M1";
            cfg.segmentation.n_exclude = 5;
            cfg.stimulation.orange_start_v = 1;
            % The trigger edge is the protocol's (rising): nothing to set.
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyTrue(report.ok, strjoin(report.errors, " "));
            testCase.verifyEqual(cfg.dmd.trigger_edge, "rising");
            cfg.session.mode = "spontaneous";
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyTrue(report.ok, strjoin(report.errors, " "));
            testCase.verifyEqual(report.mode, "yitong_compatible");
            % Connectivity settings do not make a spontaneous run modified,
            % and the other way round.
            cfg.sparse.blue_v = 3;
            testCase.verifyEqual(hadamard_stim.validate_config(cfg).mode, "yitong_compatible");
            % The number of blocks is the run's scope, like the trial range;
            % their length changes the measurement.
            cfg.spontaneous.n_blocks = 1;
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyEmpty(report.deviations);
            cfg.spontaneous.block_frames = 1000;
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyEqual(string({report.deviations.path}), "spontaneous.block_frames");
            cfg.spontaneous.block_frames = hadamard_stim.default_config().spontaneous.block_frames;
            cfg.session.mode = "connectivity";
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyEqual(string({report.deviations.path}), "sparse.blue_v");
            % Streams off are warnings, never deviations.
            cfg.sparse.blue_v = 4;
            cfg.behavior.face_camera_enabled = false;
            report = hadamard_stim.validate_config(cfg);
            testCase.verifyEmpty(report.deviations);
            testCase.verifyEqual(report.mode, "yitong_compatible");
            testCase.verifyNumElements(report.warnings, 2);
            cfg.session.mode = "other";
            testCase.verifySubstring(strjoin(hadamard_stim.validate_config(cfg).errors), "session.mode");
        end

        function aSessionMustHaveWhatItsModeNeedsBeforeItRuns(testCase)
            [c, ~] = testCase.session(n_blocks=1, drift=false, z_reference=false);
            testCase.assertEqual(c.LifecycleState, "READY");
            testCase.verifyTrue(c.legalActions().start_run);
            % Switched to connectivity: the z-stack is missing, so Run waits.
            cfg = c.Config;
            cfg.session.mode = "connectivity";
            c.setConfig(cfg);
            testCase.verifyFalse(c.legalActions().start_run);
            testCase.verifyTrue(c.legalActions().acquire_z_reference);
            testCase.verifyError(@() c.startRun(testCase.Folder), "hadamard_stim:NoZReference");
            testCase.verifyFalse(isfolder(testCase.Folder));
            r = hadamard_stim.apply_controller_action(c, "acquire_z_reference", struct(), c.Revision);
            testCase.verifyTrue(r.ok, r.message);
            testCase.verifyTrue(c.legalActions().start_run);
            % The DMD checks a mode uses; a missing slide test is a warning,
            % not a refusal, and a spontaneous session uses neither.
            context = struct("hardware_validation", struct());
            gate = hadamard_stim.metadata.hardware_gate(context, "spontaneous");
            testCase.verifyTrue(gate.all_passed);
            testCase.verifyEqual(string({gate.items.status}), ["not_needed" "not_needed"]);
            gate = hadamard_stim.metadata.hardware_gate(context, "connectivity");
            testCase.verifyEqual(gate.missing, "slide_queue");
            testCase.verifyEqual(string({gate.items.status}), ["info" "warning"]);
        end

        function aFullLengthBlockThroughTheAdapterHoldsNoSamples(testCase)
            % His block length, encoder and face camera on, through
            % LuminosRig and the fake Luminos (which builds each row as
            % Luminos does). The package keeps descriptions and records
            % only; the process stays well inside the memory cap.
            [c, app, cfg] = tab_session(testCase.Folder);
            cfg.session.mode = "spontaneous";
            cfg.spontaneous.n_blocks = 1;
            cfg.spontaneous.drift_correction = false;
            cfg.behavior.wheel_encoder_enabled = true;
            c.setConfig(cfg);
            c.prepareRig();
            use_parity_scans(c, testCase.Root);
            c.acquireReferenceImage();
            c.proposeCells();
            c.approveCells();
            testCase.assertEqual(c.LifecycleState, "READY");
            c.runPreflight();
            memory_check = c.Preflight.checks(string({c.Preflight.checks.id}) == "block_memory");
            testCase.verifySubstring(memory_check.message, "36.6 M samples");
            c.startRun(fullfile(testCase.Folder, "run"), AcknowledgedWarnings="config_deviations");
            testCase.assertEqual(c.LifecycleState, "COMPLETED", c.LastError);
            block = app.Acquisitions(end);
            n = (200 + 288000) * 127;
            testCase.verifyEqual(block.n_samples, n);
            testCase.verifyEqual(block.dmd_showing, "static");
            testCase.verifyEqual(sort([block.ports.port]), sort(["Dev1/port0/line9" "Dev1/port0/line10" ...
                "Dev1/ao0" "Dev1/ao3" "Dev1/port0/line26" "Dev1/port0/line0"]));
            testCase.verifyEqual(unique([block.ports.n_samples]), n);
            kinetix = block.cameras([block.cameras.name] == "Teledyne Kinetix");
            testCase.verifyEqual(kinetix.frames, 288000);
            grasshopper = block.cameras([block.cameras.name] == "Grasshopper3");
            testCase.verifyEqual(grasshopper.frames, floor(288000 * 1.27 / 25));
            % What the package kept.
            rig = c.Env.hw; %#ok<NASGU>
            acquisitions = c.Env.hw.acquisitions; %#ok<NASGU>
            info = whos("acquisitions");
            testCase.verifyLessThan(info.bytes, 1e6);
            state = c.RunState; %#ok<NASGU>
            info = whos("state");
            testCase.verifyLessThan(info.bytes, 50e6);   % the cells' masks and reference images
            testCase.verifyLessThan(strlength(jsonencode(c.getState())), 64e3);
            record = jsondecode(fileread(fullfile(testCase.Folder, "run", "blocks", "block_01.json")));
            testCase.verifyEqual(record.acquisition.encoder.status, 'recorded');
            testCase.verifyEqual(record.acquisition.encoder.n_samples, n);
            testCase.verifyEqual(record.acquisition.behavior.frames, floor(288000 * 1.27 / 25));
            % Released: the static picture is gone and the DMD handed back.
            dmd = app.getDevice("ALP_DMD");
            testCase.verifyEqual(dmd.Displaying, "dark");
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyTrue(any(c.LastCleanup.steps == "restore_target"));
        end

        function theTabAndTheProgrammaticPathAskForTheSameBlocks(testCase)
            folders = testCase.Folder + ["_a" "_b"];
            testCase.addTeardown(@() arrayfun(@rmdir_if, folders));
            cfg = [];
            acquisitions = cell(1, 2);
            for k = 1:2
                mkdir(folders(k));
                [c, app, base] = tab_session(folders(k));
                base.session.mode = "spontaneous";
                base.spontaneous.n_blocks = 2;
                base.spontaneous.block_frames = 1200;
                base.bleaching.enabled = false;
                base.behavior.face_camera_enabled = false;
                base.behavior.wheel_encoder_enabled = true;
                cfg = base;
                if k == 1
                    c.setConfig(cfg);
                    c.prepareRig();
                    use_parity_scans(c, testCase.Root);
                    c.acquireReferenceImage();
                    c.proposeCells();
                    c.approveCells();
                    c.acquireZReference();
                    c.startRun(fullfile(folders(k), "run"), AcknowledgedWarnings="config_deviations");
                else
                    act = @(a, p) hadamard_stim.apply_controller_action(c, a, p, c.Revision);
                    changes = config_changes(cfg);
                    testCase.assertTrue(act("update_config", struct("changes", changes)).ok);
                    testCase.assertTrue(act("prepare_rig", struct()).ok);
                    use_parity_scans(c, testCase.Root);
                    for step = ["acquire_reference_image" "propose_cells" "approve_cells" "acquire_z_reference"]
                        r = act(step, struct());
                        testCase.assertTrue(r.ok, step + ": " + r.message);
                    end
                    r = act("start_run", struct("run_folder", fullfile(folders(k), "run"), ...
                        "acknowledged_warnings", "config_deviations"));
                    testCase.assertTrue(r.ok, r.message);
                end
                testCase.assertEqual(c.LifecycleState, "COMPLETED");
                testCase.assertEqual(c.Config, cfg);
                acquisitions{k} = rmfield(app.Acquisitions, ["folder" "tag"]);
            end
            testCase.verifyEqual(acquisitions{2}, acquisitions{1});
        end
    end

    methods
        function [c, env] = session(testCase, options)
            arguments
                testCase
                options.n_blocks (1, 1) double = 3
                options.block_frames (1, 1) double = 1200
                options.drift (1, 1) logical = true
                options.z_reference (1, 1) logical = true
            end
            [cfg, env, inputs] = spontaneous_environment(fullfile(testCase.Root, "tests", "fixtures"), ...
                n_blocks=options.n_blocks, block_frames=options.block_frames);
            cfg.spontaneous.drift_correction = options.drift;
            c = hadamard_stim.HadamardStimController(env);
            for step = {{"set_config", struct("config", cfg)}, {"set_reference_image", struct("image", inputs.ref_im)}, ...
                    {"propose_cells", struct()}, {"approve_cells", struct()}}
                r = hadamard_stim.apply_controller_action(c, step{1}{1}, step{1}{2}, c.Revision);
                assert(r.ok, r.message);
            end
            if options.z_reference && c.LifecycleState ~= "READY"
                r = hadamard_stim.apply_controller_action(c, "acquire_z_reference", struct(), c.Revision);
                assert(r.ok, r.message);
            end
        end
    end
end

function changes = config_changes(cfg)
% The tab's edits that turn the default configuration into cfg.
defaults = hadamard_stim.default_config();
changes = struct("path", {}, "value", {});
for f = hadamard_stim.ui.config_fields()'
    v = cfg;
    d = defaults;
    for p = split(f.path, ".")'
        v = v.(p);
        d = d.(p);
    end
    if ~isequal(v, d)
        changes(end+1) = struct("path", f.path, "value", v); %#ok<AGROW>
    end
end
end

function abort_in_block(ctrl, block)
if ~isempty(ctrl.Phase) && ctrl.Phase.name == "spontaneous" && isfield(ctrl.Phase, "block") ...
        && ctrl.Phase.block == block && ctrl.legalActions().abort
    ctrl.requestAbort();
end
end

function records = block_records(folder)
% The block records, without what legitimately differs between runs.
records = struct([]);
for f = dir(fullfile(folder, "blocks", "block_*.json"))'
    r = jsondecode(fileread(fullfile(f.folder, f.name)));
    r = rmfield(r, intersect(fieldnames(r), ["started_utc" "written_utc" "recipe_hash"]));
    if isfield(r, "acquisition") && isstruct(r.acquisition)
        r.acquisition = rmfield(r.acquisition, intersect(fieldnames(r.acquisition), "index"));
    end
    if isempty(records)
        records = r;
    else
        records(end+1) = r; %#ok<AGROW>
    end
end
end

function records = without_stage(records)
records = rmfield(records, "correction");
for k = 1:numel(records)
    records(k).acquisition = rmfield(records(k).acquisition, "motor_z");
end
end

function rmdir_if(folder)
if isfolder(folder)
    rmdir(folder, "s");
end
end
