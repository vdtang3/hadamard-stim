function names = ls(pattern)
%LS Shim reproducing Windows ls(): a char matrix with one matching name per
%row, which Yitong's reconstruction iterates row by row. On Linux the
%builtin returns a single row, so only the first file would be used.
listing = builtin("dir", pattern);
listing = listing(~ismember({listing.name}, {'.', '..'}));
names = char({listing.name});
end
