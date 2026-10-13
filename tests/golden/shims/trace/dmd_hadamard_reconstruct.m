function im = dmd_hadamard_reconstruct(app, m_q, folder, cal_prefix, ref_prefix)
%DMD_HADAMARD_RECONSTRUCT Shim for drift correction: returns the synthetic
%scan of the last drift acquisition. Keeps the real function's side effect
%of overwriting function_data.hadamard_ref.
rig = getappdata(0, "hadamard_stim_golden_rig");
im = rig.current_scan;
app.function_data.hadamard_ref = im;
end
