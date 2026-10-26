function calibration = active_blue_calibration(modulator, blue_threshold)
%ACTIVE_BLUE_CALIBRATION The rig's current blue calibration, in the form the protocol uses.
%
%   calibration = hadamard_stim.luminos.active_blue_calibration(modulator, blue_threshold)
%
%   modulator       the Luminos Modulator_Device that drives the blue light
%                   ("Blue LED 488" on Firefly)
%   blue_threshold  calibration points with power at or below this (in the
%                   calibration's power units) are dropped; required, no
%                   default (parity issue P2, below)
%
%   Luminos's calibration of a modulator is its calibration_curve,
%   [command; output], together with either calibration_info (recorded by
%   Set_Calibration, e.g. Calibrate_Modulator_On_Slide: camera counts on a
%   uniform slide, Yitong's own method) or the iscalibrated flag. Luminos
%   keeps and saves it; there is no Hadamard calibration store, and
%   Yitong's blueCal.mat is used only by the parity tests. Refuses when the
%   modulator has no usable calibration.
%
%   Returns the fields linearize_blue_voltage reads, plus provenance:
%     v_blue          volts, row
%     blue_intens_c   power scaled by 15 / blue_threshold, column
%     identity        what was used (device, curve hash, threshold)
%     source, utc
%
%   P2. His linearize_blue_voltage drops points with intensity <= 15 in his
%   raw camera units, then normalises by the maximum. Scaling the power by
%   15 / blue_threshold leaves the normalised curve unchanged and turns
%   that test into "power <= blue_threshold", so the ported function runs
%   unmodified with the threshold the operator chose.
arguments
    modulator
    blue_threshold
end
name = string(modulator.name);
if isempty(blue_threshold) || ~isscalar(blue_threshold) || ~isfinite(blue_threshold) ...
        || blue_threshold <= 0
    error("hadamard_stim:BlueThresholdMissing", ...
        ['blue_threshold is not set. Yitong dropped blue calibration points at or ' ...
         'below 15 in his raw camera units, which mean nothing for the %s ' ...
         'calibration; choose the equivalent power level in that calibration''s ' ...
         'units and pass it (it is recorded as a deviation).'], name);
end
info = [];
if isprop(modulator, "calibration_info") || (isstruct(modulator) && isfield(modulator, "calibration_info"))
    info = modulator.calibration_info;
end
recorded = isstruct(info) && ~isempty(info);
if isempty(modulator.calibration_curve) || ~(recorded || isequal(modulator.iscalibrated, true))
    error("hadamard_stim:NoBlueCalibration", ...
        ['%s has no active calibration in Luminos. With a uniform slide under the objective, ' ...
         'use Calibrate blue LED (slide) in the Hadamard Stim tab, or ' ...
         'Calibrate_Modulator_On_Slide(app, "%s", camera=...), then start again.'], name, name);
end
curve = double(modulator.calibration_curve);
v = curve(1, :);
p = curve(2, :);
problems = strings(0, 1);
if size(curve, 1) ~= 2 || size(curve, 2) < 2
    problems(end+1) = "calibration_curve is not 2 x N";
elseif any(~isfinite(curve(:)))
    problems(end+1) = "calibration_curve has non-finite values";
else
    if min(v) < double(modulator.min) || max(v) > double(modulator.max)
        problems(end+1) = sprintf("its volts leave the modulator range %g to %g V", ...
            modulator.min, modulator.max);
    end
    if ~any(p > blue_threshold)
        problems(end+1) = sprintf("no point has power above blue_threshold (%g)", blue_threshold);
    end
end
if ~isempty(problems)
    error("hadamard_stim:BlueCalibrationUnusable", ...
        "The %s calibration cannot be used: %s. Recalibrate it in Luminos.", ...
        name, strjoin(problems, "; "));
end

calibration.v_blue = v;
calibration.blue_intens_c = p(:) * (15 / blue_threshold);

% Usable means his linearisation gives a voltage everywhere a protocol can
% ask for one (0 to 5 in his "linear" units).
try
    probe = hadamard_stim.yitong.linearize_blue_voltage(0:0.25:5, calibration);
    usable = all(isfinite(probe));
catch
    usable = false;
end
if ~usable
    error("hadamard_stim:BlueCalibrationUnusable", ...
        ['The %s calibration cannot be used: his linearisation does not give a ' ...
         'voltage over the whole 0 to 5 range with blue_threshold %g. Recalibrate it ' ...
         'in Luminos, or check blue_threshold.'], name, blue_threshold);
end
calibration.source = "luminos_modulator_calibration";
calibration.utc = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
calibration.identity = struct("source", calibration.source, "device", name, ...
    "device_class", string(class(modulator)), ...
    "curve_sha256", hadamard_stim.metadata.sha256(curve), "n_points", size(curve, 2), ...
    "volts_range", [v(1) v(end)], "blue_threshold", blue_threshold, ...
    "threshold_translation", "blue_intens_c = power * 15 / blue_threshold (P2)", ...
    "recorded", "not recorded (iscalibrated set by hand)", ...
    "resolved_utc", calibration.utc);
if recorded
    calibration.identity.recorded = struct("method", string(field_or(info, "method")), ...
        "units", string(field_or(info, "units")), ...
        "measured_utc", string(field_or(info, "measured_utc")), ...
        "camera", string(field_or(info, "camera")));
end
end

function v = field_or(s, name)
v = "";
if isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
end
end
