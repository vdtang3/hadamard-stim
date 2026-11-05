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

## 2026-10-26: the Firefly checks as MATLAB calls

The four checks real runs need (hardware_gate) each have a function in `+hadamard_stim/+checks` that runs the check and returns `check_result(name, passed, evidence, details)`. `record_firefly_check(file, result)` writes it into the checks file the rig settings name; it replaces that entry, keeps the others, and records failures too.

- `driver_check()`: `ALP_DMD.Probe_Drivers()` with Luminos closed. Passes when a driver opens the board and recognises a 1024 × 768 DMD.
- `trigger_edge_check(app)`: `Get_State().trigger_edge` right after Luminos starts (2009 rising, 2008 falling). Gives the edge the configuration needs.
- `queue_support_check(app)`: `Supports_Sequence_Queue()`.
- `slide_queue_check(app)`, on a uniform slide.
  - It loads a queue through `LuminosRig.dmd_load_queue`, the protocol's own path: 3 pictures × 2 repeats, then 2 × 3, so capacity 12.
  - It steps the queue with one DAQ trigger per camera frame for 16 frames (his static Hadamard waveform at the calibration-scan settings, blue off).
  - The pictures are nested bands of 1/6 to 5/6 of the DMD, so brightness rises with the picture and no DMD calibration is needed.
  - Each frame is classified against a line fitted to the predicted pictures. The check passes when all 12 frames match `alp_queue_display`, with steps more than 5 × the noise.
  - What the 4 frames after running dry showed is reported, not judged: the model leaves it open (Phase 2).
  - It needs only the DAQ, DMD and camera, and releases the rig however it ends.

These live in `+checks`, not `+luminos`, because they use the protocol's queue model and waveforms, and the adapter runs no protocol code. Tests: `TestFireflyChecks` (7), including a queue one trigger behind failing and recorded checks making the tab's preflight pass.

**Result.** `run_tests('full')` under the 12 GB cap: 207 passed, 0 failed.

## 2026-10-27: readiness — warn and record; block only what cannot run

**Decision (Vincent).** The experimenter may go ahead after being clearly
warned about a scientific or data-quality risk. Hard refusals are kept for
what is impossible, undefined, or a conflict over the hardware. The
resume-on-a-changed-calibration rule of 2026-10-15 is the model, now
general: say what changed and what it means, offer one "Continue anyway",
record it.

**Readiness items.** Every check is a `metadata.readiness_item` (id,
label, status, message, consequence, group, details) with status pass /
info / warning / blocker / disabled / not_needed; `metadata.readiness_report`
gives `can_run` (no blockers), `blockers`, `warnings`, `info`, `checks`.
Warnings never make `can_run` false. `luminos.preflight`,
`LuminosBackend.preflight`, `LuminosRig.begin` and `make_environment`
return or act on this report; `report.ok` is gone.

**What blocks (no override).**
- Luminos on another rig (the port map is Firefly's wiring), or acquiring.
- A device the session needs is missing (an enabled face camera included).
- The DMD: no open board (`mexPointer` 0 or debug mode, new), another
  owner, another canvas size, `invert_output` (blue on everything but the
  cells), no live sequence-queue support for connectivity.
- The DAQ: no `global_props`; another waveform on one of the protocol's
  ports.
- Encoder lines that cannot be recorded; a block that does not fit in memory.
- A compressed camera (the package reads raw frames).
- No usable blue calibration or no `blue_threshold` (below); no
  camera-to-DMD transform, the active transform not the Kinetix's (the
  record would name a transform that was not used), or no calibration
  reference image.
- No Hadamard calibration scans when the session reconstructs; named
  folders that do not exist; an unwritable data folder.
- The configuration's own errors; no approved cells, no z-reference, rig
  not prepared (for Run).

