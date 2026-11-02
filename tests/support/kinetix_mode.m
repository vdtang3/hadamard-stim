function kinetix_mode(camera, mode)
%KINETIX_MODE Put a fake Kinetix in a Bit Depth mode, as Luminos reports it.
%
%   kinetix_mode(camera, "hfw8")        8-bit High Full Well (Speed Mode)
%   kinetix_mode(camera, "standard16")  16-bit Standard (Dynamic Range Mode)
%   kinetix_mode(camera, "unmeasured8") an 8-bit mode with no measured offset
%
%   The ids and labels are the ones Yi-Chieh Huang's Firefly recordings
%   carry (output_data.mat, 2026-08 and 2026-10).
switch mode
    case "hfw8"
        assign_mode(camera, 8, 8, 'p1_s0_g1', '8-bit High Full Well (Speed Mode)');
    case "standard16"
        assign_mode(camera, 16, 16, 'p2_s0_g1', '16-bit Standard (Dynamic Range Mode)');
    case "unmeasured8"
        assign_mode(camera, 8, 8, 'p1_s0_g0', '8-bit Low Noise (Speed Mode)');
    otherwise
        error("kinetix_mode:Unknown", "No mode %s.", mode);
end
end

function assign_mode(camera, storage, pixel, id, label)
camera.bit_depth = storage;
camera.pixel_bit_depth = pixel;
camera.bit_mode_id = id;
camera.bit_mode_label = label;
end
