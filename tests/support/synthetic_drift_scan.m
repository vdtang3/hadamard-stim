function im = synthetic_drift_scan(ref, dx, dy, dz)
%SYNTHETIC_DRIFT_SCAN A Hadamard reference image after the sample moved by
%(dx, dy) pixels and is defocused by dz motor units.
im = imtranslate(synthetic_defocus(ref, dz), [dx dy], "cubic", "FillValues", median(ref(:)));
end
