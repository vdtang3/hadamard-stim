function [c, app, cfg, inputs] = tab_session(folder, options)
%TAB_SESSION A controller as the Luminos tab makes it, on a fake Firefly.
%
%   [c, app, cfg, inputs] = tab_session(folder, validated=true)
%
%   A HadamardStimController on a LuminosBackend (the Hadamard_Stim
%   device's construction) over hadamard_stim.testing.make_fake_luminos,
%   with his blue curve. The backend's settings carry blue_threshold 15
%   and a hardware validation file in folder recording the two DMD
%   commissioning checks (passed when validated), recorded today with provenance that
%   names no commit (so none is compared). The configuration is the parity one;
%   nothing has been sent to the controller yet. Scans reconstruct from
%   synthetic calibration movies until use_parity_scans is called after
%   prepare_rig.
arguments
    folder (1, 1) string
    options.validated (1, 1) logical = true
end
if ~isfolder(folder)
    mkdir(folder);
end
[app, cfg, inputs] = fake_firefly(folder);
validation_file = fullfile(folder, "firefly_checks.json");
check = struct("passed", options.validated, "evidence", "test", ...
    "date", string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
    "details", struct("trigger_edge", "rising"), ...
    "provenance", struct("hadamard_stim_commit", "unknown", "luminos_commit", "unknown", "dmd_serial", "unknown"));
write_text(validation_file, jsonencode(struct("queue_support", check, "slide_queue", check)));
rng(3, "twister");
calibration = uint16(100 + randi(500, 16, 600, 64));
backend = hadamard_stim.luminos.LuminosBackend(app, blue_threshold=15, ...
    hardware_validation_file=validation_file, calibration_movies={calibration}, ...
    acquisition_function=@hadamard_stim.testing.fake_luminos_acquisition);
c = hadamard_stim.HadamardStimController(backend);
end

function write_text(file, text)
fid = fopen(file, "w");
fwrite(fid, text);
fclose(fid);
end
