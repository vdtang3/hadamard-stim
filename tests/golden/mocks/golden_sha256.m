function hex = golden_sha256(value)
%GOLDEN_SHA256 SHA-256 of an array's raw bytes, in column-major order.
%   Class and size are not part of the hash; record them separately.
if islogical(value)
    value = uint8(value);
end
bytes = typecast(reshape(value, [], 1), "int8");   % Java byte[] is signed
md = java.security.MessageDigest.getInstance("SHA-256");
if ~isempty(bytes)
    md.update(bytes);
end
hex = lower(reshape(dec2hex(typecast(md.digest(), "uint8"), 2).', 1, []));
end
