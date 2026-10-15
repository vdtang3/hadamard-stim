function [state, record] = run_trial(cfg, env, state, iTrial)
%RUN_TRIAL One pass of his trial loop: retarget, stimulate, measure bleaching.
%
%   [state, record] = hadamard_stim.protocol.run_trial(cfg, env, state, iTrial)
%
%   Line references are to RunSynchronizedAQMulti_sparse_pulse_hadamard_behavior_v1.m.
record = struct("trial", iTrial, "started_utc", utc_now(), "kind", "", "folder", "", "skipped", false, ...
    "retarget", false, "correction", [], "orange_v", NaN, "blue_v", NaN, ...
    "params", [], "c_idx_all_it", false(0, 0), "picnum", [], "repeats", [], ...
    "b0", NaN, "b1", NaN, "acquisition", []);

% Lines 114-129: every retarget_every trials, and at trial 1.
record.retarget = mod(iTrial, cfg.drift.retarget_every) == 0 || iTrial == 1;
if record.retarget
    if cfg.drift.enabled
        hadamard_stim.protocol.report_phase(env, "drift_correction", struct("trial", iTrial));
        [state, record.correction] = hadamard_stim.protocol.run_drift_correction(cfg, env, state, iTrial);
    end
    if iTrial > 1 && cfg.bleaching.enabled
        if isempty(state.b0) || isempty(state.b1)
            error("hadamard_stim:BleachingUnknown", ...
                ['Trial %d rescales orange by b0/b1, but they have not both ' ...
                 'been measured. Resume from a checkpoint, or start at trial 1.'], iTrial);
        end
        state.orange_v = state.orange_v * state.b0/state.b1;
    end
end

% Line 132: every (n_trial / n_hadamard)th trial is a Hadamard trial.
trialRatio = cfg.trials.n_trial / (cfg.trials.n_trial - cfg.trials.n_sparse);
sparse = mod(iTrial, trialRatio) ~= 0;
if sparse && ~cfg.trials.run_sparse
    hadamard_stim.protocol.report_phase(env, "skipped", struct("trial", iTrial));
    record.kind = "sparse";
    record.skipped = true;
    return
end
if sparse
    hadamard_stim.protocol.report_phase(env, "sparse", struct("trial", iTrial));
    [state, plan] = plan_sparse_trial(cfg, env, state, iTrial);
else
    hadamard_stim.protocol.report_phase(env, "hadamard", struct("trial", iTrial));
    [state, plan] = plan_hadamard_trial(cfg, env, state, iTrial);
end

env.hw.dmd_load_queue(plan.pictures, plan.repeats);
waveform = hadamard_stim.protocol.stimulation_waveform(cfg, env, ...
    state.exposure_waveform_ms, state.orange_v, plan.blue_v, plan.params);
