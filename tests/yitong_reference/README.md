# Frozen Yitong reference (test-only)

This folder holds a verbatim copy of the files from Yitong Qi's Firefly
("Dragonfly") control package that the golden-fixture generator executes, or
that a `+hadamard_stim/+yitong` port mirrors. It is not the whole package.

- **Source:** `Lab/Labmembers/Yitong Qi/code/ff_control/Dragonfly_yq_v1_2026_02_09`, plus four lab helpers it calls from elsewhere (under `external/lab/`).
- **Inventory:** `MANIFEST.tsv` lists every file with its size, source modification time, SHA-256 and the reason it is frozen.
- **Write-protected:** files are read-only. Change the set only by re-running `tools/freeze_yitong_reference.sh`, and record why in `docs/notebook.md`.
- **Never on the runtime path:** `setup_project` and `run_tests` do not add this folder. Only `tests/golden/generate_yitong_goldens` adds it, and only temporarily.
- **Tested:** `TestYitongReference` checks the hashes, checks that nothing is present without a manifest entry, and checks that the folder stays off the path.

## Snapshot notes

- Every relevant file predates his 2025-03-08 experiment, with one exception: `dmd_control/quick_functions/hadamard_ref.m` was edited on 2026-02-10 to transpose the reference image, alongside a Kinetix camera-MEX change. His 2025-03-08 session shows the earlier behaviour, where `ref_im` equals `hadamard_ref` with no transpose. The earlier version (SHA-256 `ca83885b…`, in the `Dragonfly_yq_v1_2026_02_08` snapshot) differs only on that line.
- `Waveforms/dragonflyStaticHadamardWaveform_yq.m` is the copy at the root of `Waveforms/`. Under his `addpath(genpath('Waveforms'))` it shadows the older copies in `kinetix/` and `hamamatsu/`.
- `nextHadamard`/`libHadamard`/`pickFactors` come from the lab's `VIALUX control/Patterns` folder, because the copy in Yitong's `imaging/` folder lacks `pickFactors`. For the 63-code scan, both resolve to MATLAB `hadamard(64)`.
- `blueCal.mat` is his historical blue-LED calibration. It is a test input only. Production uses the active Luminos blue calibration.
