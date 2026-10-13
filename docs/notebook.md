# Engineering notebook

## 2026-10-13: Purpose, architecture and the parity rule

We are porting Yitong Qi's Firefly ("Dragonfly") protocol into Luminos. The
source is `RunSynchronizedAQMulti_sparse_pulse_hadamard_behavior_v1.m` and
its helpers, from `ff_control/Dragonfly_yq_v1_2026_02_09`.

**Parity first.** v1 must reproduce his protocol exactly. That covers the
stimulation matrix, trial and code order, DMD queue, DAQ samples,
rolling-shutter blanking, sparse selection, spot geometry, drift correction,
bleaching compensation and the default trial range. Where his code does
something unusual we reproduce it. Behaviour that looks like a bug but
changes the experiment is recorded under *Parity issues* below, not fixed.
Orthogonal codes, timing redesign and other improvements wait until parity
has been shown on Firefly.

**Architecture.** This package will own the protocol, its state and its
experimental logic, mirroring `software/adaptive-optopatch`:

- **This package:** configuration, matrix, schedule, segmentation, sparse selection, masks, queue plan, waveforms, drift, bleaching, protocol and checkpoint state, metadata and the parity tests.
- **Luminos:** generic hardware and acquisition APIs, one adapter device with a few `*_js` endpoints, and a thin `userTabs/HadamardStim` tab.
- **Not shared:** nothing depends on Adaptive Optopatch. Small helpers are copied rather than imported.

The full plan, including phases and directory layout, lives outside this
repository and is summarised here as decisions are made.

**Decisions taken before Phase 1:**

- **Blue calibration source is fixed.** It is the active Luminos blue calibration, not a configuration choice. Yitong's `blueCal.mat` is test input only. Every rig run records the change of source as a deviation. Until Luminos persists a blue calibration, rig runs refuse to start.
- **Cell geometry is kept twice.** The approved segmentation is held as canonical and never edited. The drift-corrected geometry is held as current. An append-only correction history connects them. Yitong always corrects from the reference ROIs, so current = canonical + latest correction.
- **Records are split by mutability.** An immutable run recipe (config, canonical cells, matrix, reference hashes, both git commits, calibration identities, deviations) is written once. Per-trial records and a mutable resume checkpoint each carry the recipe's hash.
- **Both commits are recorded.** Each run records the hadamard-stim commit and the Luminos commit, including a dirty-tree flag.
- **The frozen reference is test-only and minimal.** See `tests/yitong_reference/README.md`.

## 2026-10-13: Phase 1, frozen reference and golden fixtures

**How the goldens are made.** `tests/golden/generate_yitong_goldens.m`
executes the frozen copy of his code. It never re-implements it.

- **Replaced by mocks and shims:** only hardware, file I/O and interactive prompts. That means the ALP device and sequences (as a call recorder), the DMD and Dragonfly apps, the Z motor, the SpinView mouse automation, the `input()` prompt, and Windows-only `memory`/`ls`.
- **Loaded verbatim:** `load_sequence_multi.m`, inside a mock class folder, so the ALP call order the Luminos MEX must reproduce comes from his method.
- **Run as written:** his protocol script, cell by cell. The one textual substitution is the trial-loop range, recorded in the fixture.
- **Operator steps written out:** he changed the apps by hand between cells. Those steps are listed explicitly in the trace fixture: load the two cell patterns, select the stimulation waveform, 1.25/1.27 ms exposure, starting orange voltage.

The `session_inputs` section is the only one that reads experimental data. It
extracts about 1 MB, read-only, from his 2025-03-08 and 2024-08-23 sessions.
Synthetic inputs (reference image, drift scans, z-stack, movies) come from
deterministic functions in `tests/support/`. Fixtures store a SHA-256 of
each input rather than the input.

**Findings with evidence.** The port must honour these.

