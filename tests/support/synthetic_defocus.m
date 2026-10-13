function im = synthetic_defocus(ref, dz)
%SYNTHETIC_DEFOCUS Asymmetric blur standing in for defocus by dz (motor
%units). Blur grows along x for dz > 0 and along y for dz < 0, so +dz and
%-dz give different spatial spectra, as Yitong's Z-drift correlation needs.
s0 = 0.5;
k = 80;    % blur per motor unit; 0.030 units gives ~2.9 px
sx = s0 + k * max(dz, 0);
sy = s0 + k * max(-dz, 0);
im = imgaussfilt(ref, [sy sx]);
end
