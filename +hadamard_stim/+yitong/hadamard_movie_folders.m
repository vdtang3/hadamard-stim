function names = hadamard_movie_folders(pattern)
%HADAMARD_MOVIE_FOLDERS Names matching a wildcard, as his ls() loop saw them.
%
%   names = hadamard_stim.yitong.hadamard_movie_folders(pattern)
%
%   His reconstruction lists movie folders with Windows ls(pattern), which
%   returns a char matrix with one name per row, and takes the first
%   whitespace-separated token of each row. This returns the same names in
%   the same order using dir(), which MATLAB provides on every platform
%   (ls() returns all names on one row outside Windows).
%
%   Port of tests/yitong_reference/dragonfly/Utilities/hadamard_reconstruct.m
%   SHA-256 0c85aa74840bbd2143635b3caa5fb8bb2132e96fa24fe1b1df1a3c1336f3631e
%   Port of tests/yitong_reference/dragonfly/dmd_control/dmd_hadamard_reconstruct.m
%   SHA-256 c8aa7e8684f038a8ad241e9cc5512064a63dedecc2c4893bc20f3472d7d8b530
%   Changes: ls() replaced by dir() as described above.
listing = dir(pattern);
listing = listing(~ismember({listing.name}, {'.', '..'}));
f_list = char({listing.name});
names = cell(1, size(f_list,1));
for ii = 1:size(f_list,1)
    cur_f = strsplit(f_list(ii,:));
    names{ii} = cur_f{1};
end
end
