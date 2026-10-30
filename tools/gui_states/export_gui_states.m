function export_gui_states(out_folder)
%EXPORT_GUI_STATES The Hadamard Stim tab's input in four situations, from the real controller.
%
%   export_gui_states(out_folder)
%
%   Off-rig, for looking at the tab (luminos-private frontend harness,
%   harness/hadamard-stim.html). Each scenario drives a real
%   HadamardStimController on a LuminosBackend over the fake Firefly
%   (tests/support/tab_session) through prepare, reference scan,
%   segmentation, approval and z-reference, with trials 1-4, then runs the
%   readiness check, and writes <scenario>.json: the controller's getState
%   and the views the tab asks for (controller_view).
%
%   The two DMD commissioning records are made by the real check functions
%   on the fake rig. To show records from other days or other software,
%   their dates and Luminos commit are then edited in the file, as they
%   would be after time passes. The Hadamard scans' and the slide test's
%   items come from a second backend that names a scan folder with a
%   record (the fake rig otherwise reconstructs from movies, "Given as
%   movies") and that is told whether Luminos's DMD code changed since the
%   slide test (there is no Luminos repository off-rig).
%
%     ready     commissioned rig; old but compatible calibrations, shown
%               with their age only (blue 9 days, scans 3 weeks, DMD
%               geometry 4 months)
%     warnings  the same ages, with two real reasons to distrust: scans
%               taken at another camera area, and a slide test recorded
%               before Luminos's DMD code changed
%     blocker   ready, but the DMD owned by Adaptive Optopatch
%     preview   ready, with the orange preview on (start_orange_preview)
%
%   Not part of the package or its tests; a development aid.
arguments
    out_folder (1, 1) string
end
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(here));
% The Luminos stand-in shadows luminos_session_info: put the path back
% however this ends, so it never outlives the export.
original = path;
restore = onCleanup(@() path(original)); %#ok<NASGU>
addpath(root, fullfile(root, "tests", "support"), fullfile(here, "luminos_shim"));
if ~isfolder(out_folder)
    mkdir(out_folder);
end
scenarios = struct( ...
    "ready", struct("scan_roi", [], "dmd_changed", false, "owner", "", "preview", false), ...
    "warnings", struct("scan_roi", [0 512 0 512], "dmd_changed", true, "owner", "", "preview", false), ...
    "blocker", struct("scan_roi", [], "dmd_changed", false, "owner", "adaptive_optopatch", "preview", false), ...
    "preview", struct("scan_roi", [], "dmd_changed", false, "owner", "", "preview", true));
for name = string(fieldnames(scenarios))'
    folder = string(tempname);
    mkdir(folder);
    cleanup = onCleanup(@() rmdir(folder, "s"));
    out = scenario(root, folder, scenarios.(name));
    hadamard_stim.metadata.write_text(string(jsonencode(out, "PrettyPrint", true)), fullfile(out_folder, name + ".json"));
    fprintf("%s: %d blockers, %d warnings\n", name, numel(out.state.readiness.blockers), ...
        numel(out.state.readiness.warnings));
    clear cleanup
end
end

