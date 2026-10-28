function result = trigger_edge_check(app, profile)
%TRIGGER_EDGE_CHECK Historical diagnostic: the board's trigger edge right after Luminos starts.
%
%   result = hadamard_stim.checks.trigger_edge_check(app)
%
%   Read before any stack or queue is loaded, this is the edge Yitong's
%   loader inherited (it never set one). It is not readiness and nothing
%   reads its record: the protocol sets its queue edge explicitly
%   (cfg.dmd.trigger_edge, rising), and queue playback on a slide
%   (slide_queue_check) verifies that edge on Firefly. Kept for
%   investigating his data. Passes when the board reports an edge.
arguments
    app
    profile struct = hadamard_stim.luminos.firefly_profile()
end
dmd = the_dmd(app, profile);
state = dmd.Get_State();
edge = "";
raw = [];
if isstruct(state) && isfield(state, "trigger_edge")
    raw = state.trigger_edge;
    if isnumeric(raw) && isscalar(raw)
        switch raw
            case 2009, edge = "rising";
            case 2008, edge = "falling";
        end
    elseif (isstring(raw) || ischar(raw)) && ~isempty(raw)
        edge = lower(string(raw));
    end
end
if ismember(edge, ["rising" "falling"])
    evidence = sprintf("Get_State().trigger_edge is %s (%s) right after Luminos started.", ...
        edge, string(mat2str(raw)));
    if isstring(raw) || ischar(raw)
        evidence = sprintf("Get_State().trigger_edge is %s right after Luminos started.", edge);
    end
    passed = true;
else
    evidence = "The DMD did not report a trigger edge (Get_State returned no trigger_edge; is Luminos in debug mode?).";
    passed = false;
end
result = hadamard_stim.checks.check_result("trigger_edge", passed, evidence, ...
    struct("trigger_edge", edge, "raw", raw), hadamard_stim.checks.check_provenance(app, profile));
end

function dmd = the_dmd(app, profile)
[devices, ~] = hadamard_stim.luminos.resolve_hardware(app, profile);
dmd = devices.dmd;
if isempty(dmd)
    error("hadamard_stim:NoDmd", "%s is not on this rig.", profile.devices.dmd.name);
end
end
