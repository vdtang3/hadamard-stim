function golden_save(ctx, section, data)
%GOLDEN_SAVE Write one fixture with provenance attached.
%   Records the non-MathWorks files MATLAB had loaded, so a fixture names
%   every piece of code (frozen reference, mock, shim, lab library) that
%   could have influenced it.
provenance = ctx.provenance;
provenance.section = section;
loaded = string(inmem("-completenames"));
loaded = loaded(isfile(loaded) & ~startsWith(loaded, matlabroot));
loaded = sort(loaded);
hashes = strings(size(loaded));
for k = 1:numel(loaded)
    hashes(k) = golden_file_sha256(loaded(k));
end
provenance.loaded_files = erase(loaded, ctx.repo + filesep);
provenance.loaded_sha256 = hashes;
data.provenance = provenance;
file = fullfile(ctx.fixtures, "yitong_" + section + ".mat");
save(file, "-struct", "data", "-v7");
d = dir(file);
fprintf("wrote %s (%.0f kB)\n", erase(file, ctx.repo + filesep), d.bytes / 1024);
end
