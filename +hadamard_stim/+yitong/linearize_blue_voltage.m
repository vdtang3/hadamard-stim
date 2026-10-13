function vLinear = linearize_blue_voltage(v, calibration)
%LINEARIZE_BLUE_VOLTAGE Blue LED command voltage for a "linear" 0-5 value.
%
%   vLinear = hadamard_stim.yitong.linearize_blue_voltage(v, calibration)
%
%   calibration.v_blue (row) and calibration.blue_intens_c (column) are the
%   vBlue and blueIntensC of a blue calibration, as in his blueCal.mat.
%   Points with intensity <= 15 (his raw camera units) are dropped: parity
%   issue P2, kept exactly.
%
%   Port of tests/yitong_reference/dragonfly/Utilities/linearize_blue_voltage.m
%   SHA-256 d885196832e22acf8e7b324b0f7c1ca0976b77d11d5b4e8cdff381bb2997e5b8
%   Changes: the calibration is an argument instead of blueCal.mat beside
%   the file (production passes the active Luminos calibration).

vMax = 5; % volt, hardware dependent

vBlue = calibration.v_blue;
iBlue = calibration.blue_intens_c';
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
