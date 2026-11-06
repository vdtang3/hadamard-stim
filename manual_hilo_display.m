function manual_hilo_display(dmd, pattern)
%MANUAL_HILO_DISPLAY Show one pattern on a DMD, as the DMD tab and Hadamard Stim's preview do.
%
%   manual_hilo_display(dmd, patterns.uniform)        a manual_hilo_patterns pattern
%   manual_hilo_display(dmd, patterns.structured)
%   manual_hilo_display(dmd, "C:\...\orange_mask.mat")  a mask file (variable "mask"):
%                                                     manual_segment_dmd's or the
%                                                     Hadamard Stim tab's export
%   manual_hilo_display(dmd, "dark")                  all mirrors off
%
%   The pattern must be logical (or 0/1), exactly the DMD canvas
%   (dmd.Pattern_Canvas_Size(), [rows columns]); it is never resized. It is
%   shown the way the DMD tab's "Hadamard Stim Orange Mask" pattern and
%   Hadamard Stim's orange preview show a picture: dmd.Target = pattern,
%   then dmd.Write_Static() - a static picture, no trigger. A DMD that
%   Hadamard Stim or the HiLo tab holds (pattern ownership) is refused, so
%   this cannot overwrite a running protocol. The orange light is not
%   touched: set it in Luminos.
arguments
    dmd
    pattern
end
if isprop(dmd, "pattern_owner") && strlength(string(dmd.pattern_owner)) > 0
    error("hadamard_stim:DmdOwned", "%s is held by %s; stop that first.", dmd.name, dmd.pattern_owner);
end
if (isstring(pattern) || ischar(pattern)) && strcmpi(string(pattern), "dark")
    dmd.Write_Dark();
    return
end
if isstring(pattern) || ischar(pattern)
    file = string(pattern);
    if ~isfile(file)
        error("hadamard_stim:PatternFile", "No pattern file at %s.", file);
    end
    saved = load(file, "-mat");
    if ~isfield(saved, "mask")
        error("hadamard_stim:PatternFile", ['%s holds no "mask". For manual_hilo_patterns'' file, ' ...
            'load it and pass patterns.uniform or patterns.structured.'], file);
    end
    pattern = saved.mask;
end
canvas = double(dmd.Pattern_Canvas_Size());
if ~isequal(size(pattern), canvas)
    error("hadamard_stim:PatternSize", "The pattern is %s; %s's canvas is %s (rows x columns).", ...
        mat2str(size(pattern)), dmd.name, mat2str(canvas));
end
if ~islogical(pattern) && ~all(pattern(:) == 0 | pattern(:) == 1)
    error("hadamard_stim:PatternSize", "The pattern must be logical (or 0 and 1 only).");
end
dmd.Target = logical(pattern);
dmd.Write_Static();
end
