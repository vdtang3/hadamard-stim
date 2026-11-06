function write_segmentation_settings(file, settings)
%WRITE_SEGMENTATION_SETTINGS Save segmentation settings as JSON, to reload with segmentation_settings.
%
%   hadamard_stim.manual.write_segmentation_settings("my_settings.json", settings)
%   manual_segment_dmd(..., settings="my_settings.json")
arguments
    file (1, 1) string
    settings struct
end
settings = hadamard_stim.manual.segmentation_settings(settings);   % checked
folder = fileparts(file);
if strlength(folder) > 0 && ~isfolder(folder)
    mkdir(folder);
end
fid = fopen(file, "w");
if fid < 0
    error("hadamard_stim:SegmentationSettings", "Cannot write %s.", file);
end
closer = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(struct("segmentation", settings), "PrettyPrint", true), "char");
end
