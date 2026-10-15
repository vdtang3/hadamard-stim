function names = checkpoint_fields(state)
%CHECKPOINT_FIELDS The run-state fields a checkpoint keeps, by session mode.
%
%   names = hadamard_stim.metadata.checkpoint_fields(state)
if isfield(state, "session_mode") && state.session_mode == "spontaneous"
    names = ["session_mode" "next_block" "orange_v" "exposure_waveform_ms" "b0" "b1"];
else
    names = ["next_trial" "cnt" "cnt_had" "picked" "sparse_pictures" "orange_v" ...
        "exposure_waveform_ms" "b0" "b1"];
end
end
