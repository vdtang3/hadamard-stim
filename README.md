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

Real acquisition still needs:
- the Firefly hardware checks listed in `docs/notebook.md`;
- a Luminos calibration of the blue LED, taken on the slide from the tab
  (a spontaneous session does not need it), and a `blue_threshold` in its
  camera counts.

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
  +metadata/               run recipe, trial and block records, checkpoints
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
tools/export_yitong_alp_queue_log.m   his queue-loader calls, for Luminos's ALP tests
tests/
  yitong_reference/        frozen, minimal copy of Yitong's code (test-only)
  fixtures/                golden fixtures generated from that code
  golden/                  the generator, its mocks and shims
  support/                 deterministic synthetic inputs shared with tests
docs/notebook.md           engineering notebook: decisions, findings, parity issues
```

## Usage

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

**On the rig, through Luminos.** Put this repository on the MATLAB path in
the rig's `startup.m` and add the device and tab to your user file for
Firefly (Luminos `src/Users/Vincent.json` does):

```json
"rigs": { "Firefly": {
  "devices": [{ "deviceType": "Hadamard_Stim", "name": "Hadamard Stim",
                "calibration_folders": ["..."],
                "hardware_validation_file": "...firefly_checks.json" }],
  "tabs": ["HadamardStim"] } }
```

`blue_threshold` can be set there too, but it has no default: it is a power
in the active blue calibration's own units (parity issue P2), not his 15.

The **Hadamard Stim** tab then shows one shared controller. Choose the
session mode and the optional streams at the top (Session panel). With a
uniform slide under the objective, Take calibration scans (his `had_cal`
recordings; they become the rig's scan calibration) and Calibrate blue LED
(his slide method, run by Luminos, which keeps the calibration). Then, with the
sample in place, work through: Preflight (read only, one line per requirement; streams that are
off show "disabled"), Prepare rig, Take reference scan, Segment, Approve
cells, Acquire z-reference (not needed for a spontaneous session without
drift correction), Run.
Stop after this trial and Abort are honoured while a run is going; a
stopped, failed or aborted run resumes from its checkpoint (Resume panel).
If the blue or DMD calibration has changed since the run started, the
Resume panel shows both and what that means, and resumes only after
"Continue anyway"; each resume is recorded in the run's `resumes/` folder.
The rig settings (blue threshold, calibration scan folders, the Firefly
checks file, the wheel encoder's A/B lines) can also be set from the tab.
The encoder lines default to his wiring (`Dev1/port0/line9`, `line10`),
which is not yet checked on Firefly. The checks file records the
four Firefly checks as `{"driver": {"passed": true, "evidence": "...",
"date": "..."}, "trigger_edge": ..., "queue_support": ..., "slide_queue": ...}`.

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
