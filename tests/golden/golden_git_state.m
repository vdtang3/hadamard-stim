function state = golden_git_state(repo)
%GOLDEN_GIT_STATE Commit and dirty flag of the hadamard-stim checkout.
[status, commit] = system(sprintf('git -C "%s" rev-parse HEAD', repo));
if status ~= 0
    commit = "uncommitted";
end
[~, porcelain] = system(sprintf('git -C "%s" status --porcelain', repo));
state = struct("commit", strtrim(string(commit)), "dirty", strlength(strtrim(string(porcelain))) > 0);
end