1. **The "Hadamard" stimulation matrix is a seeded Bernoulli(0.5) matrix.**
   Every element of `hadamard(320)` is ±1, and the two unseeded `randperm`
   lines only write −1. So `xor(hadMat, rand>.5)` equals
   `rand(320) <= .5` under `rng(0,'twister')`, and the Hadamard structure
   is discarded. The result is deterministic and independent of the
   incoming RNG state. *Fixture: `yitong_matrix`.*
2. **Segmentation reproduces his real session exactly.** On his
   2025-03-08 reference image, `static_image_seg_v5` with threshold 320
   returns his saved, ordered 320 `cell_coord` exactly when the interactive
   "cells to exclude" answer is 5. Cells are in ascending-contrast order,
   which is the order that assigns matrix rows. *Fixture: `yitong_segmentation`.*
3. **Spot geometry.**
   - Pattern 1 (orange illumination) is Auto Square with `SquareSize = 5`: 12-vertex circles of radius 2.5 around each cell.
   - Pattern 2 (blue stimulation) is `reduce_spot_size_sequence(app, 3, 2)` applied to pattern 1. It scales about the vertex mean, which counts the duplicated closing vertex. The stimulation spots therefore have radius 1.636, not 1.5, and sit 0.072 px right of the cell centre.
   - Both reproduce his saved 2024-08-23 camera-space ROIs with zero error. *Fixture: `yitong_masks`.*
4. **His DMD masks cannot be reproduced bit for bit.** The best integer camera offset still leaves 1607 of 7583 pixels different along spot edges in his saved 2024 mask. This is consistent with the `correction_tform` step in `dmd_draw_hidden`, whose transform was never saved. Mask parity is therefore defined at the level of camera-space ROIs. Rasterisation to the DMD goes through the Luminos geometric calibration, which is already a recorded deviation.
5. **DMD orientation.** His ALP API reported `height = 1024`, `width = 768`, and masks are stored 1024×768. They are permuted before `alp_logical_to_btd`, giving 128×768 packed bytes per picture.
6. **Stimulation frame count is 8000.** His 2025-03-08 settings have `camFramesIn = 8000`, with IR 0.5 V and Grasshopper 25 ms. With the 200-frame wait a trial is 8200 frames × 1.27 ms ≈ 10.4 s, matching the script's "~10 s per trial" comment. This replaces the earlier 5000-frame assumption.
7. **DMD trigger counts versus queue length.**
   - A sparse trial sends 961 DMD triggers into a queue of 992 pictures: 29 sequences of 2 pictures × 16, then 1 × 32.
   - A Hadamard trial sends 9601 triggers into 10800 pictures: 7 sequences × 2 × 600, then 2 × 1200.
   - In sparse trials each 160-frame period uses exactly one sequence (32 triggers). The period opens with a trigger that shows the orange pattern for the 144 off-frames. The first pulse frame then triggers only the blue picture, and the remaining 15 frames trigger orange and blue.
   - In Hadamard trials each 600-frame period uses exactly one sequence (1200 triggers), with no opening trigger.
   - Both waveforms end with one extra trigger. The doubled last sequence absorbs it, so the queue never runs dry.
   - The scan waveform (64 patterns × 10, 2.52 ms) is 162 280 samples, the same length as the `DAQ_data` he recorded with that scan.

   *Fixture: `yitong_waveforms`.*
8. **The script cannot start where it is written.** It resumes at
   `iTrial = 5` and depends on workspace variables from an earlier partial
   run (`b0`, the current masks). Parity runs start at trial 1. A resumed
   port run must restore `b0` and the current geometry from its checkpoint.
9. **Drift correction.**
   - XY drift is computed from the reference ROIs every time, so it is not cumulative.
   - Z correction moves the motor relative to its current position.
   - It switches to the Hadamard waveform, doubles the exposure, then restores exposure, folder name and orange. It leaves blue at 0 V, which is harmless because the script sets blue before every trial.
   - Each scan overwrites `function_data.hadamard_ref`, which is harmless because the script keeps its own copy of the reference.
   - `static_Hadamard_patterns` seeds the global RNG (`rng(142857)`) and never restores it, which is harmless in this protocol.

   *Fixture: `yitong_drift`.*
