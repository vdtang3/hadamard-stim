function data = golden_session_inputs(ctx)
%GOLDEN_SESSION_INPUTS Small, read-only extracts of Yitong's own sessions.
%
%   2025-03-08, M-YQ0201-29 (the z01 plane of the reference z-stack taken
%   immediately before the sparse-pulse/Hadamard protocol): the Hadamard
%   reference image he segmented, the 320 ordered cell centres, and the
%   DMD registration in force.
%
%   2024-08-23, M-YQ0201-27, opto1V test: the only saved session that holds
%   both spot patterns (illumination and stimulation) as ROIs and as DMD
%   masks, which pins down spot sizes and mask rendering.
%
%   Nothing is written under yitong_data_root.
root = ctx.paths.yitong_data_root;
s25_rel = "2025_03_08/163203_M-YQ0201-29_FOV1_Arch_z01_rpt01/settings.mat";
s24_rel = "2024_08_23_M-YQ0201-27_expChk/204634_M-YQ0201-27_FOV2_opto1V_test/settings.mat";

s25 = load(fullfile(root, s25_rel), "ref_im", "dmd_session_data", ...
    "dmd_registration_data", "DAQ_channels", "zPosition");
data.session_2025.source = s25_rel;
data.session_2025.source_sha256 = golden_file_sha256(fullfile(root, s25_rel));
data.session_2025.ref_im = s25.ref_im;
data.session_2025.hadamard_ref_equals_ref_im = isequal(s25.ref_im, s25.dmd_session_data.hadamard_ref);
data.session_2025.cell_coord = s25.dmd_session_data.cell_coord;
data.session_2025.registration_data = s25.dmd_registration_data;
data.session_2025.daq_channels = string(s25.DAQ_channels);
data.session_2025.z_position = s25.zPosition;

s24 = load(fullfile(root, s24_rel), "dmd_session_data", "dmd_registration_data", ...
    "dmd_mask_sequence_rois", "dmd_mask_sequence");
data.session_2024.source = s24_rel;
data.session_2024.source_sha256 = golden_file_sha256(fullfile(root, s24_rel));
data.session_2024.cell_coord = s24.dmd_session_data.cell_coord;
data.session_2024.registration_data = s24.dmd_registration_data;
data.session_2024.mask_sequence_rois = s24.dmd_mask_sequence_rois;
data.session_2024.mask_sequence = s24.dmd_mask_sequence;
end
