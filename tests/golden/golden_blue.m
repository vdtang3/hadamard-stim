function data = golden_blue(ctx)
%GOLDEN_BLUE linearize_blue_voltage with Yitong's blueCal.mat.
%   His file is test input only; production uses the active Luminos blue
%   calibration.
golden_use_path(ctx);
cal = load(fullfile(ctx.dragonfly, "Utilities", "blueCal.mat"));
data.calibration_fields = string(fieldnames(cal));
data.v_blue = cal.vBlue;
data.blue_intens_c = cal.blueIntensC;
data.v_grid = linspace(0, 5, 5001);
data.v_linear_grid = linearize_blue_voltage(data.v_grid);
% The stimulation waveform passes v_blue + eps, so 5 V commands fall just
% outside the interpolation range.
data.v_edge = [0 eps 2 2+eps 4 4+eps 5 5+eps];
data.v_linear_edge = linearize_blue_voltage(data.v_edge);
end
