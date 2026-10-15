function fields = config_fields()
%CONFIG_FIELDS The configuration settings an experimenter changes between runs.
%
%   fields = hadamard_stim.ui.config_fields()
%
%   The tab's configuration panel is this list, in this order; nothing
%   else in default_config can be edited from it (update_config refuses
%   other paths). Each entry: path (into default_config), group, label,
%   kind ("number", "integer", "boolean", "text" or "choice"), unit,
%   choices, required (no value is known from his session; must be set),
%   note, and modes: the session modes that use it ("connectivity",
%   "spontaneous"), so the tab shows only what applies. Changing any field
%   that is not required, the trial range or a behaviour stream makes the
%   run "modified" (validate_config lists the deviations; a stream turned
%   off is a warning).
f = @(path, group, label, kind, unit, note) struct("path", path, "group", group, ...
    "label", label, "kind", kind, "unit", unit, "choices", {strings(1, 0)}, ...
    "required", false, "note", note, "modes", {["connectivity" "spontaneous"]});
fields = [
    f("session.mode", "Session", "Session mode", "choice", "", "Connectivity: his stimulation trials. Spontaneous: imaging in blocks, no blue light")
    f("naming.prefix", "Run", "Mouse and field of view", "text", "", "e.g. M-YQ0201-29_FOV1; names every folder")
    f("trials.first", "Run", "First trial", "integer", "", "The run's scope, not a deviation")
    f("trials.last", "Run", "Last trial", "integer", "", "The run's scope, not a deviation")
    f("trials.run_sparse", "Run", "Run sparse-pulse trials", "boolean", "", "Off: sparse trials are skipped, Hadamard trials still run")
    f("trials.n_trial", "Run", "Trials in the protocol", "integer", "", "")
    f("trials.n_sparse", "Run", "Sparse trials among them", "integer", "", "Every n_trial/(n_trial - n_sparse)th trial is a Hadamard trial")
    f("spontaneous.n_blocks", "Run", "Blocks", "integer", "", "His sessions: 10")
    f("spontaneous.block_frames", "Run", "Frames per block", "integer", "frames", "288000 is about 6.1 min at 1.27 ms (from his analysis; his block settings are not yet read)")
    f("spontaneous.drift_correction", "Run", "Drift correction between blocks", "boolean", "", "He corrected drift before every block")
    f("behavior.face_camera_enabled", "Behaviour", "Face camera", "boolean", "", "Grasshopper face video with IR light; off: neither is driven")
    f("behavior.wheel_encoder_enabled", "Behaviour", "Wheel encoder", "boolean", "", "Raw A/B lines on the acquisition clock (lines: rig settings)")
    f("segmentation.n_exclude", "Segmentation", "Top-contrast candidates to skip", "integer", "cells", "His answer at the prompt after looking at min_val (5 for his FOV)")
    f("segmentation.threshold", "Segmentation", "Cells to keep", "integer", "cells", "Must equal the matrix order")
    f("segmentation.illum_spot_size", "Segmentation", "Orange spot size", "integer", "px", "Auto Square SquareSize")
    f("segmentation.stim_spot_size", "Segmentation", "Blue spot size", "integer", "px", "reduce_spot_size_sequence(app, 3, 2)")
    f("matrix.order", "Stimulation", "Stimulation matrix order", "integer", "rows", "rand(order) <= 0.5 under rng(0)")
    f("stimulation.orange_start_v", "Imaging and stimulation", "Starting orange voltage", "number", "V", "He set it by hand; it was not saved")
    f("stimulation.camera_exposure_ms", "Imaging and stimulation", "Camera exposure", "number", "ms", "")
    f("stimulation.waveform_period_ms", "Imaging and stimulation", "Frame period", "number", "ms", "")
    f("stimulation.n_frames", "Imaging and stimulation", "Frames per trial", "integer", "frames", "")
    f("stimulation.wait_frames", "Imaging and stimulation", "Orange frames before recording", "integer", "frames", "")
    f("stimulation.ir_v", "Imaging and stimulation", "IR voltage", "number", "V", "Face illumination")
    f("stimulation.grasshopper_period_ms", "Imaging and stimulation", "Face camera period", "number", "ms", "")
    f("sparse.blue_v", "Sparse pulses", "Blue voltage", "number", "V", "One value")
    f("sparse.pulse_frames", "Sparse pulses", "Pulse length", "integer", "frames", "")
    f("sparse.period_frames", "Sparse pulses", "Pulse period", "integer", "frames", "")
    f("sparse.n_pulses", "Sparse pulses", "Pulses per trial", "integer", "", "")
    f("sparse.dist_cutoff_px", "Sparse pulses", "Minimum distance between cells", "number", "px", "0.8 mm at 6.5 um per pixel")
    f("hadamard.blue_v", "Hadamard trials", "Blue voltage", "number", "V", "")
    f("hadamard.frames_per_code", "Hadamard trials", "Frames per code", "integer", "frames", "")
    f("scan.camera_exposure_ms", "Scans", "Scan camera exposure", "number", "ms", "Reference image and z-stack")
    f("scan.waveform_period_ms", "Scans", "Scan frame period", "number", "ms", "")
    f("scan.orange_v", "Scans", "Scan orange voltage", "number", "V", "")
    f("scan.repeats", "Scans", "Scan repeats", "integer", "", "")
    f("z_reference.enabled", "Z reference", "Acquire the reference z-stack", "boolean", "", "Needed by drift correction")
    f("z_reference.half_range", "Z reference", "Half range", "number", "mm", "Either side of the focus")
    f("z_reference.n_steps", "Z reference", "Steps", "integer", "", "n_steps + 1 planes")
    f("drift.enabled", "Drift correction", "Correct drift", "boolean", "", "")
    f("drift.retarget_every", "Drift correction", "Every", "integer", "trials", "And at trial 1")
    f("drift.exposure_scale", "Drift correction", "Exposure scale", "number", "x", "Times the frame exposure")
    f("bleaching.enabled", "Bleaching", "Compensate bleaching", "boolean", "", "Orange rescaled at each drift correction")
    f("bleaching.n_pix_cell", "Bleaching", "Pixels per cell", "integer", "px", "")
    f("dmd.trigger_edge", "DMD", "Queue trigger edge", "choice", "", "The board's power-on edge his loader inherited (Firefly check)")
    f("dmd.picture_time_us", "DMD", "Picture time", "number", "us", "")
    ];
required = ["naming.prefix" "segmentation.n_exclude" "stimulation.orange_start_v" "dmd.trigger_edge"];
for k = 1:numel(fields)
    fields(k).required = ismember(fields(k).path, required);
end
connectivity_only = ["trials." "matrix." "sparse." "hadamard." "dmd." ...
    "stimulation.n_frames" "z_reference.enabled" "drift.enabled" "drift.retarget_every"];
for k = 1:numel(fields)
    if startsWith(fields(k).path, connectivity_only)
        fields(k).modes = "connectivity";
    elseif startsWith(fields(k).path, "spontaneous.")
        fields(k).modes = "spontaneous";
    end
end
fields([fields.path] == "dmd.trigger_edge").choices = ["rising" "falling"];
fields([fields.path] == "session.mode").choices = ["connectivity" "spontaneous"];
end
