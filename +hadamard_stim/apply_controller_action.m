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
%   moved on, nothing is changed. stop_after_current and abort are exempt,
%   because a running protocol bumps the revision as it goes.
%
%   Actions and payloads:
%     set_config            payload.config (whole struct)
%     update_config         payload.changes: path/value pairs, only the
%                           fields hadamard_stim.ui.config_fields lists
%     set_rig_settings      payload.settings (backend settings to change)
%     run_preflight         read-only rig checks
%     acquire_calibration_scans   his Hadamard calibration scans, on a slide
%     calibrate_blue_led    the rig's slide calibration of the blue light
%     run_commissioning_check   payload.name: one of the two DMD
%                           commissioning checks, "queue_support" or
%                           "slide_queue" (on a uniform slide), recorded
%     prepare_rig           build the environment from the backend
%     acquire_reference_image   one Hadamard scan, reconstructed
%     set_reference_image   payload.image
%     propose_cells, approve_cells, acquire_z_reference
%     start_run             payload.run_folder (optional with a backend)
%                           payload.acknowledged_warnings: the ids of the
%                           readiness warnings the operator chose to go
%                           ahead with (all of them, or the run refuses)
%                           payload.operator_note (optional)
%     resume_run            payload.run_folder (optional: the session's own)
%                           payload.continue_with_changed_calibration: resume
%                           although a calibration changed (recorded)
%                           payload.acknowledged_warnings, operator_note: as
%                           for start_run
%     stop_after_current    finish the trial in progress, then stop
%     abort                 abandon what the rig is doing; then release it
%     new_session           start again on a new field of view
%     start_orange_preview  show the approved cells' illumination mask on
%                           the DMD with the orange LED at orange_start_v
%                           (an operator aid; nothing is acquired)
%     stop_orange_preview   LED off, DMD dark, rig released
arguments
    controller (1, 1) hadamard_stim.HadamardStimController
    action (1, 1) string
    payload struct = struct()
    expected_revision = []
end
known = ["set_config" "update_config" "set_rig_settings" "run_preflight" ...
    "acquire_calibration_scans" "calibrate_blue_led" "run_commissioning_check" "prepare_rig" ...
    "acquire_reference_image" "set_reference_image" "propose_cells" "approve_cells" ...
    "acquire_z_reference" "start_run" "resume_run" "stop_after_current" "abort" "new_session" ...
    "start_orange_preview" "stop_orange_preview"];
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
if ~ismember(action, ["stop_after_current" "abort"]) && ~isempty(expected_revision) && ...
        expected_revision ~= controller.Revision
    response = reply(controller, false, "stale_revision", ...
        "The session changed since this was requested; nothing was done.", "");
    return
end

try
    switch action
        case "set_config"
            controller.setConfig(payload.config);
        case "update_config"
            controller.updateConfig(payload.changes);
        case "set_rig_settings"
            controller.setRigSettings(payload.settings);
        case "run_preflight"
            controller.runPreflight();
        case "acquire_calibration_scans"
            controller.acquireCalibrationScans();
        case "calibrate_blue_led"
            controller.calibrateBlueLed();
        case "run_commissioning_check"
            controller.runCommissioningCheck(string(payload.name));
        case "start_orange_preview"
            controller.startOrangePreview();
        case "stop_orange_preview"
            controller.stopOrangePreview();
        case "prepare_rig"
            controller.prepareRig();
        case "acquire_reference_image"
            controller.acquireReferenceImage();
        case "set_reference_image"
            controller.setReferenceImage(payload.image);
        case "propose_cells"
            controller.proposeCells();
        case "approve_cells"
            controller.approveCells();
        case "acquire_z_reference"
            controller.acquireZReference();
        case "start_run"
            controller.startRun(optional_folder(payload), ...
                AcknowledgedWarnings=acknowledged(payload), OperatorNote=note(payload));
        case "resume_run"
            controller.resumeRun(optional_folder(payload), ContinueWithChangedCalibration= ...
                isfield(payload, "continue_with_changed_calibration") ...
                && isequal(payload.continue_with_changed_calibration, true), ...
                AcknowledgedWarnings=acknowledged(payload), OperatorNote=note(payload));
        case "stop_after_current"
            controller.requestStop();
        case "abort"
            controller.requestAbort();
        case "new_session"
            controller.newSession();
    end
catch err
    response = reply(controller, false, "failed", string(err.message), string(err.identifier));
    return
end
response = reply(controller, true, "applied", "", "");
end

function folder = optional_folder(payload)
folder = "";
if isfield(payload, "run_folder") && ~isempty(payload.run_folder)
    folder = string(payload.run_folder);
end
end

function ids = acknowledged(payload)
ids = strings(1, 0);
if isfield(payload, "acknowledged_warnings") && ~isempty(payload.acknowledged_warnings)
    ids = reshape(string(payload.acknowledged_warnings), 1, []);
end
end

function text = note(payload)
text = "";
if isfield(payload, "operator_note") && ~isempty(payload.operator_note)
    text = string(payload.operator_note);
end
end

function response = reply(controller, ok, status, message, identifier)
response = struct("ok", ok, "status", status, "message", message, ...
    "identifier", identifier, "revision", controller.Revision, ...
    "state", controller.getState());
end
