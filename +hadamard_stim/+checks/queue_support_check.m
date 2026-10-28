function result = queue_support_check(app, profile)
%QUEUE_SUPPORT_CHECK Firefly check 3: the DMD driver supports the sequence queue.
%
%   result = hadamard_stim.checks.queue_support_check(app)
arguments
    app
    profile struct = hadamard_stim.luminos.firefly_profile()
end
[devices, ~] = hadamard_stim.luminos.resolve_hardware(app, profile);
dmd = devices.dmd;
if isempty(dmd)
    error("hadamard_stim:NoDmd", "%s is not on this rig.", profile.devices.dmd.name);
end
supported = logical(dmd.Supports_Sequence_Queue());
if supported
    evidence = sprintf("%s.Supports_Sequence_Queue() returned true.", dmd.name);
else
    evidence = sprintf(['%s.Supports_Sequence_Queue() returned false: the loaded ALP driver ' ...
        'does not accept the queue mode his stimulation trials need.'], dmd.name);
end
result = hadamard_stim.checks.check_result("queue_support", supported, evidence, struct(), ...
    hadamard_stim.checks.check_provenance(app, profile));
end
