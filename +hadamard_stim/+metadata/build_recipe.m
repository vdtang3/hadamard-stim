function [recipe, arrays] = build_recipe(cfg, state, context)
%BUILD_RECIPE The immutable description of a run, written once at its start.
%
%   [recipe, arrays] = hadamard_stim.metadata.build_recipe(cfg, state, context)
%
%   cfg      validated configuration
%   state    hadamard_stim.protocol.new_run_state (before the first trial)
%   context  where the run happens:
%     .luminos             git_provenance of Luminos (or a struct saying
%                          why there is none, e.g. a simulation)
%     .geometry_identity   env.geometry.identity
%     .blue_calibration    struct with at least .identity and .source
%     .standing_deviations strings: what always differs from his rig here
%                          (the Luminos adapter supplies them)
%     .simulated           true off the rig
%     .hardware_validation the Firefly checks (hardware_gate), recorded
%     .hardware            optional: rig facts (hadamard_stim.luminos.hardware_facts)
%
%   recipe is JSON-safe; every later record carries recipe.recipe_hash, the
%   SHA-256 of its canonical JSON. arrays holds what is too big for JSON
%   (masks, z-stack, reference image), saved beside it in run_recipe.mat;
%   the recipe records their hashes.
report = hadamard_stim.validate_config(cfg);
if ~report.ok
    error("hadamard_stim:InvalidConfig", "The configuration cannot run:\n  %s", ...
        strjoin(report.errors, newline + "  "));
end
canonical = state.cells.canonical;
ref = state.reference;
repo = fileparts(fileparts(fileparts(mfilename("fullpath"))));

recipe.kind = "hadamard_stim_run_recipe";
recipe.schema_version = "1.0.0";
recipe.created_utc = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
recipe.mode = report.mode;
recipe.config = cfg;
recipe.deviations = report.deviations;
recipe.standing_deviations = context.standing_deviations(:)';

recipe.cells.n_cells = size(canonical.cell_coord, 1);
recipe.cells.cell_coord = canonical.cell_coord;
recipe.cells.illum_rois = canonical.illum_rois;
recipe.cells.stim_rois = canonical.stim_rois;
recipe.cells.illum_mask_sha256 = hadamard_stim.metadata.sha256(canonical.illum_mask);
recipe.cells.stim_mask_sha256 = hadamard_stim.metadata.sha256(canonical.stim_mask);
if isfield(canonical, "excluded_coord")
    recipe.cells.excluded_coord = canonical.excluded_coord;
end
if isfield(canonical, "min_val")
    recipe.cells.min_val = canonical.min_val;
end

recipe.matrix = struct("order", cfg.matrix.order, "seed", 0, "generator", "twister", ...
    "sha256", hadamard_stim.metadata.sha256(state.had_mat));

recipe.reference.z_all = ref.z_all;
recipe.reference.z_focus = field_or(ref, "z_focus", NaN);
recipe.reference.had_ref_sha256 = hadamard_stim.metadata.sha256(ref.had_ref);
recipe.reference.had_z_stack_sha256 = hadamard_stim.metadata.sha256(ref.had_z_stack);
if isfield(ref, "acquisitions") && ~isempty(ref.acquisitions)
    recipe.reference.folders = [ref.acquisitions.folder];
end

manifest = fullfile(repo, "tests", "yitong_reference", "MANIFEST.tsv");
recipe.yitong_reference.manifest_sha256 = file_sha256(manifest);

recipe.software.hadamard_stim = hadamard_stim.metadata.git_provenance(repo);
recipe.software.luminos = context.luminos;
gate = hadamard_stim.metadata.hardware_gate(context);
recipe.hardware_validation = gate.validation;
recipe.simulated = isfield(context, "simulated") && context.simulated;
recipe.calibrations.geometry = context.geometry_identity;
recipe.calibrations.blue = context.blue_calibration.identity;
recipe.calibrations.blue_source = context.blue_calibration.source;
if isfield(context, "hardware")
    % What the rig reported about itself (hadamard_stim.luminos.hardware_facts).
    recipe.hardware = context.hardware;
end

recipe.recipe_hash = recipe_hash(recipe);

arrays.canonical = canonical;
arrays.reference = ref;
arrays.had_mat = state.had_mat;
end

function h = recipe_hash(recipe)
text = hadamard_stim.metadata.canonical_json(recipe);
h = hadamard_stim.metadata.sha256(unicode2native(char(text), "UTF-8"));
end

function v = field_or(s, name, default)
v = default;
if isfield(s, name)
    v = s.(name);
end
end

function hex = file_sha256(file)
fid = fopen(file, "r");
if fid < 0
    hex = "unavailable";
    return
end
closer = onCleanup(@() fclose(fid));
hex = hadamard_stim.metadata.sha256(fread(fid, inf, "*uint8"));
end
