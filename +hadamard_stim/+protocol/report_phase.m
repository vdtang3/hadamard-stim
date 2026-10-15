function report_phase(env, name, details)
%REPORT_PHASE Tell an observer which part of the protocol is starting.
%
%   hadamard_stim.protocol.report_phase(env, name, details)
%
%   name     "z_reference", "reference_scan", "drift_correction",
%            "sparse", "hadamard" or "skipped"
%   details  struct of small facts (trial, plane, n_planes)
%
%   Observation only: env.phase_changed, when present, is called with
%   struct(name=..., details...) and its result is ignored. Without it this
%   does nothing. The controller uses it to show the status of a run that
%   is still going.
arguments
    env struct
    name (1, 1) string
    details struct = struct()
end
if ~isfield(env, "phase_changed") || isempty(env.phase_changed)
    return
end
phase = details;
phase.name = name;
env.phase_changed(phase);
end
