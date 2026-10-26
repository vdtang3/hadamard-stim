function result = fake_slide_calibration(app, modulator_name, options)
%FAKE_SLIDE_CALIBRATION Stands in for Luminos's Calibrate_Modulator_On_Slide.
%
%   result = fake_slide_calibration(app, modulator_name, camera=name)
%
%   Records on the fake modulator what the Luminos routine would: Yitong's
%   blueCal.mat curve as camera counts above the LED-off level, with the
%   calibration_info Measure_Modulator_On_Slide writes. iscalibrated is
%   left as it was, as Luminos leaves it.
arguments
    app
    modulator_name (1, 1) string
    options.camera (1, 1) string = ""
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
blue = load(fullfile(root, "tests", "yitong_reference", "dragonfly", "Utilities", "blueCal.mat"));
modulator = app.getDevice("Modulator_Device", "name", modulator_name);
curve = [blue.vBlue(:)'; blue.blueIntensC(:)'];
info = struct("method", "camera_on_slide", ...
    "units", "camera counts: mean of a full frame minus the mean with the source off", ...
    "camera", options.camera, "measured_utc", ...
    string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'")));
modulator.Set_Calibration(curve, info);
result = struct("curve", curve, "info", info);
end
