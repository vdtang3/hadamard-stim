function data = read_vm_movie(folder)
%READ_VM_MOVIE A camera movie folder as the lab's vm class reads it.
%
%   data = hadamard_stim.yitong.read_vm_movie(folder)
%
%   Reads Sq_camera.bin (uint16, little endian, column-major per frame with
%   columns first) using the frame size in experimental_parameters.txt, and
%   returns uint16 [rows x cols x frames]. This is what vm(folder).data
%   returns in his reconstruction code (lab "Image Processing/@vm/vm.m",
%   load_movie_uint.m, readBinMov.m), reduced to the one file layout used.
%
%   Port of tests/yitong_reference/dragonfly/Utilities/hadamard_reconstruct.m
%   SHA-256 0c85aa74840bbd2143635b3caa5fb8bb2132e96fa24fe1b1df1a3c1336f3631e
%   Port of tests/yitong_reference/dragonfly/dmd_control/dmd_hadamard_reconstruct.m
%   SHA-256 c8aa7e8684f038a8ad241e9cc5512064a63dedecc2c4893bc20f3472d7d8b530
%   Changes: replaces the vm(folder) calls of both files with plain arrays;
%   only the Sq_camera.bin + experimental_parameters.txt layout is read.
expfile = fullfile(folder,'experimental_parameters.txt');
binfile = fullfile(folder,'Sq_camera.bin');
if ~(exist(expfile,'file') && exist(binfile,'file'))
    error('hadamard_stim:MovieFolder', ...
        '%s does not hold Sq_camera.bin and experimental_parameters.txt.', folder);
end
numcell = strsplit(fileread(expfile),'[\D]','DelimiterType','RegularExpression');
rows = str2double(numcell{3});
cols = str2double(numcell{2});

fid = fopen(binfile);
closer = onCleanup(@() fclose(fid));
tmp = fread(fid, '*uint16', 'l');
nrow = int64(rows);
ncol = int64(cols);
L = int64(floor(length(tmp)/(nrow*ncol)));
tmp = tmp(1:L*nrow*ncol,1);
mov = reshape(tmp, [ncol nrow L]);
data = permute(mov, [2 1 3]);
end
