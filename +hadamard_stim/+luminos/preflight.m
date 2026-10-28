function report = preflight(app, cfg, options)
%PREFLIGHT Whether this rig can run cfg, checked without changing anything.
%
%   report = hadamard_stim.luminos.preflight(app, cfg, blue_threshold=..., ...
%       profile=..., wheel_encoder_lines=..., purpose=..., now=...)
%
%   A readiness report (hadamard_stim.metadata.readiness_report):
%   report.can_run   no blockers
%   report.checks    every requirement, one readiness_item each: id,
%                    label, status (pass / info / warning / blocker /
%                    disabled / not_needed), message, consequence
%   report.blockers, report.warnings, report.info   the items of each kind
%   report.failures  the blockers' messages, for an error naming them all
%   report.devices   the resolved devices (resolve_hardware)
%
%   Blockers are kept for what cannot be done or would fight another owner
%   of the hardware: Luminos busy or on another rig, a device missing, the
%   DMD not open, owned by someone else, of another size, inverted, or
%   without the sequence queue a connectivity session needs, a DAQ output
%   the protocol drives already scheduled by someone else, a camera file
%   the package cannot read, no blue calibration to compute a command
%   from, no camera-to-DMD transform. What only differs from Yitong's rig
%   (another DAQ clock, binning, a DMD calibration taken at another camera
%   area) is a warning: it is said, with what it means for the data, and a
%   run may go ahead once the operator chooses to. When a calibration was
%   taken is shown and never judged: age alone is not a warning.
%
%   Only what the configuration asks for is required. Always: the imaging
%   camera, the DAQ, the DMD and its calibration. A connectivity session
%   also needs the DMD's sequence queue, the blue LED and its calibration.
%   The stage, when the session takes a z-stack or drift-corrects. The face
%   camera and the wheel encoder only when enabled; when not, their checks
%   say "disabled" and nothing about them is read.
%
%   purpose "calibration_scan" (acquire_calibration_scans, on a slide)
%   needs only the DAQ, the DMD and the imaging camera: no stage, no blue
%   LED, no DMD calibration (the scan covers the whole DMD), no streams.
%
%   Nothing is written to any device, and the protocol state is not
%   touched: every check reads a property or calls an inquiry method.
%   LuminosRig.begin runs it before any hardware is used.
arguments
    app
    cfg struct
    options.blue_threshold = []
    options.profile struct = hadamard_stim.luminos.firefly_profile()
    options.wheel_encoder_lines string = strings(1, 0)
    options.purpose (1, 1) string {mustBeMember(options.purpose, ["run" "calibration_scan"])} = "run"
    options.now (1, 1) datetime = datetime("now", "TimeZone", "UTC")
end
profile = options.profile;
calibrating = options.purpose == "calibration_scan";
lines = options.wheel_encoder_lines;
if isempty(lines)
    lines = profile.wheel_encoder.lines;
end
spontaneous = hadamard_stim.metadata.session_mode(cfg) == "spontaneous";
face_camera = ~calibrating && (~isfield(cfg, "behavior") || isequal(cfg.behavior.face_camera_enabled, true));
encoder = ~calibrating && isfield(cfg, "behavior") && isequal(cfg.behavior.wheel_encoder_enabled, true);
no_blue = spontaneous || calibrating;
checks = hadamard_stim.metadata.readiness_report(struct([])).checks;
current = 0;
RANK = struct("pass", 0, "info", 1, "warning", 2, "blocker", 3);
    function requirement(id, label, group)
        if nargin < 3
            group = "rig";
        end
        checks(end+1) = hadamard_stim.metadata.readiness_item(id, label, "pass", group=group);
        current = numel(checks);
    end
    function found(status, message, consequence)
        % Add what was found to the current requirement; its status is the
        % worst found.
        if nargin < 3
            consequence = "";
        end
        c = checks(current);
        if ismember(c.status, ["pass" "info" "warning" "blocker"]) && RANK.(status) > RANK.(c.status)
            c = hadamard_stim.metadata.readiness_item(c.id, c.label, status, group=c.group, ...
                message=c.message, consequence=c.consequence, details=c.details);
        end
        c.message = strip(strjoin([c.message string(message)], " "));
        c.consequence = strip(strjoin([c.consequence string(consequence)], " "));
        checks(current) = c;
    end
    function block(varargin)
        found("blocker", sprintf(varargin{:}));
    end
    function set_status(status, message)
        c = checks(current);
        checks(current) = hadamard_stim.metadata.readiness_item(c.id, c.label, status, ...
            group=c.group, message=message);
    end

