function [had_all, ref_all] = hadamard_reconstruct(m_q, folder, cal_prefix, ref_prefix, varargin)
%HADAMARD_RECONSTRUCT Shim for the protocol's z-stack reconstruction: returns
%the synthetic stack at the motor positions the script actually visited.
%Yitong's reconstruction itself has its own golden (reconstruction section).
rig = getappdata(0, "hadamard_stim_golden_rig");
had_all = synthetic_z_stack(rig.ref, rig.stack_z - rig.z_center);
ref_all = had_all;
end
