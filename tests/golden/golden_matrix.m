function data = golden_matrix(ctx)
%GOLDEN_MATRIX Run the protocol script's matrix lines, verbatim.
golden_use_path(ctx);
script = readlines(fullfile(ctx.dragonfly, "Auto Scripts", ...
    "RunSynchronizedAQMulti_sparse_pulse_hadamard_behavior_v1.m"));
first = find(strtrim(script) == "hadOrder = 320;");
last = find(strtrim(script) == "rng('default')");
assert(isscalar(first) && isscalar(last) && last > first, "Matrix block not found");
block = script(first:last);
data.source_lines = [first last];
data.source = block;

rng(12345, "twister");             % prove the block does not depend on the incoming state
hadMat = run_block(block);
data.had_mat = hadMat;
data.rng_restored_to_default = isequal(rng, rng("default"));
rng(54321, "twister");
data.independent_of_incoming_rng = isequal(run_block(block), hadMat);

% Finding: every element of hadamard(320) is +-1 and both randperm lines
% only write -1, so the matrix is nonzero everywhere and xor() reduces to
% ~(rand > .5). The unseeded randperm calls have no effect.
rng(0, "twister");
data.equals_seeded_bernoulli = isequal(hadMat, rand(320) <= .5);
rng("default");
end

function hadMat = run_block(block)
eval(strjoin(block, newline));
end
