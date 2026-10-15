function state = new_spontaneous_state(cfg, canonical, reference)
%NEW_SPONTANEOUS_STATE Protocol state before the first spontaneous block.
%
%   state = hadamard_stim.protocol.new_spontaneous_state(cfg, canonical_cells, reference)
%
%   canonical  approved cells (segment_cells): cell_coord, illum_rois,
%              stim_rois, illum_mask, stim_mask
%   reference  had_ref, and z_all and had_z_stack when drift correction
%              between blocks is on (run_z_reference)
%
%   What his behaviour script kept between blocks, so a checkpoint of this
%   struct resumes at a block boundary: next_block, orange_v,
%   exposure_waveform_ms, b0, b1, and the current geometry.
if isempty(cfg.stimulation.orange_start_v)
    error("hadamard_stim:OrangeStartMissing", ...
        "stimulation.orange_start_v is not set (Yitong set it by hand; it was not saved).");
end
if size(canonical.cell_coord, 1) < 1
    error("hadamard_stim:CellCount", "No cells were approved.");
end
state.session_mode = "spontaneous";
state.next_block = 1;
state.orange_v = cfg.stimulation.orange_start_v;
state.exposure_waveform_ms = cfg.stimulation.waveform_period_ms;
state.b0 = [];
state.b1 = [];

state.cells.canonical = canonical;
state.cells.current = struct("illum_rois", canonical.illum_rois, "stim_rois", canonical.stim_rois, ...
    "illum_mask", canonical.illum_mask, "stim_mask", canonical.stim_mask);
state.cells.corrections = struct("trial", {}, "cell_shift", {}, "flow_at_cells", {}, ...
    "z_drift", {}, "z_fallback", {}, "motor_before", {}, "motor_after", {}, ...
    "illum_mask_sha256", {}, "stim_mask_sha256", {});

state.reference = reference;
end
