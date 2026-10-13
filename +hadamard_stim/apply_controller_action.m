function response = apply_controller_action(controller, action, payload, expected_revision)
%APPLY_CONTROLLER_ACTION Run one named action from a frontend.
%
%   response = hadamard_stim.apply_controller_action(controller, action, payload, expected_revision)
%
%   The whole write surface a frontend has: every action is listed in the
%   switch below, and anything else is refused. (The pattern is Adaptive
%   Optopatch's, copied rather than shared.)
%
%   response.ok, .status (applied | stale_revision | not_legal |
%   unknown_action | failed), .message, .identifier, .revision, .state.
%   The state is returned on success and on every refusal, so the frontend
%   always ends up showing what the controller holds.
%
%   A mutation carries the revision its caller saw; if the controller has
%   moved on, nothing is changed. stop_after_current is exempt, because a
%   running protocol bumps the revision after every trial.
%
%   Actions and payloads:
%     set_config            payload.config (whole struct)
%     set_reference_image   payload.image
%     propose_cells, approve_cells, acquire_z_reference
%     start_run, resume_run payload.run_folder
%     stop_after_current
arguments
    controller (1, 1) hadamard_stim.HadamardStimController
    action (1, 1) string
    payload struct = struct()
    expected_revision = []
end
known = ["set_config" "set_reference_image" "propose_cells" "approve_cells" ...
    "acquire_z_reference" "start_run" "resume_run" "stop_after_current"];
if ~ismember(action, known)
    response = reply(controller, false, "unknown_action", ...
        "There is no action called '" + action + "'.", "");
    return
end
legal = controller.legalActions();
if ~legal.(action)
    response = reply(controller, false, "not_legal", ...
        "'" + action + "' is not possible while the session is " + ...
        controller.LifecycleState + ".", "");
    return
end
if action ~= "stop_after_current" && ~isempty(expected_revision) && ...
        expected_revision ~= controller.Revision
    response = reply(controller, false, "stale_revision", ...
        "The session changed since this was requested; nothing was done.", "");
    return
end

try
    switch action
        case "set_config"
            controller.setConfig(payload.config);
        case "set_reference_image"
            controller.setReferenceImage(payload.image);
        case "propose_cells"
            controller.proposeCells();
        case "approve_cells"
            controller.approveCells();
        case "acquire_z_reference"
            controller.acquireZReference();
        case "start_run"
            controller.startRun(string(payload.run_folder));
        case "resume_run"
            controller.resumeRun(string(payload.run_folder));
        case "stop_after_current"
            controller.requestStop();
    end
catch err
    response = reply(controller, false, "failed", string(err.message), string(err.identifier));
    return
end
response = reply(controller, true, "applied", "", "");
end

function response = reply(controller, ok, status, message, identifier)
response = struct("ok", ok, "status", status, "message", message, ...
    "identifier", identifier, "revision", controller.Revision, ...
    "state", controller.getState());
end