function out = scenario(root, folder, s)
[c, app, cfg] = tab_session(folder);
now_utc = datetime("now", "TimeZone", "UTC");
stamp = @(d) string(datetime(d, "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));

% The two DMD records from the real checks, as if recorded 13 days ago.
file = c.Backend.settings().hardware_validation_file;
delete(file);
results = {hadamard_stim.checks.queue_support_check(app), ...
    hadamard_stim.checks.slide_queue_check(app, acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition, ...
        frame_means=@(acq) slide_means())};
for k = 1:numel(results)
    hadamard_stim.checks.record_firefly_check(file, results{k});
end
records = jsondecode(fileread(file));
luminos_now = luminos_session_info(app).git.commit;
for name = string(fieldnames(records))'
    records.(name).date = stamp(now_utc - days(13));
    records.(name).provenance.luminos_commit = luminos_now;
end
if s.dmd_changed
    records.slide_queue.provenance.luminos_commit = "a36342a70c1d9e8f2b7a6c5d4e3f2a1b0c9d8e7f";
end
hadamard_stim.metadata.write_text(string(jsonencode(records, "PrettyPrint", true)), file);

% The blue LED calibrated on the slide 9 days ago, the DMD 4 months ago.
blue = app.getDevice("NI_DAQ_Modulator", "name", "Blue LED 488");
blue.calibration_info = struct("method", "Calibrate_Modulator_On_Slide", "units", "camera counts above LED-off", ...
    "measured_utc", stamp(now_utc - days(9)), "camera", "Teledyne Kinetix, 10 ms, 448 x 328, bin 1");
app.getDevice("ALP_DMD").MeasuredUtc = stamp(now_utc - days(122));

cfg.trials.first = 1;
cfg.trials.last = 4;
cfg.naming.prefix = "M1_FOV1";
cfg.behavior.face_camera_enabled = false;
cfg.behavior.wheel_encoder_enabled = false;
act = @(a, p) hadamard_stim.apply_controller_action(c, a, p, c.Revision);
must = @(r, what) assert(r.ok, what + ": " + r.message);
must(act("set_config", struct("config", cfg)), "set_config");
must(act("prepare_rig", struct()), "prepare_rig");
use_parity_scans(c, root);
for step = ["acquire_reference_image" "propose_cells" "approve_cells" "acquire_z_reference"]
    must(act(step, struct()), step);
end
if strlength(s.owner) > 0
    app.getDevice("ALP_DMD").pattern_owner = s.owner;
end
must(act("run_preflight", struct()), "run_preflight");
if s.preview
    must(act("start_orange_preview", struct()), "start_orange_preview");
end
state = c.getState();

% The scans and the slide test as a backend naming recorded scans, and
% knowing whether Luminos's DMD code changed, reports them.
scans = fullfile(folder, "scans", "had_cal_1x_arch_1");
mkdir(scans);
camera = app.getDevice("Camera", "name", "Teledyne Kinetix");
roi = camera.getROIForAcquisition();
if ~isempty(s.scan_roi)
    roi = s.scan_roi;
end
record = struct("kind", "hadamard_stim_calibration_scan", "schema_version", "1.0.0", ...
    "taken_utc", stamp(now_utc - days(21)), "settings", cfg.calibration_scan, "m_q", cfg.scan.m_q, ...
    "camera", struct("name", "Teledyne Kinetix", "roi", roi, "bin", 1), ...
    "dmd", "DMD (shared)", "folders", scans, "waveform_sha256", "");
hadamard_stim.metadata.write_text(hadamard_stim.metadata.canonical_json(record), fullfile(scans, "hadamard_calibration_scan.json"));
if s.dmd_changed
    changed = @(~, ~) deal(true, "src/Devices/Patterning/DMD/ALP/ALP_DMD.m");
else
    changed = @(~, ~) deal(false, strings(1, 0));
end
named = hadamard_stim.luminos.LuminosBackend(app, blue_threshold=15, calibration_folders=scans, ...
    hardware_validation_file=file, run_root=folder, ...
    acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition, ...
    dmd_code_changed_function=changed);
fresh = named.preflight(c.Config).checks;
checks = state.readiness.checks;
for id = ["scan_calibration" "firefly_slide_queue" "firefly_queue_support"]
    item = fresh(string({fresh.id}) == id);
    state.preflight.checks(string({state.preflight.checks.id}) == id) = item;
    checks(string({checks.id}) == id) = item;
end
state.readiness = hadamard_stim.metadata.readiness_report(checks);
state.readiness = rmfield(state.readiness, "failures");

out.state = state;
for view = ["segmentation" "config_fields" "summary" "commissioning_checklist"]
    out.views.(view) = hadamard_stim.controller_view(c, view);
end
out.views.calibration_scan_sets = struct("ok", true, "name", "calibration_scan_sets", ...
    "message", "", "data", named.calibration_scan_sets());
end

function means = slide_means()
% A uniform slide's frame means as the queue model predicts them.
shown = hadamard_stim.protocol.alp_queue_display([3 2], [2 3], 16);
offset = [0 3];
picture = 5 * ones(1, 16);
live = shown.sequence > 0;
picture(live) = offset(shown.sequence(live)) + shown.picture(live);
means = 100 + 40 * picture + 0.5 * sin(1:16);
end
