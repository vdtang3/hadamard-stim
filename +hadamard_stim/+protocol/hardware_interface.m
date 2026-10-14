function methods_ = hardware_interface()
%HARDWARE_INTERFACE The hardware operations the protocol uses, and nothing more.
%
%   names = hadamard_stim.protocol.hardware_interface()
%
%   Everything the protocol does to the rig goes through an object with
%   these methods: hadamard_stim.testing.SimulatedRig off the rig,
%   hadamard_stim.luminos.LuminosRig on it. DMD details (ALP calls, packing,
%   the trigger edge, picture time, ownership) live entirely behind
%   dmd_load_queue and dmd_load_stack.
%
%   Used by +protocol:
%     z = motor_position()
%     motor_move_to(z)                     absolute, returns when there
%     dmd_load_stack(masks)                scan patterns, canvas [W x L x n],
%                                          one picture per trigger
%     dmd_load_queue(sequences, repeats)   sequences{k} canvas [W x L x n_k],
%                                          played repeats(k) times in turn
%     acq = acquire(spec)                  one synchronized acquisition of
%                                          spec (acquisition_spec); returns
%                                          spec plus what was done
%     im = movie_mean(acq, frames)         mean image of those frames
%
%   Used by the controller around a session of hardware use (never by
%   +protocol):
%     report = begin(cfg)                  read-only checks that the rig can
%                                          run cfg, then adopt it; report.ok,
%                                          report.failures (strings)
%     release()                            return the rig to how it was
%                                          found; safe to call at any time,
%                                          any number of times
methods_ = ["motor_position" "motor_move_to" "dmd_load_stack" "dmd_load_queue" ...
    "acquire" "movie_mean" "begin" "release"];
end
