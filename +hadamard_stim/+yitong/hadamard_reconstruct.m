function [had_all, ref_all, scorr] = hadamard_reconstruct(m_q, folder, cal_prefix, ref_prefix)
%HADAMARD_RECONSTRUCT Hadamard and widefield images of scan movies on disk.
%
%   [had_all, ref_all, scorr] = hadamard_stim.yitong.hadamard_reconstruct(m_q, folder, cal_prefix, ref_prefix)
%
%   File-reading wrapper around hadamard_reconstruct_core: calibrates from
%   every folder matching *cal_prefix* in FOLDER, then returns one Hadamard
%   and one widefield plane for every folder matching *ref_prefix*, in
%   name order. The protocol uses it for the reference z-stack.
%
%   Port of tests/yitong_reference/dragonfly/Utilities/hadamard_reconstruct.m
%   SHA-256 0c85aa74840bbd2143635b3caa5fb8bb2132e96fa24fe1b1df1a3c1336f3631e
%   Changes: ls() and vm replaced (hadamard_movie_folders, read_vm_movie);
%   the showPinhole/showResults figures are dropped; the calibration is
%   also returned; the arithmetic lives in hadamard_reconstruct_core and
%   hadamard_pinhole_calibration so in-memory movies can use it.
scorr = hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, read_movies(folder, cal_prefix));
[had_all, ref_all] = hadamard_stim.yitong.hadamard_reconstruct_core(m_q, ...
    read_movies(folder, ref_prefix), scorr);
end

function movies = read_movies(folder, prefix)
names = hadamard_stim.yitong.hadamard_movie_folders(fullfile(folder, ['*' char(prefix) '*']));
movies = cellfun(@(name) hadamard_stim.yitong.read_vm_movie(fullfile(folder, name)), ...
    names, 'UniformOutput', false);
end
