function paste_to_textarea(varargin)
%PASTE_TO_TEXTAREA Shim: Yitong drove SpinView (behaviour camera) with mouse
%automation. Recorded so the trace shows when recording started/stopped.
rig = getappdata(0, "hadamard_stim_golden_rig");
rig.spinview(end+1) = "paste_to_textarea(" + strjoin(cellfun(@(a) string(mat2str(a)), varargin), ", ") + ")";
end
