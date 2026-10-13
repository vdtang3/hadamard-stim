function mov = vm(path, frames)
%VM Shim for the protocol's bleaching estimate, which opens frames 501:1000
%of the last stimulation movie and uses only mov.mean. (Folder names contain
%dots such as "16.0", so the path is not split with fileparts.)
assert(isequal(frames, 501:1000), "Unexpected frame range");
rig = getappdata(0, "hadamard_stim_golden_rig");
mov = struct("mean", rig.movie_mean(path));
end
