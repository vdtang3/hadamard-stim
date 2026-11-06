function tuner = segmentation_tuner(image, settings, keep, options)
%SEGMENTATION_TUNER A small window to tune the tab's segmentation on one image and choose cells.
%
%   tuner = hadamard_stim.manual.segmentation_tuner(image, settings, keep)
%
%   Opened by manual_segment_dmd(..., review=true). Left: the image, with
%   every cell's orange spot outlined and numbered (green kept, red
%   dropped); click a cell to drop or restore it. Right: the tab's
%   segmentation settings (the same labels, hadamard_stim.ui.config_fields),
%   Segment (runs again on the same image: no Snap, reconstruction or
%   hardware), Keep all, Load / Save settings (.json), Accept and Cancel.
%   Nothing is drawn on the DMD here: the mask is made after Accept.
%
%   tuner: fig, and functions for the caller (and tests): set(name, value),
%   run(), toggle(k), keep_all(), save(file), load(file), accept(),
%   cancel(), state() -> struct(settings, cells, kept, accepted, done,
%   message).
arguments
    image
    settings struct
    keep double = []
    options.visible (1, 1) logical = true
end
fields = hadamard_stim.ui.config_fields();
fields = fields(startsWith([fields.path], "segmentation."));
st = struct("settings", hadamard_stim.manual.segmentation_settings(settings), "cells", [], ...
    "kept", [], "accepted", false, "done", false, "message", "");
initial_keep = keep;

fig = uifigure("Name", "Segmentation (Hadamard Stim settings)", "Visible", options.visible, ...
    "Position", [100 100 1100 700], "CloseRequestFcn", @(~, ~) cancel());
layout = uigridlayout(fig, [1 2], "ColumnWidth", {'1x', 330});
ax = uiaxes(layout);
ax.Toolbar.Visible = "off";
panel = uigridlayout(layout, [numel(fields) + 5, 2], "RowHeight", repmat({28}, 1, numel(fields) + 5), ...
    "ColumnWidth", {'1x', 90});
edits = struct();
for k = 1:numel(fields)
    name = extractAfter(fields(k).path, "segmentation.");
    label = fields(k).label;
    if strlength(fields(k).unit) > 0
        label = label + " (" + fields(k).unit + ")";
    end
    l = uilabel(panel, "Text", label, "Tooltip", fields(k).note);
    l.Layout.Row = k; l.Layout.Column = 1;
    if fields(k).kind == "boolean"
        e = uicheckbox(panel, "Text", "", "Value", logical(st.settings.(name)));
    else
        e = uieditfield(panel, "text", "Value", value_text(st.settings.(name)), "Tooltip", fields(k).note);
    end
    e.Layout.Row = k; e.Layout.Column = 2;
    edits.(name) = e;
end
row = numel(fields) + 1;
button("Segment", row, 1, @(~, ~) guarded(@run));
button("Keep all", row, 2, @(~, ~) keep_all());
button("Load settings...", row + 1, 1, @(~, ~) guarded(@() load_dialog()));
button("Save settings...", row + 1, 2, @(~, ~) guarded(@() save_dialog()));
button("Accept", row + 2, 1, @(~, ~) accept());
button("Cancel", row + 2, 2, @(~, ~) cancel());
status = uilabel(panel, "Text", "Set the settings and press Segment.", "WordWrap", "on");
status.Layout.Row = [row + 3 row + 4]; status.Layout.Column = [1 2];
draw();

tuner = struct("fig", fig, "set", @set_value, "run", @run, "toggle", @toggle, "keep_all", @keep_all, ...
    "save", @save_settings, "load", @load_settings, "accept", @accept, "cancel", @cancel, "state", @state);
if ~isempty(st.settings.n_exclude)
    guarded(@run);
