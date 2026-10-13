function [state, records] = run_protocol(cfg, env, state)
%RUN_PROTOCOL Yitong's trial loop, from state.next_trial to cfg.trials.last.
%
%   [state, records] = hadamard_stim.protocol.run_protocol(cfg, env, state)
%
%   cfg    hadamard_stim.default_config, completed and validated
%   state  hadamard_stim.protocol.new_run_state, or a resumed checkpoint
%   env    what the protocol runs on:
%     env.hw                  hardware (hadamard_stim.testing.SimulatedRig
%                             off-rig; the +luminos adapter on the rig)
%     env.geometry            camera-to-DMD mapping (see
%                             hadamard_stim.testing.yitong_affine_geometry)
%     env.blue_calibration    the blue LED curve
%     env.reconstruct_scan    @(acq) Hadamard image of a drift scan
%     env.waveform_cache      optional containers.Map
%     env.after_trial         optional @(state, record), e.g. a checkpoint
%     env.stop_requested      optional @() true to stop after this trial
%
%   Each trial is complete when it returns: state.next_trial then names the
%   next one, so stopping or failing between trials leaves a state that
%   resumes exactly.
records = {};
for iTrial = state.next_trial:cfg.trials.last
    [state, record] = hadamard_stim.protocol.run_trial(cfg, env, state, iTrial);
    state.next_trial = iTrial + 1;
    records{end+1} = record; %#ok<AGROW>
    if isfield(env, "after_trial") && ~isempty(env.after_trial)
        env.after_trial(state, record);
    end
    if isfield(env, "stop_requested") && ~isempty(env.stop_requested) && env.stop_requested()
        break
    end
end
records = [records{:}];
end
