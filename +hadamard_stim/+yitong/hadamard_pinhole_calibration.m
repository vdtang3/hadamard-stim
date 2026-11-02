function scorr = hadamard_pinhole_calibration(m_q, cal_movies, offset)
%HADAMARD_PINHOLE_CALIBRATION Digital pinholes from Hadamard calibration movies.
%
%   scorr = hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, cal_movies)
%   scorr = hadamard_stim.yitong.hadamard_pinhole_calibration(m_q, cal_movies, offset)
%
%   m_q is [m q] (63 14); cal_movies is a cell array of calibration movies,
%   uint16 (or uint8, 8-bit Kinetix) [rows x cols x frames] as the camera wrote them (what his code
%   read from Sq_camera.bin; see read_vm_movie), each m+1 patterns
%   repeated. offset is the camera's dark offset in the movies' counts
%   (camera_format f.offset; 100 if not given, his). At offset 100 any
%   movie but uint8 is his arithmetic exactly: in uint16 the subtraction
%   saturates at 0 (the sum over recordings is double). 8-bit movies, and
%   any other offset, are subtracted in double, without clipping: the
%   8-bit offset is about 20, and in uint8 at 100 most of a movie is 0.
%   Returns
%   double [rows x cols x m+1], each
%   camera pixel's pinhole weights already multiplied by the Hadamard code:
%   what his code stored as app.function_data.hadamard_cal (.data).
%
%   This block is identical in his hadamard_reconstruct.m and
%   dmd_hadamard_reconstruct.m. The lab vm class operations it used are
%   written out on plain arrays with the same element types, so values are
%   bit for bit his (vm methods: mtimes, rdivide, max, abs, imresize, cat,
%   times, constructor with a size).
%
%   Port of tests/yitong_reference/dragonfly/Utilities/hadamard_reconstruct.m
%   SHA-256 0c85aa74840bbd2143635b3caa5fb8bb2132e96fa24fe1b1df1a3c1336f3631e
%   Port of tests/yitong_reference/dragonfly/dmd_control/dmd_hadamard_reconstruct.m
%   SHA-256 c8aa7e8684f038a8ad241e9cc5512064a63dedecc2c4893bc20f3472d7d8b530
%   Changes: takes movies in memory, not folders found with ls(); vm replaced by
%   arrays; the Windows-only memory() check (refuse to run below 16x the
%   pinhole array in free RAM) is dropped; the offset is an argument, and
%   uint8 movies or another offset are subtracted in double (8-bit modes).
if nargin < 3
    offset = 100;
end
n = m_q(1)+1;
m = m_q(1);

if offset == 100 && ~any(cellfun(@(c) isa(c,'uint8'), cal_movies))
    mov_hcal = [];
    for ii = 1:numel(cal_movies)
        mov = cal_movies{ii};
        mov_hcal = cat(4,mov_hcal,mov-100);           % uint16: saturates at 0, as his did
    end
    mov_hcal = sum(mov_hcal,4);
else
    % Same sum, in double: integer counts, so exact in either order.
    mov_hcal = 0;
    for ii = 1:numel(cal_movies)
        mov_hcal = mov_hcal + (double(cal_movies{ii}) - offset);
    end
end
[rows, cols, ~] = size(mov_hcal);
mov_hcal = single(mean(reshape(mov_hcal,rows,cols,n,[]),4));

hadtraces = hadamard_stim.yitong.hadamard_bincode_nopermutation(m)'*2-1;

% vm mtimes: double(tovec(data)) * matrix, reshaped back to frames
ccorr = reshape(double(reshape(mov_hcal,rows*cols,[]))*hadtraces,rows,cols,[]);
clear mov_hcal
ccorr = bsxfun(@rdivide,ccorr,double(imgaussfilt(max(abs(ccorr),[],3),1)));

maxImgSize = 4096;
ups_n = floor(maxImgSize/max([rows cols])/2)*2;
ccorr = imresize(ccorr,ups_n,'bilinear');
ccorr = cat(3,ccorr,bsxfun(@times,-1,ccorr));
[~,ind] = max(ccorr,[],3);
clear ccorr
rpattern = ones(size(ind));
rpattern(ind>size(hadtraces,2)) = -1;
ind(ind>size(hadtraces,2)) = ind(ind>size(hadtraces,2)) - size(hadtraces,2);
sind = sparse(1:numel(ind),ind,rpattern);
vmind = reshape(full(sind),size(ind,1),size(ind,2),[]);
clear ind sind
scorr = imresize(vmind,1/ups_n,'bilinear');
clear vmind
[srows, scols, ~] = size(scorr);
scorr = reshape(double(reshape(scorr,srows*scols,[]))*hadtraces',srows,scols,[]);
end
