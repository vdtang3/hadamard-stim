function report = preflight(app, cfg, options)
%PREFLIGHT Whether this rig can run cfg, checked without changing anything.
%
%   report = hadamard_stim.luminos.preflight(app, cfg, blue_threshold=..., profile=...)
%
%   report.ok        no failures
%   report.failures  one sentence per problem, saying what to do about it
%   report.checks    every requirement, failed or not: id, label, status
%                    ("pass", "fail" or "not_needed") and message (the
%                    failures that belong to it, joined)
%   report.devices   the resolved devices (resolve_hardware)
%
%   Nothing is written to any device, and the protocol state is not
%   touched: every check reads a property or calls an inquiry method.
%   LuminosRig.begin runs it before any hardware is used.
arguments
    app
    cfg struct
    options.blue_threshold = []
    options.profile struct = hadamard_stim.luminos.firefly_profile()
end
profile = options.profile;
failures = strings(0, 1);
checks = struct("id", {}, "label", {}, "status", {}, "message", {});
current = 0;
    function requirement(id, label)
        checks(end+1) = struct("id", id, "label", label, "status", "pass", "message", "");
        current = numel(checks);
    end
    function fail(varargin)
        failures(end+1, 1) = string(sprintf(varargin{:}));
        checks(current).status = "fail";
        checks(current).message = strjoin([checks(current).message failures(end)], " ");
        checks(current).message = strip(checks(current).message);
    end

% The rig and the app.
requirement("rig", "Luminos is running the " + profile.rig_name + " rig");
if string(read(app, "rigName", "")) ~= profile.rig_name
    fail("This Luminos session is the %s rig, not %s.", string(read(app, "rigName", "unknown")), profile.rig_name);
end
requirement("luminos_idle", "Luminos is not acquiring");
if isequal(read(app, "acquisition_active", false), true)
    fail("Luminos is in the middle of an acquisition; wait for it to finish or abort it.");
end

% The devices this configuration needs.
[devices, missing] = hadamard_stim.luminos.resolve_hardware(app, profile);
needs_stage = cfg.z_reference.enabled || cfg.drift.enabled;
for role = string(fieldnames(profile.devices))'
    requirement("device_" + role, profile.devices.(role).name + " is available");
    for m = missing(string([missing.role]) == role)
        if role == "stage" && ~needs_stage
            checks(current).status = "not_needed";
            checks(current).message = "Not needed: z-reference and drift correction are off.";
            continue
        end
        fail("%s", m.message);
    end
end

% DMD: queue support, ownership, canvas, polarity.
dmd = devices.dmd;
if ~isempty(dmd)
    requirement("dmd_queue", "The DMD supports the sequence queue");
    if ~call(@() dmd.Supports_Sequence_Queue(), false)
        fail("%s does not report sequence-queue support (Supports_Sequence_Queue), which his stimulation trials need.", dmd.name);
    end
    requirement("dmd_ownership", "The DMD can be claimed for hadamard_stim");
    owner = string(read(dmd, "pattern_owner", ""));
    if strlength(owner) > 0 && owner ~= profile.owner
        fail("%s is owned by ""%s""; stop that before starting.", dmd.name, owner);
    end
    requirement("dmd_canvas", "The DMD canvas matches his masks");
    canvas = call(@() dmd.Pattern_Canvas_Size(), []);
    if ~isequal(canvas, fliplr(cfg.dmd.size))
        fail("%s has a %s canvas; his masks need %d x %d (rows x columns).", dmd.name, ...
            mat2str(canvas), cfg.dmd.size(2), cfg.dmd.size(1));
    end
    requirement("dmd_polarity", "The DMD output is not inverted");
    if isequal(read(dmd, "invert_output", false), true)
        fail("%s has invert_output set; his loader sent masks uninverted.", dmd.name);
    end
end

% DAQ: his rate on the DAQ's own clock, and no other outputs scheduled.
daq = devices.daq;
if ~isempty(daq)
    requirement("daq_rate", "The DAQ runs at his 100 kHz on its own clock");
    gp = read(daq, "global_props", []);
    if ~isstruct(gp) || ~isfield(gp, "rate")
        fail("%s has no waveform settings (global_props); open the Waveforms tab once.", daq.name);
    elseif double(gp.rate) ~= cfg.daq.rate || cfg.daq.rate ~= profile.daq_rate
        fail("The DAQ rate is %g Hz; his waveforms are %g Hz samples. Set it in the Waveforms tab.", ...
            double(gp.rate), cfg.daq.rate);
    end
    if isstruct(gp) && isfield(gp, "clock_source") && ~isempty(gp.clock_source) ...
            && ~contains(string(gp.clock_source), "Internal", "IgnoreCase", true)
        fail("The DAQ is clocked from %s; his waveforms need the DAQ's own clock.", string(gp.clock_source));
    end
    if ~isempty(read(daq, "external_clock_rate", []))
        fail("The DAQ has an external clock rate override; clear the camera clock in the Waveforms tab.");
    end
    requirement("daq_outputs", "No other waveforms are scheduled on the DAQ");
    wf = read(daq, "wfm_data", struct());
    for kind = ["ao" "do"]
        if ~isstruct(wf) || ~isfield(wf, kind)
            continue
        end
        for r = reshape(wf.(kind), 1, [])
            owner = "";
            if isfield(r, "script_owner")
                owner = string(r.script_owner);
            end
            % camera_trigger records are Luminos's own, dropped by every acquisition.
            if ismember(owner, [profile.owner "camera_trigger"])
                continue
            end
            fail("The DAQ already drives %s (""%s""); clear it from the Waveforms tab, because his protocol owns every output during a run.", ...
                string(r.port), string(r.name));
        end
    end
end

% Cameras.
camera = devices.camera;
if ~isempty(camera)
    requirement("camera_settings", camera.name + " records raw, unbinned frames");
    if string(read(camera, "compression_method", "None")) ~= "None"
        fail("%s records with %s compression; set it to None (the adapter reads raw frames).", ...
            camera.name, string(camera.compression_method));
    end
    if double(read(camera, "bin", 1)) ~= 1
        fail("%s is binned %g x; his scans and segmentation used 1 x 1.", camera.name, double(camera.bin));
    end
end

% Calibrations: the active ones, as a run would resolve them.
if ~isempty(devices.blue_modulator)
    requirement("blue_calibration", "The active blue calibration is valid");
    try
        hadamard_stim.luminos.active_blue_calibration(devices.blue_modulator, options.blue_threshold);
    catch err
        fail("%s", err.message);
    end
end
if ~isempty(dmd) && ~isempty(camera)
    requirement("dmd_calibration", "The DMD calibration for " + camera.name + " is valid");
    try
        hadamard_stim.luminos.active_geometry(dmd, camera);
    catch err
        fail("%s", err.message);
    end
end

report.ok = isempty(failures);
report.failures = failures;
report.checks = checks;
report.devices = devices;
end

function v = read(object, name, default)
% A property, or default when the object does not have it.
v = default;
try
    if isprop(object, name) || (isstruct(object) && isfield(object, name))
        v = object.(name);
    end
catch
end
end

function v = call(fn, default)
v = default;
try
    v = fn();
catch
end
end
