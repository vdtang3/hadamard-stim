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

## 2026-10-14: the full suite exhausted memory

Twice, running all the tests filled the workstation's 60 GB and crashed it.
The cause was `run_trial`: a quoting slip (`['waveform" "image']`, a single
char vector) meant the waveform was never removed from the trial record. A
stimulation waveform is about 50 MB of doubles, and `run_protocol` keeps all
640 records.

What was changed:
- **The quoting is fixed.** Records keep the settings and, new, the SHA-256 of the samples, which the plan's metadata list asked for.
- **The reference z-stack drops its 21 waveforms and plane images** once reconstructed. They lived in the run state and in `run_recipe.mat`.
- **The waveform cache is bounded to four entries.** Orange changes at every retarget, so earlier settings never recur.

`TestController` now checks that nothing the run keeps holds samples or images.
Trial records also gained `status` and `started_utc` (Clarification 3's
"status, timings").

To find the cause safely, each test class ran in its own MATLAB under a
memory-capped systemd scope:

    systemd-run --user --scope -p MemoryMax=12G -p MemorySwapMax=0 matlab -batch ...

Every class except the protocol run peaks at 1 to 4 GB.

## 2026-10-14: Phase 4, the Luminos adapter, off-rig

`+hadamard_stim/+luminos` connects the Phase 3 protocol to Luminos
(`luminos-private` `f5b464d93`) without changing it. No protocol, `+yitong`
or golden file changed. Luminos itself is not changed in this phase: the
device, endpoints, accessor and user config move to Phase 5 with the tab,
because nothing here needs them.

**The contract.** `LuminosRig` implements the same interface as
`SimulatedRig`. The interface gained two lifecycle methods, called by the
controller and never by `+protocol`:
- `begin(cfg)` runs a read-only preflight;
- `release()` is the single idempotent cleanup.

`TestLuminosAdapterActions` runs the z-reference and trials 1–4 through both
backends in the parity world. Each acquisition must have asked for the same
things:
- the same samples on Yitong's ports;
- the same DMD queue bytes and repeats, picture time and edge;
- the same scan stacks, stage moves and camera frame counts.

`TestLuminosBoundary` checks the dependencies:
- `+protocol`, `+yitong` and `+metadata` never call the adapter or name a Firefly device or port;
- `+luminos` uses the port only to probe the blue calibration and to reconstruct scans.

**How each action reaches Luminos.**
- **Stage:** `Get_Current_Position` / `Move_To_Position`, in mm, which were also his motor units. Every move is recorded as `[from to reached]`.
- **DMD:**
  - claimed with `Claim_Pattern_Ownership("hadamard_stim")` on first use;
  - queues load through `Load_Sequence_Queue` with the configured edge and 44 µs;
  - scan stacks load through `pattern_stack` + `Write_Stack('slave')`;
  - `Record_Owned_Pattern` after each load, so Luminos's own acquisition script neither overwrites nor misses a change.
- **DAQ:** each driven waveform row becomes a `wfm_data` record whose wavefile, `sampled_waveform`, plays the protocol's samples as they are and refuses a length mismatch. `total_time` is set to samples / rate.
- **Cameras:** one frame per rising edge of the protocol's trigger row.
  - The Kinetix is `External`, at the protocol's exposure.
  - The Grasshopper is `External` when his Grasshopper line pulses, else `Off`.
  - Every other camera is `Off` with one frame.
- **Acquisition:** `Waveform_Camera_Sync_Acquisition` with the protocol's folder as the tag. The adapter polls `exp_complete`/`round_complete` with a timeout and treats `last_run_aborted` as an error. It then appends `hadamard_stim_acquisition` (no samples) to `output_data.mat`.
- **Bleaching:** reads only frames 501–1000 of the 8000 (`read_frames`), never the 2.3 GB movie.
- **Queue identity:** `metadata.queue_fingerprint` hashes each queue in his `AlpSeqPut` byte layout, in both backends, so real trial records compare directly with the trace golden.