end

    function s = state()
        s = st;
    end

    function button(text, r, c, callback)
        b = uibutton(panel, "Text", text, "ButtonPushedFcn", callback);
        b.Layout.Row = r; b.Layout.Column = c;
    end

    function set_value(name, value)
        e = edits.(name);
        if isa(e, "matlab.ui.control.CheckBox")
            e.Value = logical(value);
        else
            e.Value = value_text(value);
        end
    end

    function s = read_settings()
        s = struct();
        for n = string(fieldnames(edits))'
            e = edits.(n);
            if isa(e, "matlab.ui.control.CheckBox")
                s.(n) = e.Value;
            else
                s.(n) = str2num(e.Value); %#ok<ST2NM> numbers or empty
            end
        end
        s = hadamard_stim.manual.segmentation_settings(st.settings, s);
    end

    function run()
        s = read_settings();
        cells = hadamard_stim.manual.segment(image, s);
        n = size(cells.cell_coord, 1);
        st.settings = s;
        st.cells = cells;
        if isempty(st.kept) && ~isempty(initial_keep)
            st.kept = initial_keep(initial_keep >= 1 & initial_keep <= n);
            initial_keep = [];
        else
            st.kept = 1:n;    % a new segmentation: every cell, numbered anew
        end
        st.message = sprintf("%d cells found (n_exclude %d, threshold %d%s).", n, s.n_exclude, ...
            s.threshold, pick(s.select_all, ", all candidates", ""));
        draw();
    end

    function toggle(k)
        if isempty(st.cells), return, end
        if ismember(k, st.kept)
            st.kept = setdiff(st.kept, k);
        else
            st.kept = sort([st.kept k]);
        end
        draw();
    end

    function keep_all()
        if isempty(st.cells), return, end
        st.kept = 1:size(st.cells.cell_coord, 1);
        draw();
    end

    function save_settings(file)
        hadamard_stim.manual.write_segmentation_settings(file, read_settings());
        st.message = "Settings saved to " + file;
        draw();
    end

    function load_settings(file)
        s = hadamard_stim.manual.segmentation_settings(file);
        for n = string(fieldnames(edits))'
            set_value(n, s.(n));
        end
        st.settings = s;
        st.message = "Settings loaded from " + file + ". Press Segment.";
        draw();
    end

    function load_dialog()
        [f, p] = uigetfile({'*.json;*.mat', 'Segmentation settings'});
        if ~isequal(f, 0), load_settings(string(fullfile(p, f))); end
    end

    function save_dialog()
        [f, p] = uiputfile("*.json", "Save segmentation settings", "segmentation_settings.json");
        if ~isequal(f, 0), save_settings(string(fullfile(p, f))); end
    end

    function accept()
        if isempty(st.cells)
            st.message = "Segment first.";
            draw();
            return
        end
        st.accepted = true;
        finish();
    end

    function cancel()
        st.accepted = false;
        finish();
    end

    function finish()
        st.done = true;
        if isvalid(fig)
            uiresume(fig);
            delete(fig);
        end
    end

    function guarded(action)
        try
            action();
        catch err
            st.message = "Error: " + string(err.message);
            draw();
        end
    end

    function clicked(~, event)
        if isempty(st.cells), return, end
        xy = event.IntersectionPoint(1:2);
        [d, k] = min(hypot(st.cells.cell_coord(:, 1) - xy(1), st.cells.cell_coord(:, 2) - xy(2)));
        if d <= 2 * max(1, double(st.settings.illum_spot_size))
            toggle(k);
        end
    end

    function draw()
        if ~isvalid(fig), return, end
        cla(ax);
        values = sort(image(:));
        limits = values(max(1, round([0.005 0.995] * numel(values))))';
        if limits(2) <= limits(1), limits(2) = limits(1) + 1; end
        h = imagesc(ax, image, limits);
        h.ButtonDownFcn = @clicked;
        colormap(ax, gray);
        axis(ax, "image");
        hold(ax, "on");
        if ~isempty(st.cells)
            spots = hadamard_stim.yitong.split_rois(st.cells.illum_rois);
            for j = 1:numel(spots)
                colour = [0.85 0.2 0.2];
                if ismember(j, st.kept), colour = [0.2 0.9 0.3]; end
                p = spots{j};
                line(ax, p([1:end 1], 1), p([1:end 1], 2), "Color", colour, "HitTest", "off");
                text(ax, st.cells.cell_coord(j, 1), st.cells.cell_coord(j, 2), string(j), "Color", colour, ...
                    "FontSize", 7, "HorizontalAlignment", "center", "HitTest", "off");
            end
            title(ax, sprintf("%d of %d cells kept (green). Click a cell to drop/restore it.", ...
                numel(st.kept), size(st.cells.cell_coord, 1)));
        end
        hold(ax, "off");
        status.Text = st.message;
    end
end

function t = value_text(v)
if isempty(v)
    t = "";
else
    t = string(num2str(v));
end
end

function v = pick(c, a, b)
if c, v = a; else, v = b; end
end