% The rig and the app.
requirement("rig", "Luminos is running the " + profile.rig_name + " rig");
if string(read(app, "rigName", "")) ~= profile.rig_name
    found("blocker", sprintf("This Luminos session is the %s rig, not %s.", ...
        string(read(app, "rigName", "unknown")), profile.rig_name), ...
        "The protocol's outputs are Firefly's wiring; on another rig they would drive whatever is connected there.");
end
requirement("luminos_idle", "Luminos is not acquiring");
if isequal(read(app, "acquisition_active", false), true)
    block("Luminos is in the middle of an acquisition; wait for it to finish or abort it.");
end

% The devices this configuration needs.
[devices, missing] = hadamard_stim.luminos.resolve_hardware(app, profile);
if calibrating
    needs_stage = false;
    stage_reason = "Not needed: calibration scans do not move the stage.";
elseif spontaneous
    needs_stage = isequal(cfg.spontaneous.drift_correction, true);
    stage_reason = "Not needed: drift correction between blocks is off.";
else
    needs_stage = cfg.z_reference.enabled || cfg.drift.enabled;
    stage_reason = "Not needed: z-reference and drift correction are off.";
end
for role = string(fieldnames(profile.devices))'
    requirement("device_" + role, profile.devices.(role).name + " is available");
    if role == "behavior_camera" && ~face_camera
        message = "The face camera is off in the configuration.";
        if calibrating
            message = "Not recorded during calibration scans.";
        end
        set_status("disabled", message);
        continue
    end
    if role == "blue_modulator" && no_blue
        set_status("not_needed", "Not needed: no blue light is used.");
        continue
    end
    for m = missing(string([missing.role]) == role)
        if role == "stage" && ~needs_stage
            set_status("not_needed", stage_reason);
            continue
        end
        block("%s", m.message);
    end
end

% DMD: the board open, queue support, ownership, canvas, polarity.
dmd = devices.dmd;
if ~isempty(dmd)
    requirement("dmd_board", "Luminos has the DMD board open");
    if ~board_open(dmd)
        found("blocker", sprintf(['%s has no open board (debug mode, or the driver did not open it ' ...
            'when Luminos started).'], dmd.name), "Nothing can be projected: restart Luminos with the board connected.");
    end
    requirement("dmd_queue", "The DMD supports the sequence queue");
    if spontaneous || calibrating
        set_status("not_needed", "Not needed: no stimulation queue is loaded.");
    elseif ~call(@() dmd.Supports_Sequence_Queue(), false)
        found("blocker", sprintf("%s reports no sequence-queue support (Supports_Sequence_Queue is false).", dmd.name), ...
            "Every stimulation trial loads a sequence queue; this driver cannot play one.");
    else
        found("pass", "Supported (live Supports_Sequence_Queue).");
    end
    requirement("dmd_ownership", "The DMD can be claimed for hadamard_stim");
    owner = string(read(dmd, "pattern_owner", ""));
    if strlength(owner) > 0 && owner ~= profile.owner
        found("blocker", sprintf("%s is owned by ""%s"".", dmd.name, owner), ...
            "Two owners would overwrite each other's patterns; stop that owner first.");
    end
    requirement("dmd_canvas", "The DMD canvas matches his masks");
    canvas = call(@() dmd.Pattern_Canvas_Size(), []);
    if ~isequal(canvas, fliplr(cfg.dmd.size))
        block("%s has a %s canvas; his masks need %d x %d (rows x columns).", dmd.name, ...
            mat2str(canvas), cfg.dmd.size(2), cfg.dmd.size(1));
    end
    requirement("dmd_polarity", "The DMD output is not inverted");
    if isequal(read(dmd, "invert_output", false), true)
        found("blocker", sprintf("%s has invert_output set.", dmd.name), ...
            "Every mask would be projected inverted: blue light on everything except the chosen cells.");
    end
end

