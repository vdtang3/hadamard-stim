function [changed, files] = dmd_code_changed(then_commit, now_commit, options)
%DMD_CODE_CHANGED Whether Luminos's DMD code differs between two commits.
%
%   [changed, files] = hadamard_stim.luminos.dmd_code_changed(then_commit, now_commit)
%   [...] = dmd_code_changed(..., repo=..., paths=...)
%
%   A slide queue check recorded under one Luminos commit is still evidence
%   under another when the code that loads and plays the queue is the same
%   (hardware_gate). This asks git which files under paths (default
%   firefly_profile().luminos_dmd_paths: the ALP class and its MEX) differ.
%
%   changed  true, false, or [] when it cannot be told (no git, the Luminos
%            repository not found, a commit unknown to it)
%   files    the files that differ, relative to the repository
%
%   repo defaults to the git repository holding ALP_DMD.m on the path.
arguments
    then_commit (1, 1) string
    now_commit (1, 1) string
    options.repo (1, 1) string = ""
    options.paths string = hadamard_stim.luminos.firefly_profile().luminos_dmd_paths
end
changed = [];
files = strings(1, 0);
if strlength(then_commit) == 0 || strlength(now_commit) == 0 ...
        || isempty(regexp(then_commit + " " + now_commit, "^[0-9a-f]+ [0-9a-f]+$", "once"))
    return
end
if then_commit == now_commit
    changed = false;
    return
end
repo = options.repo;
if strlength(repo) == 0
    where = string(which("ALP_DMD"));
    if strlength(where) == 0
        return
    end
    [status, out] = system(sprintf('git -C "%s" rev-parse --show-toplevel', fileparts(where)));
    if status ~= 0
        return
    end
    repo = strip(string(out));
end
paths = strjoin(compose('"%s"', reshape(options.paths, 1, [])), " ");
[status, out] = system(sprintf('git --no-pager -C "%s" -c color.ui=never diff --name-only %s %s -- %s', ...
    repo, then_commit, now_commit, paths));
if status ~= 0
    return
end
files = splitlines(strip(string(out)))';
files = files(strlength(files) > 0);
changed = ~isempty(files);
end
