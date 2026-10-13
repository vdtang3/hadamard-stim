function vLinear = linearize_blue_voltage(v)

vMax = 5; % volt, hardware dependent


[fpath,~,~] = fileparts(mfilename('fullpath'));
mf = matfile(fullfile(fpath,'blueCal.mat'));

vBlue = mf.vBlue;
iBlue = mf.blueIntensC';
[~,idxIBlueMax] = max(iBlue);
idxC = find(iBlue > 15,1,'first'):idxIBlueMax;
iBlueC = iBlue(idxC);
vBlueC = vBlue(idxC);
iBlueC = iBlueC/max(iBlueC)*vMax;
ivRatio = vBlueC./iBlueC;
ivRatio = [0 ivRatio];
iBlueC = [0 iBlueC];

vLinear = interp1(iBlueC,ivRatio,v) .* v;
end