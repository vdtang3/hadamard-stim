function selected = use_kinetix_calibration(dmd, camera)
%USE_KINETIX_CALIBRATION Make the DMD project through the Kinetix's own calibration.
%
%   selected = hadamard_stim.luminos.use_kinetix_calibration(dmd, camera)
%
%   Luminos keeps one camera-to-DMD calibration per camera and, at startup,
%   makes the most recently used one active, which can be another camera's.
%   Hadamard Stim draws only through
%   the imaging camera's (the Kinetix's), so when the DMD holds a stored
%   calibration for this camera and is using another, it is selected
%   (Patterning_Device.use_calibration_camera), as choosing the camera in the
%   DMD tab would. Nothing else is done: with no stored calibration for this
%   camera the DMD is left as it is and active_geometry refuses - another
%   camera's transform is never used in its place. selected says whether the
%   selection changed.
selected = false;
identity = dmd.calibration_identity(camera.name);
if identity.has_pair_calibration && ~identity.active_transform_is_pair_transform
    dmd.use_calibration_camera(string(camera.name));
    selected = true;
end
end