10. **Reconstruction.** `dmd_hadamard_reconstruct` on synthetic movies
    correlates 0.9999 with the true sample. `hadamard_reconstruct`, used for
    the z-stack, divides by the code length (64), not by the number of
    repeats: a uniform scale factor, which the normalised Z correlation
    removes. *Fixture: `yitong_reconstruction`.*
11. **Cosmetic only.** His app's "dmdTrigsOut" counter reads DAQ row 2,
    which is the Grasshopper trigger, so it displayed Grasshopper frames.

## 2026-10-13: Phase 2, the DMD sequence queue in Luminos

Yitong's trials depend on the ALP sequence queue. A sparse trial uploads 30
two-picture sequences, a Hadamard trial 8, and the DAQ's DMD triggers then
play them with no software in the loop. Luminos had no queue, so its ALP MEX
gained one, on Luminos branch `vdtang3/hadamard-stim`:

- **Commands:** `Supports_Sequence_Queue`, `Load_Sequence_Queue`, `Reset_Sequence_Queue`, `Get_Queue_State`.
- **Wrappers:** methods of the same names on `ALP_DMD`.

**Call-for-call parity, with three stated differences.** `Load_Sequence_Queue`
makes the calls his `load_sequence_multi` made, in the same order, with the
same values. That covers slave mode, queue mode, packed top-down binary data,
`ALP_SEQ_REPEAT`, uninterrupted binary mode, 44 µs and `ProjStart` per
sequence. It also covers his quirk of feeding each sequence the timing read
back from the one before. His wrapper ignored return codes, but on the board
his data came from every call succeeded. So any refusal now aborts the whole
load and names the failing call; a refused `SeqTiming`, for example, would
otherwise leave the 30 Hz default.

The three differences pin down state his loader inherited from a board
nothing else had touched:

1. The trigger edge (`ALP_VD_EDGE`) is set explicitly. Luminos's stack path sets rising, while his code never set it, so his edge was the board's power-on default. That default is not known yet, so callers must name the edge.
2. Frame stepping is switched off. That is the power-on state, and Luminos master-mode stacks arm it.
3. Freeing a queue returns the controller to legacy mode. His single-sequence loaders did the same before starting. Between two trials this adds one `ProjControl` before queue mode is set again.

**How parity is tested off-rig.**
- `tools/export_yitong_alp_queue_log.m` writes his calls for one sparse and one Hadamard trial, taken from `yitong_trace`, as text into Luminos `tests/fixtures/alp_queue/`.
- Luminos `tests/alp_host` compiles the real `ALP_DMD.cpp` against a recording fake driver. It requires the log to match his, apart from the differences above. Mutating a structural line of his log makes it fail.
- `TestAlpSequenceQueue` covers the MATLAB side: ownership, bit packing (identical to his `alp_logical_to_btd`), `invert_output`, fingerprints and failure bookkeeping.

**What the queue showed in each frame.** `hadamard_stim.protocol.alp_queue_display`
models slave-mode queue playback. `TestAlpQueueModel` runs his waveform
triggers through his queues and confirms finding 7 frame by frame:

- Each stimulation period is played by its own sequence.
- The queue never runs dry.
- The final extra trigger lands in the doubled last sequence and brings the orange picture up for the remaining 3199 frames.

What the hardware does after a queue runs dry is not modelled, because his
protocol never gets there.

**Which driver ran his DMD is still open.**
- The lab-server ALPTool's `alp4395.dll` (1.0.19.8) is byte-identical to Luminos's first-choice driver.
- But that ALPTool has no queue constants, and his wrapper used `api.PROJ_QUEUE_MODE`. His rig therefore ran a locally updated ALPTool, whose DLL we have not seen.
- His 1024×768 masks are packed as 1024-mirror lines, which only fits an XGA board.

