# hadamard-stim

MATLAB package that will run Yitong Qi's Firefly Hadamard protocol inside
Luminos. The protocol combines sparse-pulse and Hadamard-coded patterned
optogenetic stimulation with Hadamard structured-illumination scans, drift
correction and bleaching compensation.

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

Phases 1 to 3 are complete off-rig.
- Yitong's reference code is frozen, and golden fixtures are generated from it.
- Luminos's ALP MEX has a sequence queue that matches his loader call for call.
- The whole protocol runs on a simulated rig and reproduces his 640-trial trace exactly.

Next is the Luminos adapter (Phase 4). The Firefly hardware checks listed in
`docs/notebook.md` must pass before any real acquisition.

## Layout

```text
+hadamard_stim/            the package
  default_config.m         the experiment, as he ran it
  validate_config.m        errors, and deviations from his settings
  HadamardStimController.m one session: setup, then a run
  apply_controller_action.m  the only write path for a frontend
  +yitong/                 ports of his functions (source path + SHA-256 in each)
  +protocol/               his script, step by step, on a hardware interface
  +metadata/               run recipe, trial records, checkpoints
  +testing/                simulated rig, his affine geometry
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
run_tests            % everything, including the 640-trial parity run (~10 min)
run_tests("fast")    % everything else
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
