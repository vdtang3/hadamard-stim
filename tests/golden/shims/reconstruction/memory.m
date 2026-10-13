function [userview, systemview] = memory()
%MEMORY Shim: MATLAB's memory() exists only on Windows. Yitong's
%reconstruction uses it only to refuse to run when RAM is short.
userview = struct();
systemview.PhysicalMemory.Available = 1e12;
end
