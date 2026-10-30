function write_text(text, file)
%WRITE_TEXT Write text to a file as UTF-8, one line per element.
%
%   hadamard_stim.metadata.write_text(text, file)
%
%   What writelines(text, file) does, for MATLAB before R2022a (Firefly
%   runs R2021b, which has no writelines). Each element of text ends with
%   a newline; the file is replaced.
arguments
    text string
    file (1, 1) string
end
[fid, message] = fopen(file, "w", "n", "UTF-8");
if fid < 0
    error("hadamard_stim:CannotWrite", "Cannot write %s: %s", file, message);
end
closer = onCleanup(@() fclose(fid));
fprintf(fid, "%s\n", text(:));
clear closer
end
