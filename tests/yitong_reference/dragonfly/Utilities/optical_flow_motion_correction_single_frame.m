function [mov_mc,flow_xy]= optical_flow_motion_correction_single_frame(movImg,refImg)

tic

movImg = mat2gray(movImg);
refImg = mat2gray(refImg);

opticFlow = opticalFlowFarneback;

flow = estimateFlow(opticFlow,refImg);
flow = estimateFlow(opticFlow,movImg);
xField = flow.Vx;
yField = flow.Vy;

mov_mc = imwarp(single(movImg),cat(3,flow.Vx,flow.Vy),'cubic');

flow_xy = cat(3,xField,yField);
toc