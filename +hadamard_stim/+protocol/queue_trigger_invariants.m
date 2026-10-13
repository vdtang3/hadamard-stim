function report = queue_trigger_invariants(waveform, picnum, repeats, params)
%QUEUE_TRIGGER_INVARIANTS Will this waveform play this queue the way he did?
%
%   report = hadamard_stim.protocol.queue_trigger_invariants(waveform, picnum, repeats, params)
%
%   Runs the waveform's DMD triggers through the slave-mode queue model
%   (alp_queue_display) and checks what his trials relied on (notebook,
%   finding 7):
%     - stimulation period p, of params(3) camera frames, is played entirely
%       by sequence p;
%     - triggers after the last period land in the last sequence;
%     - the queue never runs dry.
%   report.ok, report.problems (strings), report.n_triggers, report.capacity.
%   run_trial refuses to acquire when report.ok is false.
cam = rising_edges(waveform, "cameraTrigger");
dmd = rising_edges(waveform, "dmdTrigger");
shown = hadamard_stim.protocol.alp_queue_display(picnum, repeats, numel(dmd));
report.n_triggers = numel(dmd);
report.capacity = shown.capacity;
problems = strings(0, 1);
if shown.ran_dry
    problems(end+1) = sprintf("%d DMD triggers but the queue holds %d pictures.", ...
        numel(dmd), shown.capacity);
end
if any(dmd < cam(1))
    problems(end+1) = "A DMD trigger comes before the first camera frame.";
end
if isempty(problems)
    frame = discretize(dmd, [cam; inf]);
    period = ceil(frame / params(3));
    n_periods = params(4);
    expected = min(period, n_periods);
    wrong = find(shown.sequence(:) ~= expected(:), 1);
    if ~isempty(wrong)
        problems(end+1) = sprintf(['DMD trigger %d, in camera frame %d (period %d), ' ...
            'would show sequence %d.'], wrong, frame(wrong), period(wrong), shown.sequence(wrong));
    end
end
report.problems = problems;
report.ok = isempty(problems);
end

function t = rising_edges(waveform, channel)
row = waveform.amplitude(waveform.channels == channel, :);
t = find(diff([0 row]) > 0)';
end
