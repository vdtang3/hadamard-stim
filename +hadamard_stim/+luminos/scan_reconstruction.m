function [reconstruct_scan, reconstruct_z_stack, scorr] = scan_reconstruction(m_q, calibration_movies)
%SCAN_RECONSTRUCTION How the rig turns its scan acquisitions into Hadamard images.
%
%   [reconstruct_scan, reconstruct_z_stack, scorr] = ...
%       hadamard_stim.luminos.scan_reconstruction(m_q, calibration_movies)
%
%   m_q                 cfg.scan.m_q
%   calibration_movies  cell of uint16 [rows x cols x frames]: the Hadamard
%                       calibration scans (his "had_cal" acquisitions), as
%                       recorded by the imaging camera
%
%   reconstruct_scan(acq)     one drift scan, as his drift correction
%                             reconstructed it (dmd_hadamard_reconstruct)
%   reconstruct_z_stack(acqs) the reference planes, as his z-stack
%                             (hadamard_reconstruct), one movie at a time
%
%   The arithmetic is the +yitong cores, unchanged; this only reads the
%   movies LuminosRig recorded (acq.imaging.file) instead of his
%   Sq_camera.bin folders. The calibration is computed once, as his app
%   cached it.
scorr = hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, calibration_movies);
reconstruct_scan = @(acq) hadamard_stim.yitong.dmd_hadamard_reconstruct_core( ...
    m_q, {movie(acq)}, scorr);
reconstruct_z_stack = @z_stack;

    function had_all = z_stack(acqs)
        % One plane at a time: a z-stack is 21 movies of ~190 MB each.
        had_all = [];
        for k = 1:numel(acqs)
            had = hadamard_stim.yitong.hadamard_reconstruct_core(m_q, {movie(acqs(k))}, scorr);
            had_all = cat(3, had_all, had);
        end
    end
end

function mov = movie(acq)
mov = hadamard_stim.luminos.read_frames(acq.imaging.file, acq.imaging.frame_size);
end
