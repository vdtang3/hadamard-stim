function hex = sha256(value)
%SHA256 SHA-256 of an array's raw bytes in column-major order.
%
%   hex = hadamard_stim.metadata.sha256(value)
%
%   The same hash the golden fixtures record (tests/golden/mocks/
%   golden_sha256.m): logical arrays are hashed as uint8, and class and
%   size are not part of the hash.
if islogical(value)
    value = uint8(value);
end
bytes = typecast(reshape(value, [], 1), "int8");
md = java.security.MessageDigest.getInstance("SHA-256");
if ~isempty(bytes)
    md.update(bytes);
end
hex = string(lower(reshape(dec2hex(typecast(md.digest(), "uint8"), 2).', 1, [])));
end
