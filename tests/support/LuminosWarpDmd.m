classdef LuminosWarpDmd < hadamard_stim.testing.FakeAlpDmd
    %LUMINOSWARPDMD A fake DMD whose setPatterningROI is Luminos's own warp.
    %
    %   Patterning_Device.setPatterningROI (write_when_complete = false):
    %   the mask, in the calibration reference image's grid, is resized to
    %   unbinned sensor pixels and warped onto the canvas by the calibration
    %   (sensor -> DMD) composed with the reference image's sensor origin.
    %   PairTransform is that calibration. Lets a test compare a mask drawn
    %   in the calibration's own grid with one drawn from another camera area.
    methods
        function obj = LuminosWarpDmd(name)
            obj@hadamard_stim.testing.FakeAlpDmd(name);
        end

        function tmask = setPatterningROI(obj, rmask, options)
            arguments
                obj
                rmask
                options.write_when_complete logical = true
            end
            assert(~options.write_when_complete, "The adapter must not project while drawing.");
            origin = obj.ReferenceRoi(1:2);
            shift = eye(3);
            shift(1, 3) = origin(1);
            shift(2, 3) = origin(2);
            transform = affinetform2d(obj.PairTransform.A * shift);
            rmask = imresize(rmask, size(obj.refimage.img) * obj.refimage.bin);
            tmask = imwarp(rmask, transform, "OutputView", imref2d(obj.Pattern_Canvas_Size()));
        end
    end
end
