function steps = commissioning_checklist()
%COMMISSIONING_CHECKLIST Firefly's bring-up, step by step. Not the daily workflow.
%
%   steps = hadamard_stim.ui.commissioning_checklist()
%
%   Commissioning steps are not the normal daily experimental workflow. A
%   session is: reference image, cells, z-reference, run (README, "Each
%   FOV"). These are done once, or occasionally when the rig changes, and
%   what they produce (calibrations, the slide queue record) is kept and
%   reused with its date; nothing expires on its own.
%
%   Stages:
%     installation    once, outside Luminos (Luminos closed)
%     occasional      in Luminos, when the DMD, Luminos or optics change
%     bring_up        once, on the slide, before the first animal
%     biological      the first sessions with an animal
%
%   steps: struct array of step, stage, area, what, how. Read only; the tab
%   shows it collapsed under Rig / commissioning.
s = @(stage, area, what, how) struct("stage", stage, "area", area, "what", what, "how", how);
steps = [
    s("installation", "MATLAB", "Put hadamard-stim on the MATLAB path of the Luminos install", "README, First-time installation")
    s("installation", "DMD", "Probe the ALP driver and MEX: a driver opens the board and reports the 1024 x 768 DMD, its DLL, version and serial", "MATLAB, Luminos closed: hadamard_stim.checks.driver_check()")
    s("occasional", "DMD", "Sequence queue support on the live driver", "Tab: Rig / commissioning, Sequence queue, Run check")
    s("occasional", "DMD", "Queue playback on the uniform slide (rising edge)", "Tab: Rig / commissioning, Queue playback on slide, Run on slide")
    s("occasional", "Calibration", "DMD geometry for the Kinetix at the acquisition camera area", "Luminos DMD tab")
    s("occasional", "Calibration", "Hadamard calibration scans on the uniform slide", "Tab: Take new scans (or reuse an earlier set)")
    s("occasional", "Calibration", "Blue LED slide calibration, and blue_threshold", "Tab: Calibrate blue LED; rig settings")
    s("bring_up", "Settings", "Name the hardware validation file", "Tab: rig settings")
    s("bring_up", "Wiring", "IR still on ao3, and nothing else drives the protocol's ports", "Waveforms tab; Check readiness")
    s("bring_up", "Cameras", "Luminos frames have the orientation of his Sq_camera.bin (P1)", "Compare a slide scan with his")
    s("bring_up", "Stage", "Newport backlash correction behaves like his motor", "Z-reference on a slide")
    s("bring_up", "Memory", "The pinhole calibration fits in the rig PC's memory (~10 GB)", "First Prepare rig")
    s("biological", "First run", "Connectivity mode, face camera off, wheel encoder off", "Configuration")
    s("biological", "First run", "A short session: trials 1-4", "Run panel")
    s("biological", "First run", "Abort deliberately during a trial", "Abort")
    s("biological", "First run", "Resume, and confirm the incomplete trial is repeated", "Resume panel; trial records")
    s("biological", "Face camera", "Enable the face camera and check its video", "Configuration; a short run")
    s("biological", "Encoder", "Enable the wheel encoder and check the A/B lines against the camera triggers", "Rig settings; spin the wheel during a short run")
    s("biological", "Spontaneous", "Spontaneous blocks, separately, with drift correction between them", "session.mode spontaneous; two blocks")
    ];
steps = reshape(steps, 1, []);
for k = 1:numel(steps)
    steps(k).step = k;
end
steps = orderfields(steps, ["step" "stage" "area" "what" "how"]);
end
