function view = controller_view(controller, name, args)
%CONTROLLER_VIEW One read-only display product, too large or slow for getState.
%
%   view = hadamard_stim.controller_view(controller, name, args)
%
%   The read half of what a frontend has, beside apply_controller_action:
%   every view is listed below and anything else is refused. None of them
%   changes the session (the revision is untouched) or touches the rig
%   except "diagnostics", which only reads device properties. Each is
%   computed by the package, so a frontend draws what MATLAB says and
%   calculates nothing.
%
%   view.ok, .name, .message (why not, when ok is false) and .data.
%
%   Views and args:
%     config_fields    the editable configuration fields (ui.config_fields)
%                      with the current and Yitong values
%     segmentation     reference image, numbered cells, spots, excluded
%                      candidates, min_val (ui.segmentation_view)
%     pattern          args.source "matrix" or "last_trial", args.index:
%                      the cell numbers one pattern stimulates (connectivity)
%     summary          what will run / ran (ui.run_summary)
%     recipe           the saved run recipe of the session's run folder,
%                      without the per-cell arrays
%     checkpoint       args.run_folder (default the session's): what a
%                      resume continues from (ui.checkpoint_summary)
%     diagnostics      what the rig's devices report now (backend)
%     run_folders      run folders a resume could continue (backend)
arguments
    controller (1, 1) hadamard_stim.HadamardStimController
    name (1, 1) string
    args struct = struct()
end
view = struct("ok", true, "name", name, "message", "", "data", []);
try
    switch name
        case "config_fields"
            view.data = fields_with_values(controller.Config);
        case "segmentation"
            view.data = hadamard_stim.ui.segmentation_view(controller);
        case "pattern"
            view.data = hadamard_stim.ui.pattern_view(controller, ...
                string(arg(args, "source", "matrix")), double(arg(args, "index", 1)));
        case "summary"
            view.data = hadamard_stim.ui.run_summary(controller);
        case "recipe"
            view.data = saved_recipe(string(arg(args, "run_folder", controller.RunFolder)));
        case "checkpoint"
            context = [];
            if isfield(controller.Env, "context")
                context = controller.Env.context;
            end
            view.data = hadamard_stim.ui.checkpoint_summary( ...
                string(arg(args, "run_folder", controller.RunFolder)), context);
        case "diagnostics"
            require_backend(controller);
            view.data = controller.Backend.diagnostics();
        case "run_folders"
            require_backend(controller);
            view.data = controller.Backend.run_folders();
        otherwise
            view.ok = false;
            view.message = "There is no view called '" + name + "'.";
    end
catch err
    view.ok = false;
    view.message = string(err.message);
    view.data = [];
end
end

function v = arg(args, name, default)
v = default;
if isfield(args, name) && ~isempty(args.(name))
    v = args.(name);
end
end

function require_backend(controller)
if isempty(controller.Backend)
    error("hadamard_stim:NoBackend", "This session has no rig backend.");
end
end

function fields = fields_with_values(cfg)
% Each field with its value, his, and whether it is one of the run's
% deviations as validate_config reports them (only the fields the session
% mode uses can be). The wheel encoder is off by default until Firefly's
% wiring is checked, but he recorded it: his value is shown as on.
yitong = hadamard_stim.default_config();
yitong.behavior.wheel_encoder_enabled = true;
report = hadamard_stim.validate_config(cfg);
deviating = string({report.deviations.path});
fields = hadamard_stim.ui.config_fields();
[fields.value] = deal([]);
[fields.yitong] = deal([]);
[fields.deviates] = deal(false);
for k = 1:numel(fields)
    fields(k).value = get_path(cfg, fields(k).path);
    fields(k).yitong = get_path(yitong, fields(k).path);
    fields(k).deviates = ismember(fields(k).path, deviating);
end
end

function v = get_path(s, path)
v = s;
for part = split(path, ".")'
    v = v.(part);
end
end

function recipe = saved_recipe(run_folder)
if strlength(run_folder) == 0
    error("hadamard_stim:NoRunFolder", "This session has not started a run yet.");
end
file = fullfile(run_folder, "run_recipe.json");
if ~isfile(file)
    error("hadamard_stim:NoRecipe", "%s holds no run recipe.", run_folder);
end
recipe = jsondecode(fileread(file));
recipe.file = string(file);
% The per-cell arrays are in segmentation_view; the recipe keeps their hashes.
recipe.cells = struct("n_cells", recipe.cells.n_cells, ...
    "illum_mask_sha256", recipe.cells.illum_mask_sha256, ...
    "stim_mask_sha256", recipe.cells.stim_mask_sha256);
end
