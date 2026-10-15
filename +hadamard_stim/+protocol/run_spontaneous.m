function [state, records] = run_spontaneous(cfg, env, state)
%RUN_SPONTANEOUS Spontaneous voltage imaging in blocks, from state.next_block.
%
%   [state, records] = hadamard_stim.protocol.run_spontaneous(cfg, env, state)
%
%   His RunSynchronizedAQMulti_behavior_NPY_GFP_v1 (2025-02-21), the block
%   loop. Before each block, when cfg.spontaneous.drift_correction is on:
%   a drift scan and correction (run_drift_correction with smooth=false,
%   stim=false, i.e. his square_target_drift_correction_single_v1), then,
%   from the second block on, orange rescaled by b0/b1 as in his trials.
%   Then the illumination mask goes up as a static DMD picture and one
%   continuous acquisition records cfg.spontaneous.block_frames frames with
%   orange only (spontaneous_waveform). Blue is never driven.
%
%   b0 is measured on the first block and b1 on every block, from
%   cfg.bleaching.frames, but only when the update will be applied (drift
%   correction on, bleaching on, more than one block): a one-block test
%   needs no particular length.
%
%   env as for run_protocol, with env.after_block(state, record) in place
%   of after_trial. Each block is complete when it returns, so stopping or
%   failing leaves a state that resumes at a block boundary; a block that
%   was interrupted is acquired again in full.
%
%   Not ported from his script: the RFP z-stack (the reference z-stack here
%   is run_z_reference's, with whatever filter is in place), the closing
%   GFP z-stack, the SpinView clicks (the face camera is Luminos's), and
%   his manual pause before the last block.
s = cfg.spontaneous;
measure = s.drift_correction && cfg.bleaching.enabled && s.n_blocks > 1;
records = {};
for iBlock = state.next_block:s.n_blocks
    record = struct("block", iBlock, "n_blocks", s.n_blocks, "started_utc", utc_now(), ...
        "kind", "spontaneous", "folder", "", "retarget", s.drift_correction, ...
        "correction", [], "orange_v", NaN, "n_frames", s.block_frames, ...
        "b0", NaN, "b1", NaN, "streams", [], "acquisition", []);

    if s.drift_correction
        hadamard_stim.protocol.report_phase(env, "drift_correction", ...
            struct("block", iBlock, "n_blocks", s.n_blocks));
        [state, record.correction] = hadamard_stim.protocol.run_drift_correction( ...
            cfg, env, state, iBlock, smooth=false, stim=false);
        if iBlock > 1 && measure
            if isempty(state.b0) || isempty(state.b1)
                error("hadamard_stim:BleachingUnknown", ...
                    ['Block %d rescales orange by b0/b1, but they have not both ' ...
                     'been measured. Resume from a checkpoint, or start at block 1.'], iBlock);
            end
            state.orange_v = state.orange_v * state.b0/state.b1;
        end
    end

    hadamard_stim.protocol.report_phase(env, "spontaneous", ...
        struct("block", iBlock, "n_blocks", s.n_blocks));
    env.hw.dmd_show_mask(state.cells.current.illum_mask);
    waveform = hadamard_stim.protocol.spontaneous_waveform(cfg, ...
        state.exposure_waveform_ms, state.orange_v, s.block_frames);
    folder = block_folder(cfg, iBlock);
    spec = hadamard_stim.protocol.acquisition_spec("spontaneous", folder, waveform, ...
        trial=iBlock, camera_exposure_ms=cfg.stimulation.camera_exposure_ms, ...
        streams=hadamard_stim.protocol.acquisition_streams(cfg, "spontaneous"));
    acq = env.hw.acquire(spec);

    if measure
        n_cells = size(state.cells.canonical.cell_coord, 1);
        im = env.hw.movie_mean(acq, cfg.bleaching.frames);
        b = hadamard_stim.yitong.bleaching_signal(im, n_cells, cfg.bleaching.n_pix_cell);
        if iBlock == 1
            state.b0 = b;
        end
        state.b1 = b;
    end

    record.folder = folder;
    record.orange_v = spec.orange_v;
    record.streams = spec.streams;
    record.b0 = empty_to_nan(state.b0);
    record.b1 = empty_to_nan(state.b1);
    record.acquisition = rmfield(acq, intersect(fieldnames(acq), ["waveform" "image"]));

    state.next_block = iBlock + 1;
    records{end+1} = record; %#ok<AGROW>
    if isfield(env, "after_block") && ~isempty(env.after_block)
        env.after_block(state, record);
    end
    if isfield(env, "stop_requested") && ~isempty(env.stop_requested) && env.stop_requested()
        break
    end
end
records = [records{:}];
end

function folder = block_folder(cfg, iBlock)
% His names: <prefix>_behavior_mask5_DC_01, mask the illumination spot
% size, DC when drift corrected.
name = sprintf('%s_behavior_mask%d', cfg.naming.prefix, cfg.segmentation.illum_spot_size);
if cfg.spontaneous.drift_correction
    name = [name '_DC'];
end
folder = string(sprintf('%s_%02i', name, iBlock));
end

function t = utc_now()
t = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end

function v = empty_to_nan(v)
if isempty(v)
    v = NaN;
end
end
