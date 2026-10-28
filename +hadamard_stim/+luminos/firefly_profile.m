function profile = firefly_profile()
%FIREFLY_PROFILE What the adapter needs to know about Firefly, and nothing else.
%
%   profile = hadamard_stim.luminos.firefly_profile()
%
%   Every Firefly-specific fact the adapter relies on is here, so none of
%   them leaks into +protocol or +yitong. Device names are the ones in
%   Luminos src/Applications/Firefly/Firefly.json (f5b464d93).
%
%   The channels are Yitong's dragonflySettings.m map (tests/yitong_reference/
%   dragonfly/Settings), in the order of cfg.daq.channels, which is also
%   the order of the waveform rows. Firefly is still wired the same way;
%   some of his ports now carry other Luminos devices (now_used_by). Rows
%   that are zero throughout an acquisition are not driven at all (see
%   daq_records), which is what keeps the adapter off those ports.
profile.rig_name = "Firefly";
profile.owner = "hadamard_stim";

profile.devices.daq = struct("type", "DAQ", "name", "DAQ_Session");
profile.devices.dmd = struct("type", "ALP_DMD", "name", "DMD (shared)");
profile.devices.camera = struct("type", "Camera", "name", "Teledyne Kinetix");
profile.devices.behavior_camera = struct("type", "Camera", "name", "Grasshopper3");
profile.devices.stage = struct("type", "Newport_Motor_Controller", "name", "NewportTRB25CC");
profile.devices.blue_modulator = struct("type", "NI_DAQ_Modulator", "name", "Blue LED 488");
% The orange LED on Dev1/ao0 (his orangeIntensity row). Not a device a run
% needs (the protocol drives ao0 in its waveforms); only the orange preview
% sets it, as a static level, through Luminos's own modulator (the Main
% tab's toggles use the same on-demand write). Its level is volts: Firefly
% gives it no calibration, so it is the waveform's orange_v.
profile.orange_modulator = struct("type", "NI_DAQ_Modulator", "name", "Red LED 615");

% Which waveform rows trigger which camera.
profile.camera_trigger_row = "cameraTrigger";
profile.behavior_trigger_row = "grashopperTrigger";
% Rows that only serve the face camera: its trigger and the 850 nm light.
% With the face camera off they are not driven (the protocol's samples
% are unchanged).
profile.face_camera_rows = ["grashopperTrigger" "IRVoltage"];

% The wheel encoder's A and B lines, sampled as buffered digital inputs on
% the acquisition clock (wfm_data.di), as his DAQ sampled them into
% DAQ_data. His dragonflySettings.m wiring; whether Firefly is still wired
% this way is a Firefly check. The rig setting wheel_encoder_lines
% overrides it.
profile.wheel_encoder = struct("names", ["encoderA" "encoderB"], ...
    "lines", ["Dev1/port0/line9" "Dev1/port0/line10"], ...
    "source", "Yitong's dragonflySettings.m (encoderA, encoderB); not yet checked on Firefly");

profile.daq_rate = 1e5;            % his DAQ ran on its own clock at 100 kHz
% The clock every Hadamard acquisition sets (and restores afterwards):
% the DAQ's own, whatever the Waveforms tab or the rig file chose.
profile.daq_clock_source = "Internal Dev1";

% Luminos's DMD code: the ALP class and its MEX. A slide queue check stays
% evidence across Luminos commits that leave these unchanged
% (dmd_code_changed, hardware_gate).
profile.luminos_dmd_paths = "src/Devices/Patterning/DMD/ALP";

channel = @(name, port, kind, now_used_by) struct("name", name, "port", port, ...
    "kind", kind, "now_used_by", now_used_by);
profile.channels = [
    channel("cameraTrigger",     "Dev1/port0/line26", "do", "Teledyne Kinetix trigger")
    channel("grashopperTrigger", "Dev1/port0/line0",  "do", "Grasshopper3 trigger")
    channel("dmdTrigger",        "Dev1/port0/line8",  "do", "DMD (shared) trigger")
    channel("blueIntensity",     "Dev1/ao2",          "ao", "Blue LED 488")
    channel("orangeIntensity",   "Dev1/ao0",          "ao", "Red LED 615")
    channel("redShutter",        "Dev1/port0/line22", "do", "")
    channel("limeShutter",       "Dev1/port0/line23", "do", "shutter405")
    channel("blueShutter",       "Dev1/port0/line28", "do", "")
    channel("piezoTrigger",      "Dev1/ao1",          "ao", "Heater Set Out")
    channel("IRVoltage",         "Dev1/ao3",          "ao", "")
    channel("magnetPTrigger",    "Dev1/port0/line27", "do", "Whisker Stim Trigger +")
    channel("magnetNTrigger",    "Dev1/port0/line14", "do", "Whisker Stim Trigger -")
    ];

% Always different from his rig when this adapter runs; recorded in every
% recipe (build_recipe, context.standing_deviations).
profile.standing_deviations = [
    "Blue linearisation uses the active Luminos calibration of ""Blue LED 488"", not his blueCal.mat; the intensity threshold is the configured blue_threshold (parity issue P2)."
    "Masks are projected through the Luminos DMD calibration for the Teledyne Kinetix, not his affine registration and correction transform."
    "Waveform rows that are zero throughout an acquisition are not driven; his DAQ held them at 0 V. On Firefly some of those ports now belong to other devices (Heater Set Out, shutter405, Whisker Stim)."
    "Luminos ends every driven port at 0, so IRVoltage drops from 0.5 V to 0 V on the last sample and stays there between acquisitions."
    "The behaviour camera is recorded by Luminos in the same acquisition, triggered by his grashopperTrigger line, instead of by SpinView."
    "The wheel encoder's A/B lines are recorded by Luminos as buffered digital inputs on the acquisition clock (output_data.mat), not in his settings.mat DAQ_data; his analogIn1 (ai0, unconnected in his data) is not recorded."
    "DMD queue trigger edge is explicitly set to rising (cfg.dmd.trigger_edge); Yitong's original loader inherited the board's existing edge. Scan pattern stacks are also stepped on the rising edge (Luminos Write_Stack)."
    "Stage moves go through the Newport controller, including its backlash correction on downward moves."
    "Luminos records every camera on the rig; cameras the protocol does not use take one free-running frame."
    ];
end
