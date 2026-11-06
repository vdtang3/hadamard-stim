function [roi, bin] = camera_grid(camera)
%CAMERA_GRID The pixel grid a camera acquires in now.
%
%   [roi, bin] = hadamard_stim.luminos.camera_grid(camera)
%
%   roi is [x0 y0 width height] in unbinned sensor pixels - the convention
%   of a Snap's ref2d world limits and of Patterning_Device.reference_geometry
%   - from Camera.getROIForAcquisition, which is [x0 width y0 height].
%   bin is the camera's binning.
r = double(reshape(camera.getROIForAcquisition(), 1, []));
roi = [r(1) r(3) r(2) r(4)];
bin = double(camera.bin);
end
