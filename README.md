# hadamard-stim

MATLAB package that will run Yitong Qi's Firefly Hadamard protocol inside
Luminos. The protocol combines sparse-pulse and Hadamard-coded patterned
optogenetic stimulation with Hadamard structured-illumination scans, drift
correction and bleaching compensation. A second, simpler session mode
records spontaneous activity in blocks, with no blue light, as his
behaviour sessions did. Face video and the wheel encoder are optional
companions of either mode.

**v1 goal: behavioural parity with Yitong's code.** Each trial must load the
same DMD sequence queue, drive the same DAQ samples and select the same cells
as his `Dragonfly_yq_v1_2026_02_09` package. Behaviour that looks unusual is
reproduced and documented as a parity issue, not corrected. Improvements
(orthogonal codes, timing changes) come only after parity has been shown on
the rig.

The package will own the protocol logic. Luminos will only provide hardware
access, through a narrow adapter and a thin tab. The layout follows
`software/adaptive-optopatch`.

## Status

Phases 1 to 6 are complete off-rig.
- Yitong's reference code is frozen, and golden fixtures are generated from it.
- Luminos's ALP MEX has a sequence queue that matches his loader call for call.
- The whole protocol runs on a simulated rig and reproduces his 640-trial trace exactly.
- The Luminos adapter (`+luminos`) asks Luminos for the same actions as the
  simulated rig, checks the rig before touching it and restores it afterwards.
- The Luminos **Hadamard Stim** tab drives the same controller (Phase 5):
  preflight, prepare, reference scan, segmentation, z-reference, run, stop,
  abort and resume, with the recipe, deviations and rig diagnostics on view.
- Session modes (Phase 6): **Connectivity** (the parity-tested protocol,
  unchanged) and **Spontaneous** (orange-only voltage imaging in blocks,
  optional drift correction between them). Face camera and wheel encoder are
  switches: when off, nothing about them is required, driven or triggered,
  and the recipe records that they were off.

