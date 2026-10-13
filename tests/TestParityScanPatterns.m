classdef TestParityScanPatterns < matlab.unittest.TestCase
    %TESTPARITYSCANPATTERNS The 63x14 Hadamard scan masks are his, bit for
    %bit, with and without a saved DMD mask, and leave the global random
    %generator where his left it.

    methods (TestClassSetup)
        function addPackage(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fileparts(fileparts(mfilename("fullpath")))));
        end
    end

    methods (Test)
        function masksMatchHisScanWithoutSavedMask(testCase)
            golden = load(fixture("drift"), "in_range").in_range.scan_acquisition;
            masks = hadamard_stim.yitong.static_hadamard_patterns();
            testCase.verifyClass(masks, "logical");
            testCase.verifySize(masks, golden.mask_sequence_size);
            testCase.verifyEqual(string(sha256_of(masks)), golden.mask_sequence_sha256);
        end

        function masksMatchHisScanWithSavedMask(testCase)
            golden = load(fixture("drift"), "saved_mask").saved_mask.scan_acquisition;
            saved_mask = false(1024, 768);
            saved_mask(201:900, 101:700) = true;
            masks = hadamard_stim.yitong.static_hadamard_patterns(saved_mask);
            testCase.verifyEqual(string(sha256_of(masks)), golden.mask_sequence_sha256);
        end

        function globalGeneratorIsLeftSeededAsHisWas(testCase)
            % His scan patterns call rng(142857, 'twister'), draw the
            % scramble mask and never restore the generator (notebook,
            % finding 9). The port keeps that.
            rng(1, "twister");
            before = rng;
            hadamard_stim.yitong.static_hadamard_patterns();
            after = rng;
            testCase.verifyNotEqual(after, before);
            rng(142857, "twister");
            randn(63 * [2 1] .* ceil([1024/63/2 768/63]));
            testCase.verifyEqual(after, rng);
        end

        function packingRoundTrips(testCase)
            masks = hadamard_stim.yitong.static_hadamard_patterns();
            btd = hadamard_stim.yitong.alp_logical_to_btd(permute(masks(:, :, 1:3), [2 1 3]));
            testCase.verifySize(btd, [128 768 3]);
            testCase.verifyEqual(hadamard_stim.yitong.alp_btd_to_logical(btd), masks(:, :, 1:3));
        end
    end
end

function file = fixture(name)
file = fullfile(fileparts(mfilename("fullpath")), "fixtures", "yitong_" + name + ".mat");
end

function hex = sha256_of(value)
% As tests/golden/mocks/golden_sha256: column-major bytes, logical as uint8.
if islogical(value)
    value = uint8(value);
end
md = java.security.MessageDigest.getInstance("SHA-256");
md.update(typecast(reshape(value, [], 1), "int8"));
hex = lower(reshape(dec2hex(typecast(md.digest(), "uint8"), 2).', 1, []));
end
