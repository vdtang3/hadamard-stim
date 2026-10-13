classdef TestAlpQueueModel < matlab.unittest.TestCase
    %TESTALPQUEUEMODEL What Yitong's DMD showed in each camera frame.
    %
    %   Runs the DMD triggers of his stimulation waveforms (yitong_waveforms)
    %   through the queue his loader built for the same trials (yitong_trace),
    %   using the slave-mode queue model in hadamard_stim.testing. This pins
    %   down finding 7: each stimulation period is played by exactly one
    %   sequence, the queue never runs dry, and the frames see the pictures
    %   in the order the protocol intends. The port's queue plan must
    %   reproduce these, and the Firefly queue gate (Phase 6) checks the
    %   model against the hardware.

    properties
        Waveforms
        Trace
    end

    methods (TestClassSetup)
        function loadFixtures(testCase)
            root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
            fixtures = fullfile(root, "tests", "fixtures");
            testCase.Waveforms = load(fullfile(fixtures, "yitong_waveforms.mat"));
            testCase.Trace = load(fullfile(fixtures, "yitong_trace.mat"), "acquisitions");
        end
    end

    methods (Test)
        function triggersStepThroughEachSequenceInTurn(testCase)
            shown = hadamard_stim.protocol.alp_queue_display([2 3], [2 1], 8);
            testCase.verifyEqual(shown.sequence, [1 1 1 1 2 2 2 0]);
            testCase.verifyEqual(shown.picture, [1 2 1 2 1 2 3 0]);
            testCase.verifyEqual(shown.capacity, 7);
            testCase.verifyTrue(shown.ran_dry);
        end

        function sparsePeriodsEachUseOneSequence(testCase)
            [frames, shown, queue] = testCase.play("stim_sparse", 30);
            testCase.verifyEqual(shown.capacity, 992);
            testCase.verifyFalse(shown.ran_dry);
            for j = 1:30
                period = (j - 1) * 160 + (1:160);
                seq = unique(shown.sequence(ismember(frames, period)));
                testCase.verifyEqual(seq, j, sprintf("period %d", j));
                % Frame 1 brings up the orange picture, which holds through
                % the 144 frames without a pulse. Frame 145 brings up blue
                % alone; frames 146-160 each bring up orange, then blue.
                testCase.verifyEqual(testCase.picturesIn(frames, shown, period(1)), 1);
                testCase.verifyEmpty(testCase.picturesIn(frames, shown, period(2:144)));
                testCase.verifyEqual(testCase.picturesIn(frames, shown, period(145)), 2);
                for f = period(146:160)
                    testCase.verifyEqual(testCase.picturesIn(frames, shown, f), [1 2]);
                end
            end
            % One trigger after the last period, absorbed by the doubled last
            % sequence: orange comes up and holds for the rest of the frames.
            testCase.verifyEqual(testCase.picturesIn(frames, shown, 4801), 1);
            testCase.verifyEqual(shown.sequence(end), 30);
            testCase.verifyEqual(max(frames), 4801);
            testCase.verifyEqual(queue.picnum, 2 * ones(1, 30));
        end

        function hadamardPeriodsEachUseOneSequence(testCase)
            [frames, shown] = testCase.play("stim_hadamard", 8);
            testCase.verifyEqual(shown.capacity, 10800);
            testCase.verifyFalse(shown.ran_dry);
            for j = 1:8
                period = (j - 1) * 600 + (1:600);
                seq = unique(shown.sequence(ismember(frames, period)));
                testCase.verifyEqual(seq, j, sprintf("period %d", j));
                % Every frame of a code brings up orange, then blue.
                for f = period([1 2 300 600])
                    testCase.verifyEqual(testCase.picturesIn(frames, shown, f), [1 2]);
                end
            end
            testCase.verifyEqual(testCase.picturesIn(frames, shown, 4801), 1);
            testCase.verifyEqual(shown.sequence(end), 8);
        end
    end

    methods (Test)
        function theRuntimeCheckAcceptsHisTrials(testCase)
            w = testCase.Waveforms;
            for name = ["stim_sparse" "stim_hadamard"]
                d = w.(name);
                waveform = decode(d);
                n = d.settings.trial.params(4);
                repeats = [d.settings.trial.params(2) * ones(1, n - 1) 2 * d.settings.trial.params(2)];
                report = hadamard_stim.protocol.queue_trigger_invariants(waveform, ...
                    2 * ones(1, n), repeats, d.settings.trial.params);
                testCase.verifyTrue(report.ok, name + ": " + strjoin(report.problems));
            end
        end

        function theRuntimeCheckRefusesAMisalignedQueue(testCase)
            d = testCase.Waveforms.stim_sparse;
            waveform = decode(d);
            % Without his doubled last sequence the final trigger drains the queue.
            report = hadamard_stim.protocol.queue_trigger_invariants(waveform, ...
                2 * ones(1, 30), 16 * ones(1, 30), d.settings.trial.params);
            testCase.verifyFalse(report.ok);
            testCase.verifySubstring(report.problems(1), "queue holds 960");
            % One repeat too many in the first sequence shifts every period.
            report = hadamard_stim.protocol.queue_trigger_invariants(waveform, ...
                2 * ones(1, 30), [17 16 * ones(1, 28) 32], d.settings.trial.params);
            testCase.verifyFalse(report.ok);
            testCase.verifySubstring(report.problems(1), "would show sequence 1");
        end
    end

    methods
        function [frames, shown, queue] = play(testCase, waveform, n_sequences)
            % Camera frame of every DMD trigger, and what each trigger shows,
            % for the first trial in the trace whose queue has n_sequences.
            w = testCase.Waveforms.(waveform);
            cam = rising_edges(w, "cameraTrigger");
            dmd = rising_edges(w, "dmdTrigger");
            frames = discretize(dmd, [cam; inf])';
            testCase.assertFalse(any(isnan(frames)), "a DMD trigger precedes the first frame");

            a = testCase.Trace.acquisitions;
            stim = a([a.kind] == "stimulation");
            queue = stim(find(arrayfun(@(s) s.queue.n_sequences == n_sequences, stim), 1)).queue;
            shown = hadamard_stim.protocol.alp_queue_display( ...
                queue.picnum, queue.repeat, numel(dmd));
        end

        function pictures = picturesIn(~, frames, shown, f)
            pictures = shown.picture(ismember(frames, f));
        end
    end
end

function t = rising_edges(w, channel)
r = find(w.rows == channel);
values = w.values{r}(:);
starts = cumsum([1; w.run_lengths{r}(:)]);
starts = starts(1:end-1);
t = starts(find(values(2:end) > 0 & values(1:end-1) <= 0) + 1);
if values(1) > 0
    t = [starts(1); t];
end
end

function waveform = decode(d)
% The fixture's run-length rows back into samples.
waveform.channels = d.rows;
waveform.amplitude = zeros(numel(d.rows), d.n_samples);
for r = 1:numel(d.rows)
    waveform.amplitude(r, :) = repelem(d.values{r}, d.run_lengths{r});
end
end