**Decisions.**
- **His port map is Firefly's wiring** (`dragonflySettings.m`). The adapter drives his ports, not Luminos device names.
- **Rows that are zero throughout are not driven.** His `ao1` (piezo) is now Heater Set Out, `line23` is shutter405, and `line27`/`line14` are Whisker Stim. Driving his zeros there would override those devices, for example turning the heater off. This is a standing deviation.
- **The blue calibration is the modulator's own.** Luminos's only modulator calibration is `iscalibrated` + `calibration_curve` ([V; power], from `Calibrate_DAQ_Modulator`) on "Blue LED 488". **None exists today:** nothing sets `iscalibrated`, nothing persists a curve, and Firefly has no power meter. Real runs therefore refuse with instructions, as Clarification 1 intended. There is no Hadamard calibration store.
- **P2 is translated exactly, never guessed.** `blue_threshold` is a required setting in the calibration's power units, with no default. The adapter passes `power·15/blue_threshold` to the unmodified `linearize_blue_voltage`. Because his function normalizes by the maximum, this is exactly "drop points with power ≤ blue_threshold". On his own curve at 15, the result is bit for bit the parity result (tested). The threshold is recorded in the blue calibration identity and as a standing deviation.
- **Geometry is the Luminos per-camera DMD calibration.** Spots are filled in camera space and warped by `setPatterningROI(…, write_when_complete=false)`. The adapter refuses unless the Kinetix has a pair calibration, it is the transform in use, and its reference image has the acquisition size and binning. Without his `saved_mask`, P3 does not arise on the rig.
- **Scan reconstruction** uses the `+yitong` cores on the recorded files, one movie at a time. The pinhole calibration comes from operator-named Luminos calibration acquisitions.
- **The recipe stays the package's.** `hardware_facts` supplies:
  - rig and user;
  - DMD model, serial, size, API and queue support;
  - every camera's id, ROI, binning and compression;
  - stage class and units;
  - the DAQ rate, clock and full port map;
  - the blue modulator;
  - the Luminos commit (`luminos_session_info`).

  It also supplies the scan-calibration hash. `build_recipe` stores all of it under `hardware`.

**Preflight** (`preflight.m`, read only, every failure listed with what to do):
- **Rig:** it is Firefly; Luminos is not acquiring.
- **Devices:** each one is present exactly once; the stage only when z or drift is on.
- **DMD:** queue support; no other owner; a 768×1024 canvas; not inverted.
- **DAQ:** 100 kHz on its own clock, with no external clock override and no foreign ao/do records.
- **Kinetix:** uncompressed, unbinned.
- **Calibrations:** a usable blue calibration and threshold; a valid Kinetix DMD calibration.

The controller's existing hardware gate still requires the four recorded Firefly checks.

**Cleanup** (`LuminosRig.release`): every change is journaled just before it is made, and only journaled changes are undone. The order is:
1. abort the acquisition;
2. restore the cameras;
3. restore DAQ `global_props`/`wfm_data`;
4. reset the queue, blank the DMD, restore `pattern_stack`;
5. **release ownership last.**

Each step is guarded, so one failure does not stop the rest, and the call is idempotent. The stage is not moved back (he never did). `TestLuminosCleanup` injects a failure at each step (claim, stack write, queue load, DAQ install, a camera part way, the acquisition, a Luminos abort, a hang, a stage move, a failing restore step).

**Memory.**
- `/tmp` on the workstation is tmpfs, so files written there are RAM. The fake acquisition writes sparse movie files, and every test removes its folder.
- His pinhole calibration upsamples to ~4096 px along the longest side. At the Kinetix ROI (328 × 448) it briefly needs about 10 GB (his code required 16× the pinhole array free), so the rig PC needs that headroom.
- With a small square test image the upsampling is ~170×, so tests use wide images, as `TestParityReconstruction` does.

**Still needs Firefly** (in addition to the Phase 2 checks):
- whether the current blue calibration can be created, resolved and applied;
- IR still on `ao3`, and no conflicts on the driven ports;
- Kinetix/Grasshopper/Blackfly lifecycle and restore, including `Off` mode on the GenTL cameras;
- the orientation of Luminos frames against his `Sq_camera.bin` (P1);
- the scan stack's hard-coded rising edge against his loader;
- Newport backlash correction against his motor;
- the pinhole calibration's memory on the rig PC.

## 2026-10-14: Phase 5, the Luminos tab

The Luminos **Hadamard Stim** tab is a thin skin over the same controller
the programmatic path uses (Luminos `vdtang3/hadamard-stim`). There is one
execution path:

```text
tab → hadamard_stim_action_js / get_hadamard_stim_state_js / get_hadamard_stim_view_js
    → hadamard_stim.apply_controller_action / controller_view
    → HadamardStimController → +protocol → LuminosRig → Luminos
```

**Luminos side, copied from Adaptive Optopatch's pattern (no dependency on it).**
- A `Hadamard_Stim` device (`src/Devices/User_Devices/Hadamard_Stim`) lazily builds one shared controller on a `LuminosBackend`. Its initializer carries the rig settings (`blue_threshold`, `calibration_folders`, `hardware_validation_file`, `run_root`). It pushes the controller's `getState()` as `hadamard_stim_progress`, and `Allows_UI_Interrupt` admits only `stop_after_current` and `abort`.
- `Rig_Control_App.getHadamardStimController` is the accessor.
- `src/Users/Vincent.json` enables the device and tab on Firefly.
- The tab (`userTabs/HadamardStim/`) polls once a second while visible, adopts pushes, and fetches images and the other views only when they can have changed.

**Why a backend.** The tab needs the controller before there is an
environment: to show the preflight and the calibration status, and to take
the rig settings. `HadamardStimController(backend)` builds its env with
`make_environment` when the operator presses Prepare. `HadamardStimController(env)`
is unchanged, and every existing test uses it.

**Controller additions.**
- **Actions:** `update_config` (only the fields `ui.config_fields` lists, coerced to their `default_config` types; `validate_config` still decides), `set_rig_settings`, `run_preflight` (read only), `prepare_rig`, `acquire_reference_image`, `abort` and `new_session`.
- **State:**
  - lifecycle `ABORTED`;
  - an `Activity` and protocol `Phase`, so the tab can show drift correction, sparse pulse, Hadamard trial or z-reference plane while a run is going;
  - the cleanup report;
  - the last error's identifier.
- **Release before the outcome.** The rig is released before COMPLETED, STOPPED, FAILED or ABORTED is reported. The old `onCleanup` guard stays as a safety net and is a no-op after that.
- **Size:** `getState` stays about 10 KB. Images, masks, waveforms, queues, records and checkpoints are left out; the largest array is the proposal's cell coordinates.

**Abort.**
- **The interface gains `abort()`** (hardware interface, both backends). It only sets a flag, so it is safe inside a JS_Server interrupt. `LuminosRig` acts on it in its acquisition wait: it calls `app.abortAcquisition`, waits for Luminos to finish, then raises `hadamard_stim:Aborted`. Every later operation refuses until the next `begin`.
- **The trial in progress is not recorded.** Resuming repeats it from the last checkpoint, exactly as after a failure. `TestControllerSession` checks that an aborted and resumed run writes the same trial records as an uninterrupted one.
- **Stop-after-trial is unchanged.**

**Protocol changes (observation and display only; no parity output changed):**
- **`report_phase`** is an optional observer, called in `run_trial` and `run_z_reference`. Without `env.phase_changed` it does nothing.
- **`acquire_reference_image`** (spec kind `reference_scan`) formalises the step Yitong did by hand before his script: one Hadamard scan, reconstructed, as the image cells are found on. It uses the drift scan's patterns (over the scan area) at the `cfg.scan` settings and does not move the stage. *Open (rig):* whether his app's Hadamard function used the same pattern area. A provided image (`set_reference_image`) remains possible.
- **`static_image_seg_v5` also returns the skipped candidates.** These are the `n_exclude` candidates with the highest contrast. They are kept as `cells.excluded_coord` for display and the recipe. `x`, `y` and `min_val` are unchanged; the excluded candidates are exactly the last `n_exclude` rows of a run with `threshold + n_exclude` and nothing skipped (tested).

**Preflight is one check per requirement** (id, label, pass/fail/not_needed, message). The adapter's preflight is restructured without changing its `failures`. The backend adds:
- named scan-calibration folders;
- a writable data folder;
- each of the four recorded Firefly checks.

`report.calibration` gives the blue calibration's status (valid/missing/invalid) as a run would resolve it.

**Views** (`controller_view`) are computed in MATLAB, so the tab draws and never calculates:
- **segmentation:** a PNG of the reference and each cell's number, coordinate and spots, in `cell_coord` order (= matrix row); also the excluded candidates and `min_val`. About 340 KB, fetched on demand.
- **pattern:** cell numbers on in matrix code k, or in pattern k of the last trial as played.
- **also:** summary, saved recipe (without per-cell arrays), checkpoint (read through `load_checkpoint`, so it refuses what resume would refuse), diagnostics (read only) and resumable run folders.