% DAQ: its waveform settings, its clock, and no conflicting outputs.
daq = devices.daq;
if ~isempty(daq)
    % Hadamard Stim sets the rate, its own clock (profile.daq_clock_source),
    % self-triggering and the duration for each acquisition and restores
    % the DAQ afterwards (LuminosRig.acquire), so no Waveforms tab setup is
    % needed and what the tab holds is only noted.
    requirement("daq_rate", "The DAQ plays the protocol's samples at their rate");
    gp = read(daq, "global_props", []);
    if ~isstruct(gp) || isempty(gp)
        if ~ismethod(daq, "Default_Global_Props")
            block(['%s has no waveform settings, and this Luminos build has no ' ...
                'DAQ.Default_Global_Props to start from; update Luminos.'], daq.name);
        else
            found("pass", sprintf(['No Waveforms-tab settings: each acquisition installs %g Hz on ' ...
                '%s itself.'], cfg.daq.rate, profile.daq_clock_source));
        end
    else
        found("pass", sprintf("Each acquisition sets %g Hz on %s and restores the DAQ afterwards.", ...
            cfg.daq.rate, profile.daq_clock_source));
        if isfield(gp, "rate") && double(gp.rate) ~= cfg.daq.rate
            found("info", sprintf("The Waveforms tab is at %g Hz; it is put back after each acquisition.", ...
                double(gp.rate)));
        end
        if isfield(gp, "clock_source") && ~isempty(gp.clock_source) ...
                && string(gp.clock_source) ~= profile.daq_clock_source
            found("info", sprintf(['The Waveforms tab clocks the DAQ from %s; Hadamard acquisitions ' ...
                'use %s and put %s back afterwards.'], string(gp.clock_source), ...
                profile.daq_clock_source, string(gp.clock_source)));
        end
    end
    if ~isempty(read(daq, "external_clock_rate", []))
        found("info", sprintf(['The DAQ has an external clock rate override (%g Hz); Hadamard ' ...
            'acquisitions clear it and put it back afterwards.'], double(read(daq, "external_clock_rate", NaN))));
    end
    requirement("daq_outputs", "No other waveform drives the protocol's outputs");
    ports = string({profile.channels.port});
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
            if ismember(string(r.port), ports)
                found("blocker", sprintf("The Waveforms tab already drives %s (""%s""), one of the protocol's outputs.", ...
                    string(r.port), string(r.name)), ...
                    "Two waveforms cannot control one output; clear it from the Waveforms tab.");
            else
                found("warning", sprintf("The Waveforms tab schedules %s (""%s"").", string(r.port), string(r.name)), ...
                    "It will not play during Hadamard acquisitions: each one replaces the DAQ's output list and restores it afterwards.");
            end
        end
    end
end

% The wheel encoder: its lines are a rig setting; whether they are wired
% to the encoder can only be checked at the rig (a Firefly check).
requirement("wheel_encoder", "The wheel encoder's A/B lines can be recorded", "session");
if ~encoder
    set_status("disabled", "The wheel encoder is off in the configuration.");
else
    for problem = encoder_problems(lines, profile, daq)
        block("%s", problem);
    end
    if checks(current).status == "pass"
        checks(current).message = sprintf("A = %s, B = %s, sampled on the acquisition clock. %s.", ...
            lines(1), lines(2), profile.wheel_encoder.source);
    end
end

% A spontaneous block is one long acquisition; Luminos holds every driven
% row and recorded line for its whole length while it runs.
if spontaneous && ~calibrating
    requirement("block_memory", "One spontaneous block fits in memory");
    [need, detail] = hadamard_stim.luminos.block_memory(cfg, face_camera, encoder);
    available = available_memory();
    checks(current).message = sprintf("About %.1f GB while a block runs (%s).", need / 2^30, detail);
    if isfinite(available) && need > 0.8 * available
        found("blocker", sprintf("Only %.1f GB is free.", available / 2^30), ...
            "Running out of memory mid-acquisition can leave the rig's outputs in an unknown state; use shorter blocks (spontaneous.block_frames) or free memory.");
    elseif isfinite(available)
        checks(current).message = checks(current).message + sprintf(" %.1f GB free.", available / 2^30);
    end
end

% Cameras.
camera = devices.camera;
if ~isempty(camera)
    requirement("camera_settings", camera.name + " records raw, unbinned, 16-bit frames");
    if string(read(camera, "compression_method", "None")) ~= "None"
        found("blocker", sprintf("%s records with %s compression.", camera.name, string(camera.compression_method)), ...
            "The package reads raw frames; a compressed movie cannot be read or reconstructed. Set compression to None.");
    end
    storage = double(read(camera, "bit_depth", 16));
    if storage ~= 16
        found("blocker", sprintf("%s stores %g-bit frames (Bit Depth: %s).", camera.name, storage, ...
            string(read(camera, "bit_mode_label", "?"))), ...
            "The package reads 16-bit frames; another storage depth would be misread. Choose a 16-bit Bit Depth mode in the Camera tab.");
    end
    if double(read(camera, "bin", 1)) ~= 1
        found("warning", sprintf("%s is binned %g x.", camera.name, double(camera.bin)), ...
            "His scans and segmentation used 1 x 1 pixels: segmentation's cell-size settings and the scans assume unbinned pixels, so cells may be found differently.");
    end
end

