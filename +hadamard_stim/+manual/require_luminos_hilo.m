function require_luminos_hilo(functions)
%REQUIRE_LUMINOS_HILO Refuse clearly when Luminos's HiLo code is not on the path.
%
%   hadamard_stim.manual.require_luminos_hilo(["generate_hilo_pattern" ...])
%
%   The manual HiLo tools reuse Luminos's own HiLo functions (pattern
%   generator, FOV mask, reconstruction) rather than copies of them, so the
%   patterns and images are the ones the HiLo tab makes. In Luminos's MATLAB
%   they are on the path already; elsewhere add
%   <luminos>/src/Experimental_Scripts/HiLo (and, for the FOV mask,
%   <luminos>/src/utils/Data_Structures for CL_RefImage).
arguments
    functions (1, :) string
end
missing = functions(arrayfun(@(f) exist(f, "file") ~= 2, functions));
if ~isempty(missing)
    error("hadamard_stim:LuminosHiLoMissing", ...
        ['%s not found: these tools use Luminos''s HiLo code itself. Add it to the path, e.g. ' ...
         'addpath(fullfile(<luminos>, "src", "Experimental_Scripts", "HiLo")) - from ' ...
         'luminos-private on vdtang3/adaptive-optopatch.'], strjoin(missing, ", "));
end
end
