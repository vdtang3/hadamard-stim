function s = segmentation_settings(base, overrides)
%SEGMENTATION_SETTINGS The Hadamard Stim tab's segmentation settings, for manual_segment_dmd.
%
%   s = hadamard_stim.manual.segmentation_settings()                 the tab's defaults
%   s = hadamard_stim.manual.segmentation_settings(base, overrides)
%
%   The settings are cfg.segmentation, the struct the tab edits (its
%   "Segmentation" fields, hadamard_stim.ui.config_fields) and
%   protocol.segment_cells reads - one definition, so the tool and the tab
%   cannot drift apart. Defaults are default_config().segmentation (his).
%
%   base: a struct of segmentation settings, or a file - a .json written by
%   write_segmentation_settings, or a .mat holding "settings" or
%   "segmentation" (a manual_segment_dmd result, whose settings are reused).
%   overrides: struct of fields that win over base. Every field must be one
%   of cfg.segmentation's; values are checked by the tab's own rules
%   (protocol.segmentation_problems). n_exclude may stay unset here (the tab
%   asks for it too); segmenting refuses it unset.
arguments
    base = struct()
    overrides struct = struct()
end
s = hadamard_stim.default_config().segmentation;
names = string(fieldnames(s))';
if isstring(base) || ischar(base)
    base = read_file(string(base));
end
for source = {base, overrides}
    given = source{1};
    unknown = setdiff(string(fieldnames(given))', names);
    if ~isempty(unknown)
        error("hadamard_stim:SegmentationSettings", ...
            "Unknown segmentation setting(s): %s. The tab's are: %s.", strjoin(unknown, ", "), strjoin(names, ", "));
    end
    for name = string(fieldnames(given))'
        value = given.(name);
        if name == "select_all"
            value = logical(value);
        end
        s.(name) = value;
    end
end
problems = hadamard_stim.protocol.segmentation_problems(s);
if ~isempty(s.n_exclude) && ~(isnumeric(s.n_exclude) && isscalar(s.n_exclude) && isfinite(s.n_exclude) ...
        && s.n_exclude >= 0 && s.n_exclude == round(s.n_exclude))
    problems(end+1) = "segmentation.n_exclude must be a whole number, 0 or more.";
end
for name = ["illum_spot_size" "stim_spot_size"]
    v = s.(name);
    if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v > 0)
        problems(end+1) = "segmentation." + name + " must be a positive number of pixels."; %#ok<AGROW>
    end
end
if ~isempty(problems)
    error("hadamard_stim:SegmentationSettings", "Segmentation settings: %s", strjoin(problems, " "));
end
end


function s = read_file(file)
if ~isfile(file)
    error("hadamard_stim:SegmentationSettings", "No settings file at %s.", file);
end
[~, ~, extension] = fileparts(file);
if strcmpi(extension, ".json")
    s = jsondecode(fileread(file));
    if isfield(s, "segmentation")
        s = s.segmentation;
    end
    return
end
saved = load(file, "-mat");
if isfield(saved, "settings")
    s = saved.settings;
elseif isfield(saved, "segmentation") && isfield(saved.segmentation, "settings")
    s = saved.segmentation.settings;
else
    error("hadamard_stim:SegmentationSettings", "%s holds no segmentation settings.", file);
end
end
