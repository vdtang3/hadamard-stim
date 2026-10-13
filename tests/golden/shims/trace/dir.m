function listing = dir(varargin)
%DIR Shim: the protocol finds its last movie with dir(fullfile('E:', ...)).
%Only paths on the rig's E: drive are faked; everything else is the builtin.
p = string(varargin{1});
if nargin == 1 && startsWith(p, "E:")
    name = extractAfter(p, "*");
    listing = struct("folder", "E:", "name", "000000_" + name);
else
    listing = builtin("dir", varargin{:});
end
end
