function fake_luminos_acquisition(app, bins, options)
%FAKE_LUMINOS_ACQUISITION Stands in for Luminos's Waveform_Camera_Sync_Acquisition.
%
%   Plays the DAQ the way Luminos builds it (DAQ.Calculate_tvec, feval of
%   each record's wavefile, the last sample of every port forced to 0) and
%   logs, per port, the SHA-256 of what would have been output; digital
%   inputs (wfm_data.di) are logged by port. Each row is built and hashed
%   in turn, as Luminos holds them, so a long block's peak is a few rows. Cameras
%   get frames<k>.bin of the requested size (sparse, all zero) in a new
%   folder <datafolder>/<NNNNNN><tag> with an output_data.mat.
arguments
    app
    bins %#ok<INUSA>
    options.tag = ''
    options.fullpath = ''
end
n = numel(app.Acquisitions) + 1;
app.Log(end+1, 1) = "app:acquisition";
if isequal(app.FailOnAcquisition, n)
    error("fake:AcquisitionFailed", "Injected failure in acquisition %d.", n);
end
app.acquisition_active = true;
app.exp_complete = false;
app.round_complete = false;
app.last_run_aborted = false;

daq = app.getDevice("DAQ");
gp = daq.global_props;
N = round(gp.total_time * gp.rate);
tvec = linspace(0, 1/gp.rate*(N - 1), N);
ports = struct("port", {}, "kind", {}, "sha256", {}, "n_samples", {}, "final", {});
% Inputs are recorded, not played: logged with the samples they would
% take, and no data.
if isfield(daq.wfm_data, "di")
    for r = reshape(daq.wfm_data.di, 1, [])
        ports(end+1) = struct("port", string(r.port), "kind", "di", "sha256", "", ...
            "n_samples", N, "final", NaN); %#ok<AGROW>
    end
end
for kind = ["ao" "do"]
    for r = reshape(daq.wfm_data.(kind), 1, [])
        params = r.params;
        data = feval(r.wavefile, tvec, params{:});
        data(end) = 0;
        ports(end+1) = struct("port", string(r.port), "kind", kind, ...
            "sha256", hadamard_stim.metadata.sha256(double(data)), ...
            "n_samples", numel(data), "final", data(end)); %#ok<AGROW>
    end
end

cameras = app.getDevice("Camera");
folder = fullfile(app.datafolder, sprintf('%06d', n) + string(options.tag));
mkdir(folder);
cams = struct("name", {}, "frametrigger_source", {}, "frames", {}, "exposure_s", {});
for k = 1:numel(cameras)
    c = cameras(k);
    cams(end+1) = struct("name", c.name, "frametrigger_source", c.frametrigger_source, ...
        "frames", c.frames_requested, "exposure_s", c.acquisition_exposuretime); %#ok<AGROW>
    roi = c.getROIForAcquisition();
    bytes = c.frames_requested * roi(2) * roi(4) * 2;
    % Sparse: all zeros, and no disk or (on tmpfs) memory until written.
    file = java.io.RandomAccessFile(fullfile(folder, sprintf('frames%d.bin', k)), "rw");
    file.setLength(bytes);
    file.close();
end
Device_Data = {}; %#ok<NASGU>
save(fullfile(folder, "output_data.mat"), "Device_Data");

dmd = app.getDevice("ALP_DMD");
record = struct("tag", string(options.tag), "folder", folder, "rate", gp.rate, ...
    "n_samples", N, "ports", ports, "cameras", cams, ...
    "stack", dmd.Stack, "queue", dmd.Queue, "queue_settings", dmd.QueueSettings, ...
    "dmd_owner", dmd.pattern_owner, "dmd_showing", dmd.Displaying);
if isempty(app.Acquisitions)
    app.Acquisitions = record;
else
    app.Acquisitions(end+1) = record;
end

app.expfolder = folder;
if app.LeaveRunning
    return
end
app.acquisition_active = false;
app.exp_complete = true;
app.round_complete = true;
app.last_run_aborted = isequal(app.AbortOnAcquisition, n);
end