**Decisions.**
- **Changing rig settings, or preparing, drops the proposal.** The DMD masks were drawn with the old geometry, so both are allowed only before the cells are approved.
- **Resume uses the checkpoint only.** A calibration that differs from the one the run recorded is handled as described in the next entry.
- **The default run folder** is `<Luminos data folder>/<HHmmss>_<prefix>_hadamard_stim`. The Resume panel lists run folders under the user's dated data folders.

**Tests.**
- **Package:** `TestControllerSession` (10), `TestUiViews` (8), `TestLuminosBackend` (8: tab path versus programmatic path, same acquisitions, samples, DMD contents and stage moves; abort during a hung acquisition), `TestUiBoundary` (3).
- **Luminos:** `TestHadamardStimDevice` (5). The frontend has 10 vitest tests, including a source scan for protocol vocabulary and for any MATLAB call outside the three endpoints.
- **Unchanged:** the Phase 3 and 4 tests.
- **Result:** `run_tests('full')` under the 12 GB cap: 175 passed, 0 failed (peak 4.5 GB, 21 min). Frontend: typecheck clean, 153/153 vitest, and the production bundle builds.

**Still needs Firefly**, now through the tab: the Phase 2 and Phase 4 lists, plus:
- the reference scan's pattern area;
- the tab's Abort during a real acquisition (`app.abortAcquisition` from the wait loop).

## 2026-10-15: resuming on a changed calibration

**Decision (Vincent).** A calibration that changed since a run started is a warning, not a refusal. Hard refusals are kept for cases where the experiment cannot run correctly or safely; a resume on a recalibrated rig can still run.

