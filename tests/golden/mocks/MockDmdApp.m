classdef MockDmdApp < handle
    %MOCKDMDAPP The fields of Yitong's dmd_control app that his DMD
    %functions read or write, and nothing else. UI edit fields are structs
    %with a Value field, as App Designer components are accessed.
    properties
        mask_sequence = []
        mask_sequence_rois = {}
        current_rois = {}
        current_mask = []
        saved_mask = []
        correction_tform = []
        registration_data = []
        ref_im = []
        function_data = struct()
        fig_mask_draw
        h_mask_sequence_rois = gobjects(1)
        dmd
        MaskNoTotalEditField = struct("Value", 0)
        HorizontalOffsetEditField = struct("Value", 0)
        VerticalOffsetEditField = struct("Value", 0)
        SquareSizeEditField = struct("Value", 5)
        ThresholdEditField = struct("Value", 320)
        DMDMaskGenButtonGroup = struct("SelectedObject", struct("Text", "Auto Square"))
        FunArgsTextArea = struct("Value", {{''}})
    end
    methods
        function obj = MockDmdApp(dmd)
            obj.dmd = dmd;
            obj.fig_mask_draw = MockFigure();
        end
    end
end
