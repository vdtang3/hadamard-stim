function [had_all, ref_all] = hadamard_reconstruct_core(m_q, ref_movies, scorr, offset)
%HADAMARD_RECONSTRUCT_CORE Hadamard and widefield images of movies in memory.
%
%   [had_all, ref_all] = hadamard_stim.yitong.hadamard_reconstruct_core(m_q, ref_movies, scorr)
%
%   ref_movies is a cell array of scan movies, uint16 or uint8 [rows x cols x
%   frames] as the camera wrote them; scorr comes from
%   hadamard_pinhole_calibration. Returns one Hadamard plane and one
%   widefield (mean) plane per movie. Unlike dmd_hadamard_reconstruct_core
%   it reconstructs each repeat separately, sums them and divides by the
%   code length n = m+1, not by the number of repeats (notebook, finding
%   10): a uniform scale factor.
%
%   Port of tests/yitong_reference/dragonfly/Utilities/hadamard_reconstruct.m
%   SHA-256 0c85aa74840bbd2143635b3caa5fb8bb2132e96fa24fe1b1df1a3c1336f3631e
%   Changes: the reconstruction loop of his file, taking movies instead of
%   reading folders; vm replaced by arrays (correct_blank_marker, minus,
%   frame indexing, times, mean, ffzpad written out); the pinhole padding
%   is computed once per movie instead of once per repeat (same values);
%   8-bit (uint8) movies average the blank marker without saturating; the
%   camera offset is an argument (100 if not given, his).
if nargin < 4
    offset = 100;    % his; camera_format f.offset gives the mode's
end
n = m_q(1)+1;
had_all = [];
ref_all = [];
for ii = 1:numel(ref_movies)
    mov_h = correct_blank_marker(ref_movies{ii});
    mov_h = bsxfun(@minus,double(mov_h),double(offset));
    [rows, cols, frames] = size(mov_h);
    ref = mean(mov_h,3);
    had = zeros([rows cols]);
    pinholes = ffzpad(scorr,[rows cols]);
    for jj = 1:(frames/n)
        had_j = mean(bsxfun(@times,mov_h(:,:,(1:n)+(jj-1)*n),pinholes),3)*2;
        had = had + had_j;
    end
    had = had/n;
    had_all = cat(3,had_all,had);
    ref_all = cat(3,ref_all,ref);
end
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
