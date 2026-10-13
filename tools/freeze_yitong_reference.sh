#!/usr/bin/env bash
# Copy the minimal set of Yitong Qi's Firefly ("Dragonfly") files that the
# golden-fixture generator executes, or that a +hadamard_stim/+yitong port
# mirrors, into tests/yitong_reference/, and write MANIFEST.tsv.
#
# The source tree is read-only. This script only reads from it.
#
# Usage: tools/freeze_yitong_reference.sh <yitong_code_root> <lab_code_root>
#   yitong_code_root = ".../Lab/Labmembers/Yitong Qi/code"
#   lab_code_root    = ".../Lab/Computer Code"
#
# Re-running overwrites tests/yitong_reference/. Any change to the frozen set
# must be recorded in docs/notebook.md, because every golden fixture records
# the hashes it was generated from.
set -euo pipefail

src_root="${1:?usage: $0 <yitong_code_root> <lab_code_root>}"
lab_root="${2:?usage: $0 <yitong_code_root> <lab_code_root>}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$repo_root/tests/yitong_reference"
dragonfly="ff_control/Dragonfly_yq_v1_2026_02_09"

# path relative to $src_root (or LAB:path relative to $lab_root) <TAB> why it is frozen
files=$(cat <<'EOF'
ff_control/Dragonfly_yq_v1_2026_02_09/Auto Scripts/RunSynchronizedAQMulti_sparse_pulse_hadamard_behavior_v1.m	protocol: matrix, trial loop, sparse/Hadamard sequencing, bleaching (executed by the trace golden)
ff_control/Dragonfly_yq_v1_2026_02_09/Auto Scripts/square_target_drift_correction_v4.m	XY/Z drift correction (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Waveforms/dragonflyMultiPatWaveform_2color_periodicPulse_v2_yq.m	stimulation DAQ waveform (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Waveforms/dragonflyStaticHadamardWaveform_yq.m	Hadamard scan DAQ waveform; this root copy shadows kinetix/ and hamamatsu/ copies under Yitong's genpath order (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Waveforms/helper_functions/baseWave.m	waveform class used by both waveform functions (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Waveforms/helper_functions/arbWave.m	waveform class base (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Waveforms/helper_functions/flexRampTrainWave.m	orange and blue envelope trains (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Waveforms/helper_functions/flexRampWave.m	flexRampTrainWave superclass (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Waveforms/helper_functions/rampWave.m	flexRampWave superclass (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Utilities/static_image_seg_v5.m	auto-square segmentation and cell ordering (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Utilities/quasi_equidist_hardsphere_v2.m	sparse-pulse cell selection (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Utilities/linearize_blue_voltage.m	blue LED voltage linearization (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Utilities/blueCal.mat	Yitong's historical blue calibration; test input only, never a production source (loaded by linearize_blue_voltage)
ff_control/Dragonfly_yq_v1_2026_02_09/Utilities/optical_flow_motion_correction_single_frame.m	Farneback flow for XY drift (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Utilities/hadamard_reconstruct.m	z-stack reconstruction (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/dmd_control/dmd_draw.m	Auto Square ROI construction (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/dmd_control/dmd_draw_hidden.m	camera ROI to DMD mask rendering (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/dmd_control/dmd_set_sequence.m	'Append' builds mask_sequence from dmd_draw (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/dmd_control/dmd_send_btd_sequence_multi.m	hands the per-trial sequence list to load_sequence_multi (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/dmd_control/dmd_send_sequence.m	sends the Hadamard scan patterns during drift correction (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/dmd_control/dmd_hadamard_reconstruct.m	cached-calibration reconstruction used by hadamard_ref and drift correction (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/dmd_control/dmd_apply_correction_tform.m	optional geometric correction inside dmd_draw_hidden (mirrored)
ff_control/Dragonfly_yq_v1_2026_02_09/dmd_control/quick_functions/spot_select_sequence.m	per-trial stimulation pattern from a cell subset (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/dmd_control/quick_functions/reduce_spot_size_sequence.m	builds the stimulation spots (pattern 2) from the illumination spots (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/dmd_control/quick_functions/static_Hadamard_patterns.m	Hadamard scan patterns (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/dmd_control/quick_functions/hadamard_ref.m	reference image for segmentation; edited 2026-02-10, after the 2025 experiments (mirrored, see MANIFEST.md)
ff_control/Dragonfly_yq_v1_2026_02_09/Hadamard/alp_logical_to_btd.m	DMD bit packing (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Hadamard/alp_btd_to_logical.m	DMD bit unpacking (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Hadamard/hadamard_bincode_nopermutation.m	Hadamard code matrix (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Hadamard/hadamard_patterns_scramble_nopermutation.m	scrambled 63x14 scan patterns (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Hadamard/pixel_configuration.m	DMD 1024x768 geometry (executed)
ff_control/Dragonfly_yq_v1_2026_02_09/Hardware/@vialuxDMDControl/load_sequence_multi.m	ALP sequence-queue call order; executed against a recording fake ALP
ff_control/Dragonfly_yq_v1_2026_02_09/Settings/dragonflySettings.m	DAQ output channel order that waveform rows are matched against (read)
LAB:General Matlab/VIALUX control/Patterns/nextHadamard.m	called by hadamard_bincode_nopermutation but not part of Dragonfly; the lab VIALUX copy is used because Yitong's imaging/ copy lacks pickFactors (executed)
LAB:General Matlab/VIALUX control/Patterns/libHadamard.m	called by nextHadamard; n=64 resolves to MATLAB hadamard(64), so hadlib/ is not needed (executed)
LAB:General Matlab/VIALUX control/Patterns/pickFactors.m	called by libHadamard (executed)
LAB:Image Processing/NeuroSegmentation/tovec.m	reshape helper used by the protocol's bleaching estimate and by Z-drift correlation (executed)
EOF
)

# Replace only what this script owns; README.md is hand-written.
rm -rf "$dest/dragonfly" "$dest/external" "$dest/MANIFEST.tsv"
mkdir -p "$dest"
manifest="$dest/MANIFEST.tsv"
printf 'path\tbytes\tsource_mtime_utc\tsha256\twhy\n' > "$manifest"

while IFS=$'\t' read -r rel why; do
    [ -z "$rel" ] && continue
    # Dragonfly files keep their path inside the package; everything else
    # goes under external/ so its origin stays obvious.
    case "$rel" in
        LAB:*)          rel="${rel#LAB:}"; in="$lab_root/$rel"; out_rel="external/lab/$rel" ;;
        "$dragonfly"/*) in="$src_root/$rel"; out_rel="dragonfly/${rel#"$dragonfly"/}" ;;
        *)              in="$src_root/$rel"; out_rel="external/yitong/$rel" ;;
    esac
    out="$dest/$out_rel"
    mkdir -p "$(dirname "$out")"
    cp -p "$in" "$out"
    chmod a-w "$out"
    bytes=$(stat -c %s "$in")
    mtime=$(date -u -d "@$(stat -c %Y "$in")" +%Y-%m-%dT%H:%M:%SZ)
    sha=$(sha256sum "$in" | cut -d' ' -f1)
    printf '%s\t%s\t%s\t%s\t%s\n' "$out_rel" "$bytes" "$mtime" "$sha" "$why" >> "$manifest"
done <<< "$files"

echo "froze $(($(wc -l < "$manifest") - 1)) files into $dest"
