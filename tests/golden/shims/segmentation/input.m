function answer = input(prompt, varargin)
%INPUT Shim for static_image_seg_v5's interactive "number of cells to
%exclude" prompt. The generator sets the answer with
%setappdata(0, "hadamard_stim_golden_n_exclude", n).
assert(contains(prompt, "exclude"), "Unexpected interactive prompt: %s", prompt);
answer = num2str(getappdata(0, "hadamard_stim_golden_n_exclude"));
end