**Rig checks before any biology (Phase 2 gate).** The MEX must first be
rebuilt on the rig PC.
1. With Luminos closed, run `ALP_DMD.Probe_Drivers()`: which driver and version recognises the board, and is it 1024×768?
2. Right after Luminos starts, before any stack is loaded, read `Get_State().trigger_edge` (2008 falling, 2009 rising). This is the edge his loader inherited, and it becomes the protocol's configured edge.
3. Check that `Supports_Sequence_Queue()` returns true.
4. On a slide, load a small queue of distinct patterns, step it with DAQ triggers, and compare the camera and `Get_Queue_State` with `alp_queue_display`. Include running dry.

## 2026-10-13: Phase 3, the protocol port, simulated

The protocol now runs off-rig end to end. A simulated run of all 640 trials
reproduces his trace golden exactly, and nothing is compared with a
tolerance:
- every acquisition, in order: folder, stage position, orange and blue volts, both exposures, waveform parameters;
- the cells each pulse or code stimulates;
- the DMD queue, byte for byte as his `AlpSeqPut` received it;
- the scan patterns and the current masks at every trial;
- every stage move;
- the script's variables at the end.

`TestParityProtocol` is that check (about ten minutes); `run_tests("fast")`
leaves it out.

**Layers, built bottom-up, each tested against the goldens.**
- `+yitong`: one port per file of his, under his names. Each takes its inputs as arguments instead of app fields, and carries its source path and SHA-256, checked against the manifest by `TestPortProvenance`.
  - Cells and masks: segmentation; Auto Square spots and their reduction; spot selection; both rasterisers.
  - Trials: the matrix; sparse selection; the bleaching measure.
  - Signals: both waveforms with their helper classes kept nearly verbatim; blue linearisation.
  - Scans: scan patterns, packing, reconstruction; drift-correction analysis.
