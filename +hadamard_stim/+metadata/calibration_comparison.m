function comparison = calibration_comparison(recipe, context)
%CALIBRATION_COMPARISON The calibrations a run recorded against the ones prepared now.
%
%   comparison = hadamard_stim.metadata.calibration_comparison(recipe, context)
%
%   recipe is the run's recipe (read_recipe); context is the prepared
%   environment's (env.context), or [] when nothing is prepared, in which
%   case nothing can be compared and every "matches" is [].
%
%   comparison.blue, .geometry   struct: matches (true/false/[]),
%                                recorded, current (the identities)
%   comparison.changed           true when either differs
%   comparison.imaging_format    the same for the imaging camera's
%                                storage format (camera_format: bit
%                                depth, mode); not a calibration, so not
%                                in changed: the caller refuses on it
%   comparison.consequence       what continuing on the current
%                                calibrations means for the run's data
%
%   The blue identity's resolved_utc is when Luminos was asked for the
%   calibration, not part of the calibration, so it is not compared. A
%   difference is a warning: resume continues on the current calibrations
%   when told to (resumeRun's ContinueWithChangedCalibration), and the
%   resume record says so.
comparison = struct("blue", side(recipe.calibrations.blue), ...
    "geometry", side(recipe.calibrations.geometry), "changed", false, ...
    "consequence", strings(1, 0), "imaging_format", side(recorded_format(recipe)));
if isempty(context) || ~isstruct(context)
    return
end
if isfield(context, "hardware") && isfield(context.hardware, "imaging_format")
    current = context.hardware.imaging_format;
    comparison.imaging_format.current = current;
    recorded = comparison.imaging_format.recorded;
    if isstruct(current) && isstruct(recorded)
        % What a legacy record does not know (NaN, "") is not compared.
        comparison.imaging_format.matches = recorded.storage_bits == current.storage_bits ...
            && (isnan(recorded.pixel_bits) || recorded.pixel_bits == current.pixel_bits) ...
            && (strlength(string(recorded.mode_id)) == 0 ...
                || string(recorded.mode_id) == string(current.mode_id));
    end
end
% A spontaneous session uses no blue light: its blue calibration is
% recorded but not compared.
spontaneous = isfield(recipe, "session_mode") && recipe.session_mode == "spontaneous";
if isfield(context, "blue_calibration") && ~spontaneous
    current = context.blue_calibration.identity;
    comparison.blue.current = current;
    comparison.blue.matches = isequal(jsonencode(comparable(recipe.calibrations.blue)), ...
        jsonencode(comparable(current, recipe.calibrations.blue)));
end
if isfield(context, "geometry_identity")
    current = context.geometry_identity;
    comparison.geometry.current = current;
    comparison.geometry.matches = isequal(jsonencode(recipe.calibrations.geometry), ...
        jsonencode(current));
end
if isequal(comparison.blue.matches, false)
    comparison.consequence(end+1) = ...
        "Blue: the resumed trials convert blue intensity to LED voltage with the " + ...
        "current calibration, so the same requested intensity may give a different " + ...
        "blue power than in the trials already recorded.";
end
if isequal(comparison.geometry.matches, false)
    comparison.consequence(end+1) = ...
        "DMD: the checkpoint's illumination masks were drawn with the recorded " + ...
        "camera-to-DMD calibration, while the stimulation spots (and the masks of any " + ...
        "later drift correction) are drawn with the current one, so cells may be " + ...
        "patterned at shifted DMD positions.";
end
comparison.changed = ~isempty(comparison.consequence);
end

function s = side(recorded)
s = struct("matches", [], "recorded", recorded, "current", []);
end

function identity = comparable(identity, recorded)
if isstruct(identity) && isfield(identity, "resolved_utc")
    identity = rmfield(identity, "resolved_utc");
end
% The camera mode a calibration was measured in is recorded since
% 2026-11-02; a run recorded before compares without it.
if nargin > 1 && isstruct(identity) && isfield(identity, "recorded") && isstruct(identity.recorded) ...
        && isstruct(recorded) && isfield(recorded, "recorded") && isstruct(recorded.recorded)
    added = setdiff(string(fieldnames(identity.recorded)), string(fieldnames(recorded.recorded)));
    identity.recorded = rmfield(identity.recorded, added);
end
end

function format = recorded_format(recipe)
% The run's imaging format; a run recorded before 8-bit support was 16-bit
% (preflight refused every other depth), with its mode not recorded.
format = [];
if isfield(recipe, "hardware") && isfield(recipe.hardware, "imaging_format")
    format = recipe.hardware.imaging_format;
elseif isfield(recipe, "hardware")
    format = struct("storage_bits", 16, "pixel_bits", NaN, "mode_id", "", ...
        "description", "raw 16-bit frames (uint16)", "mode_label", "not recorded");
end
end
