classdef MockFigure < handle
    %MOCKFIGURE Stand-in for the DMD app's mask-drawing figure.
    %   Yitong's dmd_draw_hidden calls figure(app.fig_mask_draw) before every
    %   mask render, purely for display. On a real figure that raises a
    %   window (about 0.2 s each, 30 times per trial). Because this class
    %   defines its own figure() and get(), MATLAB dispatches those calls
    %   here and they do nothing; isvalid() is true as for a live handle.
    methods
        function figure(~)
        end
        function value = get(~, ~)
            value = [];     % no 'Children': nothing drawn to clean up
        end
    end
end
