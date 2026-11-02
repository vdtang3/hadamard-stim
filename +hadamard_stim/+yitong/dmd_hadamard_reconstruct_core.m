function im = dmd_hadamard_reconstruct_core(m_q, ref_movies, scorr, offset)
%DMD_HADAMARD_RECONSTRUCT_CORE Hadamard image of scan movies in memory.
%
%   im = hadamard_stim.yitong.dmd_hadamard_reconstruct_core(m_q, ref_movies, scorr)
%
%   ref_movies is a cell array of scan movies, uint16 or uint8 [rows x cols x
%   frames] as the camera wrote them (frames a multiple of m+1); scorr is a
%   calibration from hadamard_pinhole_calibration. Returns one Hadamard
%   plane per movie, [rows x cols x numel(ref_movies)]: the repeats are
%   averaged first, then weighted by the pinholes, averaged over the code
%   and doubled. The lab vm class operations are written out on arrays
%   with the same element types, so the values are bit for bit his.
%
%   Port of tests/yitong_reference/dragonfly/dmd_control/dmd_hadamard_reconstruct.m
%   SHA-256 c8aa7e8684f038a8ad241e9cc5512064a63dedecc2c4893bc20f3472d7d8b530
%   Changes: the reconstruction loop of his file, taking movies instead of
%   reading folders; vm replaced by arrays (correct_blank_marker, minus,
%   times, mean, ffzpad written out below); 8-bit (uint8) movies average
%   the blank marker without saturating; the camera offset is an argument
%   (100 if not given, his).
if nargin < 4
    offset = 100;    % his; camera_format f.offset gives the mode's
end
n = m_q(1)+1;
had_all = [];
for ii = 1:numel(ref_movies)
    mov_h = correct_blank_marker(ref_movies{ii});
    mov_h = bsxfun(@minus,double(mov_h),double(offset));
    [rows, cols, ~] = size(mov_h);
    mov_h = squeeze(mean(reshape(mov_h,rows,cols,n,[]),4));
    had = mean(bsxfun(@times,mov_h,ffzpad(scorr,[rows cols])),3)*2;
    had_all = cat(3,had_all,had);
end
im = had_all;
end

function data = correct_blank_marker(data)
% vm.correct_blank_marker, in the movie's own class (uint16 as his were).
% 8-bit movies: the sum of two counts above 127 would saturate at 255, so
% it is taken in uint16 and the mean returned in uint8 (same rounding).
crow = ceil(size(data,1)/2);
if isa(data,'uint8')
    data(crow,1:4,:) = uint8((uint16(data(crow+1,1:4,:)) + uint16(data(crow-1,1:4,:)))/2);
else
    data(crow,1:4,:) = (data(crow+1,1:4,:) + data(crow-1,1:4,:))/2;
end
end

function m = ffzpad(m,ts)
% vm.ffzpad: centred zero pad or crop to ts.
m = permute(ffzpadrows(m,ts(1)),[2 1 3:ndims(m)]);
m = permute(ffzpadrows(m,ts(2)),[2 1 3:ndims(m)]);
end

function m = ffzpadrows(m,rows)
[sr, sc, sf] = size(m);
dr = rows - sr;
if dr < 0
    m = m(1-floor(dr/2):end+ceil(dr/2),:,:);
elseif dr > 0
    m = [zeros(ceil(dr/2),sc,sf); m; zeros(floor(dr/2),sc,sf)];
end
end