**What warns.**
- The four Firefly checks: never recorded, recorded as failed (the slide
  test's failure says to continue only for diagnostic data), older than
  180 days, recorded under another Luminos commit or on another DMD
  serial, or a configured trigger edge other than the commissioned one.
  What is impossible now is found live instead (board, queue support).
  Another hadamard-stim commit is only a note.
- DAQ on an external clock or with a clock-rate override; another
  waveform on a port the protocol does not drive (it does not play during
  acquisitions).
- Camera binning; a DMD calibration taken at another camera area or
  binning; Hadamard scans taken at another area or binning (the
  reconstruction pads or crops, so it runs, but may be spatially wrong) or
  without a record of their area.
- Blue calibration and Hadamard scans older than 7 days (another day
  within 7 days is a note: "reused").
- Settings that differ from Yitong's (one item for all of them).

**Notes (info).** Streams that are off, the Waveforms tab at another rate
(each acquisition sets the protocol's and restores it), a calibration
reused from an earlier day, a DMD calibration without a recorded time.

The ages are in `firefly_profile().stale_after_days`. *(Superseded
2026-10-28: age is never a warning; the driver and trigger-edge checks
left readiness.)*

**Missing blue calibration stays a blocker.** His blue values (`sparse.blue_v`,
the Hadamard blue) are "linear" 0–5 intensities that `linearize_blue_voltage`
maps through the curve (normalised to its maximum), not volts. Reading them
as raw modulator volts would be a different experiment that only looks
the same: the same number would give another power. Nothing in the code or
data says how to interpret them without a curve, so no command is defined.
A raw-volt mode would need its own setting (e.g. `stimulation.blue_command
= "raw_volts"`), values checked against the modulator's range, a recipe
identity that says "uncalibrated", and its own deviation; it is not built.

**One override.** `startRun(..., AcknowledgedWarnings=ids, OperatorNote=...)`
(`start_run` with `acknowledged_warnings`, `operator_note`) computes a
fresh readiness (preflight with a backend; the recorded checks otherwise),
refuses with `hadamard_stim:HardwareNotReady` on any blocker and with
`hadamard_stim:WarningsNotAcknowledged` unless every warning id is
acknowledged. The recipe gains `start_override` (operator_override,
acknowledged_utc, operator_note, each warning with message, consequence
and details), or `[]` when there were none, so no recipe claims an override
nobody made. Trial records are unchanged. Setup (prepare, reference scan,
z-reference) never asks: warnings are shown, only blockers refuse.

**Resume uses the same machinery.** Its warnings are the rig's now plus a
changed blue or DMD calibration (`calibration_changed_blue` /
`_geometry`); the configuration's deviations were acknowledged at the
start and are not asked again. `ContinueWithChangedCalibration` still
acknowledges the calibration ones, and a changed calibration alone still
stops with `hadamard_stim:CalibrationChanged`. `resumes/resume_NNN.json`
gains `operator_override` and `override`.

**Commissioning records carry provenance.** `check_result` stores
`provenance` (`checks.check_provenance`): hadamard-stim and Luminos
commits, DMD serial, model and API, camera and DAQ. The tab can run
`queue_support` and `slide_queue` again (`run_commissioning_check`); the
driver check (Luminos closed) and the trigger edge (right after Luminos
starts) stay MATLAB calls, and the tab shows the call.

**Calibrations are reusable.** `LuminosBackend.calibration_scan_sets` lists
earlier scan sets under the data folders with whether each fits the camera
now; reusing one is `set_rig_settings` with its folders. The blue
calibration is Luminos's and persists across sessions.

**The tab** (luminos-private `vdtang3/hadamard-stim`): Session, Rig readiness
(one line each for the rig's devices, DMD queue, trigger edge, DMD
geometry, blue calibration and Hadamard scans, with dates; everything
else under a collapsed "Rig / commissioning": commissioning records with
provenance and rerun, calibration actions and earlier scan sets, every
check, the rig settings, and the commissioning checklist), FOV setup
(prepare, reference image, cells, z-reference) and Run (blockers in red
with Run disabled; warnings counted, reviewable, and acknowledged in one
dialog with an optional note). The checklist (`ui.commissioning_checklist`,
25 steps from this notebook's "still needs Firefly" lists) is labelled as
first bring-up, not a daily procedure.

**Screenshots.** `tools/gui_states/export_gui_states.m` drives the real
controller on the fake Firefly into ready / warnings / blocker states and
writes the tab's input; luminos-private `frontend/harness/` renders the
real tab from them (development only, `vite.harness.config.js`).

## 2026-10-28: two DMD checks, an explicit edge, and calibrations that do not expire

**Decisions (Vincent).** (1) The driver probe and the power-on trigger edge
leave readiness. (2) The queue's trigger edge is set by the protocol,
rising, instead of discovered. (3) The tab's DMD commissioning is two
checks: sequence-queue support and queue playback on a slide.
(4) Calibration age informs the experimenter; it does not expire the
calibration. (5) `spontaneous.n_blocks` is run scope.

**The driver probe is installation, not readiness.** `ALP_DMD.Probe_Drivers`
opens the board itself, so it needs Luminos closed and cannot belong to a
tab that exists only while Luminos runs. `checks.driver_check` stays as a
diagnostic, documented in the README (First-time installation; repeat
after a MEX, DLL, driver or board change, or to diagnose a board Luminos
cannot open). Nothing reads its record. Whether Luminos has the board open
is read live (`dmd_board`), which is what can actually stop a run.

**The edge is explicit: rising.** His `load_sequence_multi` never set
`ALP_VD_EDGE`, so his trials used the board's power-on edge, which is why
it was a commissioning check. `ALP_DMD.Load_Sequence_Queue` takes the edge
as a required argument (`"rising"`/`"falling"`) and the MEX sets it, so
the board's startup state no longer matters. Rising was chosen because:
- Luminos's stack path (`Write_Stack`, the scan patterns) already uses it;
- the off-rig model counts each rising edge of `dmdTrigger` as one advance
  (`protocol.queue_trigger_invariants`, `TestAlpQueueModel`), and the
  640-trial parity checks pass on that model;
- each `dmdTrigger` pulse returns to 0 before the next, so every intended
  advance has exactly one rising edge;
- nothing in his code or data requires falling.

`default_config().dmd.trigger_edge = "rising"`; it is no longer required
input nor a tab field (`ui.config_fields`), is recorded with the
configuration in every recipe, and another edge is a deviation. A new
standing deviation says: "DMD queue trigger edge is explicitly set to
rising; Yitong's original loader inherited the board's existing edge."
`checks.trigger_edge_check` stays as a historical diagnostic.
`slide_queue_check` defaults to the protocol's edge (it no longer reads the
board's), so the slide test verifies the edge the runs use.

**The two DMD checks** (`hardware_gate`, `hardware_checks`):
- `queue_support`: history only. The live `Supports_Sequence_Queue` is
  asked at every preflight (`dmd_queue`), and that blocks connectivity when
  false. The record never warns, whatever it says.
- `slide_queue`: the evidence. Never run or failed is a warning. A pass
  stays a pass until it is no longer evidence about this rig: another DMD
  serial, a record on another edge, or Luminos's DMD code changed since
  (warning). A Luminos commit change alone is not a warning:
  `luminos.dmd_code_changed` asks git whether
  `firefly_profile().luminos_dmd_paths` (`src/Devices/Patterning/DMD/ALP`)
  differ between the record's commit and now. Same code, or not
  comparable (no git, unknown commit), is a note; another hadamard-stim
  commit is a note. A spontaneous session needs neither.

`run_commissioning_check` runs these two; the controller reads the rig
again afterwards, so the tab shows the new record.

**Age is information, not validity.** `metadata.calibration_age` words a
time ("Taken today (Oct 28, 2026)", "Taken Oct 19, 2026 (9 days ago)",
"3 weeks ago", "4 months ago", "Date not recorded"). Blue calibration, DMD
geometry and Hadamard scans: taken today passes; any other day, or no
recorded date, is a note ("reused"). `firefly_profile().stale_after_days`
is gone, and with it every age threshold. A calibration warns only for a
reason to distrust it, whatever its age: taken at another camera area or
binning (DMD geometry, scans), scans without a record of their area, or a
calibration changed during a run (resume). It blocks only when nothing
usable exists for an operation that needs it: no blue curve (connectivity),
no Kinetix transform or one that would make the record false, no scans
when drift correction or the z-reference reconstructs.

**Run scope.** `spontaneous.n_blocks` is skipped by `validate_config` like
the trial range; `spontaneous.block_frames` remains a deviation (block
duration, and when drift and bleaching are corrected).

**The tab.** Rig readiness: Rig devices, Rig prepared (with Prepare rig,
moved out of FOV setup), DMD queue (live support and the slide test),
DMD geometry, Blue calibration, Hadamard scans, each with its age.
Collapsed below: DMD commissioning (Sequence queue: Run check; Queue
playback on slide: Run on slide, with provenance), Calibrations (DMD
geometry; Blue LED: Calibrate blue LED; Hadamard scans: Take new scans,
Find earlier scans), a pointer to the README for the driver, rig settings,
all checks, and the checklist. FOV setup is 1 Reference image, 2 Cells,
3 Z reference, then Run. The Configuration panel stays open.

**Checklist** (`ui.commissioning_checklist`) has stages: one-time
installation (outside Luminos), occasional commissioning (in Luminos),
first bring-up on the slide, first biological commissioning (connectivity
with face camera and encoder off, trials 1-4, a deliberate Abort, Resume
repeating the incomplete trial, then the face camera, the encoder, and
spontaneous blocks separately). It and the README say commissioning steps
are not the daily workflow.

## 2026-10-28 (later): who owns what in an acquisition; the orange preview

**Calibration age is text only.** A compatible calibration (blue, DMD
geometry, Hadamard scans) now *passes* whatever its age; "Taken Oct 19,
2026 (9 days ago) — reused" is its message, not an info status. Only a
misfit warns or blocks.

**Audit: the DAQ without the Waveforms tab.** Luminos's `DAQ.global_props`
and `wfm_data` start as `[]`; only the Waveforms tab's frontend
(`getDefaultGlobalProps` filled by `get_wfm_startup_info_js`) or
`load_waveform_from_json` fills them, and `Build_Waveforms` reads
`global_props.total_time` unguarded. `LuminosRig` set only `rate` and
`total_time` and inherited the tab's clock and trigger, and preflight
blocked "open the Waveforms tab once". Adaptive Optopatch also requires an
active waveform. Changes:
- Luminos gains `DAQ.Default_Global_Props` (static
  `DAQ.Waveform_Tab_Defaults`, tested in `TestDaqWaveformDefaults`): the
  tab's own starting values, so nothing fabricates a partial struct.
- `LuminosRig.acquire` starts from it when the tab never ran, and sets
  for every acquisition: rate (`cfg.daq.rate`), `clock_source`
  (`firefly_profile().daq_clock_source`, "Internal Dev1": his DAQ ran on
  its own clock), `daq_master` true (self-triggered), `completion_trigger`
  "None", `total_time`, and clears `external_clock_rate`. All of it is
  journaled and restored, including `external_clock_rate`.
- Preflight no longer blocks on missing settings, and another tab rate,
  clock or clock-rate override is a note (it is set aside and put back).
  A foreign waveform on a protocol port still blocks: Luminos has no DAQ
  ownership, so exclusivity is only the per-acquisition replacement of
  the output list. The always-mounted Waveforms tab re-pushes its
  settings when its contents change; editing it during an acquisition is
  still unsafe (not new).

**Audit: the Kinetix.** `frametrigger_source` other than Off/Standalone
maps to PVCAM `EXT_TRIG_EDGE_RISING` (`Kinetix_Cam.cpp:1104`): one frame
per rising edge, exposure as programmed. Luminos exposes no other trigger,
readout, clear or scan mode, so the package's three settings
(`frametrigger_source` "External", `frames_requested` = rising edges,
`acquisition_exposuretime`) are the whole of the timing it can own; they
are journaled and restored, also after a failure. Inherited from the
Camera tab: ROI, binning and Bit Depth (PVCAM port/speed). An 8-bit
storage mode is now a blocker (`read_frames` reads uint16). (Since
2026-11-02, 8-bit is supported; see that entry.) Not checked:
exposure plus the camera's frame overhead against the trigger period
(`Camera.frameOverhead` is only valid after setup); his 0.02 ms margin is
kept.

**`cfg.camera.rows` was his live area, not a constant.** His
`dragonflyStaticHadamardWaveform_yq` takes `nRows =
df_app.camApp.liveArea(1)`; on 2025-03-08 `RCaMPtopatch.set` has
`ActiveareaDropDown: "328 x 448"` and `experimental_parameters.txt`
"Vertical pixel: 328". So it is the acquisition area's sensor rows, read
from the camera each time, and the blanking is 3.75 µs per row. It is now
`hw.camera_rows()`: `LuminosRig` reads `getROIForAcquisition()` (`[x
width y height]`, unbinned) element 4; `SimulatedRig` gives his 328.
`scan_waveform` requires it (`camera_rows=`) and records it in
`waveform.settings.n_rows`. `cfg.camera.rows` is removed from the
configuration. 328 rows reproduce his scan samples exactly; 200 rows
light each frame 48 samples earlier.

**Field of view is inherited and shown.** `LuminosBackend.imaging_camera`
(getState `imaging_camera`) gives the Kinetix ROI, size, binning and Bit
Depth; the tab shows it under a short "controls / inherited" note at the
top.

**Orange preview.** To choose `stimulation.orange_start_v` on the live
image: `startOrangePreview` (`start_orange_preview`) holds a hardware
session (`holdHardware`), shows `Cells.illum_mask` through
`LuminosRig.dmd_show_mask` (owned, `Write_Static`, journaled) and sets
Luminos's "Red LED 615" modulator `.level` (the Main tab's own on-demand
AO write; volts, Firefly gives it no calibration, 0–4.5 V) to
`orange_start_v` (0 V while unset). Changing `orange_start_v` moves the
LED; a value outside its range ends the preview. Release turns the LED to
0 V first, then blanks the DMD, then releases ownership (Adaptive
Optopatch's order); the level is not restored to what it was, because
Luminos does not track it after a buffered run and a lit LED must not
outlive the preview. `beginHardware` and every setup, calibration,
commissioning, run, resume and new-session path stop it first, as do
Abort and the controller's `delete`. The LED is not a run requirement
(`profile.orange_modulator`, outside `profile.devices`).

## 2026-10-28: first Run on slide on Firefly (R2021b)

Live sequence-queue support passed. Run on slide then hit, in order:

1. **No hardware validation file.** Refused, correctly: the check records
   its result there. The tab now disables both DMD checks while the rig
   settings name no file, and says why next to them.
2. **Full-sensor camera area (3200 rows).** `static_hadamard_waveform`
   blanks 3.75 µs per row (12 ms) inside an 11 ms frame and asked
   `baseWave.extend` for -1.01 ms: an indexing error. Now
   `protocol.max_scan_rows(period, rate)` gives the tallest area a scan
   frame can light (671 rows for the 2.52 ms reference, z-stack and drift
   scans; 2930 for the 11 ms calibration and slide scans, whose lit window
   is floor(11e-3/1e-5)*1e-5 = 10.99 ms in floating point, as in his
   code). `scan_waveform` refuses a taller area with
   `hadamard_stim:CameraAreaTooTall`, naming the limit, and preflight's
   new `camera_area` item blocks for the scans the purpose will run, so
   Run on slide is refused before the DMD or DAQ is touched. His 328 is
   unchanged.
3. **`tests/golden/shims/trace/dir.m` shadowed `dir`** (the repository had
   been added with subfolders), so reading the slide movie failed with
   "Unrecognized field name bytes". The golden generator and the tests
   already restore the path; the leak was the install. `setup_project`
   now removes any subfolder of the repository from the path (with a
   warning), preflight blocks while `tests/golden` or
   `tests/yitong_reference` is on it (`stray_path_folders`), the README
   says to add the root only, and the GUI-state exporter restores the
   path it changes (its Luminos stand-in shadows `luminos_session_info`).
4. **`writelines` is R2022a.** It wrote the check's record, and also the
   run recipe, trial, block and resume records and the calibration-scan
   record, so a real run on R2021b would have failed at its first write.
   All go through `metadata.write_text` (fopen/fprintf UTF-8, onCleanup).
   A test scans the package for writelines and other post-R2021b
   functions. `jsonencode(..., "PrettyPrint", true)` is R2021a, so it
   stays.
5. **"Run progress could not be sent: Cannot access method 'write'".**
   `JS_Server.write` is private and always was, so the tab's progress
   push (and Adaptive Optopatch's) never reached the browser; the tab
   only updated when it asked. Luminos gains a public
   `JS_Server.broadcast(event, data)` (as `notifyDeviceAvailabilityChanged`
   already wrapped `write`), both devices use it, and a failing push is
   now reported once per device.

Still to see on the rig: Run on slide end to end at 328 rows on R2021b
(movie read, classification, record written), and progress arriving in
the tab during a run.

## 2026-10-30: the driver probe on Firefly

With Luminos closed, `hadamard_stim.checks.driver_check()` passed:
`alp4395.dll 1.0.19.8 (4.3); serial 13119, DLP7000 1024x768, recognised true`.
So Firefly's DMD is a DLP7000 (XGA, 1024 x 768, as his packed masks assumed)
on ALP API 4.3, through `alp4395.dll` 1.0.19.8, Luminos's first-choice
driver. Together with the live queue check and Run on slide passing the same
day, this closes the open question of which DLL opens the board and whether
it accepts `ALP_PROJ_QUEUE_MODE`.

It also settles the earlier puzzle (2026-10-28): the lab-server ALPTool's
DLL is this same 1.0.19.8 and has no queue constants, yet his wrapper used
`api.PROJ_QUEUE_MODE`. The constant is part of the 4.3 API, which this DLL
implements; what the old ALPTool lacked was the MATLAB-side definition, so
his "locally updated ALPTool" was most likely an updated wrapper over the
same DLL. That is an inference: his local copy was never seen. Nothing in
the code depends on it: Luminos's MEX takes the constant from its own
`alp.h` (`ALP_PROJ_QUEUE_MODE 2314`).

## 2026-10-30: segmentation on Firefly, and P4

Run on slide, DMD geometry, Prepare rig (after recalibrating) and the
reference image now work on Firefly. **Segment** then failed with "Unable to
perform assignment because the left and right sides have a different number
of elements".

**What the data shows** (`20261030/162655__had_ref`, reconstructed offline
with the `1625xx_had_cal_1x_arch_*` scans and the rig's own reader and
cores): a 472 x 1112 image (the Camera tab's area was 1112 x 472 at x 1104,
y 1384, not his 328 x 448) of a uniform slide, a bright illumination field
with dust and a scratch, and no cells. It was not a zero-cell failure:
41,034 watershed regions, 596 candidates for 320 cells.

**The failure is P4.** `static_image_seg_v5` line 83 (his line 85),
`[ctr_r(j),ctr_c(j)] = ind2sub(size(imRef),find(ismember(imRef(:),ctr_val(j))))`:
the left side is one element, and the right two for j = 366 (value
320.85888671875023 at rows/columns (134, 625) and (327, 652), the second in
an unkept region) and j = 539. The reconstruction is quantised (median step
between distinct values 2.9e-4; 2.6 % of pixels share a value), and the
area has 3.6x his pixels, so a coincidence somewhere in the image is likely.
Not orientation, the ROI's shape or R2021b: the same image fails the same
way here on R2026a.

**Changed (Vincent asked for the fix).** The maximum is found among the
region's own pixels (the first, column-major, if the region holds it
twice). Where his code ran, the value occurred exactly once, inside the
region, so every result he could get is unchanged: his image, the synthetic
image, the fixtures and the 640-trial run all still match. Too few watershed
regions (1000) or candidates (threshold plus n_exclude, and threshold + 99
for min_val) now raise `hadamard_stim:TooFewRegions` / `TooFewCandidates`,
"No cells detected: ...", instead of an indexing error. The algorithm never
returns zero cells: it returns exactly `segmentation.threshold` or refuses.
On today's slide it returns 320 "cells" that are noise and dust, as his would
have; approving them is the operator's call.

**Tests.** `TestParityGeometry`: a kept cell's maximum copied to a far,
non-peak pixel leaves the cells unchanged; the integer image his code failed
on now segments; a blank image and too few candidates say no cells were
detected. `TestController`: Segment on a blank image reports
`TooFewRegions` and leaves the session in CONFIGURING.

## 2026-10-30: a QC of the Hadamard calibration

Asked for (Vincent): something to look at that says whether a calibration
can be trusted, from the data the pipeline uses.

**Where.** The calibration (`scorr`) is built in only one place,
`make_environment` at Prepare rig, from `calibration_folders`. Newly taken
and reused scan sets both arrive there (taking or reusing drops the
prepared rig). Right after `scan_reconstruction`, when the movies came from
folders, `luminos.calibration_qc(m_q, movies, scorr)` computes the QC and
`luminos.write_calibration_qc` saves `hadamard_calibration_qc.png/.json/.mat`
in every folder of the set, skipped when the JSON already names that
`scorr_sha256`. The record of the environment
(`context.hardware.scan_calibration.qc`) lists the PNGs written, or the
error. A failure only warns: the QC is for the operator and must not stop a
rig that can run. Movies passed in memory (tests) write nothing.

**What it shows.** Nothing is reconstructed differently for display:
- widefield, the movies' mean above the offset;
- the calibration movies reconstructed with `scorr` by
  `dmd_hadamard_reconstruct_core` (the reference image's and drift scans'
  path), per recording and averaged, and their ratio to widefield where lit;
- pinhole contrast, the calibration's own first stage (recordings summed,
  repeats averaged, correlated with the 63 codes), max over median per
  pixel;
- the pinhole `scorr` assigns each pixel, exact from `scorr` through the
  codes' pseudo-inverse, zoomed so the lattice is visible.
A first measure, the assigned pinhole's share of `scorr`'s weights, was
dropped: bilinear down-sampling mixes pinholes alike for good and bad
calibrations (0.39 vs 0.35 on synthetic ones), so it said nothing.

**On synthetic recordings** (`TestCalibrationQc`): a seen pattern gives
contrast 312 lit / 88 dark, ratio CV 0.002, recordings r = 1.000; no
pattern gives 3.8 / 3.8, CV 0.29, r = -0.21.

**On today's Firefly set** (`1625xx_had_cal_1x_arch_1..3`, rendered offline
into the scratchpad, not the lab share): the lattice is clean and regular,
all 63 pinholes used, the recordings agree (r = 0.978), nothing saturated
(peak 28,600). But pinhole contrast is only 4.3 where lit against 3.5 in
the dark, and the ratio varies (CV 0.19) in smooth blobs that match the
slide's dark spots, so they are probably the slide rather than the
calibration. Low contrast says most of each pixel's light is not from its
pinhole (a thick or defocused slide, or out-of-focus background). Whether
4.3 is normal for this method is unknown: we have none of his real
calibration movies to compare with. Worth comparing a thinner slide or a
refocused one.

## 2026-11-02: 8-bit or 16-bit Kinetix frames

Asked for (Vincent): run Firefly in 8-bit as well as 16-bit, for a larger
area at the same disk and bandwidth. The mode is inherited from the Camera
tab, like the area, rather than being a package setting.

**What sets the bytes.** Luminos's `Camera.bit_depth` is the storage depth
(8 or 16), read back from the camera after every mode change
(`sync_bit_depth_from_camera`, `Get_Storage_Bit_Depth`). It is what
`Extract_Mov` sizes a recording by. `pixel_bit_depth` is what the sensor
delivers: a 12-bit mode is stored in 16 bits and saturates at 4095.
`bit_mode_id` / `bit_mode_label` name the mode and are only shown, never
parsed. `+luminos/camera_format` turns these into one descriptor: storage
bits, bytes/pixel, class (`uint8`/`uint16`), pixel bits, saturation, mode,
compression and whether it is supported (raw 8 or 16).

**The 16-bit assumptions, and what replaced them.**
- `read_frames`: 2 bytes/pixel, `*uint16`. It now takes `format=` and reads
  in the format's class, never widened. Frame count and offsets come from
  `bytes_per_pixel`.
- Its three callers (`LuminosRig.movie_mean`, used for bleaching;
  `scan_reconstruction`, used for the reference image, z-stack and drift
  scans; `slide_queue_check`) now read through `acquisition_frames(acq)`.
  It uses `acq.imaging.format`, which `LuminosRig.acquire` records with
  every movie. An acquisition without one is 16-bit, because preflight
  refused every other depth until now.
- Preflight `camera_settings`: 16-bit only. It now accepts raw 8/16 and
  says which ("records raw 8-bit frames (uint8): supported. Mode: …").
  Compressed or other depths stay blockers.
- `calibration_qc`: saturation was `intmax("uint16")`. It is now the
  format's (2^pixel_bits − 1).
- The two reconstruction cores' `correct_blank_marker` averages two counts
  in the movie's class. In uint8, two counts above 127 saturate. It now
  sums in uint16 for uint8 movies (same rounding); uint16 is unchanged.
  This is the only change to the parity ports.
- `fake_luminos_acquisition` sized files at 2 bytes/pixel and now uses the
  fake camera's depth.
- Docs and argument comments that said uint16.
- Already format-aware, untouched: `Extract_Mov` (calibration folders)
  returns the recording's own class. `hadamard_pinhole_calibration`'s
  `mov-100` saturates at 0 in uint8 exactly as in uint16, and its sum over
  recordings is double. *(Wrong for the real camera: the 8-bit offset is
  about 20, so this clip erases 8-bit movies. See "The 8-bit offset is 20"
  below.)*
- Not camera data: `read_vm_movie` (his `Sq_camera.bin`, parity tests
  only) and `alp_logical_to_btd`'s `bit_depth` (DMD bit planes).

**Scale.** Every algorithm downstream of reading converts to double and
none uses the 0–65535 range:
- Reconstruction subtracts 100 in double. Each code column sums to zero
  (32 ±1 each), so an offset cancels exactly.
- The calibration normalises each pixel's correlation by its blurred
  maximum before the argmax, so it is gain-invariant.
- Segmentation ranks regions by contrast, so it is scale-invariant.
- Drift: optical flow works on `mat2gray` images, and the z-correlation is
  z-scored.
- Bleaching is the ratio b0/b1, invariant within one mode.

The constants that are in counts are the offset of 100 (both cores, the
calibration and the QC) and `blue_threshold`.

Tested on a synthetic slide (`TestCameraFormat`). *(This test kept the
8-bit offset at 100, which the real Kinetix does not; superseded below.)*
The same counts as uint8
and uint16 give identical calibrations and reconstructions. The same slide
at 1/16 the counts in 8 bits gives a calibration whose reconstruction of a
16-bit scan has r 0.9999 and 0.3 % rms difference from the 16-bit one's.
Two 16-bit calibrations from different noise differ by 0.4 %. The
calibration's pinhole contrast drops from 312 to 172 (quantisation). Which
pinhole is largest at a pixel agrees for only 18 % of lit pixels even
between two 16-bit calibrations (weights spread after the bilinear
resampling), so that is not a usable comparison.

**Rules chosen.**
- *Within a session or run, one mode.* `LuminosRig` keeps the format it
  saw at `begin`. An acquisition after a change raises
  `hadamard_stim:CameraFormatChanged` before anything is driven. Resuming
  a run whose recipe records another mode is a blocker
  (`camera_format_changed`): the checkpoint's b0 is in the recorded
  mode's counts, so b0/b1 would scale orange by the gain ratio. Runs
  recorded before today count as 16-bit, with the mode not compared.
- *Hadamard calibration scans.* The math above says they are in principle
  mode-independent, apart from the offset clip and quantisation, but that
  is shown only on a synthetic slide. So a set from another depth is not
  "compatible" (it is not offered as fitting, and readiness warns, as for
  another area) until the rig comparison shows it. The scan record
  (`hadamard_calibration_scan.json`) records `camera.format`; sets from
  before are 16-bit. The calibration's identity in the recipe
  (`hardware.scan_calibration.format`) and its QC JSON record it.
  Calibration scans of mixed depths are refused
  (`MixedCalibrationFormats`).
- *Blue LED.* The curve is camera counts above the LED-off level, measured
  in whatever mode the camera was in. `linearize_blue_voltage` normalises
  by the maximum, so the curve itself does not depend on the mode a run
  images in. `blue_threshold` is in the calibration's counts, though, and
  the same light gives different counts in different modes (the ratio of
  the modes' gains, to be measured). Luminos's `Measure_Modulator_On_Slide` did not record the
  mode, so Hadamard Stim could not tell. It now records
  `camera_bit_depth`, `camera_pixel_bit_depth`, `camera_bit_mode_id` and
  `_label` (Luminos change). `active_blue_calibration` carries them in the
  identity, and readiness says the mode ("Measured in 16-bit (Dynamic
  Range) counts; blue_threshold 15 is in them"). It warns when the camera
  is now in another mode, because a threshold chosen while looking at
  this mode would be on the wrong scale. Older calibrations say the mode
  is not recorded. Recalibrating in 8-bit also risks saturating the
  frame mean near the top of the sweep (255).

**Metadata.**
- Run recipe: `hardware.imaging_format` and `hardware.cameras(k).format`.
- Each acquisition: `imaging.format`, in `output_data.mat`
  `hadamard_stim_acquisition`.
- Scan set: `camera.format`.
- QC JSON: `camera_format`, plus `storage_class`, `saturation_count` and
  `dark_median_raw` in the summary.
- Blue identity: `recorded.camera_bit_*`.

**Memory and disk.** No existing estimate counted camera bytes.
`block_memory` is the DAQ's rows only: Luminos streams frames to disk
(`FrameStreamRecorder`). New readiness item `imaging_storage` (connectivity
and spontaneous) estimates the session's trial or block movies at the
current area and bytes/pixel, against free space on the data folder's
disk. It is informational (`info` when short), not gating. At his area,
connectivity is 640 × 8000 frames ≈ 1.5 TB at 16-bit and 0.75 TB at 8-bit.
At 472 × 1112, one spontaneous block of 288,000 frames is 302 GB at 16-bit
and 151 GB at 8-bit. A message-building bug was fixed in passing: the
block-memory line appended free GB to a char with `+`.

**Needs the rig.**
- The Kinetix offset in each 8-bit mode. Everything subtracts 100.
  `dark_median_raw` in the QC shows it (needs a dark area or a dark
  frame). If it is below 100, `mov-100` clips signal at 0 in the
  calibration. *(Answered from Yi-Chieh's data: 20. See below.)*
- Whether Luminos's `Get_Storage_Bit_Depth` really reports 8 for the
  Kinetix 8-bit modes, so files are 1 byte/pixel. Compare a recording's
  size with frames × area.
- Calibration scans in 8 vs 16 bit on the same slide: QC, reconstruction
  agreement. Then decide whether to relax the compatibility rule.
- Saturation, background noise and dF/F precision at 8-bit. If the 8-bit
  offset is also 100, only ~155 counts lie above it.
- `blue_threshold` in 8-bit counts, if the LED is recalibrated in 8-bit.
- Luminos UI: whether the Bit Depth control can be changed while the tab
  holds the rig. The rig refuses the next acquisition if it is.

## 2026-11-02: the 8-bit offset is 20, not 100

**What the data show.** A read-only audit of Yi-Chieh Huang's Firefly
Kinetix recordings (`/mnt/cohen-lab/Lab/Labmembers/YiChieh Huang/Firefly/Data/`,
`20260618_8bit_test`, `20260619_8bit_test`, `20261013_LED_test`,
`20261021_Cux2_LOP_CS_009_1st`; nothing written there):
- 8-bit recordings are exactly 1 byte/pixel (all 36 raw ones), so
  `Get_Storage_Bit_Depth` reports 8 as assumed.
- The modes, as Luminos records them: `p1_s0_g1` "8-bit High Full Well
  (Speed Mode)" and `p2_s0_g1` "16-bit Standard (Dynamic Range Mode)".
- 8-bit dark level: median 20 (18–24) with all light off
  (`20260619_8bit_test/213710…`), and 20–22 outside the cranial window in
  vivo. Read noise 0.2–0.6 counts; lit pixels 1.3–2.7 counts, so shot
  noise, not quantisation, dominates.
- A slide pair 3 min apart (8 vs 16 bit, same light): 1 8-bit count ≈ 82
  16-bit counts (signal and noise ratios agree); relative noise the same.
- Nothing saturates: 8-bit maximum 225 on the slide, 200 in vivo.
- His `mov-100` in uint8 zeroes 92 % of the slide's 8-bit samples, 100 %
  at 0.5X, and 44 % in vivo. At slide levels the calibration then fails
  ("Incorrect dimensions for matrix multiplication"); at in-vivo levels it
  runs but its reconstructions are 35 % rms off.
- The 16-bit offset was not measured directly (no 16-bit dark frames);
  our 20261030 calibration scan bottoms out at 124–130, consistent with
  about 100.

**What changed.**
- `firefly_profile.camera_offsets`: the offset per mode, keyed by
  `bit_mode_id` and `bit_mode_label` (both must match), with its source.
  16-bit Standard → 100 (his); 8-bit High Full Well → 20 (measured). A
  16-bit mode not listed, or 16 bits with no mode (old records), takes
  100. An 8-bit mode not listed has none.
- `camera_format` carries `offset`, `offset_source` and `offset_known`. A
  recorded format keeps the offset it recorded; one recorded before
  offsets were is looked up by its mode.
- `hadamard_pinhole_calibration(m_q, movies, offset)`: at 100, any movie
  but uint8 is his arithmetic exactly (uint16 subtraction, clipping at 0).
  uint8 movies, or any other offset, are subtracted in double, without
  clipping. The two reconstruction cores take the offset too (they
  already subtracted in double; it cancels in the Hadamard image but not
  in `hadamard_reconstruct_core`'s widefield `ref`). Called without it,
  every port gives his values, and the golden tests are unchanged.
- `scan_reconstruction(..., offset=)` passes the calibration scans'
  offset to the calibration and both cores; `NaN` (unknown) is refused
  (`UnknownCameraOffset`). `make_environment` takes it from the scans'
  format (`scans_format`), which comes from the scan record, else the
  camera now.
- `calibration_qc(..., offset=)`: widefield, ratio, dark level and the
  contrast stage use it, the contrast stage with the calibration's own
  subtraction rule. The summary records `offset`; the QC panel shows it.
- Preflight `camera_settings`: the pass message names the offset and its
  source; a raw mode with no known offset is a blocker. Calibration scan
  sets taken at another offset do not fit (`scanSetFits`).
- Metadata: the offset is in every recorded format (`imaging.format`,
  `hardware.imaging_format`, `cameras(k).format`, the scan record's
  `camera.format`, the QC JSON's `camera_format`), plus
  `hardware.scan_calibration.offset` (what the calibration subtracted).
- Parity: when the imaging camera or the calibration scans are not his
  case (16-bit at 100), the run's `standing_deviations` add
  `profile.eight_bit_deviation`. 16-bit runs record exactly the list they
  did before.
- Still incompatible: 8- and 16-bit calibration sets (offset 20 vs 100,
  gain about 82×).

**Tests.** `TestCameraFormat`'s 8-bit slide is now the Kinetix's: offset
20 and 1/25 the counts above it, so every 8-bit count is ≤ 100. Calibrated
at 20 in double, its reconstruction of a 16-bit scan differs from the
16-bit calibration's by r 0.99988 and 0.31 % rms (two 16-bit calibrations
from different noise: 0.36 %). Pinhole contrast 120 against 312, as
quantisation would predict, and the lit area 0.290 against 0.287. The same
movies through his uint8 `-100` are 100 % zero and the calibration fails.
New: `sixteenBitMoviesAreHisArithmetic` (offset 100 given or not, clipping
kept), `anEightBitCameraUsesAndRecordsItsModesOffset` (environment, record,
deviation, refusal), preflight blocker `unmeasured_8_bit`. Fake cameras use
the real mode ids and labels (`tests/support/kinetix_mode`).

**Still needs Firefly.**
- A real 8-bit Hadamard calibration on a slide, against a 16-bit one,
  with the QC: then decide whether 8/16 calibration sets can be
  compatible.
- Dark frames in 16-bit Standard, to confirm 100, and in any other mode
  someone wants to use (add it to `camera_offsets`).
- Whether the 8-bit offset drifts (temperature, days); `dark_median_raw`
  in each QC shows it when the slide leaves a dark area.
- `blue_threshold` if the LED is calibrated in 8-bit: about 80× fewer
  counts for the same light.

## 2026-11-02: exporting the orange mask for ordinary Luminos acquisitions

Asked for (Vincent): a fallback while the run pipeline is not usable. After
reference image, segmentation and approval, take the approved cells'
orange illumination and use it from Luminos's own tabs.

- `HadamardStimController.exportOrangeMask(file_stem)`, action
  `export_orange_mask` (payload `file_stem` optional with a backend: then
  `<data folder>/<HHmmss>_<prefix>_orange_mask`). Legal with approved cells
  (CELLS_APPROVED or READY) and nothing in progress; a preview may be on.
- It writes `Cells.illum_mask` itself, the array `startOrangePreview`
  passes to `dmd_show_mask` (Target, Write_Static) and the trials put first
  in every queue. Nothing is regenerated or resampled.
  `metadata.write_orange_mask` saves `mask` and `info` to .mat (-v7) and the
  mask as a 1-bit PNG, one pixel per mirror, same orientation.
  `info.mask_sha256` is the hash the preview and `run_recipe.json`
  (`cells.illum_mask_sha256`) record.
- Provenance (`info`): cells (id, x/y, camera-space spots, excluded,
  threshold, n_exclude, spot size), the reference image and its source,
  the DMD calibration identity (`geometry.identity`), the imaging format at
  Prepare, the camera as the Camera tab has it now (area, bin, mode; read
  only), orange_start_v, canvas size, time.
- No hardware: the rig is not begun, no device method is called beyond
  reading the Camera tab's area. Tested by comparing every device's
  properties before and after, and the device log.
- Luminos: `Preset_pattern/pdHadamard_Stim_Orange_Mask.m`, a DMD-space
  (`pd`) pattern function. The DMD tab lists it as "Hadamard Stim Orange
  Mask", with a Mask file text field. It loads `mask`, refuses another
  canvas size or a file that is not an export, and returns the array; a
  `pd` function goes out through Target and Write_Static, as the preview
  did. Tested: it returns exactly what the preview showed.
- Still for the operator: the orange LED is set in the ordinary tabs (the
  export does not turn it on), and the export is of the cells as approved,
  not as redrawn after drift correction during a run.

## 2026-11-03: a Luminos Snap as the reference image

Asked for (Vincent): HiLo tab → Snap → Hadamard Stim → segmentation →
approve → orange DMD mask → preview / export, as an alternative to the
Hadamard reference scan, which stays as it was.

- **Action** `load_reference_snap` (payload `file`), legal with a backend in
  CONFIGURING / CELLS_PROPOSED; view `reference_snaps` lists the imaging
  camera's Snaps (`<data folder>/Snaps/*_cam-<camera>.mat`, today's and the
  dated folders beside it). The image becomes `ReferenceImage` exactly as
  saved (double of `snap.img`); `ReferenceSource` is kind "snap" with the
  file, the Snap's description (camera, type, ROI, bin, timestamp,
  transforms, HiLo provenance, image sha256) and how it fits.
- **Reading** (`luminos.read_reference_snap`) follows Adaptive Optopatch's
  `read_reference_snapshot` rules for the same files (img, name, ref2d
  required; bin, timestamp optional; ref2d world limits are the ROI in
  unbinned sensor pixels; tform by DMD name). Copied, not shared: the two
  packages do not depend on each other, and Firefly does not have AO on
  its path.
- **Compatibility** (`luminos.check_reference_snap`). Cells are drawn by
  Luminos's `setPatterningROI`, which takes a mask to be in the grid of the
  DMD calibration's reference image (`dmd.refimage`: its ROI origin, size,
  binning). So a Snap must be that grid exactly, from the calibrated
  camera, with a calibration for it in use; its image must be one frame of
  its own ROI (a transposed image fails here); a transform it recorded for
  this DMD must be the calibration in use (otherwise it was taken under
  another calibration). Each is a refusal (`hadamard_stim:IncompatibleSnap`)
  naming what differs. Nothing is resampled, shifted or flipped to fit: the
  scan path's `active_geometry` only warns about a camera-area mismatch,
  but a Snap chosen by hand is cheap to retake at the right area.
  A Snap with no transform for this DMD is accepted and says so.
- **No preparation, no hardware.** Segmenting needs only the geometry;
  before the rig is prepared the backend reads it (`geometry()`:
  `active_geometry` on the resolved devices, nothing begun; drawing
  projects nothing). So loading, segmenting, approving and exporting need
  neither the Hadamard calibration scans nor the blue calibration, and
  touch no device (tested against every device property and the device
  log). With a prepared rig, segmentation uses `Env.geometry` as before.
  The geometry identity used is kept with the proposal and the cells
  (`ProposalGeometry`, `CellsGeometry`) and is what the mask export
  records, prepared or not.
- **Limits, on purpose.** The orange preview is a hardware session and
  still needs Prepare rig (so the scans, for a configuration that
  reconstructs them); making it work unprepared would mean a new preflight
  purpose and a second rig path. Drift correction registers each Hadamard
  scan to the reference image, so a drift-correcting run with a Snap
  reference is blocked (readiness `reference_kind`, and `start_run`); a
  spontaneous session without drift correction may run. The run recipe
  records the reference image's hash, not its source.
- **HiLo on Firefly.** HiLo is on Luminos's `vdtang3/blanket-depolarization`
  branch (the VU), not on Firefly's `vdtang3/hadamard-stim`. Any Camera
  Snap loads the same way; a HiLo Snap on Firefly needs that branch merged.
- **Tests** (`TestReferenceSnap`). The acceptance test: the same image as a
  scan reference on a prepared rig and as a Snap on an unprepared one give
  identical cells, spots and masks, the same geometry identity, and an
  export the DMD tab's `pdHadamard_Stim_Orange_Mask` reads back as that
  mask; the preview shows it. Also: no Hadamard calibration and no
  commissioning needed, no device touched; the image used exactly; every
  refusal (camera, transposed, ROI origin, binning, area, transform, NaN,
  not a .mat, no snap, missing) changes nothing; the drift blocker; the
  listing. A real Firefly Snap (`20261030/Snaps/161218_cam-TeledyneKinetix`,
  full sensor) is read as written and refused against the 448 x 328
  calibration, accepted when the calibration is at its area with its
  transform. Off the suite: a HiLo Snap written by the HiLo branch's own
  `create_hilo_snap` (CL_RefImage with provenance) loaded, segmented (320
  cells), approved and exported on the fake Firefly, unprepared. No real
  HiLo Snap exists yet (20261020's HiLo run failed before its Snap).

## 2026-11-04: many cells; targeting without Prepare; commissioning out of readiness

Asked for (Vincent), for animal experiments the next day: segmentation for
far more than his 320 cells, Snap -> Segment -> Approve -> Preview/Export
without preparing the rig, and a routine readiness without one-time
commissioning.

**What limited the cell count was segmentation's pool, not 320.**
`static_image_seg_v5` keeps `thres` cells (320), but its candidates are the
top `nROILim = 1000` watershed regions by peak-minus-local-median contrast
(strictly above the 1000th, so at most 999) that are larger than 10 px. It
needed `thres + max(n_exclude, 99)` candidates (the 99 for the min_val
curve) or refused. There is no intensity threshold anywhere: candidates are
a ranking, so the meaningful sensitivity setting is the size of that pool.
The filter is `fspecial('gaussian', 7, 7)` cut to its central disk and made
zero-mean (gSiz = gSig = 7).

**Changed.** His constants are options with his values as defaults
(`segmentation.candidate_pool` 1000, `min_area_px` 10, `filter_size_px` 7,
`select_all` false); the parity tests (his image, the synthetic image,
min_val) are unchanged. Fewer candidates than `thres` keeps them all, and
`info` reports regions, ranked, candidates, available, requested and
selected; min_val is NaN where it would need candidates that do not exist.
Fewer regions than the pool ranks them all. A candidate must have positive
contrast: where his code ran the pool's cutoff was positive, so nothing of
his changes, and a featureless image still says "No cells detected" instead
of returning its 4 border regions. His per-candidate pass over the image to
build the label matrix is now a lookup (same labels): it would be
O(candidates x pixels), too slow for large pools. On his reference:
983 candidates at 1000, 1755 at 2000, 2806 at 4000; a 3200 x 3200 Snap
takes 26 s.

**Modalities.** Both rankings are differences of intensities on a zero-mean
filter: a gain changes no cell; an offset changes only regions within the
filter's width of the border (3 of 640 for +500), through the filter's zero
padding. So Hadamard, HiLo and camera Snaps share one pipeline and his
defaults; no normalisation was added. What does change the cells is noise:
his image at a quarter of the contrast with added noise keeps 145 of 320
cells within 3 px. A noisy reference is better improved at acquisition
(more scan repeats, or averaging) than by a preprocessing step; an optional
denoise was not added without evidence.

**The run's limit is the matrix.** `stim_matrix(order)` starts from
MATLAB's `hadamard(order)`, which exists only when order, order/12 or
order/20 is a power of 2 (320 = 20 x 16), and `new_run_state` needs one
row per approved cell. Nothing else in the trial loop depends on N: a
sparse or Hadamard trial is 30 or 8 DMD pictures whatever the count, masks
are canvas-sized, and `picked` and `had_mat` are N x 640 and N x N. So
`validate_config` now checks the order (`is_hadamard_order`) and the
`segmentation.threshold == matrix.order` error is gone: the controller's
readiness compares the approved cells with `matrix.order` instead
(`cells_matrix`, a blocker for a connectivity run only), so segmenting and
exporting any count are not "invalid configurations". Another order also
changes how often the matrix is covered: his 160 Hadamard trials of 8
codes cover 320 rows exactly 4 times; other orders get a note when the
last pass is partial (1024: 1.25 passes). A larger N is a protocol change
(recorded as deviations), not made here.

**Prepare is not destructive.** It cleared proposed cells and returned to
CONFIGURING, and was legal only before approval. Now it is legal in any
setup state and discards only what the new environment invalidates: cells
drawn with another DMD calibration (`geometry.identity` differs), and a
z-reference reconstructed with other Hadamard calibration scans
(`scorr_sha256`); `SetupNotice` says what went and why. Rig settings, new
calibration scans and a blue calibration no longer discard a proposal
(none of them moves the DMD calibration).

**Targeting without Prepare.** The orange preview with a backend now
always claims only what it uses (`LuminosBackend.orange_preview_hardware`:
a LuminosRig begun with preflight purpose `orange_preview`, which checks
the DMD board, ownership, canvas and polarity and its calibration, and
nothing a run needs), so an unrelated run blocker cannot refuse it; it is
released on stop, abort (now legal while previewing) and error. It refuses
(`GeometryChanged`) when the active DMD calibration is not the one the
cells were drawn with, so the preview shows the exported mask in the same
place. `getState().stages` gives reference / targeting / acquisition
readiness.

**Changing segmentation settings discards cells explicitly.** Proposed and
approved cells and their masks were drawn with the old settings; keeping
them under new settings would be silently wrong, and keeping the old
settings visible while showing new numbers would be confusing. The
reference image and any z-reference are kept (approving again returns to
READY). The tab asks before sending a change that discards cells.

**Commissioning left readiness.** The slide queue record was the last
one-time check that warned (never run, failed, or stale): every run
without it had to acknowledge it. It is now a note with the same text
(history, kept in every recipe), as queue support already was; the checks
and their tab actions remain. Remaining routine checks are current
conditions: camera mode and depth, calibrations that fit, live DMD board,
queue support and ownership, DAQ conflicts, area, data folder. Tests that
used the slide warning to exercise the override now use a settings
deviation.

## 2026-11-04: the imaging camera is a setting (Firefly's Tucsen Libra)

Firefly is trying a Tucsen Libra 5514 Pro in place of the Kinetix. The goal
for now is targeting only: Libra Snap -> segment -> approve -> orange mask.
`firefly_profile(camera_name)` and `LuminosBackend(camera_name=...)` (from the
Luminos device's `camera_name`) make the imaging camera a setting; the
default stays the Kinetix, so nothing changes without it. Everything already
keyed by the profile camera follows: Snap listing (`*_cam-Libra5514Pro.mat`),
the Snap check, the active DMD calibration and the recipe's text.

Dark offsets: his 100 for an unlisted 16-bit mode is his Kinetix's black
level. It now applies to the Kinetix only (`unlisted_16bit_offset_camera`);
another camera's unlisted modes have no offset, so preflight refuses its
scans until its dark frames are measured and added to `camera_offsets`.
Snaps and segmentation never use the offset.

Pixel sizes: segmentation (`filter_size_px` 7, `min_area_px` 10) and the spot
sizes (orange 5, blue 3) are in reference-image pixels, chosen at his Kinetix
sampling. Nothing is rescaled automatically: the Libra's sample-plane scale is
not known until it is measured on the rig. Snaps now report the camera's
stage calibration (`pixel_to_sample_um`, `um_per_px`), shown in the tab, so
sizes can be set from a measured scale. A synthetic check at 2048 x 2048
(2,500 blobs, pool 4,000) selected 2,000 cells in about 10 s at either filter
size, so the segmenter has no frame-size limit. Scaling the image by a gain
leaves the selection unchanged. Adding an offset swapped 4-6 of 1,500 cells,
and none of them were within 15 px of the border, so the 2026-11-04 entry's
"except near the border" is not the whole story. Minor; not investigated.

Not ported: the native Hadamard reference scan. Its blanking is the
Kinetix's rolling shutter (3.75 us/row in `max_scan_rows`, `scan_waveform`,
`static_hadamard_waveform`, preflight), which is the wrong model for a global
shutter; the Libra's dark offsets and its timing at 1.25/1.27 ms are
unmeasured. With `camera_name` set to the Libra, preflight blocks scans on
the missing offset, so nothing runs on the Kinetix's timing by accident.

## Parity issues (behaviour that may be a bug; reproduced, not fixed)

- **P1. Reference-image orientation changed after the experiments.** `hadamard_ref.m` gained a transpose on 2026-02-10, after his 2025 data, alongside a Kinetix MEX change. In the newest snapshot, segmentation would run on the transposed image while drift correction compares untransposed scans with the untransposed `hadamard_ref`. The fixtures follow his 2025-03-08 session, which is the untransposed behaviour he actually ran. In Luminos the reference image, scans and DMD calibration must all share Luminos's camera orientation. **Confirmed 2026-10-13: the port follows the untransposed 2025 behaviour.** The transposed `hadamard_ref.m` stays frozen only as evidence.
- **P2. `linearize_blue_voltage` threshold.** It drops calibration points with intensity ≤ 15 in his raw camera units. That number has no meaning for a Luminos calibration. Since Phase 4 the operator must set `blue_threshold` in the calibration's own units. It is applied exactly (power·15/blue_threshold into the unmodified port) and recorded as a deviation; no translation is invented.
- **P3. Masks redrawn after drift correction skip the `saved_mask` AND** that the initial Auto Square masks receive. Reproduced.
- **P4. Segmentation fails on tied maxima.** His code looked up each kept region's maximum value in the whole image, so it errored whenever that value also occurred at any other pixel (not only another region's maximum), and with fewer than 1000 watershed regions. Reproduced, with the error recorded. **Changed 2026-10-30** after it stopped segmentation on Firefly: the maximum is looked up within the region, which changes nothing his code could return; too few regions or candidates refuse with "No cells detected" errors.
- **P5. Bleaching state.** `b0` is measured only at trial 1. The orange voltage is rescaled only at retarget trials, from the last trial's `b1`.

## Open questions

- His starting orange voltage for stimulation trials was not saved. The fixtures use a 1.0 V placeholder; it only scales the orange row.
- Whether `saved_mask` was set during his 2025 sessions is unknown. The drift fixture covers both cases.
