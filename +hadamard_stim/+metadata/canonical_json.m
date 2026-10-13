function text = canonical_json(value)
%CANONICAL_JSON JSON with fields sorted, so equal content gives equal text.
%
%   text = hadamard_stim.metadata.canonical_json(value)
%
%   Used for the recipe and its hash, which must not depend on the order
%   fields happened to be added in. jsonencode writes doubles with enough
%   digits to read back exactly.
text = string(jsonencode(sort_fields(value), "ConvertInfAndNaN", true, "PrettyPrint", true));
end

function v = sort_fields(v)
if isstruct(v)
    v = orderfields(v);
    names = fieldnames(v);
    for k = 1:numel(v)
        for n = 1:numel(names)
            v(k).(names{n}) = sort_fields(v(k).(names{n}));
        end
    end
elseif iscell(v)
    v = cellfun(@sort_fields, v, "UniformOutput", false);
end
end
