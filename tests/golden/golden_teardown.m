function golden_teardown(ctx)
%GOLDEN_TEARDOWN Restore the path and working folder; remove temporaries.
path(ctx.original_path);
cd(ctx.original_dir);
for key = ["hadamard_stim_golden_rig" "hadamard_stim_golden_n_exclude"]
    if isappdata(0, key)
        rmappdata(0, key);
    end
end
close all force
if isfolder(ctx.tmp)
    rmdir(ctx.tmp, "s");
end
end
