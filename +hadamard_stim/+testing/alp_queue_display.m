function shown = alp_queue_display(pictures, repeats, n_triggers)
%ALP_QUEUE_DISPLAY Which queued picture each DMD trigger brings up.
%
%   shown = hadamard_stim.testing.alp_queue_display(pictures, repeats, n_triggers)
%
%   Model of an ALP in slave mode with ALP_PROJ_SEQUENCE_QUEUE and
%   ALP_BIN_UNINTERRUPTED, as loaded by Yitong's load_sequence_multi and by
%   ALP_DMD.Load_Sequence_Queue. Sequence k holds pictures(k) pictures and
%   plays them repeats(k) times. Each trigger brings up the next picture,
%   which stays until the next trigger; when sequence k has had
%   pictures(k) * repeats(k) triggers, the next trigger starts sequence k+1.
%
%   shown.sequence(t), shown.picture(t)  what trigger t brings up (1-based)
%   shown.capacity                       triggers the queue can take
%   shown.ran_dry                        more triggers than that arrived
%
%   Triggers after the queue has run dry are reported as sequence 0 and
%   picture 0. What the controller actually does then has not been observed
%   on Firefly (Phase 6); Yitong's protocol never gets there, which is what
%   the tests check.
arguments
    pictures (1, :) double {mustBeInteger, mustBePositive}
    repeats (1, :) double {mustBeInteger, mustBePositive}
    n_triggers (1, 1) double {mustBeInteger, mustBeNonnegative}
end
assert(numel(pictures) == numel(repeats), ...
    "hadamard_stim:QueueShape", "One repeat count per sequence.");

per_sequence = pictures .* repeats;
shown.capacity = sum(per_sequence);
shown.ran_dry = n_triggers > shown.capacity;

t = 1:min(n_triggers, shown.capacity);
ends = cumsum(per_sequence);
sequence = discretize(t, [0 ends] + 0.5);
starts = [0 ends(1:end-1)];
within = t - starts(sequence);                  % 1-based position in the sequence
picture = mod(within - 1, pictures(sequence)) + 1;

shown.sequence = zeros(1, n_triggers);
shown.picture = zeros(1, n_triggers);
shown.sequence(t) = sequence;
shown.picture(t) = picture;
end
