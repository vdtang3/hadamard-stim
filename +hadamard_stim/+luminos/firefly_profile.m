function profile = firefly_profile(camera_name)
%FIREFLY_PROFILE What the adapter needs to know about Firefly, and nothing else.
%
%   profile = hadamard_stim.luminos.firefly_profile()
%   profile = hadamard_stim.luminos.firefly_profile(camera_name)
%
%   camera_name is the imaging camera's Luminos device name; by default
%   "Teledyne Kinetix", the camera Yitong's experiment was built on. Another
%   camera (Firefly's Tucsen "Libra 5514 Pro") changes which camera's Snaps
%   and DMD calibration are accepted, and nothing else: its dark offsets are
%   unmeasured, so camera_format gives its modes none and preflight refuses
%   scans with it until they are added to camera_offsets.
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
arguments
    camera_name (1, 1) string = "Teledyne Kinetix"
end
profile.rig_name = "Firefly";
profile.owner = "hadamard_stim";

profile.devices.daq = struct("type", "DAQ", "name", "DAQ_Session");
profile.devices.dmd = struct("type", "ALP_DMD", "name", "DMD (shared)");
profile.devices.camera = struct("type", "Camera", "name", camera_name);
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

% The Kinetix's dark offset in each readout mode, in that mode's counts:
% what the calibration, its QC and the scan reconstructions subtract
% (camera_format f.offset). Keyed by the mode as Luminos reports it
% (Camera.bit_mode_id and bit_mode_label, both must match), not by bit
% depth: another mode at the same depth may sit elsewhere. A 16-bit mode
% not listed takes his 100 (every recording he reconstructed was 16-bit);
% an 8-bit mode not listed has no offset, and preflight refuses it.
% Only Yitong's camera takes his 100 for a 16-bit mode not listed
% (camera_format); any other camera's unlisted modes have no offset.
profile.unlisted_16bit_offset_camera = "Teledyne Kinetix";
offset = @(id, label, bits, counts, source) struct("mode_id", id, "mode_label", label, ...
    "storage_bits", bits, "offset", counts, "source", source);
profile.camera_offsets = [
    offset("p2_s0_g1", "16-bit Standard (Dynamic Range Mode)", 16, 100, ...
        "Yitong's 100, subtracted by every reconstruction of his (16-bit parity)")
    offset("p1_s0_g1", "8-bit High Full Well (Speed Mode)", 8, 20, ...
        "Measured: Firefly Kinetix dark frames, median 20 (18-24), Yi-Chieh Huang's 20260619_8bit_test (notebook 2026-11-02)")
    ];

% Luminos's DMD code: the ALP class and its MEX. A slide queue check stays
% evidence across Luminos commits that leave these unchanged
% (dmd_code_changed, hardware_gate).
profile.luminos_dmd_paths = "src/Devices/Patterning/DMD/ALP";

channel = @(name, port, kind, now_used_by) struct("name", name, "port", port, ...
    "kind", kind, "now_used_by", now_used_by);
profile.channels = [
    channel("cameraTrigger",     "Dev1/port0/line26", "do", camera_name + " trigger")
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
    "Masks are projected through the Luminos DMD calibration for the " + camera_name + ", not his affine registration and correction transform."
    "Waveform rows that are zero throughout an acquisition are not driven; his DAQ held them at 0 V. On Firefly some of those ports now belong to other devices (Heater Set Out, shutter405, Whisker Stim)."
    "Luminos ends every driven port at 0, so IRVoltage drops from 0.5 V to 0 V on the last sample and stays there between acquisitions."
    "The behaviour camera is recorded by Luminos in the same acquisition, triggered by his grashopperTrigger line, instead of by SpinView."
    "The wheel encoder's A/B lines are recorded by Luminos as buffered digital inputs on the acquisition clock (output_data.mat), not in his settings.mat DAQ_data; his analogIn1 (ai0, unconnected in his data) is not recorded."
    "DMD queue trigger edge is explicitly set to rising (cfg.dmd.trigger_edge); Yitong's original loader inherited the board's existing edge. Scan pattern stacks are also stepped on the rising edge (Luminos Write_Stack)."
    "Stage moves go through the Newport controller, including its backlash correction on downward moves."
    "Luminos records every camera on the rig; cameras the protocol does not use take one free-running frame."
    ];
% Recorded only when the imaging camera is in that kind of mode
% (make_environment adds it to context.standing_deviations).
profile.eight_bit_deviation = ...
    "8-bit camera mode: the calibration, its QC and the scan reconstructions subtract the mode's measured dark offset (camera_offsets) in double, without clipping at 0; his code subtracted 100 in the movie's integer class (uint16), which clips. 16-bit modes are unchanged.";
end
