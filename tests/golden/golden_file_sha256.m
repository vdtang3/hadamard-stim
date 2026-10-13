function hex = golden_file_sha256(file)
%GOLDEN_FILE_SHA256 SHA-256 of a file's bytes, streamed.
md = java.security.MessageDigest.getInstance("SHA-256");
fid = fopen(file, "r");
assert(fid > 0, "Cannot open %s", file);
closer = onCleanup(@() fclose(fid));
while true
    chunk = fread(fid, 2^24, "*uint8");
    if isempty(chunk)
        break
    end
    md.update(chunk);
end
hex = string(lower(reshape(dec2hex(typecast(md.digest(), "uint8"), 2).', 1, [])));
end
