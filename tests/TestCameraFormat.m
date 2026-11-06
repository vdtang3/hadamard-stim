classdef TestCameraFormat < matlab.unittest.TestCase
    %TESTCAMERAFORMAT 8- and 16-bit Kinetix movies, read and reconstructed as recorded.
    %
    %   The storage depth comes from Luminos (Camera.bit_depth) and travels
    %   with each acquisition; frames are read in their own class, never
    %   widened. Each mode has its own dark offset (firefly_profile
    %   camera_offsets): the Kinetix's 8-bit High Full Well sits at about
    %   20 counts, not his 100 (Yi-Chieh Huang's dark frames, notebook
    %   2026-11-02). The Hadamard arithmetic gives the same values for an
    %   8-bit movie as for the same counts in 16 bits at the same offset.

    properties
        Folder
        Patterns
        Slide
    end

    methods (TestClassSetup)
        function setUp(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, "tests", "support")));
            testCase.Patterns = hadamard_stim.yitong.alp_btd_to_logical( ...
                hadamard_stim.yitong.hadamard_patterns_scramble_nopermutation([63 14], 1));
            [x, y] = meshgrid(1:160, 1:48);
            testCase.Slide = 2000 * exp(-((x - 80).^2 / (2 * 35^2) + (y - 24).^2 / (2 * 14^2)));
        end
    end

    methods (TestMethodSetup)
        function makeFolder(testCase)
            temp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            testCase.Folder = string(temp.Folder);
        end
    end

    methods (Test)
        function theFormatIsTheStorageDepth(testCase)
            cam = hadamard_stim.testing.FakeLuminosCamera("Teledyne Kinetix");
            f = hadamard_stim.luminos.camera_format(cam);
            testCase.verifyEqual([f.storage_bits f.bytes_per_pixel f.saturation], [16 2 65535]);
            testCase.verifyEqual(f.class, "uint16");
            testCase.verifyTrue(f.supported);
            testCase.verifyEqual(f.description, "raw 16-bit frames (uint16)");
            testCase.verifyEqual(f.offset, 100);
            testCase.verifyTrue(f.offset_known);
            kinetix_mode(cam, "standard16");
            f = hadamard_stim.luminos.camera_format(cam);
            testCase.verifyEqual(f.offset, 100);
            testCase.verifySubstring(f.offset_source, "16-bit parity");
            kinetix_mode(cam, "hfw8");
            f = hadamard_stim.luminos.camera_format(cam);
            testCase.verifyEqual([f.storage_bits f.bytes_per_pixel f.saturation], [8 1 255]);
            testCase.verifyEqual(f.class, "uint8");
            testCase.verifyEqual(f.description, "raw 8-bit frames (uint8)");
            testCase.verifyEqual(f.mode_label, "8-bit High Full Well (Speed Mode)");
            testCase.verifyEqual(f.offset, 20);
            testCase.verifyTrue(f.offset_known);
            % Keyed by the mode, not the depth: another 8-bit mode, or 8
            % bits with no mode, has no offset (preflight refuses it).
            kinetix_mode(cam, "unmeasured8");
            f = hadamard_stim.luminos.camera_format(cam);
            testCase.verifyTrue(f.supported);
            testCase.verifyFalse(f.offset_known);
            testCase.verifyTrue(isnan(f.offset));
            testCase.verifyTrue(isnan(jsondecode_format(f).offset), "NaN survives JSON (null)");
            testCase.verifyFalse(hadamard_stim.luminos.camera_format(8).offset_known);
            testCase.verifyEqual(hadamard_stim.luminos.camera_format(16).offset, 100);
            % A record keeps the offset it recorded, whatever the table says now.
            kinetix_mode(cam, "hfw8");
            record = hadamard_stim.luminos.camera_format(cam);
            record.offset = 21;
            testCase.verifyEqual(jsondecode_format(record).offset, 21);
            % Recorded before offsets were: looked up by its mode.
            old = rmfield(hadamard_stim.luminos.camera_format(cam), ["offset" "offset_source" "offset_known"]);
            testCase.verifyEqual(hadamard_stim.luminos.camera_format(old).offset, 20);
            % A 12-bit mode is stored in 16 bits: read as uint16, saturating at 4095.
            cam.bit_depth = 16;
            cam.pixel_bit_depth = 12;
            f = hadamard_stim.luminos.camera_format(cam);
            testCase.verifyEqual([f.storage_bits f.bytes_per_pixel f.saturation], [16 2 4095]);
            testCase.verifyTrue(f.supported);
            % Neither 8 nor 16 bits, or compressed: not read.
            testCase.verifyFalse(hadamard_stim.luminos.camera_format(10).supported);
            cam.compression_method = "FSE";
            testCase.verifyFalse(hadamard_stim.luminos.camera_format(cam).supported);
            % A recorded format (JSON) comes back the same.
            cam.compression_method = "None";
            f = hadamard_stim.luminos.camera_format(cam);
            testCase.verifyEqual(jsondecode_format(f), f);
        end

        function eightBitFramesAreReadAsUint8(testCase)
            mov = uint8(randi([0 255], 5, 7, 9));
            file = write_movie(testCase.Folder, mov);
            f8 = hadamard_stim.luminos.camera_format(8);
            all_ = hadamard_stim.luminos.read_frames(file, [5 7], format=f8);
            testCase.verifyClass(all_, "uint8");
            testCase.verifyEqual(all_, mov);
            testCase.verifyEqual(hadamard_stim.luminos.read_frames(file, [5 7], [2 3 7 9], format=f8), ...
                mov(:, :, [2 3 7 9]));
            testCase.verifyError(@() hadamard_stim.luminos.read_frames(file, [5 7], 10, format=f8), ...
                "hadamard_stim:MissingFrames");
            % Read as 16-bit, the same file holds half as many frames: the
            % frame count and offsets come from the bytes per pixel.
            testCase.verifySize(hadamard_stim.luminos.read_frames(file, [5 7]), [5 7 4]);
            testCase.verifyError(@() hadamard_stim.luminos.read_frames(file, [5 7], 1, ...
                format=hadamard_stim.luminos.camera_format(10)), "hadamard_stim:UnsupportedFrames");
        end

        function sixteenBitFramesAreReadAsBefore(testCase)
            mov = uint16(reshape(1:5*7*9, 5, 7, 9) * 700);
            file = write_movie(testCase.Folder, mov);
            testCase.verifyEqual(hadamard_stim.luminos.read_frames(file, [5 7]), mov);
            testCase.verifyEqual(hadamard_stim.luminos.read_frames(file, [5 7], [9 1 2], ...
                format=hadamard_stim.luminos.camera_format(16)), mov(:, :, [9 1 2]));
            testCase.verifyError(@() hadamard_stim.luminos.read_frames(file, [5 7], 10), ...
                "hadamard_stim:MissingFrames");
        end

        function anAcquisitionIsReadInItsRecordedFormat(testCase)
            mov = uint8(randi([0 255], 5, 7, 6));
            acq.imaging = struct("file", write_movie(testCase.Folder, mov), "frame_size", [5 7], ...
                "format", hadamard_stim.luminos.camera_format(8));
            testCase.verifyEqual(hadamard_stim.luminos.acquisition_frames(acq), mov);
            testCase.verifyEqual(hadamard_stim.luminos.acquisition_frames(acq, 4:5), mov(:, :, 4:5));
            % Recorded before 8-bit support: 16-bit.
            mov16 = uint16(randi([0 65535], 5, 7, 6));
            legacy.imaging = struct("file", write_movie(testCase.Folder + filesep + "old", mov16), ...
                "frame_size", [5 7]);
            testCase.verifyEqual(hadamard_stim.luminos.acquisition_frames(legacy), mov16);
        end

        function sixteenBitMoviesAreHisArithmetic(testCase)
            % At his offset, uint16 movies are subtracted in uint16 and
            % clip at 0, as his were, whether the offset is given or not.
            m_q = [63 14];
            cal = cell(1, 2);
            for k = 1:2
                cal{k} = synthetic_hadamard_movie(testCase.Patterns, testCase.Slide, 1, k);
                cal{k}(1:3, :, :) = 60;   % below the offset: clipped
            end
            scorr = hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, cal);
            testCase.verifyEqual(hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, cal, 100), scorr);
            testCase.verifyEqual(hadamard_stim.yitong.dmd_hadamard_reconstruct_core(m_q, cal, scorr, 100), ...
                hadamard_stim.yitong.dmd_hadamard_reconstruct_core(m_q, cal, scorr));
            [h, r] = hadamard_stim.yitong.hadamard_reconstruct_core(m_q, cal, scorr, 100);
            [h0, r0] = hadamard_stim.yitong.hadamard_reconstruct_core(m_q, cal, scorr);
            testCase.verifyEqual({h r}, {h0 r0});
            % The clipping is there: the same counts in double (not clipped)
            % give a different calibration.
            unclipped = hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, ...
                cellfun(@double, cal, "UniformOutput", false), 99.999);
            testCase.verifyNotEqual(unclipped, scorr);
            % The adapter: unknown offsets are refused, not guessed.
            testCase.verifyError(@() hadamard_stim.luminos.scan_reconstruction(m_q, cal, offset=NaN), ...
                "hadamard_stim:UnknownCameraOffset");
        end

        function eightBitCountsReconstructAsTheSameCountsInSixteen(testCase)
            % Everything after reading is the same arithmetic on the same
            % counts at the same offset. The blank marker's mean (two
            % counts above 127) is where uint8 arithmetic would have
            % saturated.
            m_q = [63 14];
            cal = cell(1, 2);
            for k = 1:2
                cal{k} = eight_bit(synthetic_hadamard_movie(testCase.Patterns, testCase.Slide, 1, k));
            end
            scan = eight_bit(synthetic_hadamard_movie(testCase.Patterns, testCase.Slide, 1, 7));
            crow = ceil(size(scan, 1) / 2);
            scan(crow + [-1 1], 1:4, :) = 201;
            scan(crow + 1, 1, :) = 220;
            wide = @(c) cellfun(@uint16, c, "UniformOutput", false);
            scorr8 = hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, cal, 20);
            testCase.verifyEqual(scorr8, hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, wide(cal), 20));
            testCase.verifyEqual(hadamard_stim.yitong.dmd_hadamard_reconstruct_core(m_q, {scan}, scorr8, 20), ...
                hadamard_stim.yitong.dmd_hadamard_reconstruct_core(m_q, {uint16(scan)}, scorr8, 20));
            testCase.verifyEqual(hadamard_stim.yitong.hadamard_reconstruct_core(m_q, {scan}, scorr8, 20), ...
                hadamard_stim.yitong.hadamard_reconstruct_core(m_q, {uint16(scan)}, scorr8, 20));
        end

        function eightBitScansReconstructLikeSixteenBitOnes(testCase)
            % The same slide in 8 and 16 bits, as the Kinetix records it:
            % 8-bit High Full Well at offset 20 with 1/25 the counts above
            % it, so most 8-bit counts are at or below 100 (Yi-Chieh's
            % slide: median 90), where his uint16-style subtraction of 100
            % would leave nothing. Subtracted at 20, in double, the
            % pinholes are found by a normalised correlation, so a
            % 16-bit scan reconstructed with either calibration is the same
            % image, as close as two 16-bit calibrations are to each other
            % (r 0.9999, 0.3 % rms on this slide). Which pinhole is largest
            % at a pixel is not stable between any two calibrations (18 %
            % agree between two 16-bit ones), so that is not compared. Its
            % QC reads the 8-bit counts as 8-bit.
            m_q = [63 14];
            movies16 = cell(1, 3);
            movies8 = cell(1, 3);
            for k = 1:3
                movies16{k} = synthetic_hadamard_movie(testCase.Patterns, testCase.Slide, 1, k);
                movies8{k} = eight_bit(movies16{k});
            end
            all8 = cat(3, movies8{:});
            testCase.verifyGreaterThan(mean(all8(:) <= 100), 0.5);
            scorr16 = hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, movies16);
            scorr8 = hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, movies8, 20);
            qc16 = hadamard_stim.luminos.calibration_qc(m_q, movies16, scorr16);
            qc8 = hadamard_stim.luminos.calibration_qc(m_q, movies8, scorr8, offset=20);
            lit = qc16.illuminated & qc8.illuminated;
            scan = synthetic_hadamard_movie(testCase.Patterns, testCase.Slide, 1, 99);
            h16 = hadamard_stim.yitong.dmd_hadamard_reconstruct_core(m_q, {scan}, scorr16);
            h8 = hadamard_stim.yitong.dmd_hadamard_reconstruct_core(m_q, {scan}, scorr8, 100);
            r = corrcoef(h8(lit), h16(lit));
            testCase.verifyGreaterThan(r(1, 2), 0.999);
            testCase.verifyLessThan(norm(h8(lit) - h16(lit)) / norm(h16(lit)), 0.01);
            testCase.verifyEqual(qc8.summary.pinholes_used_illuminated, 63);
            testCase.verifyEqual(qc8.summary.storage_class, "uint8");
            testCase.verifyEqual(qc8.summary.saturation_count, 255);
            testCase.verifyEqual(qc8.summary.saturated_fraction, 0);
            testCase.verifyEqual([qc8.summary.offset qc16.summary.offset], [20 100]);
            % Raw counts are the mode's: 1/25 above its own offset.
            testCase.verifyEqual(qc8.summary.dark_median_raw - 20, ...
                (qc16.summary.dark_median_raw - 100) / 25, "AbsTol", 0.5);
            % Only the offset changes the widefield image: in counts above
            % it, 8-bit is 16-bit / 25, to within the 8-bit rounding (half
            % a count; the synthetic noise is far below one 8-bit count).
            testCase.verifyEqual(double(qc8.widefield(lit)), double(qc16.widefield(lit)) / 25, ...
                "AbsTol", 0.5);
            % A 12-bit mode in 16-bit storage saturates at 4095, not 65535.
            hot = movies16;
            hot{1}(1, 1, :) = 4095;
            qc = hadamard_stim.luminos.calibration_qc(m_q, hot, scorr16, saturation=4095);
            testCase.verifyGreaterThan(qc.summary.saturated_fraction, 0);
        end
    end
end

function file = write_movie(folder, mov)
% frames1.bin as Luminos writes it: each frame rows first, in its class.
if ~isfolder(folder)
    mkdir(folder);
end
file = fullfile(folder, "frames1.bin");
fid = fopen(file, "w", "ieee-le");
fwrite(fid, permute(mov, [2 1 3]), class(mov));
fclose(fid);
end

function mov = eight_bit(mov16)
% The same slide in 8-bit High Full Well: offset 20 (measured), the signal
% above it 1/25 (its own gain; Yi-Chieh's slide pair gave about 1/82, and
% this keeps the synthetic slide at her 8-bit levels).
mov = uint8(round(20 + (double(mov16) - 100) / 25));
end

function f = jsondecode_format(f)
f = hadamard_stim.luminos.camera_format(jsondecode(jsonencode(f)));
end
