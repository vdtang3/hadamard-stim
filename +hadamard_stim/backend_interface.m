function methods_ = backend_interface()
%BACKEND_INTERFACE What a controller needs from a rig before it has an environment.
%
%   names = hadamard_stim.backend_interface()
%
%   A controller made with HadamardStimController(env) is given its
%   environment ready-made (tests, scripts). One made with
%   HadamardStimController(backend) - the Luminos tab's form - builds it
%   when the operator prepares the rig, from a backend with these methods
%   (hadamard_stim.luminos.LuminosBackend on the rig):
%
%     s = settings()               rig settings, JSON-safe (e.g. blue_threshold)
%     set_settings(changes)        change some of them; errors, changing
%                                  nothing, if any is invalid
%     report = preflight(cfg)      read only: report.ok, report.checks (id,
%                                  label, status pass/fail/not_needed,
%                                  message), report.failures, and
%                                  report.calibration (blue calibration
%                                  status: valid/missing/invalid, identity)
%     env = environment(cfg)       what the protocol runs on (see
%                                  hadamard_stim.protocol.run_protocol),
%                                  with env.context for the recipe
%     d = diagnostics()            read only: what the devices report now
%     folder = default_run_folder(cfg)
%     runs = run_folders()         run folders that can be resumed
%                                  (folder, name, modified)
%     hw = calibration_hardware(cfg)
%                                  hardware (hardware_interface) begun for
%                                  his Hadamard calibration scans only; it
%                                  needs no environment. The caller runs
%                                  protocol.acquire_calibration_scans on it
%                                  and releases it
%     r = calibrate_blue_led()     the rig's own slide calibration of the
%                                  blue light; the rig keeps it, and the
%                                  environment reads it from there
%     r = record_calibration_scans(cfg, acquisitions)
%                                  record them; r.folders become the scan
%                                  calibration
%
%   Nothing here runs the experiment: every protocol step still goes
%   through the environment's hardware (hadamard_stim.protocol.hardware_interface).
methods_ = ["settings" "set_settings" "preflight" "environment" "diagnostics" ...
    "default_run_folder" "run_folders" "calibration_hardware" "record_calibration_scans" ...
    "calibrate_blue_led"];
end
