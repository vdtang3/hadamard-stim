function reference = run_z_reference(cfg, env)
%RUN_Z_REFERENCE The reference z-stack drift correction compares against.
%
%   reference = hadamard_stim.protocol.run_z_reference(cfg, env)
%
%   His script's first cell: Hadamard scans at cfg.z_reference.n_steps + 1
%   planes, cfg.z_reference.half_range either side of the current focus,
%   then back to the focus. The scan settings are the ones he had set by
%   hand before running it (notebook, operator steps): scan waveform, camera
%   cfg.scan.camera_exposure_ms, orange cfg.scan.orange_v, blue off, the
%   63 x 14 scan patterns on the DMD.
%
%   reference.z_all        plane positions, as linspace gave them (the
%                          drift fit uses these)
%   reference.had_z_stack  reconstructed planes
%   reference.acquisitions
%   The plane the stage actually visits is Z0 + zStep*(iz-1), which can
%   differ from z_all in the last bit; both are kept as he had them.
hw = env.hw;
zOrig = hw.motor_position();
Z0 = zOrig - cfg.z_reference.half_range;
Z1 = zOrig + cfg.z_reference.half_range;
nZ = cfg.z_reference.n_steps;
zStep = (Z1-Z0)/nZ;
zAll = linspace(Z0,Z1,nZ+1);

masks = hadamard_stim.yitong.static_hadamard_patterns(true(cfg.dmd.size));
hw.dmd_load_stack(permute(masks, [2 1 3]));
waveform = hadamard_stim.protocol.scan_waveform(cfg, cfg.scan.waveform_period_ms, ...
    cfg.scan.orange_v, size(masks, 3));

prefix = cfg.naming.prefix + "_" + cfg.z_reference.label + "_";
acquisitions = cell(1, nZ + 1);
iRpt = 1;
for iz = 1:nZ+1
    zi = Z0+zStep*(iz-1);
    hw.motor_move_to(zi);
    folder = string(sprintf([char(prefix) 'z%02u_rpt%02i'], [iz iRpt]));
    spec = hadamard_stim.protocol.acquisition_spec("z_stack_plane", folder, waveform, ...
        camera_exposure_ms=cfg.scan.camera_exposure_ms);
    acquisitions{iz} = hw.acquire(spec);
end
hw.motor_move_to(zOrig);

reference.z_all = zAll;
reference.z_focus = zOrig;
reference.acquisitions = [acquisitions{:}];
reference.had_z_stack = env.reconstruct_z_stack(reference.acquisitions);
% The reference lives in the run state and the recipe; 21 copies of the
% scan samples and the plane images are not needed once reconstructed.
reference.acquisitions = rmfield(reference.acquisitions, ...
    intersect(fieldnames(reference.acquisitions), ["waveform" "image"]));
end
