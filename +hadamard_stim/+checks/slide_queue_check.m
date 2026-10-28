function result = slide_queue_check(app, options)
%SLIDE_QUEUE_CHECK Queue playback on a slide: a small queue, stepped by DAQ triggers, plays as modelled.
%
%   result = hadamard_stim.checks.slide_queue_check(app, trigger_edge="rising")
%
%   On a uniform slide under the objective. Loads a queue of two sequences
%   through the same Luminos call the protocol uses (LuminosRig ->
%   Load_Sequence_Queue): 3 pictures played twice, then 2 pictures played
%   three times (12 triggers), and steps it with one DAQ trigger per camera
%   frame for 16 frames, so the last 4 triggers find it run dry. The
%   pictures are nested bands covering 1/6 to 5/6 of the DMD, so on a
%   uniform slide each one has its own brightness; every frame is
%   classified by its mean against a line fitted to the expected pictures,
%   and compared with what alp_queue_display predicts.
%
%   Passes when every one of the 12 frames shows the predicted picture,
%   with the brightness steps well clear of the noise. What the 4 frames
%   after it ran dry showed is reported (the model does not say); it does
%   not decide the check.
%
%   Options:
%     trigger_edge     "rising" or "falling"; default: the protocol's
%                      edge (default_config().dmd.trigger_edge, rising),
%                      which Load_Sequence_Queue sets explicitly
%     profile, acquisition_function   as for LuminosRig (tests substitute fakes)
%     frame_means      @(acq) mean of each frame; default reads the imaging
%                      camera's movie
%
%   result: check_result("slide_queue", ...), details has the per-frame
%   table (trigger, predicted sequence and picture, mean, classified
%   picture) and the fit.
arguments
    app
    options.trigger_edge (1, 1) string {mustBeMember(options.trigger_edge, ["rising" "falling"])} = hadamard_stim.default_config().dmd.trigger_edge
    options.profile struct = hadamard_stim.luminos.firefly_profile()
    options.acquisition_function = @Waveform_Camera_Sync_Acquisition
    options.frame_means = []
end
profile = options.profile;
edge = options.trigger_edge;

[devices, ~] = hadamard_stim.luminos.resolve_hardware(app, profile);
dmd = devices.dmd;
if isempty(dmd) || ~logical(dmd.Supports_Sequence_Queue())
    result = hadamard_stim.checks.check_result("slide_queue", false, ...
        "Not run: the DMD does not support the sequence queue.", struct(), ...
        hadamard_stim.checks.check_provenance(app, profile));
    return
end

pictures = [3 2];
repeats = [2 3];
n_dry = 4;
n_distinct = sum(pictures);
capacity = sum(pictures .* repeats);
n_frames = capacity + n_dry;

cfg = hadamard_stim.default_config();
cfg.dmd.trigger_edge = edge;
c = cfg.calibration_scan;    % slide imaging: 10 ms frames, orange 0.1 V, blue off

canvas = dmd.Pattern_Canvas_Size();
bands = cell(1, n_distinct);
for j = 1:n_distinct
    mask = false(canvas);
    mask(:, 1:round(j / (n_distinct + 1) * canvas(2))) = true;
    bands{j} = mask;
end
sequences = {cat(3, bands{1:3}), cat(3, bands{4:5})};

rig = hadamard_stim.luminos.LuminosRig(app, profile=profile, ...
    acquisition_function=options.acquisition_function);
release = onCleanup(@() rig.release()); %#ok<NASGU>
report = rig.begin(cfg, "calibration_scan");
if ~report.can_run
    error("hadamard_stim:HardwareNotReady", "The rig cannot run the queue check:\n  %s", ...
        strjoin(report.failures, newline + "  "));
end
rig.dmd_load_queue(sequences, repeats);
roi = double(devices.camera.getROIForAcquisition());   % [x width y height]
waveform = hadamard_stim.protocol.scan_waveform(cfg, c.waveform_period_ms, c.orange_v, n_frames, 1, ...
    camera_rows=roi(4));
n_triggers = hadamard_stim.waveform.rising_edges(waveform, "dmdTrigger");
spec = hadamard_stim.protocol.acquisition_spec("queue_check", "firefly_slide_queue_check", ...
    waveform, camera_exposure_ms=c.camera_exposure_ms);
acq = rig.acquire(spec);
if isempty(options.frame_means)
    mov = hadamard_stim.luminos.read_frames(acq.imaging.file, acq.imaging.frame_size);
    means = squeeze(mean(double(mov), [1 2]));
else
    means = options.frame_means(acq);
end
means = reshape(double(means), 1, []);

% What each trigger should bring up, as one picture number 1..5 (0: dry).
shown = hadamard_stim.protocol.alp_queue_display(pictures, repeats, n_frames);
offset = [0 cumsum(pictures(1:end-1))];
expected = zeros(1, n_frames);
live = shown.sequence > 0;
expected(live) = offset(shown.sequence(live)) + shown.picture(live);

% Brightness against picture over the frames the queue should fill; then
% each frame to the nearest level (0 = dark).
fit = polyfit(expected(live), means(live), 1);
levels = polyval(fit, 0:n_distinct);
[~, nearest] = min(abs(means(:) - levels), [], 2);
classified = reshape(nearest - 1, 1, []);
step = fit(1);
noise = std(means(live) - polyval(fit, expected(live)));
clear_steps = step > 0 && step > 5 * max(noise, eps);
matches = classified(live) == expected(live);
passed = numel(means) == n_frames && n_triggers == n_frames && all(matches) && clear_steps;

after = classified(~live);
if all(after == 0)
    dry = "dark";
elseif all(after == after(1))
    dry = sprintf("held picture %d", after(1));
else
    dry = "pictures " + strjoin(string(after), ", ");
end
evidence = sprintf(['Queue of %s pictures x %s repeats, %s edge: %d of %d triggers showed the ' ...
    'predicted picture; brightness step %.3g counts, %.1f x the noise. After running dry ' ...
    '(%d more triggers): %s.'], mat2str(pictures), mat2str(repeats), edge, nnz(matches), ...
    capacity, step, step / max(noise, eps), n_dry, dry);
if n_triggers ~= n_frames
    evidence = evidence + sprintf(" The waveform had %d DMD triggers for %d frames.", n_triggers, n_frames);
end
details = struct("trigger_edge", edge, "pictures", pictures, "repeats", repeats, ...
    "n_frames", n_frames, "expected", expected, "classified", classified, ...
    "means", means, "fit", fit, "noise", noise, "after_dry", dry, ...
    "luminos_folder", string(acq.luminos_folder));
result = hadamard_stim.checks.check_result("slide_queue", passed, evidence, details, ...
    hadamard_stim.checks.check_provenance(app, profile));
end
