classdef TestCalibrationQc < matlab.unittest.TestCase
    %TESTCALIBRATIONQC The Hadamard calibration's QC, from what the rig uses.
    %
    %   Synthetic calibration recordings of a uniform slide under his scan
    %   patterns (synthetic_hadamard_movie) give a calibration that should
    %   look good; recordings in which the pattern is not seen give one that
    %   should not. Prepare rig writes the QC beside the recordings.

    properties
        Root
        Folder
        Good        % three recordings of the slide under the patterns
        Unseen      % three recordings with no pattern in them
    end

    methods (TestClassSetup)
        function setUp(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
            patterns = hadamard_stim.yitong.alp_btd_to_logical( ...
                hadamard_stim.yitong.hadamard_patterns_scramble_nopermutation([63 14], 1));
            [x, y] = meshgrid(1:160, 1:48);
            slide = 2000 * exp(-((x - 80).^2 / (2 * 35^2) + (y - 24).^2 / (2 * 14^2)));
            blank = false(size(patterns));
            for k = 1:3
                testCase.Good{k} = synthetic_hadamard_movie(patterns, slide, 1, k);
                testCase.Unseen{k} = synthetic_hadamard_movie(blank, slide, 1, 10 + k);
            end
        end
    end

    methods (TestMethodSetup)
        function makeFolder(testCase)
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Folder = string(temp.Folder);
        end
    end

    methods (Test)
        function aGoodCalibrationLooksGood(testCase)
            qc = qc_of(testCase.Good);
            s = qc.summary;
            testCase.verifyEqual(s.n_recordings, 3);
            testCase.verifyEqual(s.frames, [64 64 64]);
            testCase.verifyEqual(s.frame_size, [48 160]);
            testCase.verifyEqual(s.pinholes_used_illuminated, 63);
            testCase.verifyGreaterThan(s.contrast_median_illuminated, 2 * s.contrast_median_dark);
            testCase.verifyGreaterThan(s.recording_consistency_min_r, 0.9);
            testCase.verifyEqual(s.saturated_fraction, 0);
            testCase.verifySize(qc.had, [48 160 3]);
            testCase.verifyClass(qc.code, "uint8");
            testCase.verifyTrue(all(isnan(qc.ratio(~qc.illuminated))));
        end

        function anUnseenPatternLooksBad(testCase)
            good = qc_of(testCase.Good).summary;
            bad = qc_of(testCase.Unseen).summary;
            testCase.verifyLessThan(bad.contrast_median_illuminated, good.contrast_median_illuminated / 2);
            testCase.verifyLessThan(bad.recording_consistency_min_r, good.recording_consistency_min_r);
            testCase.verifyGreaterThan(bad.ratio_cv_illuminated, good.ratio_cv_illuminated);
        end

        function itShowsTheCalibrationTheRigUses(testCase)
            % The reconstruction panel is the rig's own reconstruct_scan.
            m_q = [63 14];
            [reconstruct, ~, scorr] = hadamard_stim.luminos.scan_reconstruction(m_q, testCase.Good);
            qc = hadamard_stim.luminos.calibration_qc(m_q, testCase.Good, scorr);
            file = fullfile(testCase.Folder, "frames1.bin");
            fid = fopen(file, "w", "ieee-le");
            fwrite(fid, permute(testCase.Good{2}, [2 1 3]), "uint16");   % rows first, as Luminos writes
            fclose(fid);
            acq.imaging = struct("file", file, "frame_size", [48 160]);
            testCase.verifyEqual(double(qc.had(:, :, 2)), double(single(reconstruct(acq))));
            testCase.verifyError(@() hadamard_stim.luminos.calibration_qc(m_q, testCase.Good, ...
                scorr(1:40, :, :)), "hadamard_stim:CalibrationSize");
        end

        function eachFolderGetsTheBundleOnce(testCase)
            folders = testCase.Folder + filesep + ["a" "b"];
            arrayfun(@mkdir, folders);
            qc = qc_of(testCase.Good);
            written = hadamard_stim.luminos.write_calibration_qc(qc, folders, "abc");
            testCase.verifyEqual(written, fullfile(folders', "hadamard_calibration_qc.png"));
            for f = folders
                for ext = [".png" ".json" ".mat"]
                    testCase.verifyTrue(isfile(fullfile(f, "hadamard_calibration_qc" + ext)), f + ext);
                end
                record = jsondecode(fileread(fullfile(f, "hadamard_calibration_qc.json")));
                testCase.verifyEqual(string(record.scorr_sha256), "abc");
                testCase.verifyEqual(string(record.folders)', folders);
                testCase.verifyEqual(record.summary.pinholes_used_illuminated, 63);
            end
            saved = load(fullfile(folders(1), "hadamard_calibration_qc.mat"));
            testCase.verifyEqual(saved.qc.code, qc.code);
            % The same calibration again: nothing is rewritten.
            testCase.verifyEmpty(hadamard_stim.luminos.write_calibration_qc(qc, folders, "abc"));
            % Another calibration from the same folders: rewritten.
            testCase.verifyNumElements(hadamard_stim.luminos.write_calibration_qc(qc, folders, "def"), 2);
        end

        function prepareRigWritesItBesideTheRecordings(testCase)
            % Scans named by folder (taken, or reused): the folders Prepare
            % rig reads its calibration from get its QC.
            folders = testCase.Folder + filesep + "had_cal_" + (1:3);
            for k = 1:3
                mkdir(folders(k));
                mov = testCase.Good{k};
                save(fullfile(folders(k), "stub_movie.mat"), "mov");
            end
            stub = fullfile(testCase.Folder, "stub");
            mkdir(stub);
            hadamard_stim.metadata.write_text([
                "function mov = Extract_Mov(path, options)"
                "arguments"
                "    path"
                "    options.cam_indices = []"
                "end"
                "s = load(fullfile(path, 'stub_movie.mat'));"
                "mov = s.mov;"
                "end"], fullfile(stub, "Extract_Mov.m"));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(stub));
            [c, ~, cfg] = tab_session(testCase.Folder + filesep + "session", calibration_movies={});
            c.Backend.set_settings(struct("calibration_folders", folders));
            c.setConfig(cfg);
            c.prepareRig();
            report = c.Env.context.hardware.scan_calibration.qc;
            testCase.verifyEqual(report.error, "");
            testCase.verifyEqual(report.written, fullfile(folders', "hadamard_calibration_qc.png"));
            for f = folders
                testCase.verifyTrue(isfile(fullfile(f, "hadamard_calibration_qc.png")));
            end
        end

        function scansGivenAsMoviesWriteNothing(testCase)
            [c, ~, cfg] = tab_session(testCase.Folder + filesep + "session");
            c.setConfig(cfg);
            c.prepareRig();
            testCase.verifyFalse(isfield(c.Env.context.hardware.scan_calibration, "qc"));
        end
    end
end

function qc = qc_of(movies)
m_q = [63 14];
scorr = hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, movies);
qc = hadamard_stim.luminos.calibration_qc(m_q, movies, scorr);
end
