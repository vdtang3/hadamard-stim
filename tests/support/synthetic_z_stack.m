function stack = synthetic_z_stack(ref, z_offsets)
%SYNTHETIC_Z_STACK Reference z-stack: one defocused image per offset.
stack = zeros([size(ref) numel(z_offsets)]);
for k = 1:numel(z_offsets)
    stack(:, :, k) = synthetic_defocus(ref, z_offsets(k));
end
end
