function manifest = golden_verify_manifest(reference)
%GOLDEN_VERIFY_MANIFEST Refuse to generate from a modified frozen reference.
manifest = readtable(fullfile(reference, "MANIFEST.tsv"), "FileType", "text", ...
    "Delimiter", "\t", "TextType", "string");
for k = 1:height(manifest)
    actual = golden_file_sha256(fullfile(reference, manifest.path(k)));
    assert(actual == manifest.sha256(k), ...
        "Frozen reference file %s does not match MANIFEST.tsv. Re-run " + ...
        "tools/freeze_yitong_reference.sh rather than editing it.", manifest.path(k));
end
end