**Behaviour.**
- `metadata.calibration_comparison` compares the blue and DMD calibration identities in the run's recipe with the prepared ones. The blue identity's `resolved_utc` (when Luminos was asked) is not part of the calibration and is not compared.
- `resumeRun` stops with `hadamard_stim:CalibrationChanged` unless `ContinueWithChangedCalibration=true` (`continue_with_changed_calibration` in `resume_run`'s payload). The message gives both identities and the consequence. Nothing is run or written before the confirmation.
- The consequences, as stated to the operator:
  - **blue:** the resumed trials convert intensity to voltage with the current curve, so the same requested intensity may give a different power than in the trials already recorded;
  - **DMD:** the checkpoint's illumination masks were drawn with the recorded calibration, while stimulation spots (and later drift-correction masks) use the current one.
- Every resume writes `resumes/resume_NNN.json` beside the recipe: the time, the next trial, recorded and current identities, the consequences, and whether the run was continued on changed calibrations by an override. The recipe stays immutable, and trial records are unchanged.
- The tab's Resume panel shows both identities and the consequence. Resume is enabled only after "Continue anyway" is ticked.

**Tests.** `TestControllerSession` adds 3: confirmation and record, a same-calibration resume, and `resolved_utc` ignored. The frontend adds 1: the dialog and the flag sent.
- **Result:** `run_tests('full')` under the 12 GB cap: 178 passed, 0 failed (peak 4.5 GB, 21 min). Frontend: typecheck clean, 154/154 vitest.

## 2026-10-15: Phase 6, session modes and optional streams

**Scope (Vincent).** The primary goal stays connectivity sessions on Firefly. The secondary goal is spontaneous voltage imaging in his block structure. Face video and the wheel encoder are optional companions, never prerequisites. Excitability (steps + ramp), the 16-cell control, the lattice test, the RFP/GFP stack workflow and the pilot modes are out of scope. The paper-to-code audit (scratchpad `audit/`, 2026-10-15) found that the paper's data is two mice × three sessions (behaviour, sparseOpto, sparsePulseHad). Connectivity is what we ported; spontaneous is his `behavior` session.

**Decisions.**
- **Encoder:** raw A/B digital lines, recorded through Luminos's generic buffered digital input (`wfm_data.di`) on the acquisition clock. This is the signal he recorded (`DAQ_data` columns 1–2; on 2025-03-08 they toggle ~97 times in a 0.4 s z-plane, so the encoder was live).
  - The Luminos `Treadmill` device was not used. It decodes on a counter, so it needs A/B on PFI inputs, and on a USB-6343 his port0 lines cannot feed a counter. Its clocked mode keeps every sample in seven double arrays.
  - The lines are a rig setting (`wheel_encoder_lines`, default his `Dev1/port0/line9`/`line10`) and appear nowhere in protocol code. Nothing decodes them yet.
- **Continuous blocks:** Firefly runs on his PC (Vincent). His app queued each block's whole waveform (`queueOutputData`, ~102 kHz) and got every input back from `startForeground`: about 4.5 GB per 6-min block.
  - The package never builds a block's samples. `spontaneous_waveform` describes each row as a constant head, a one-frame (or one Grasshopper-period) unit and a count. Luminos expands each row once into its own DAQ buffer (`luminos.repeated_waveform`).
  - Preflight states the estimated footprint and refuses only above 80% of free memory (Windows `memory`).
  - No chunking.
- **Drift between blocks:** his `square_target_drift_correction_single_v1` is v4 without the neighbourhood smoothing, without the stimulation spots and without the blue reset. It is `yitong.drift_correction(..., smooth=false)` and `protocol.run_drift_correction(..., smooth=false, stim=false)`: one operation for both modes, no second algorithm.
  - The behaviour script (`RunSynchronizedAQMulti_behavior_NPY_GFP_v1.m`, SHA-256 `1088424a…8da2b`) and `single_v1` (`04a14583…a8f8aa`) are cited by source path and hash, **not frozen**: every golden fixture records the frozen manifest's hash, so adding files would make all fixtures stale, and fixtures are not to be regenerated. Freezing them would come with the next deliberate fixture regeneration.
- **Block waveform:** the camera, orange, Grasshopper and IR rows of his `dragonflyMultiPatWaveform_2color_periodicPulse_v2_yq` for the same settings, sample for sample (tested at 2600 and 3001 frames, 1.27 and 1.29 ms). There is no blue row and no DMD trigger.
  - The illumination mask is shown as one static picture (`dmd_show_mask` → Luminos `Write_Static`), as his `current_mask` was.
  - *Unverified:* which waveform function and frame count his behaviour blocks actually used. Their `.set` files are only on the external drives. The default `block_frames` 288000 comes from the analysis repository.
- **Streams do not change the protocol.** With the face camera off, `LuminosRig` drives neither `grashopperTrigger` nor `IRVoltage` and leaves the Grasshopper untriggered. The protocol's samples and hashes are unchanged (tested). With the encoder on, every acquisition records it, scans included, as his DAQ did.
- **Validation follows the mode.**
  - A behaviour stream that is off is a warning, never a deviation. The recipe records the stream as "disabled in the configuration".
  - A run's deviations are only the fields its mode uses.
  - Spontaneous mode does not require `dmd.trigger_edge`.
- **Preflight follows what is enabled.** The face camera and encoder checks say "disabled" when off. The blue LED, blue calibration, DMD queue and the Firefly checks `trigger_edge`/`queue_support`/`slide_queue` are "not needed" for spontaneous sessions, whose hardware gate is `driver` only. The stage is needed only when the mode's z-stack or drift correction needs it.
- **Spontaneous blocks behave like his.**
  - The bleaching update is measured on each block and applied before the next (b0/b1 both from block 1 at block 2, as in his script). It is measured only when it will be applied, so a one-block test can be any length.
  - A z-stack is needed only with drift correction; without it, approving the cells makes the session ready.
  - Checkpoints fall at block boundaries. An interrupted block is not recorded and is acquired again, from its drift correction, on resume.
  - Records go to `blocks/block_NN.json`.
- **Connectivity is unchanged.** The same trials, waveforms, queues, checkpoint fields and trial records. The recipe gains `session_mode`, `streams` and `warnings`; connectivity checkpoints keep exactly their fields.

**Not done (follow-ups).**
- RFP/GFP Hadamard z-stacks: his behaviour script's RFP reference stack and closing GFP stack, and the closing GFP stack at the end of the connectivity script we ported. The reference z-stack here is `run_z_reference` with whatever filter is in place.
- Encoder decoding.
- Chunking, if Firefly shows a block does not fit.

**Tests.**
- **Package:** `TestOptionalStreams` (6: preflight in all 8 mode × stream combinations, an unneeded stage, refused encoder lines, a connectivity run with neither stream and with both, and the face-camera switch leaving the samples unchanged). `TestSpontaneousSession` (10: his waveform rows, blocks with drift and bleaching, without drift, a one-block test, abort and resume at a block boundary, small state and records, a full 288,000-frame block through `LuminosRig` and the fake Luminos, the tab path equal to the programmatic one, validation by mode, and what a mode needs before it runs).
- **Unchanged:** every existing test file, every fixture and the frozen reference.
- **Frontend:** 2 new vitest tests (mode and stream switches; the spontaneous view).
- **Result:** `run_tests('full')` under the 12 GB cap: 194 passed, 0 failed (peak 5.3 GB, 23 min; the full 288,000-frame block included). Frontend: typecheck clean, 156/156 vitest, bundle builds. Luminos: device, interrupt and user-config tests pass; 27 rig and 28 user files validate.

**Firefly validation to add** (start with Connectivity, face camera off, encoder off):
- the encoder's wiring and lines today;
- that the A/B DI capture records the wheel and is aligned with the camera triggers;
- the Grasshopper switched on and off;
- voltage + stimulation + camera + encoder together;
- a 6-min block's stability and RAM on the rig PC;
- stage and drift correction between long blocks.

## 2026-10-16: taking the Hadamard calibration scans from the tab

**Why.** Every scan reconstruction depends on his Hadamard calibration scans (`had_cal`): the reference image, the z-stack and drift correction. Until now the package only accepted their folders. He made them by hand on a uniform (Sharpie) slide before each session, with no script. Preparing the rig needs them, so they must be taken before it.

**His settings** (`2025_03_08/150538_had_cal_1x_arch_1/RCaMPtopatch.set`):
- `dragonflyStaticHadamardWaveform_yq`, one pass of the 64 patterns (64 frames, `RepeatEditField` 1);
- camera exposure 10 ms on an 11 ms waveform period;
- orange 0.1 V, blue 0;
- a centred 512 × 512 camera area, the RCaMP filter;
- three recordings `had_cal_1x_arch_1..3` (and `_gfp_` ones for GFP stacks).

These are the defaults in `cfg.calibration_scan`, which no run counts as a deviation.

**Camera area.** His reconstruction centre-crops the calibration to each scan's size (`ffzpad`), so his 512 × 512 calibration served his 448 × 328 scans. Here the scans are taken at the experiment's own camera area. That reconstructs identically when the areas share a centre, and lets the area be checked: each folder gets a `hadamard_calibration_scan.json` (settings, camera area and binning, DMD, time). The backend's scan-calibration check refuses scans taken at another area or binning, because reconstruction would be wrong.

**How.**
- `protocol.acquire_calibration_scans(cfg, env)`: the full-DMD scan patterns, his waveform at the calibration settings, no stage move, no streams. It restores the global random stream that the pattern generator reseeds.
- The controller action `acquire_calibration_scans` is legal before the cells are approved. It runs on hardware from `backend.calibration_hardware(cfg)`: a `LuminosRig` begun with preflight purpose `"calibration_scan"`, which requires only the DAQ, the DMD and the imaging camera. No stage, blue LED, blue calibration or DMD calibration is needed.
- `backend.record_calibration_scans` writes the records and makes the folders the `calibration_folders` setting. A rig prepared with the old scans is dropped, along with any proposal.
- Abort reaches the acquisition being waited for, and the rig is released however the step ends. An aborted set leaves the previous calibration in place.
- The adapter still runs no protocol step: the controller does.

**Tests.** `TestCalibrationScans` (5): his recordings, the tab path before preparing with no stage, blue or DMD calibration, dropping a prepared rig, refusing another camera area, and abort. The frontend adds 1.

## 2026-10-26: the blue LED is calibrated on the slide, by Luminos

**Problem.** Real connectivity runs read the active Luminos calibration of "Blue LED 488" (decision of 2026-10-13: no Hadamard calibration store). On Firefly that could never exist:
- Luminos's only routine, `Calibrate_DAQ_Modulator`, needs a `Power_Meter` device, and Firefly has none.
- It never set `iscalibrated`, and the curve was not saved across sessions.
- `Modulator_Device.apply_calibration` called a `maxima` that exists nowhere, so setting `iscalibrated` would have made every `level` change error, including Luminos zeroing outputs at exit.

**Yitong's method.** He calibrated the blue LED on the slide, with the camera:
- `RunSynchronizedAQSnap_blueSweep.m` snapped one frame per blue voltage, 0.1 to 5 V in 100 steps.
- `blueLED_linearize_file_gen.m` took each frame's mean minus an LED-off baseline, giving `blueCal.mat`: voltage against camera counts. That is why his threshold of 15 is in camera counts.

**Decision (Vincent, 2026-10-26): his slide method, in Luminos.** Changes in luminos-private:
- `Measure_Modulator_On_Slide(modulator, camera, ...)` sets the raw command at each point (bypassing any calibration), snaps one frame, and turns the source off between points. It subtracts the mean of LED-off frames and records `[command; counts above baseline]` with `calibration_info` (method, units, camera with exposure/area/binning, baseline, time).
  - `Calibrate_Modulator_On_Slide(app, name, camera=...)` is the app-level entry.
- `Modulator_Device.Set_Calibration` records a calibration and saves it with the device's other config data (`AdditionalConfigData`, gitignored `.data`); the constructor loads it back.
- `apply_calibration` interpolates along the rising part of the curve.
- **`iscalibrated` is not changed** by recording a calibration. Turning it on would change what `level` means for everyone using that LED. So the active calibration is the recorded curve.
- `active_blue_calibration` accepts a curve with `calibration_info` (or, as before, with `iscalibrated`). The identity carries the recorded method, units, camera and time. `blue_threshold` is now in camera counts, as his 15 was. It still has no default, because the camera and exposure are not necessarily his.
- The tab's **Calibrate blue LED (slide)** (`calibrate_blue_led`) calls the routine through `LuminosBackend.calibrate_blue_led` on the blue LED and the imaging camera. Nothing is stored in the package. The prepared rig and any proposal are dropped.

**Tests.** Luminos `TestModulatorSlideCalibration` (5): counts above baseline, saved and loaded in the next session, a failed sweep leaving the LED off and the old calibration, calibrated levels, out-of-range refusals. Package `TestCalibrationScans` adds 1: Calibrate blue LED from the tab, read back as the run's calibration.

**Result (calibration scans and blue calibration together).** `run_tests('full')` under the 12 GB cap: 200 passed, 0 failed (peak 5.2 GB). Luminos: 39/39 (device, slide calibration, interrupts, user config, patterning calibration), 27 rig and 28 user files validate; frontend 157/157, typecheck clean, bundle builds.

## Parity issues (behaviour that may be a bug; reproduced, not fixed)

- **P1. Reference-image orientation changed after the experiments.** `hadamard_ref.m` gained a transpose on 2026-02-10, after his 2025 data, alongside a Kinetix MEX change. In the newest snapshot, segmentation would run on the transposed image while drift correction compares untransposed scans with the untransposed `hadamard_ref`. The fixtures follow his 2025-03-08 session, which is the untransposed behaviour he actually ran. In Luminos the reference image, scans and DMD calibration must all share Luminos's camera orientation. **Confirmed 2026-10-13: the port follows the untransposed 2025 behaviour.** The transposed `hadamard_ref.m` stays frozen only as evidence.
- **P2. `linearize_blue_voltage` threshold.** It drops calibration points with intensity ≤ 15 in his raw camera units. That number has no meaning for a Luminos calibration. Since Phase 4 the operator must set `blue_threshold` in the calibration's own units. It is applied exactly (power·15/blue_threshold into the unmodified port) and recorded as a deviation; no translation is invented.
- **P3. Masks redrawn after drift correction skip the `saved_mask` AND** that the initial Auto Square masks receive. Reproduced.
- **P4. Segmentation fails on tied maxima.** It errors if two region maxima tie in value (likely on integer images), and also with fewer than 1000 watershed regions. Reproduced, with the error recorded.
- **P5. Bleaching state.** `b0` is measured only at trial 1. The orange voltage is rescaled only at retarget trials, from the last trial's `b1`.

## Open questions

- Which ALP DLL opens Firefly's DMD, whether it accepts `ALP_PROJ_QUEUE_MODE`, and the board's power-on trigger edge. See the Phase 2 rig checks.
- His starting orange voltage for stimulation trials was not saved. The fixtures use a 1.0 V placeholder; it only scales the orange row.
- Whether `saved_mask` was set during his 2025 sessions is unknown. The drift fixture covers both cases.
