classdef TestOrangePreview < matlab.unittest.TestCase
    %TESTORANGEPREVIEW The approved cells' orange mask, held on the DMD to choose orange_start_v.
    %
    %   An operator aid: the exact illum_mask the trials use, shown
    %   statically through the package's own DMD ownership, with the orange
    %   LED (Luminos's "Red LED 615" modulator) held at orange_start_v and
    %   following it. Every other rig or field-of-view operation ends it,
    %   and ending it always turns the LED off before blanking the DMD and
    %   releasing it.

    properties
        Root
        Folder
    end

    methods (TestClassSetup)
        function setUp(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "tests", "support")));
            incoming = rng;
            testCase.addTeardown(@() rng(incoming));
        end
    end

    methods (TestMethodSetup)
        function makeFolder(testCase)
            testCase.Folder = string(tempname);
            mkdir(testCase.Folder);
            testCase.addTeardown(@() rmdir(testCase.Folder, "s"));
        end
    end

    methods (Test)
        function itNeedsApprovedCells(testCase)
            [c, ~, cfg] = tab_session(testCase.Folder);
            act(c, "set_config", struct("config", cfg));
            act(c, "prepare_rig");
            use_parity_scans(c, testCase.Root);
            act(c, "acquire_reference_image");
            act(c, "propose_cells");
            testCase.verifyFalse(c.legalActions().start_orange_preview);
            r = hadamard_stim.apply_controller_action(c, "start_orange_preview", struct(), c.Revision);
            testCase.verifyFalse(r.ok);
            act(c, "approve_cells");
            testCase.verifyTrue(c.legalActions().start_orange_preview);
        end

        function itShowsTheApprovedMaskAtTheStartingOrange(testCase)
            [c, app] = testCase.approved();
            dmd = app.getDevice("ALP_DMD");
            orange = app.getDevice("NI_DAQ_Modulator", "name", "Red LED 615");
            n = numel(app.Acquisitions);
            r = act(c, "start_orange_preview");
            testCase.verifyTrue(r.state.legal_actions.stop_orange_preview);
            testCase.verifyFalse(r.state.legal_actions.start_orange_preview);
            testCase.verifyEqual(dmd.Displaying, "static");
            testCase.verifyEqual(logical(dmd.Target), logical(c.Cells.illum_mask));
            testCase.verifyEqual(dmd.pattern_owner, "hadamard_stim");
            testCase.verifyEqual(orange.level, c.Config.stimulation.orange_start_v);
            testCase.verifyEqual(r.state.orange_preview.orange_v, c.Config.stimulation.orange_start_v);
            testCase.verifyEqual(r.state.orange_preview.n_cells, size(c.Cells.cell_coord, 1));
            testCase.verifyEqual(numel(app.Acquisitions), n, "nothing is acquired");
            % The session's cells are untouched.
            testCase.verifyEqual(c.LifecycleState, "READY");

            % orange_start_v follows to the LED.
            act(c, "update_config", struct("changes", struct("path", "stimulation.orange_start_v", "value", 1.7)));
            testCase.verifyEqual(orange.level, 1.7);
            testCase.verifyEqual(c.OrangePreview.orange_v, 1.7);

            % Stop: LED off, then the DMD dark, then released.
            app.Log = strings(0, 1);
            act(c, "stop_orange_preview");
            testCase.verifyEqual(orange.level, 0);
            testCase.verifyEqual(dmd.Displaying, "dark");
            testCase.verifyEqual(dmd.pattern_owner, "");
            order = [find(app.Log == "Red LED 615:set_level=0", 1), find(app.Log == "DMD (shared):Write_Dark", 1), ...
                find(app.Log == "DMD (shared):Release_Pattern_Ownership", 1)];
            testCase.verifyNumElements(order, 3);
            testCase.verifyTrue(issorted(order));
            testCase.verifyEmpty(c.getState().orange_preview);
        end

        function startingAndStoppingAgainIsSafe(testCase)
            [c, app] = testCase.approved();
            orange = app.getDevice("NI_DAQ_Modulator", "name", "Red LED 615");
            c.stopOrangePreview();                    % nothing on: nothing happens
            c.startOrangePreview();
            c.stopOrangePreview();
            c.stopOrangePreview();
            c.startOrangePreview();
            testCase.verifyEqual(orange.level, c.Config.stimulation.orange_start_v);
            c.stopOrangePreview();
            testCase.verifyEqual(orange.level, 0);
            testCase.verifyEqual(app.getDevice("ALP_DMD").pattern_owner, "");
        end

        function anyOtherRigOperationEndsItFirst(testCase)
            [c, app] = testCase.approved();
            orange = app.getDevice("NI_DAQ_Modulator", "name", "Red LED 615");
            c.startOrangePreview();
            app.Log = strings(0, 1);
            act(c, "acquire_z_reference");
            testCase.verifyEmpty(c.OrangePreview);
            testCase.verifyEqual(orange.level, 0);
            first_off = find(app.Log == "Red LED 615:set_level=0", 1);
            first_acquisition = find(app.Log == "app:acquisition", 1);
            testCase.verifyLessThan(first_off, first_acquisition);
            % A run too.
            c.startOrangePreview();
            cfg = c.Config;
            cfg.trials.last = 1;
            act(c, "set_config", struct("config", cfg));
            warnings = c.getState().readiness.warnings;
            act(c, "start_run", struct("run_folder", fullfile(testCase.Folder, "run"), ...
                "acknowledged_warnings", string({warnings.id})));
            testCase.verifyEmpty(c.OrangePreview);
            testCase.verifyEqual(orange.level, 0);
        end

        function aNewFieldOfViewEndsIt(testCase)
            [c, app] = testCase.approved();
            orange = app.getDevice("NI_DAQ_Modulator", "name", "Red LED 615");
            c.startOrangePreview();
            act(c, "new_session");
            testCase.verifyEmpty(c.OrangePreview);
            testCase.verifyEqual(orange.level, 0);
            testCase.verifyEqual(app.getDevice("ALP_DMD").Displaying, "dark");
            % The new field of view has no cells: nothing to preview.
            testCase.verifyFalse(c.legalActions().start_orange_preview);
        end

        function aFaultWhileStartingLeavesNothingOn(testCase)
            [c, app] = testCase.approved();
            orange = app.getDevice("NI_DAQ_Modulator", "name", "Red LED 615");
            orange.FailOn = "set_level=" + string(c.Config.stimulation.orange_start_v);
            r = hadamard_stim.apply_controller_action(c, "start_orange_preview", struct(), c.Revision);
            testCase.verifyFalse(r.ok);
            testCase.verifyEmpty(c.OrangePreview);
            dmd = app.getDevice("ALP_DMD");
            testCase.verifyEqual(dmd.Displaying, "dark");
            testCase.verifyEqual(dmd.pattern_owner, "");
            testCase.verifyEqual(orange.level, 0);
        end

        function aLevelTheLedCannotTakeEndsIt(testCase)
            [c, app] = testCase.approved();
            orange = app.getDevice("NI_DAQ_Modulator", "name", "Red LED 615");
            c.startOrangePreview();
            r = hadamard_stim.apply_controller_action(c, "update_config", ...
                struct("changes", struct("path", "stimulation.orange_start_v", "value", 6)), c.Revision);
            testCase.verifyEqual(r.identifier, "hadamard_stim:OrangePreviewStopped");
            testCase.verifySubstring(r.message, "4.5");
            testCase.verifyEmpty(c.OrangePreview);
            testCase.verifyEqual(orange.level, 0);
            testCase.verifyEqual(app.getDevice("ALP_DMD").pattern_owner, "");
        end

        function aControllerThatGoesAwayLeavesNothingOn(testCase)
            [c, app] = testCase.approved();
            orange = app.getDevice("NI_DAQ_Modulator", "name", "Red LED 615");
            c.startOrangePreview();
            delete(c);
            testCase.verifyEqual(orange.level, 0);
            testCase.verifyEqual(app.getDevice("ALP_DMD").Displaying, "dark");
            testCase.verifyEqual(app.getDevice("ALP_DMD").pattern_owner, "");
        end
    end

    methods
        function [c, app] = approved(testCase)
            % A tab session with cells approved and the z-reference taken.
            folder = fullfile(testCase.Folder, string(java.util.UUID.randomUUID()));
            [c, app, cfg] = tab_session(folder);
            cfg.stimulation.orange_start_v = 1.2;
            act(c, "set_config", struct("config", cfg));
            act(c, "prepare_rig");
            use_parity_scans(c, testCase.Root);
            for step = ["acquire_reference_image" "propose_cells" "approve_cells" "acquire_z_reference"]
                act(c, step);
            end
        end
    end
end

function r = act(c, action, payload)
if nargin < 3
    payload = struct();
end
r = hadamard_stim.apply_controller_action(c, action, payload, c.Revision);
assert(r.ok, "%s: %s", action, r.message);
end