invariants = hadamard_stim.protocol.queue_trigger_invariants(waveform, ...
    cellfun(@(m) size(m, 3), plan.pictures(:)'), plan.repeats, plan.params);
if ~invariants.ok
    error("hadamard_stim:QueueTriggerMismatch", ...
        "Trial %d would not play its DMD queue as Yitong's protocol did:\n  %s", ...
        iTrial, strjoin(invariants.problems, newline + "  "));
end
spec = hadamard_stim.protocol.acquisition_spec("stimulation", plan.folder, waveform, ...
    trial=iTrial, camera_exposure_ms=cfg.stimulation.camera_exposure_ms, ...
    c_idx_all_it=plan.c_idx_all_it, ...
    streams=hadamard_stim.protocol.acquisition_streams(cfg, "stimulation"));
acq = env.hw.acquire(spec);

% Lines 250-259: b0 from trial 1's movie, b1 from every trial's.
if cfg.bleaching.enabled
    n_cells = size(state.cells.canonical.cell_coord, 1);
    im = env.hw.movie_mean(acq, cfg.bleaching.frames);
    b = hadamard_stim.yitong.bleaching_signal(im, n_cells, cfg.bleaching.n_pix_cell);
    if iTrial == 1
        state.b0 = b;
    end
    state.b1 = b;
end

record.kind = plan.kind;
record.folder = plan.folder;
record.orange_v = spec.orange_v;
record.blue_v = plan.blue_v;
record.params = plan.params;
record.c_idx_all_it = plan.c_idx_all_it;
record.picnum = cellfun(@(m) size(m, 3), plan.pictures(:)');
record.repeats = plan.repeats;
record.b0 = empty_to_nan(state.b0);
record.b1 = empty_to_nan(state.b1);
% The samples (~50 MB) are not kept: a run holds 640 records, and the
% settings that regenerate them are in waveform_settings.
record.acquisition = rmfield(acq, intersect(fieldnames(acq), ["waveform" "image"]));
end

function [state, plan] = plan_sparse_trial(cfg, env, state, iTrial)
% Lines 133-191. blue_v is one value, as he ran it: with several, his loop
% loaded a queue per value but acquired only after the last.
s = cfg.sparse;
current = state.cells.current;
state.cnt = state.cnt + 1;
[cIdxAllIt, used, skipped] = hadamard_stim.yitong.sparse_trial_selection( ...
    state.cells.canonical.cell_coord, s.dist_cutoff_px, s.n_pulses, state.picked);
pictures = state.sparse_pictures;
for it = 1:s.n_pulses
    if skipped(it)
        % His "continue" left illumPatAll{it} from the previous trial.
        if isempty(pictures{it})
            error("hadamard_stim:NoPreviousPicture", ...
                ['Trial %d ran out of cells at pulse %d and his script would ' ...
                 'replay the previous trial''s picture, but there is none.'], iTrial, it);
        end
        continue
    end
    spots = hadamard_stim.yitong.spot_select(current.stim_rois, cIdxAllIt(:, it));
    pictures{it} = cat(3, current.illum_mask, env.geometry.rasterize(spots, "hidden"));
end
state.sparse_pictures = pictures;
state.picked(used, state.cnt) = true;

plan.kind = "sparse";
plan.pictures = pictures;
plan.repeats = [s.pulse_frames * ones(1, s.n_pulses - 1), 2 * s.pulse_frames];
plan.blue_v = s.blue_v;
plan.params = [cfg.stimulation.wait_frames s.pulse_frames s.period_frames s.n_pulses];
plan.c_idx_all_it = cIdxAllIt;
plan.folder = trial_folder(cfg, s.blue_v, s.pulse_frames, iTrial);
end

function [state, plan] = plan_hadamard_trial(cfg, env, state, iTrial)
% Lines 194-237.
h = cfg.hadamard;
s = cfg.sparse;
current = state.cells.current;
nCodePerIt = s.n_pulses * s.period_frames / h.frames_per_code;
nCells = size(state.cells.canonical.cell_coord, 1);
cIdxAllIt = false(nCells, nCodePerIt);
pictures = cell(nCodePerIt, 1);
for itHad = 1:nCodePerIt
    cIdx = state.had_mat(:, state.cnt_had + itHad) > 0;
    cIdxAllIt(:, itHad) = cIdx;
    spots = hadamard_stim.yitong.spot_select(current.stim_rois, cIdx);
    pictures{itHad} = cat(3, current.illum_mask, env.geometry.rasterize(spots, "hidden"));
end
state.cnt_had = mod(state.cnt_had + nCodePerIt, cfg.matrix.order);

plan.kind = "hadamard";
plan.pictures = pictures;
plan.repeats = [h.frames_per_code * ones(1, nCodePerIt - 1), 2 * h.frames_per_code];
plan.blue_v = h.blue_v;
plan.params = [cfg.stimulation.wait_frames h.frames_per_code h.frames_per_code nCodePerIt];
plan.c_idx_all_it = cIdxAllIt;
plan.folder = trial_folder(cfg, h.blue_v, h.frames_per_code, iTrial);
end

function folder = trial_folder(cfg, blue_v, frames, iTrial)
prefix = sprintf('%s_SPulseHad%i_DC', cfg.naming.prefix, cfg.matrix.order);
folder = string(sprintf([prefix '_%.0fV_%.1f_%02i'], [blue_v frames iTrial]));
end

function t = utc_now()
t = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end

function v = empty_to_nan(v)
if isempty(v)
    v = NaN;
end
end
