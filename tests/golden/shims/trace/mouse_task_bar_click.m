function mouse_task_bar_click(varargin)
%MOUSE_TASK_BAR_CLICK Shim: Yitong drove SpinView (behaviour camera) with mouse
%automation. Recorded so the trace shows when recording started/stopped.
rig = getappdata(0, "hadamard_stim_golden_rig");
rig.spinview(end+1) = "mouse_task_bar_click(" + strjoin(cellfun(@(a) string(mat2str(a)), varargin), ", ") + ")";
end
