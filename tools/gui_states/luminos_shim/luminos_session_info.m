function info = luminos_session_info(~)
%LUMINOS_SESSION_INFO Stand-in for Luminos's own, for export_gui_states only.
info = struct("git", struct("commit", "5d1e0c9b7f3a2e1d0c9b8a7f6e5d4c3b2a190807", ...
    "branch", "vdtang3/hadamard-stim", "dirty", false), "luminos_version", "gui-harness");
end
