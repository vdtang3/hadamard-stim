function p = git_provenance(folder)
%GIT_PROVENANCE Which commit of a repository is running, and whether it is clean.
%
%   p = hadamard_stim.metadata.git_provenance(folder)
%
%   p.commit, p.branch, p.dirty, p.remote. Fields git cannot answer are
%   "unknown" (dirty: missing). A dirty tree is allowed, but the recipe and
%   the tab say so.
p = struct("commit", "unknown", "branch", "unknown", "dirty", missing, "remote", "unknown");
p.commit = ask(folder, "rev-parse HEAD", p.commit);
p.branch = ask(folder, "rev-parse --abbrev-ref HEAD", p.branch);
p.remote = ask(folder, "config --get remote.origin.url", "none");
[status, changes] = system(sprintf('git -C "%s" status --porcelain', folder));
if status == 0
    p.dirty = strlength(strip(string(changes))) > 0;
end
end

function value = ask(folder, command, fallback)
[status, out] = system(sprintf('git -C "%s" %s', folder, command));
value = fallback;
if status == 0 && strlength(strip(string(out))) > 0
    value = strip(string(out));
end
end
