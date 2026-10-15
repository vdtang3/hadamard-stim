function cfg = apply_config_changes(cfg, changes)
%APPLY_CONFIG_CHANGES A configuration with some listed fields changed.
%
%   cfg = hadamard_stim.ui.apply_config_changes(cfg, changes)
%
%   changes is a struct array (or cell array of structs, as jsondecode
%   gives) with path and value. Only paths in config_fields are accepted;
%   values are converted to the field's kind, and an empty value clears a
%   required field. Nothing is changed if any change is refused. Whether
%   the result can run is validate_config's answer, not this function's.
if iscell(changes)
    changes = [changes{:}];
end
fields = hadamard_stim.ui.config_fields();
paths = [fields.path];
for change = reshape(changes, 1, [])
    path = string(change.path);
    k = find(paths == path, 1);
    if isempty(k)
        error("hadamard_stim:NotEditable", "'%s' cannot be changed from the tab.", path);
    end
    cfg = set_path(cfg, path, convert(fields(k), change.value));
end
end

function v = convert(field, v)
if isempty(v) && field.required
    v = [];
    if field.kind == "text" || field.kind == "choice"
        v = "";
    end
    return
end
switch field.kind
    case {"number" "integer"}
        if ischar(v) || isstring(v)
            v = str2double(v);
        end
        if ~(isnumeric(v) && isscalar(v) && isfinite(v))
            error("hadamard_stim:InvalidValue", "%s must be a number.", field.label);
        end
        v = double(v);
        if field.kind == "integer" && v ~= round(v)
            error("hadamard_stim:InvalidValue", "%s must be a whole number.", field.label);
        end
    case "boolean"
        if ~(islogical(v) || isnumeric(v)) || ~isscalar(v)
            error("hadamard_stim:InvalidValue", "%s must be true or false.", field.label);
        end
        v = logical(v);
    case {"text" "choice"}
        if ~(ischar(v) || isstring(v)) || ~isscalar(string(v))
            error("hadamard_stim:InvalidValue", "%s must be text.", field.label);
        end
        v = string(v);
        if field.kind == "choice" && ~ismember(v, field.choices)
            error("hadamard_stim:InvalidValue", "%s must be one of: %s.", field.label, ...
                strjoin(field.choices, ", "));
        end
end
end

function s = set_path(s, path, v)
parts = split(path, ".");
if isscalar(parts)
    s.(parts) = v;
else
    s.(parts(1)) = set_path(s.(parts(1)), strjoin(parts(2:end), "."), v);
end
end