Readiness: every check is a pass, note, warning or blocker. Only what is
impossible, undefined or a conflict over the hardware blocks, and that is
read live from the rig. Scientific risks (a calibration that does not fit
the current settings, queue playback not verified on a slide, settings
that differ from Yitong's) are warnings that a run acknowledges once, all
together, and the recipe records. Calibration age is shown, never judged
(docs/notebook.md, 2026-10-27 and 2026-10-28).

Before real data can be trusted, Firefly still needs the commissioning in
[Using Hadamard Stim on Firefly](#using-hadamard-stim-on-firefly): the
driver probe once, queue playback on a slide, and a blue LED calibration
with a `blue_threshold` in its camera counts. Without a blue calibration a
connectivity run is refused: no blue command is defined.

Next is validation on Firefly, carried out through the tab, starting with a
connectivity session with the face camera and wheel encoder off.

## Layout

```text
+hadamard_stim/            the package
  default_config.m         the experiment, as he ran it
  validate_config.m        errors, and deviations from his settings
  HadamardStimController.m one session: setup, then a run
  apply_controller_action.m  the only write path for a frontend
  controller_view.m        the read-only display products a frontend may ask for
  backend_interface.m      what a controller asks a rig before it has an env
  +yitong/                 ports of his functions (source path + SHA-256 in each)
  +protocol/               his scripts, step by step, on a hardware interface
                           (run_protocol: connectivity; run_spontaneous: blocks)
  +waveform/               reading a waveform in either form (dense samples,
                           or a repeated description for long blocks)
  +metadata/               run recipe, trial and block records, checkpoints,
                           readiness items and reports
  +checks/                 the two DMD commissioning checks (recorded), and the
                           driver probe and power-on edge diagnostics
  +ui/                     display products: config fields, numbered cells,
                           patterns, summaries (read only, no hardware)
  +luminos/                the only code that touches Luminos (LuminosRig,
                           LuminosBackend, preflight, diagnostics,
                           calibrations, Firefly facts)
  +testing/                simulated rig, his affine geometry, fake Luminos
setup_project.m            adds the repository root to the path
run_tests.m                off-rig tests
config/paths.example.m     machine paths, used only by the fixture generator
tools/freeze_yitong_reference.sh
tools/gui_states/export_gui_states.m  the tab's input in ready / warnings / blocker
                           states, for luminos-private's frontend harness
tools/export_yitong_alp_queue_log.m   his queue-loader calls, for Luminos's ALP tests
tests/
  yitong_reference/        frozen, minimal copy of Yitong's code (test-only)
  fixtures/                golden fixtures generated from that code
  golden/                  the generator, its mocks and shims
  support/                 deterministic synthetic inputs shared with tests
docs/notebook.md           engineering notebook: decisions, findings, parity issues
```

## Using Hadamard Stim on Firefly

Commissioning steps are not the normal daily experimental workflow. A
normal session is the [Each FOV](#each-fov) list below; everything before
it is done once, or occasionally when the rig changes.

### First-time installation

1. Put this repository on the MATLAB path in the rig's `startup.m`.
2. Use a Luminos build with the ALP sequence queue (branch
   `vdtang3/hadamard-stim`, `ALP_DMD.Load_Sequence_Queue`) and its
   `DMD_MEX` built on the rig PC.
3. Add the device and tab to your user file for Firefly (Luminos
   `src/Users/Vincent.json` does):

   ```json
   "rigs": { "Firefly": {
     "devices": [{ "deviceType": "Hadamard_Stim", "name": "Hadamard Stim",
                   "hardware_validation_file": "...firefly_checks.json" }],
     "tabs": ["HadamardStim"] } }
   ```

   `blue_threshold` and `calibration_folders` can be set there or in the
   tab's rig settings. `blue_threshold` has no default: it is a power in
   the active blue calibration's own units (parity issue P2), not his 15.
4. **Probe the ALP driver, with Luminos closed.** The probe opens the board
   itself, which it cannot do while Luminos holds it, so this is not in the
   tab:
   1. Close Luminos.
   2. Start MATLAB with the Luminos paths (the ALP class and `DMD_MEX`) and
      this package on the path.
   3. Run `r = hadamard_stim.checks.driver_check()` (or the underlying
      `ALP_DMD.Probe_Drivers()`).
   4. Check that a driver opens the Firefly ALP board, recognises the XGA
      1024 x 768 DMD, and reports its DLL, version and serial
      (`r.passed`, `r.evidence`).

   Repeat it only after rebuilding the ALP MEX, changing the ALP DLLs or
   driver installation, replacing the DMD or its controller, or to
   diagnose a DMD that Luminos can no longer open. It is not a per-session
   or per-experiment calibration, and no run depends on a record of it:
   whether Luminos has the board open is checked live every time.

### Occasional rig checks and calibrations

All in the tab, under **Rig readiness → Rig / commissioning**, except the
DMD geometry. Calibrations do not expire automatically. The tab displays
when each was acquired and whether it is compatible with the current
configuration. Recalibrate when the optical/hardware configuration changes
or when the experimenter has reason to distrust the calibration.

| | What it measures | Required to run? | Sensible to repeat |
|---|---|---|---|
| **Sequence queue** (Run check) | whether the live ALP driver supports the sequence queue | connectivity: the live answer is; it is asked at every Check readiness anyway | after driver changes |
| **Queue playback on slide** (Run on slide; uniform slide in place) | a small queue, loaded on the protocol's rising edge and stepped by DAQ triggers, imaged and compared picture by picture with the queue model | no: never run, failed, or run before a change to the DMD, its serial or Luminos's DMD code is a warning | after DMD, driver or Luminos DMD-code changes |
| **DMD geometry** (Luminos DMD tab) | the camera-to-DMD transform for the Teledyne Kinetix | yes: none for the Kinetix blocks; taken at another camera area is a warning | when the camera area, binning or light path changes |
| **Hadamard calibration scans** (Take new scans, or Find earlier scans → Reuse) | his `had_cal` pinhole scans on a uniform slide, which every reconstruction uses | when drift correction or the z-reference is on; taken at another camera area or binning is a warning | when the camera area, binning or illumination changes |
| **Blue LED calibration** (Calibrate blue LED; slide in place) | Luminos's slide calibration of the blue LED against the imaging camera | connectivity: yes (blocker without one) | when the LED, light path or camera settings change |

### What Hadamard Stim controls, and what it inherits

You do not need to build or activate an acquisition in the Waveforms tab
before using Hadamard Stim.

Choose the imaging ROI/FOV using the normal Kinetix/Camera controls before
preparing the FOV.

| Setting | Owner |
|---|---|
| Kinetix ROI / FOV | Current Luminos Camera state (the Camera tab), shown at the top of the tab |
| Kinetix binning | Camera tab (1 × 1 expected; other binning is a warning) |
| Kinetix Bit Depth (readout port/speed) | Camera tab; must be a 16-bit mode (another is a blocker: frames are read as 16-bit) |
| Kinetix frame trigger | Hadamard Stim: External, one frame per rising edge of `cameraTrigger` (set per acquisition, restored after) |
| Camera exposure | Hadamard Stim configuration (set per acquisition, restored after) |
| Number of frames | Hadamard Stim: the number of camera-trigger rising edges in the waveform |
| Frame period | Hadamard Stim DAQ waveform |
| Kinetix trigger/readout mode | Hadamard Stim, through the frame trigger: Luminos maps External to PVCAM's rising-edge trigger mode; Luminos exposes no other trigger, readout or scan mode |
| Scan rolling-shutter blanking | Hadamard Stim, from the ROI's rows (his `liveArea(1)`; 328 rows for his area) |
| DAQ sample rate, clock, start trigger | Hadamard Stim: 100 kHz on the DAQ's own clock, self-triggered (set per acquisition, restored after) |
| DAQ waveforms (AO, DO, encoder DI) | Hadamard Stim |
| DMD queue patterns/timing | Hadamard Stim (rising edge, 44 µs) |
| DMD geometry | Active Luminos calibration |
| Blue calibration | Active Luminos calibration |
| Hadamard reconstruction calibration | selected Hadamard scan folders |
| Starting orange voltage | Hadamard Stim configuration (chosen with the orange preview) |
| Face camera / wheel encoder | Hadamard configuration + rig hardware |

Every acquisition journals the camera and DAQ settings it changes and puts
them back afterwards, also when it fails or is aborted. With the Waveforms
tab never opened, it starts from Luminos's own defaults
(`DAQ.Default_Global_Props`, the tab's starting values) and leaves the DAQ
as it found it. What the Waveforms tab holds is only noted, except a
waveform on one of the protocol's own ports, which blocks: two waveforms
cannot drive one output.

### Each FOV

1. **Check readiness** (reads the rig, changes nothing) and **Prepare rig**
   if it is not prepared (once per session; both in Rig readiness).
2. **Acquire reference image** (one Hadamard scan, reconstructed).
3. **Segment**, inspect the cells on the image, then **Approve cells**.
4. **Preview orange illumination** (under Cells) to choose the starting
   orange voltage: the approved cells' orange mask is held on the DMD and
   the orange LED (Red LED 615) at Starting orange voltage while you watch
   Luminos's live image. Change Starting orange voltage in Configuration
   until the field is bright but not saturated; the LED follows. **Stop
   orange preview** turns the LED off and blanks the DMD; any other
   acquisition, a new FOV or new cells stop it first. Nothing is recorded.
5. **Acquire z-reference** if drift correction is used.
6. **Run.** Blockers disable it, with the reason. Warnings leave it
   enabled: Run lists them all in one dialog with what each means, and
   **Continue anyway** (with an optional note) starts the run.

**New FOV** starts the next field of view on the same prepared rig.

### During experiments

- **Stop after this trial** (or block) ends the run cleanly between trials.
- **Abort** abandons the trial in progress and releases the rig.
- A stopped, failed or aborted run **resumes** from its checkpoint (Resume
  panel): the incomplete trial is repeated. If the blue or DMD calibration
  changed since the run started, or the rig has warnings now, the same
  Continue anyway dialog asks once.
- Every override is recorded: the run's `run_recipe.json`
  (`start_override`: each warning, its consequence, the time and your
  note) and, for a resume, `resumes/resume_NNN.json`.

### Optional behaviour

The Session panel switches the **face camera** (Grasshopper3, his 40 Hz face
video) and the **wheel encoder** (A/B lines, default his wiring
`Dev1/port0/line9`, `line10`, not yet checked on Firefly; set them in rig
settings). Off, nothing about them is required, driven or triggered, and
the recipe says they were off. On but absent is a blocker: the requested
acquisition cannot be made.

### Troubleshooting

- **The DMD cannot be opened** (Rig readiness: "DMD board not open"):
  Luminos started without the board (debug mode, or the driver failed).
  Close Luminos and run the driver probe above.
- **No sequence-queue support**: the live driver does not know
  `ALP_PROJ_QUEUE_MODE`. A connectivity run cannot start; check which DLL
  the probe found, and the MEX build.
- **Slide playback failed**: the queue did not step as modelled (order or
  brightness). A run can still be started, with a warning, to collect
  diagnostic data. Check the DAQ `dmdTrigger` line, the uniform slide and
  the camera exposure, then Run on slide again.
- **Missing blue calibration**: calibrate the blue LED on the slide and set
  `blue_threshold`. His blue values are linearised intensities, not volts,
  so there is no uncalibrated fallback.
- **Scan calibration taken at another camera area or binning**: retake the
  scans at the acquisition area, or Find earlier scans for a set that fits.
- **DMD owned by another tool** (e.g. `adaptive_optopatch`): stop that tool
  or release its patterns in Luminos, then Check readiness again.

The checks file the rig settings name records the two DMD checks as
`{"queue_support": {"passed": true, "evidence": "...", "date": "...",
"provenance": {...}}, "slide_queue": ...}`.

## Development

```matlab
setup_project
run_tests            % everything, including the 640-trial parity run (~15 min)
run_tests("fast")    % everything else
```

Run long MATLAB jobs under a memory cap, so a runaway is killed instead of
freezing the workstation (twice so far):

```sh
systemd-run --user --scope -p MemoryMax=12G -p MemorySwapMax=0 matlab -batch "run_tests"
```

**The same thing from MATLAB**, for scripts and diagnosis: the device's
controller is `app.getHadamardStimController()`, and
`hadamard_stim.apply_controller_action(c, "start_run", struct(), c.Revision)`
is exactly what the tab's Run button sends. A session can also be built by
hand:

```matlab
env = hadamard_stim.luminos.make_environment(app, cfg, blue_threshold=..., ...
    calibration_folders=..., hardware_validation=...);
c = hadamard_stim.HadamardStimController(env);
```

To regenerate the fixtures (needs `config/paths.local.m`, and read-only
access to Yitong's `data&notes` for the `session_inputs` section):

```matlab
cd tests/golden
generate_yitong_goldens                              % all sections, about 30 min
generate_yitong_goldens(sections="waveforms")        % one section
```

Commit the generator before regenerating. Each fixture records the
generator's git commit and the SHA-256 of the frozen reference it ran.
