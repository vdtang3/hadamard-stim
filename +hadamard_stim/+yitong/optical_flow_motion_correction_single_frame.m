function [mov_mc, flow_xy] = optical_flow_motion_correction_single_frame(movImg, refImg)
%OPTICAL_FLOW_MOTION_CORRECTION_SINGLE_FRAME Farneback flow from refImg to movImg.
%
%   [mov_mc, flow_xy] = hadamard_stim.yitong.optical_flow_motion_correction_single_frame(movImg, refImg)
%
%   flow_xy(:, :, 1:2) is the per-pixel (x, y) displacement that drift
%   correction averages around each cell.
%
%   Port of tests/yitong_reference/dragonfly/Utilities/optical_flow_motion_correction_single_frame.m
%   SHA-256 ab6a323a67dc585e847054edf63d5492d7da634363343c635814e383a035fee5
%   Changes: tic/toc removed.
movImg = mat2gray(movImg);
refImg = mat2gray(refImg);

opticFlow = opticalFlowFarneback;

flow = estimateFlow(opticFlow,refImg); %#ok<NASGU> primes the estimator with the reference
flow = estimateFlow(opticFlow,movImg);
xField = flow.Vx;
yField = flow.Vy;

mov_mc = imwarp(single(movImg),cat(3,flow.Vx,flow.Vy),'cubic');

flow_xy = cat(3,xField,yField);
end
