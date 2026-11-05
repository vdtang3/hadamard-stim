function tf = is_hadamard_order(n)
%IS_HADAMARD_ORDER Whether MATLAB's hadamard(n) exists, so stim_matrix(n) can be built.
%
%   tf = hadamard_stim.protocol.is_hadamard_order(n)
%
%   hadamard(n) needs n, n/12 or n/20 to be a power of 2 (his 320 is 20 x 16).
tf = isnumeric(n) && isscalar(n) && isfinite(n) && n >= 1 && n == round(n) ...
    && any(arrayfun(@(d) mod(n, d) == 0 && is_power_of_two(n / d), [1 12 20]));
end

function tf = is_power_of_two(m)
[f, ~] = log2(m);
tf = f == 0.5;
end