- `+protocol`: his script step by step. Comments cite its line numbers. Covers the z-reference, drift correction, `run_trial` and `run_protocol`. State is one struct, so a checkpoint resumes exactly.
- `+metadata`: the recipe, trial records and checkpoint, as clarified before Phase 1. Both git commits and every deviation from his settings are recorded, and resuming against a different recipe is refused.
- `HadamardStimController` and `apply_controller_action`: his order of work as a lifecycle, with one allowlisted write path (Adaptive Optopatch's pattern, copied).
- `+testing`: the simulated rig and his affine geometry.

**Decisions.**
- **DMD masks are kept in the Luminos canvas orientation** (rows are ALP lines). That is exactly the array he passed to `alp_logical_to_btd`, so the same mask feeds Luminos and the parity hashes. His `[1024 x 768]` orientation appears only inside `+yitong`.
- **Hardware is six operations** (`hardware_interface`): motor position and move, DMD stack, DMD queue, acquire, movie mean. Everything about ALP (packing, trigger edge, picture time, ownership) stays behind `dmd_load_queue` and `dmd_load_stack`. Those are implemented by the simulated rig now and by the `+luminos` adapter in Phase 4. A test checks that `+protocol` calls nothing else on the hardware.
- **Geometry is an interface with two kinds of drawing.**
  - `"auto_square"` is how his initial illumination pattern was drawn: the whole DMD, ANDed with `saved_mask`.
  - `"hidden"` is every later pattern: no `saved_mask` (P3).
  - Without a `saved_mask` the two rasterisers give identical masks (tested).
  - His affine registration provides the geometry off-rig; the Luminos calibration will on the rig.
- **Scan reconstruction is a function the environment supplies.** The parity runs replace it with the synthetic scan image, exactly as the golden's shims did. Reconstruction parity is tested on its own, through his file layout and through in-memory movies (Luminos does not write `Sq_camera.bin`).
- **The queue/trigger invariants are checked before every stimulation acquisition**, not only in tests. `queue_trigger_invariants` runs the trial's DMD triggers through the queue model and refuses to acquire if any period would play the wrong sequence or the queue would run dry.
- **The four Firefly checks gate real acquisition, not the port.**
  - `metadata.hardware_gate` requires a passing record of all four: driver, trigger edge, queue support and the slide queue test.
  - The controller refuses to start or resume a run on real hardware without that record, and the recipe stores it.
  - Simulated runs (`context.simulated`) are exempt, so the port does not wait on the rig.
- **Operator steps are configuration.** What he did by hand is now explicit and required to be set: the field-of-view prefix, `n_exclude`, the starting orange voltage and the trigger edge.

**His behaviour kept, now visible in code:**
- After a drift scan he restored the waveform period as camera exposure + 0.02 ms, not as the value typed earlier. Trials after it use that value (`state.exposure_waveform_ms`).
- A sparse trial that runs out of cells replays the previous trial's pictures for the remaining pulses (`TestSparseExhaustion`). His geometry never got there: 206 to 226 of 320 cells per trial.
- The scan patterns reseed the global RNG and leave it.
- Drift corrections always start from the canonical cells, never from the previous correction.
- `b0` comes from trial 1 only; orange is rescaled only at retarget trials.

**Where the port refuses what his script did silently:**
- an approved cell count different from the matrix order (he printed a warning and continued);
- several sparse blue voltages (his loop acquired only the last);
- any ALP refusal (Phase 2);
- a retarget trial with no `b0` (his script assumed it was in the workspace).

`stim_matrix` restores the caller's RNG instead of calling `rng('default')`.
Nothing after it in his protocol used the global stream.

**Not frozen but needed.**
- His reconstruction used the lab `vm` movie class, which is outside the frozen reference. Its operations are written out on plain arrays with the same integer types in `read_vm_movie` and the cores, and parity is shown on byte-identical movies.
- His Windows `ls` and `memory` calls are replaced.
- `libHadamard`'s text-file branch now errors; the 63-code scan never reaches it.

**Not covered by any fixture:** drift correction's best-plane fallback, used when
the fitted vertex lies outside the stack. In all three drift cases, including
a drift beyond the stack, his fit stayed inside it. The branch is ported
verbatim.

## Parity issues (behaviour that may be a bug; reproduced, not fixed)

- **P1. Reference-image orientation changed after the experiments.** `hadamard_ref.m` gained a transpose on 2026-02-10, after his 2025 data, alongside a Kinetix MEX change. In the newest snapshot, segmentation would run on the transposed image while drift correction compares untransposed scans with the untransposed `hadamard_ref`. The fixtures follow his 2025-03-08 session, which is the untransposed behaviour he actually ran. In Luminos the reference image, scans and DMD calibration must all share Luminos's camera orientation. **Confirmed 2026-10-13: the port follows the untransposed 2025 behaviour.** The transposed `hadamard_ref.m` stays frozen only as evidence.
- **P2. `linearize_blue_voltage` threshold.** It drops calibration points with intensity ≤ 15 in his raw camera units. Mapping that threshold onto the Luminos blue calibration must be decided and recorded.
- **P3. Masks redrawn after drift correction skip the `saved_mask` AND** that the initial Auto Square masks receive. Reproduced.
- **P4. Segmentation fails on tied maxima.** It errors if two region maxima tie in value (likely on integer images), and also with fewer than 1000 watershed regions. Reproduced, with the error recorded.
- **P5. Bleaching state.** `b0` is measured only at trial 1. The orange voltage is rescaled only at retarget trials, from the last trial's `b1`.

## Open questions

- Which ALP DLL opens Firefly's DMD, whether it accepts `ALP_PROJ_QUEUE_MODE`, and the board's power-on trigger edge. See the Phase 2 rig checks.
- His starting orange voltage for stimulation trials was not saved. The fixtures use a 1.0 V placeholder; it only scales the orange row.
- Whether `saved_mask` was set during his 2025 sessions is unknown. The drift fixture covers both cases.
