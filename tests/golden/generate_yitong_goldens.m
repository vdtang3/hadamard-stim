function generate_yitong_goldens(options)
%GENERATE_YITONG_GOLDENS Regenerate tests/fixtures by running Yitong's code.
%
%   generate_yitong_goldens()
%   generate_yitong_goldens(sections=["matrix" "waveforms"])
%   generate_yitong_goldens(trace_trials=1:12)      % quick trace
%
%   Every fixture is produced by executing the frozen copy of Yitong Qi's
%   Firefly code in tests/yitong_reference, never by re-implementing it.
%   Only hardware, file I/O and interactive prompts are replaced, by the
%   mocks in tests/golden/mocks and the shims in tests/golden/shims.
%
%   The one fixture taken from experimental data, yitong_session_inputs.mat,
%   is extracted read-only from Yitong's data&notes folder (configured in
%   config/paths.local.m). Every other section reads that fixture, so
%   regenerating them does not need the lab share.
%
%   Sections, in dependency order:
%     session_inputs  cell geometry and reference image from his sessions
%     matrix          the 320x320 stimulation matrix
%     blue            linearize_blue_voltage on his blueCal.mat
%     segmentation    static_image_seg_v5 cell detection and ordering
%     masks           Auto Square + reduce_spot_size_sequence spot masks
%     waveforms       stimulation and scan DAQ waveforms
%     drift           square_target_drift_correction_v4, XY and Z
%     trace           the protocol script's trial loop, acquisition by acquisition
%     reconstruction  dmd_hadamard_reconstruct / hadamard_reconstruct

arguments
    options.sections (1,:) string = ["session_inputs" "matrix" "blue" ...
        "segmentation" "masks" "waveforms" "drift" "trace" "reconstruction"]
    options.trace_trials (1,:) double = 1:640
end

ctx = golden_context();
cleanup = onCleanup(@() golden_teardown(ctx)); %#ok<NASGU>

for section = options.sections
    fprintf("\n=== %s ===\n", section);
    clear functions %#ok<CLFUNC> so provenance lists only what this section loads
    started = tic;
    switch section
        case "session_inputs", data = golden_session_inputs(ctx);
        case "matrix",         data = golden_matrix(ctx);
        case "blue",           data = golden_blue(ctx);
        case "segmentation",   data = golden_segmentation(ctx);
        case "masks",          data = golden_masks(ctx);
        case "waveforms",      data = golden_waveforms(ctx);
        case "drift",          data = golden_drift(ctx);
        case "trace",          data = golden_trace(ctx, options.trace_trials);
        case "reconstruction", data = golden_reconstruction(ctx);
        otherwise, error("Unknown section %s", section);
    end
    golden_save(ctx, section, data);
    fprintf("%s done in %.1f s\n", section, toc(started));
end
end
