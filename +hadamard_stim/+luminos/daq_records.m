function [records, driven] = daq_records(waveform, profile, options)
%DAQ_RECORDS Luminos wfm_data entries that play one protocol waveform.
%
%   [records, driven] = hadamard_stim.luminos.daq_records(waveform, profile)
%   [...] = daq_records(..., skip_rows=names, encoder_lines=lines)
%
%   waveform  struct from scan_waveform or stimulation_waveform (dense:
%             channels and amplitude [n_rows x n_samples]) or from
%             spontaneous_waveform (repeated: rows of a constant head, a
%             unit and n_repeat)
%   profile   hadamard_stim.luminos.firefly_profile
%   skip_rows rows not to drive although the waveform has them: the face
%             camera's rows when it is off (profile.face_camera_rows)
%   encoder_lines  digital lines to record as the wheel encoder's A and B
%             (empty: none)
%
%   records.ao, records.do  wfm_data records, one per driven row, tagged
%                           script_owner = profile.owner
%   records.di              one per encoder line, named as
%                           profile.wheel_encoder.names, same tag
%   driven                  table of what is driven: channel, port, kind
%
%   A dense row is driven exactly as computed (sampled_waveform); a
%   repeated row by its description (repeated_waveform), which Luminos
%   expands once. A row that is zero throughout is not driven at all: his
%   DAQ held such lines at 0 V, but on Firefly some of them now belong to
%   other devices, and leaving them alone is the only safe equivalent (a
%   standing deviation).
arguments
    waveform struct
    profile struct
    options.skip_rows string = strings(1, 0)
    options.encoder_lines string = strings(1, 0)
end
records.ao = empty_records();
records.do = empty_records();
records.di = struct("name", {}, "port", {}, "script_owner", {});
channels = string(waveform.channels(:));
names = string({profile.channels.name});
driven = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    'VariableNames', ["channel" "port" "kind"]);
repeated = isfield(waveform, "form") && waveform.form == "repeated";
for row = 1:numel(channels)
    if ismember(channels(row), options.skip_rows)
        continue
    end
    if repeated
        r = waveform.rows(row);
        if ~(r.head_samples > 0 && r.head_value ~= 0) && ~(r.n_repeat > 0 && any(r.unit))
            continue
        end
        wavefile = 'hadamard_stim.luminos.repeated_waveform';
        params = {r.head_value, r.head_samples, r.unit, r.n_repeat};
    else
        samples = waveform.amplitude(row, :);
        if ~any(samples)
            continue
        end
        wavefile = 'hadamard_stim.luminos.sampled_waveform';
        params = {samples};
    end
    k = find(names == channels(row), 1);
    if isempty(k)
        error("hadamard_stim:UnknownChannel", ...
            "Waveform row %s is not driven to zero but Firefly has no port for it.", channels(row));
    end
    c = profile.channels(k);
    record = struct("name", char(c.name), "port", char(c.port), ...
        "wavefile", wavefile, "params", {params}, ...
        "operation", 'Addition', "concatTime", [], "script_owner", char(profile.owner));
    records.(c.kind)(end+1, 1) = record;
    driven(end+1, :) = {c.name, c.port, c.kind}; %#ok<AGROW>
end
lines = options.encoder_lines;
for k = 1:numel(lines)
    records.di(end+1, 1) = struct("name", char(profile.wheel_encoder.names(k)), ...
        "port", char(lines(k)), "script_owner", char(profile.owner));
end
end

function r = empty_records()
r = struct("name", {}, "port", {}, "wavefile", {}, "params", {}, ...
    "operation", {}, "concatTime", {}, "script_owner", {});
end
