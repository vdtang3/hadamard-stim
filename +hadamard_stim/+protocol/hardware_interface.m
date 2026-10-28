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
%     dmd_show_mask(mask)                  one picture, canvas [W x L], shown
%                                          continuously with no triggers
%                                          (spontaneous blocks)
%     acq = acquire(spec)                  one synchronized acquisition of
%                                          spec (acquisition_spec); returns
%                                          spec plus what was done
%     im = movie_mean(acq, frames)         mean image of those frames
%     n = camera_rows()                    sensor rows in the imaging
%                                          camera's acquisition area (his
%                                          camApp.liveArea(1)): the scan's
%                                          rolling-shutter blanking
%
%   Used by the controller around a session of hardware use (never by
%   +protocol):
%     report = begin(cfg)                  read-only checks that the rig can
%                                          run cfg, then adopt it: a readiness
%                                          report (report.can_run, false only
%                                          for blockers; report.failures, the
%                                          blockers' messages)
%     report = release()                   return the rig to how it was
%                                          found; safe to call at any time,
%                                          any number of times; report.ok,
%                                          report.steps, report.errors
%     abort()                              stop as soon as possible: abandon
%                                          the acquisition in progress, and
%                                          refuse every later operation with
%                                          hadamard_stim:Aborted until the
%                                          next begin. Safe to call from a
%                                          callback while an operation waits.
methods_ = ["motor_position" "motor_move_to" "dmd_load_stack" "dmd_load_queue" ...
    "dmd_show_mask" "acquire" "movie_mean" "camera_rows" "begin" "release" "abort"];
end
