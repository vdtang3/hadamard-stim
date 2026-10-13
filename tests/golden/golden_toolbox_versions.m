function versions = golden_toolbox_versions()
%GOLDEN_TOOLBOX_VERSIONS Products whose numerics the fixtures depend on.
wanted = ["MATLAB" "Image Processing Toolbox" "Computer Vision Toolbox" ...
    "Curve Fitting Toolbox" "Statistics and Machine Learning Toolbox"];
v = ver;
versions = strings(0, 1);
for name = wanted
    match = v(strcmp({v.Name}, name));
    if ~isempty(match)
        versions(end+1, 1) = name + " " + match.Version + " " + match.Release; %#ok<AGROW>
    end
end
end
