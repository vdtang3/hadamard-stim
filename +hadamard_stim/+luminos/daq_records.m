function [records, driven] = daq_records(waveform, profile)
%DAQ_RECORDS Luminos wfm_data entries that play one protocol waveform.
%
%   [records, driven] = hadamard_stim.luminos.daq_records(waveform, profile)
%
%   waveform  struct from scan_waveform or stimulation_waveform: channels
%             (row names) and amplitude [n_rows x n_samples]
%   profile   hadamard_stim.luminos.firefly_profile
%
%   records.ao, records.do  wfm_data records, one per driven row, tagged
%                           script_owner = profile.owner
%   driven                  table of what is driven: channel, port, kind
%
%   A row is driven exactly as computed (sampled_waveform). A row that is
%   zero throughout is not driven at all: his DAQ held such lines at 0 V,
%   but on Firefly some of them now belong to other devices, and leaving
%   them alone is the only safe equivalent (a standing deviation).
records.ao = empty_records();
records.do = empty_records();
channels = string(waveform.channels(:));
names = string({profile.channels.name});
driven = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    'VariableNames', ["channel" "port" "kind"]);
for row = 1:numel(channels)
    samples = waveform.amplitude(row, :);
    if ~any(samples)
        continue
    end
    k = find(names == channels(row), 1);
    if isempty(k)
        error("hadamard_stim:UnknownChannel", ...
            "Waveform row %s is not driven to zero but Firefly has no port for it.", channels(row));
    end
    c = profile.channels(k);
    record = struct("name", char(c.name), "port", char(c.port), ...
        "wavefile", 'hadamard_stim.luminos.sampled_waveform', "params", {{samples}}, ...
        "operation", 'Addition', "concatTime", [], "script_owner", char(profile.owner));
    records.(c.kind)(end+1, 1) = record;
    driven(end+1, :) = {c.name, c.port, c.kind}; %#ok<AGROW>
end
end

function r = empty_records()
r = struct("name", {}, "port", {}, "wavefile", {}, "params", {}, ...
    "operation", {}, "concatTime", {}, "script_owner", {});
end