% Calibrations: the active ones, as a run would resolve them. When each was
% taken is shown, never judged: a calibration warns only when it does not
% fit the current settings (calibration_age).
if ~isempty(devices.blue_modulator) && ~no_blue
    requirement("blue_calibration", "Blue LED calibration", "calibration");
    try
        calibration = hadamard_stim.luminos.active_blue_calibration(devices.blue_modulator, options.blue_threshold);
        describe_age(calibration_time(calibration.identity));
    catch err
        found("blocker", string(err.message), ...
            "Connectivity trials convert each requested blue intensity to an LED voltage through this calibration; without a usable one no blue command is defined.");
    end
end
if ~isempty(dmd) && ~isempty(camera) && ~calibrating
    requirement("dmd_calibration", "DMD calibration for " + camera.name, "calibration");
    try
        [geometry, mismatch] = hadamard_stim.luminos.active_geometry(dmd, camera);
        describe_age(parse_time(geometry.identity.measured_utc));
        if strlength(mismatch.message) > 0
            found("warning", mismatch.message, mismatch.consequence);
        end
    catch err
        found("blocker", string(err.message), ...
            "Targeted patterns are drawn in camera space and warped onto the DMD by this calibration; without it no mask can be placed on a cell.");
    end
end

report = hadamard_stim.metadata.readiness_report(checks);
report.devices = devices;

    function describe_age(when)
        % When it was taken, as text only: a usable calibration passes
        % whatever its age; only a misfit (found separately) changes that.
        age = hadamard_stim.metadata.calibration_age(when, options.now);
        c = checks(current);
        c.details = struct("measured_utc", age.taken_utc, "taken", age.taken, ...
            "ago", age.ago, "age_days", age.age_days);
        checks(current) = c;
        found("pass", age_text(age) + ".");
    end
end

function t = age_text(age)
% "Taken today (Oct 28, 2026)", "Taken Oct 19, 2026 (9 days ago) — reused",
% "Date not recorded".
t = age.text;
if ~age.today && ~isempty(age.age_days)
    t = t + " — reused";
end
end

function when = calibration_time(identity)
when = NaT("TimeZone", "UTC");
if isstruct(identity.recorded) && isfield(identity.recorded, "measured_utc")
    when = parse_time(identity.recorded.measured_utc);
end
end

function when = parse_time(value)
% A recorded time (ISO text or datetime); NaT when there is none.
when = NaT("TimeZone", "UTC");
try
    if isdatetime(value)
        when = value;
        if isempty(when.TimeZone)
            when.TimeZone = "UTC";
        end
    elseif (isstring(value) || ischar(value)) && strlength(string(value)) > 0
        when = datetime(string(value), "InputFormat", "yyyy-MM-dd'T'HH:mm:ss'Z'", "TimeZone", "UTC");
    end
catch
end
end

function tf = board_open(dmd)
% An ALP_DMD with no board open (debug mode, or the driver failed when
% Luminos started) has mexPointer 0; other DMD classes are taken as open.
tf = true;
try
    if isprop(dmd, "debug_mode") && ~isequal(dmd.debug_mode, 0)
        tf = false;
    end
    if isprop(dmd, "mexPointer") && isequal(dmd.mexPointer, 0)
        tf = false;
    end
catch
end
end

function problems = encoder_problems(lines, profile, daq)
% What stops the configured lines from being recorded as the encoder.
problems = strings(1, 0);
if numel(lines) ~= 2
    problems(end+1) = sprintf(['The wheel encoder needs two lines (A and B); the rig setting ' ...
        'wheel_encoder_lines has %d.'], numel(lines));
    return
end
bad = lines(~matches(lines, regexpPattern("^Dev\d+/port\d+/line\d+$")));
if ~isempty(bad)
    problems(end+1) = "These encoder lines are not digital lines (DevN/portN/lineN): " + strjoin(bad, ", ") + ".";
end
if lines(1) == lines(2)
    problems(end+1) = "Encoder A and B are both " + lines(1) + ".";
end
ports = string({profile.channels.port});
taken = intersect(lines, ports);
for line = taken
    k = find(ports == line, 1);
    problems(end+1) = sprintf("Encoder line %s is the %s output.", line, profile.channels(k).name); %#ok<AGROW>
end
if ~isempty(daq)
    wf = read(daq, "wfm_data", struct());
    if isstruct(wf) && isfield(wf, "di")
        for r = reshape(wf.di, 1, [])
            if ismember(string(r.port), lines)
                problems(end+1) = sprintf(['The Waveforms tab already records %s as "%s"; remove it there ' ...
                    'so the encoder can be recorded.'], string(r.port), string(r.name)); %#ok<AGROW>
            end
        end
    end
end
end

function bytes = available_memory()
% Free physical memory, where MATLAB can say (Windows); Inf elsewhere.
bytes = Inf;
try
    [~, system] = memory();
    bytes = system.PhysicalMemory.Available;
catch
end
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
