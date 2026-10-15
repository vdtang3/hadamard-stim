function view = pattern_view(controller, source, index)
%PATTERN_VIEW Which cells one stimulation pattern turns on, by cell number.
%
%   view = hadamard_stim.ui.pattern_view(controller, "matrix", k)
%   view = hadamard_stim.ui.pattern_view(controller, "last_trial", k)
%
%   "matrix": code k of the stimulation matrix (stim_matrix), the column a
%   Hadamard trial plays when its code counter reaches k. "last_trial":
%   pattern k of the last completed trial, as it was played
%   (record.c_idx_all_it: a code of a Hadamard trial, or a pulse of a
%   sparse one). view.on lists the cell numbers stimulated, in the
%   numbering of segmentation_view.
arguments
    controller
    source (1, 1) string {mustBeMember(source, ["matrix" "last_trial"])}
    index (1, 1) double {mustBeInteger, mustBePositive} = 1
end
view = struct("source", source, "index", index, "n_patterns", 0, ...
    "n_cells", 0, "on", zeros(0, 1), "trial", [], "kind", "");
switch source
    case "matrix"
        order = controller.Config.matrix.order;
        had_mat = hadamard_stim.yitong.stim_matrix(order);
        view.n_patterns = size(had_mat, 2);
        view.n_cells = size(had_mat, 1);
        columns = had_mat;
    case "last_trial"
        record = controller.LastRecord;
        if isempty(record) || isempty(record.c_idx_all_it)
            return
        end
        columns = record.c_idx_all_it;
        view.n_patterns = size(columns, 2);
        view.n_cells = size(columns, 1);
        view.trial = record.trial;
        view.kind = record.kind;
end
if index > view.n_patterns
    error("hadamard_stim:NoSuchPattern", "There are %d patterns; %d was asked for.", ...
        view.n_patterns, index);
end
view.on = find(columns(:, index) > 0);
end
