function app = make_fake_luminos(datafolder, options)
%MAKE_FAKE_LUMINOS A fake Firefly Luminos session for testing the adapter off the rig.
%
%   app = hadamard_stim.testing.make_fake_luminos(datafolder, z_start=6, blue_curve=[...])
%
%   Devices carry the names in Luminos's Firefly.json, so the adapter finds
%   them exactly as on the rig: DAQ_Session, Teledyne Kinetix, Grasshopper3,
%   Blackfly, DMD (shared), NewportTRB25CC, Blue LED 488 and Red LED 615. The blue
%   modulator is calibrated with blue_curve ([volts; power]) when one is
%   given. Acquisitions run through hadamard_stim.testing.fake_luminos_acquisition.
arguments
    datafolder (1, 1) string
    options.z_start (1, 1) double = 6
    options.blue_curve double = []
end
app = hadamard_stim.testing.FakeLuminosApp();
app.datafolder = datafolder;

kinetix = hadamard_stim.testing.FakeLuminosCamera("Teledyne Kinetix");
kinetix.trigger = "Dev1/port0/line26";
kinetix.cam_id = "\\0";
grasshopper = hadamard_stim.testing.FakeLuminosCamera("Grasshopper3");
grasshopper.type = 4;
grasshopper.trigger = "Dev1/port0/line0";
grasshopper.cam_id = "19395831";
grasshopper.ROI = [0 64 0 48];
blackfly = hadamard_stim.testing.FakeLuminosCamera("Blackfly");
blackfly.type = 4;
blackfly.trigger = "Dev1/port0/line31";
blackfly.cam_id = "26260993";
blackfly.ROI = [0 64 0 48];

blue = hadamard_stim.testing.FakeModulator("Blue LED 488");
if ~isempty(options.blue_curve)
    blue.iscalibrated = true;
    blue.calibration_curve = options.blue_curve;
end

% The orange LED as Firefly.json has it: Dev1/ao0, 0 to 4.5 V, uncalibrated.
orange = hadamard_stim.testing.FakeModulator("Red LED 615");
orange.port = "Dev1/ao0";
orange.max = 4.5;

devices = {hadamard_stim.testing.FakeLuminosDaq("DAQ_Session"), kinetix, grasshopper, blackfly, ...
    hadamard_stim.testing.FakeAlpDmd("DMD (shared)"), ...
    hadamard_stim.testing.FakeNewportStage("NewportTRB25CC", options.z_start), blue, orange};
for k = 1:numel(devices)
    devices{k}.App = app;
end
app.Devices = devices;
end
