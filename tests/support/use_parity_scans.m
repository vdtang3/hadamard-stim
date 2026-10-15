function use_parity_scans(c, root)
%USE_PARITY_SCANS Make a prepared session's scans reconstruct to the parity world.
%
%   use_parity_scans(controller, repo_root)
%
%   The fake cameras record zeros, so after prepare_rig the scans are
%   reconstructed to the images the parity world gives (as
%   TestLuminosRunRecords does): the synthetic drift at the k-th drift
%   scan, the synthetic z-stack, and his reference image for a reference
%   scan.
[~, parity, ~, inputs] = parity_environment(fullfile(root, "tests", "fixtures"));
world = parity.hw.world;
n = 0;
c.Env.reconstruct_scan = @reconstruct;
c.Env.reconstruct_z_stack = parity.reconstruct_z_stack;

    function im = reconstruct(acq)
        if acq.kind == "reference_scan"
            im = inputs.ref_im;
            return
        end
        n = n + 1;
        im = world.scan_image([], struct("kind", acq.kind, "drift_scan_number", n, ...
            "motor_z", acq.motor_z));
    end
end
