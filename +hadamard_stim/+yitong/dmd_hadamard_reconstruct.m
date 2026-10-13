function [im, scorr] = dmd_hadamard_reconstruct(m_q, folder, cal_prefix, ref_prefix, scorr)
%DMD_HADAMARD_RECONSTRUCT Hadamard image of scan movies on disk.
%
%   [im, scorr] = hadamard_stim.yitong.dmd_hadamard_reconstruct(m_q, folder, cal_prefix, ref_prefix)
%   [im, scorr] = hadamard_stim.yitong.dmd_hadamard_reconstruct(m_q, folder, [], ref_prefix, scorr)
%
%   File-reading wrapper around dmd_hadamard_reconstruct_core: calibrates
%   from every folder matching *cal_prefix* in FOLDER (unless cal_prefix is
%   empty and a calibration SCORR is given, as drift correction calls it),
%   then reconstructs every folder matching *ref_prefix*, one plane each.
%
%   His version kept the calibration in app.function_data.hadamard_cal and
%   overwrote app.function_data.hadamard_ref with the result on every call
%   (notebook, finding 9). Here both are outputs; a caller that reproduces
%   his app state stores im as its hadamard_ref.
%
%   Port of tests/yitong_reference/dragonfly/dmd_control/dmd_hadamard_reconstruct.m
%   SHA-256 c8aa7e8684f038a8ad241e9cc5512064a63dedecc2c4893bc20f3472d7d8b530
%   Changes: app state replaced by the scorr input/output; ls() and vm
%   replaced (hadamard_movie_folders, read_vm_movie); no figure; the
%   arithmetic lives in dmd_hadamard_reconstruct_core and
%   hadamard_pinhole_calibration so in-memory movies can use it. Like his,
%   a cached calibration is used only when cal_prefix is empty.
if nargin < 5 || ~isempty(cal_prefix)
    scorr = hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, ...
        read_movies(folder, cal_prefix));
end
im = hadamard_stim.yitong.dmd_hadamard_reconstruct_core(m_q, ...
    read_movies(folder, ref_prefix), scorr);
end

function movies = read_movies(folder, prefix)
names = hadamard_stim.yitong.hadamard_movie_folders(fullfile(folder, ['*' char(prefix) '*']));
movies = cellfun(@(name) hadamard_stim.yitong.read_vm_movie(fullfile(folder, name)), ...
    names, 'UniformOutput', false);
end
