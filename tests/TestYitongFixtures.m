classdef TestYitongFixtures < matlab.unittest.TestCase
    %TESTYITONGFIXTURES The golden fixtures are complete, traceable to the
    %frozen reference, and record the behaviours the port must reproduce.
    %
    %   These tests pin the fixtures themselves. The parity tests that
    %   compare +hadamard_stim against them arrive with the port (Phase 3).

    properties
        Root
        Fixtures
    end

    properties (TestParameter)
        Section = {"session_inputs", "matrix", "blue", "segmentation", ...
            "masks", "waveforms", "drift", "trace", "reconstruction"}
    end

    methods (TestClassSetup)
        function locate(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.Fixtures = fullfile(testCase.Root, "tests", "fixtures");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
        end
    end

    methods (Test)
        function fixtureRecordsItsProvenance(testCase, Section)
            p = testCase.load(Section, "provenance").provenance;
            manifest = fullfile(testCase.Root, "tests", "yitong_reference", "MANIFEST.tsv");
            testCase.verifyEqual(p.yitong_manifest_sha256, file_sha256(manifest), ...
                "Fixture was generated from a different frozen reference; regenerate it");
            testCase.verifyEqual(p.section, string(Section));
            testCase.verifyNotEmpty(p.loaded_files);
        end

        function matrixIsTheSeededBernoulliMatrix(testCase)
            m = testCase.load("matrix");
            testCase.verifySize(m.had_mat, [320 320]);
            testCase.verifyClass(m.had_mat, "logical");
            testCase.verifyTrue(m.equals_seeded_bernoulli);
            testCase.verifyTrue(m.rng_restored_to_default);
            testCase.verifyTrue(m.independent_of_incoming_rng);
        end

        function segmentationReproducesYitongsSavedCells(testCase)
            s = testCase.load("segmentation");
            testCase.verifyTrue(s.real.reproduces_saved_cell_coord);
            testCase.verifyEqual(s.real.n_exclude, 5);
            testCase.verifySize(s.real.cells, [320 2]);
            testCase.verifyEqual(s.synthetic.image_sha256, ...
                string(sha256_of(synthetic_reference_image())), ...
                "synthetic_reference_image no longer regenerates the fixture's input");
            testCase.verifyNotEqual(s.integer_image_error, "");
        end

        function masksReproduceYitongsSavedRois(testCase)
            m = testCase.load("masks");
            testCase.verifyEqual(m.check_2024.illum_rois_max_abs_error, 0);
            testCase.verifyEqual(m.check_2024.stim_rois_max_abs_error, 0);
            testCase.verifyTrue(m.canonical.cell_coord_equals_saved);
            testCase.verifySize(m.canonical.mask_sequence, [1024 768 2]);
        end

        function waveformsMatchRecordedAndExpectedCounts(testCase)
            w = testCase.load("waveforms");
            % Same length as the DAQ_data Yitong recorded with his 2025-03-08 scan.
            testCase.verifyEqual(w.scan_drift.n_samples, 162280);
            row = @(name) find(w.channels == name);
            testCase.verifyEqual(w.stim_sparse.rising_edges(row("cameraTrigger")), 8000);
            testCase.verifyEqual(w.stim_sparse.rising_edges(row("dmdTrigger")), 961);
            testCase.verifyEqual(w.stim_hadamard.rising_edges(row("dmdTrigger")), 9601);
            testCase.verifyEqual(w.scan_drift.rising_edges(row("cameraTrigger")), 640);
            for name = ["stim_sparse" "stim_hadamard" "stim_small_sparse" ...
                    "stim_small_hadamard" "scan_drift" "scan_small"]
                d = w.(name);
                testCase.verifyEqual(cellfun(@sum, d.run_lengths), ...
                    repmat(d.n_samples, numel(d.rows), 1), name + ": run lengths");
            end
        end

        function driftRecoversTheInjectedShift(testCase)
            % Sanity on the synthetic input, not parity: Yitong's optical
            % flow should find roughly the XY drift that was applied.
            d = testCase.load("drift");
            for name = ["in_range" "saved_mask"]
                c = d.(name);
                testCase.verifyEqual(mean(c.cell_shift, 1), c.sample_drift(1:2), "AbsTol", 0.1);
                testCase.verifyEqual(c.restored.exposure_waveform_ms, 1.27, "AbsTol", 1e-12);
            end
            % static_Hadamard_patterns reseeds the global RNG. Only the first
            % case starts from a different state; later cases start from the
            % state the previous case's reseed left behind.
            testCase.verifyTrue(d.in_range.global_rng_changed);
        end

        function traceFollowsTheProtocolSchedule(testCase)
            t = testCase.load("trace");
            m = testCase.load("matrix");
            a = t.acquisitions;
            kinds = [a.kind];
            stim = a(kinds == "stimulation");
            testCase.verifyEqual(nnz(kinds == "z_stack_plane"), 21);
            testCase.verifyEqual(numel(stim), numel(t.trials));
            trial = arrayfun(@(s) trial_number(s.folder), stim);
            testCase.verifyEqual(trial(:)', t.trials);
            n_drift = nnz(t.trials == 1 | mod(t.trials, 40) == 0);
            testCase.verifyEqual(nnz(kinds == "drift_scan"), n_drift);

            n_hadamard = 0;
            for k = 1:numel(stim)
                s = stim(k);
                if mod(trial(k), 4) == 0
                    n_hadamard = n_hadamard + 1;
                    cols = mod(8 * (n_hadamard - 1), 320) + (1:8);
                    testCase.verifyEqual(s.c_idx_all_it, m.had_mat(:, cols) > 0);
                    testCase.verifyEqual(s.waveform_params, ["200" "600" "600" "8"]);
                    testCase.verifyEqual(s.blue_v, 2);
                    testCase.verifyEqual(s.queue.repeat, [600 * ones(1, 7) 1200]);
                else
                    testCase.verifyEqual(s.waveform_params, ["200" "16" "160" "30"]);
                    testCase.verifyEqual(s.blue_v, 4);
                    testCase.verifyEqual(s.queue.repeat, [16 * ones(1, 29) 32]);
                    testCase.verifyLessThanOrEqual(max(sum(s.c_idx_all_it, 2)), 1, ...
                        "a cell is pulsed at most once per sparse trial");
                end
                testCase.verifyEqual(s.exposure_waveform_ms, 1.27, "AbsTol", 1e-12);
            end
        end

        function reconstructionResemblesTheSample(testCase)
            r = testCase.load("reconstruction");
            testCase.verifyGreaterThan(r.dmd.correlation_with_sample, 0.99);
            testCase.verifyTrue(r.dmd.hadamard_ref_set);
        end
    end

    methods
        function data = load(testCase, section, varargin)
            file = fullfile(testCase.Fixtures, "yitong_" + section + ".mat");
            testCase.assertTrue(isfile(file), "Missing fixture " + file + ...
                "; run tests/golden/generate_yitong_goldens");
            data = load(file, varargin{:});
        end
    end
end

function n = trial_number(folder)
parts = split(folder, "_");
n = str2double(parts(end));
end

function hex = sha256_of(value)
md = java.security.MessageDigest.getInstance("SHA-256");
md.update(typecast(reshape(value, [], 1), "int8"));
hex = lower(reshape(dec2hex(typecast(md.digest(), "uint8"), 2).', 1, []));
end

function hex = file_sha256(file)
fid = fopen(file, "r");
closer = onCleanup(@() fclose(fid));
md = java.security.MessageDigest.getInstance("SHA-256");
md.update(typecast(fread(fid, inf, "*uint8"), "int8"));
hex = string(lower(reshape(dec2hex(typecast(md.digest(), "uint8"), 2).', 1, [])));
end
