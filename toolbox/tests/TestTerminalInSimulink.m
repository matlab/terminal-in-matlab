% Copyright 2026 The MathWorks, Inc.

classdef TestTerminalInSimulink < matlab.unittest.TestCase
    %TESTTERMINALINSIMLINK Integration tests for Terminal docked in Simulink.
    %   These tests require Simulink to be installed and a display available.
    %   They are skipped automatically when Simulink is not present.

    properties (Access = private)
        ModelName string  % temporary model created for testing
    end

    methods (TestClassSetup)
        function checkSimulinkAvailable(testCase)
            % Skip everything if Simulink is not installed.
            hasSimulink = ~isempty(ver('simulink'));
            testCase.assumeTrue(hasSimulink, ...
                'Simulink is not installed — skipping Simulink terminal tests.');
        end

        function checkCanCreateTerminal(testCase)
            % Skip if we cannot create a basic terminal (no display, no binary, etc.)
            try
                t = terminal(WindowStyle="normal");
                pause(1);
                delete(t);
            catch me
                testCase.assumeFail(sprintf( ...
                    'Cannot create Terminal (%s) — skipping Simulink tests.', ...
                    me.message));
            end
        end
    end

    methods (TestMethodSetup)
        function createTemporaryModel(testCase)
            % Create a unique temporary model for each test.
            testCase.ModelName = sprintf('terminal_test_%08x', randi(2^32 - 1));
            new_system(testCase.ModelName);
            open_system(testCase.ModelName);
            pause(1);  % let Simulink editor fully initialize
        end
    end

    methods (TestMethodTeardown)
        function cleanupModelAndTerminals(testCase)
            terminal.closeAll();
            pause(0.5);
            try
                close_system(testCase.ModelName, 0);
            catch
            end
            % Delete the temp file if it was saved.
            mdlFile = [testCase.ModelName '.slx'];
            if isfile(mdlFile)
                delete(mdlFile);
            end
        end
    end

    %% --- Constructor tests ---

    methods (Test)
        function testPlaceSimulink(testCase)
            t = terminal(Place="simulink");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
            testCase.verifyEqual(t.Place, "simulink");
        end

        function testPlaceDefaultIsMatlab(testCase)
            t = terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Place, "matlab");
        end

        function testModelImpliesSimulink(testCase)
            t = terminal(Model=testCase.ModelName);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Place, "simulink");
        end

        function testModelTargetsSpecificEditor(testCase)
            t = terminal(Model=testCase.ModelName);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
        end

        function testCustomNameInSimulink(testCase)
            t = terminal(Place="simulink", Name="Build");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
        end

        function testCustomShellInSimulink(testCase)
            if ispc
                shell = "cmd.exe";
            else
                shell = "/bin/bash";
            end
            t = terminal(Place="simulink", Shell=shell);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Shell, shell);
        end

        function testThemeInSimulink(testCase)
            t = terminal(Place="simulink", Theme="dracula");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Theme, "dracula");
        end

        function testAllOptionsInSimulink(testCase)
            if ispc
                shell = "cmd.exe";
            else
                shell = "/bin/bash";
            end
            t = terminal(Model=testCase.ModelName, Name="Full", ...
                Shell=shell, Theme="monokai");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Place, "simulink");
            testCase.verifyEqual(t.Theme, "monokai");
            testCase.verifyEqual(t.Shell, shell);
        end

        %% --- Lifecycle tests ---

        function testDeleteRemovesPanel(testCase)
            t = terminal(Place="simulink");
            testCase.verifyTrue(isvalid(t));
            delete(t);
            testCase.verifyFalse(isvalid(t));
        end

        function testListIncludesSimulinkTerminal(testCase)
            before = numel(terminal.list());
            t = terminal(Place="simulink");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(numel(terminal.list()), before + 1);
        end

        function testCloseAllIncludesSimulinkTerminals(testCase)
            terminal(Place="simulink");
            testCase.verifyGreaterThanOrEqual(numel(terminal.list()), 1);
            terminal.closeAll();
            pause(0.5);
            testCase.verifyEmpty(terminal.list());
        end

        function testMultipleSimulinkTerminals(testCase)
            % A second terminal docked to the same model replaces the first.
            t1 = terminal(Place="simulink", Name="Term1");
            testCase.addTeardown(@() safeDelete(t1));
            t2 = terminal(Place="simulink", Name="Term2");
            testCase.addTeardown(@() safeDelete(t2));
            testCase.verifyFalse(isvalid(t1));
        end

        %% --- Error cases ---

        function testInvalidPlaceErrors(testCase)
            testCase.verifyError(...
                @() terminal(Place="invalid"), ...
                'MATLAB:validators:mustBeMember');
        end

        function testModelNotFoundErrors(testCase)
            testCase.verifyError(...
                @() terminal(Model="nonexistent_model_xyz_99"), ...
                'Terminal:ModelNotFound');
        end

        function testNoOpenModelErrors(testCase)
            % Close the temporary model, then verify the correct error.
            close_system(testCase.ModelName, 0);
            testCase.verifyError(...
                @() terminal(Place="simulink"), ...
                'Terminal:NoOpenSimulinkModel');
            % Re-open so teardown doesn't warn.
            new_system(testCase.ModelName);
            open_system(testCase.ModelName);
            pause(0.5);
        end

        %% --- Multi-model tests ---

        function testTargetSpecificModelAmongMultiple(testCase)
            % With two models open, targeting one by name should succeed
            % and not invalidate a terminal docked to the other.
            otherModel = sprintf('terminal_test_%08x', randi(2^32 - 1));
            new_system(otherModel);
            open_system(otherModel);
            pause(1);
            testCase.addTeardown(@() safeCloseSystem(otherModel));

            t1 = terminal(Model=testCase.ModelName);
            testCase.addTeardown(@() safeDelete(t1));
            t2 = terminal(Model=otherModel);
            testCase.addTeardown(@() safeDelete(t2));

            % Both terminals should coexist since they target different models.
            testCase.verifyTrue(isvalid(t1));
            testCase.verifyTrue(isvalid(t2));
        end

        function testModelWithSamePrefix(testCase)
            % A model whose name is a prefix of another should match
            % exactly — both should get their own terminal without conflict.
            longerModel = testCase.ModelName + "_extended";
            new_system(longerModel);
            open_system(longerModel);
            pause(1);
            testCase.addTeardown(@() safeCloseSystem(longerModel));

            t1 = terminal(Model=testCase.ModelName);
            testCase.addTeardown(@() safeDelete(t1));
            t2 = terminal(Model=longerModel);
            testCase.addTeardown(@() safeDelete(t2));

            % Both should coexist — prefix model should not steal the
            % longer-named model's terminal or vice versa.
            testCase.verifyTrue(isvalid(t1));
            testCase.verifyTrue(isvalid(t2));
        end

        function testModelTargetsLongerNameNotPrefix(testCase)
            % Requesting the longer-named model should succeed even when
            % a shorter prefix model is also open. Both should coexist.
            longerModel = testCase.ModelName + "_v2";
            new_system(longerModel);
            open_system(longerModel);
            pause(1);
            testCase.addTeardown(@() safeCloseSystem(longerModel));

            t1 = terminal(Model=testCase.ModelName);
            testCase.addTeardown(@() safeDelete(t1));
            t2 = terminal(Model=longerModel);
            testCase.addTeardown(@() safeDelete(t2));

            testCase.verifyTrue(isvalid(t1));
            testCase.verifyTrue(isvalid(t2));
        end

        %% --- Lifecycle edge cases ---

        function testDeleteTwiceDoesNotError(testCase)
            t = terminal(Place="simulink");
            delete(t);
            testCase.verifyWarningFree(@() delete(t));
        end

        function testPlaceSimulinkDocksToMostRecentModel(testCase)
            % Without Model=, Place="simulink" should dock to the most
            % recently active model rather than an arbitrary one.
            otherModel = sprintf('terminal_test_%08x', randi(2^32 - 1));
            new_system(otherModel);
            open_system(otherModel);
            pause(1);
            testCase.addTeardown(@() safeCloseSystem(otherModel));

            % otherModel was opened last so it should be most recent.
            % A terminal targeting testCase.ModelName should coexist with
            % one created via Place="simulink" (which targets otherModel).
            t1 = terminal(Model=testCase.ModelName);
            testCase.addTeardown(@() safeDelete(t1));
            t2 = terminal(Place="simulink");
            testCase.addTeardown(@() safeDelete(t2));

            % If Place="simulink" targeted testCase.ModelName (not the most
            % recent), t1 would be invalidated by the replacement logic.
            testCase.verifyTrue(isvalid(t1));
            testCase.verifyTrue(isvalid(t2));
        end

        function testListCountsTerminalsAcrossModels(testCase)
            % terminal.list() should include terminals docked to
            % different Simulink models.
            otherModel = sprintf('terminal_test_%08x', randi(2^32 - 1));
            new_system(otherModel);
            open_system(otherModel);
            pause(1);
            testCase.addTeardown(@() safeCloseSystem(otherModel));

            before = numel(terminal.list());
            t1 = terminal(Model=testCase.ModelName);
            testCase.addTeardown(@() safeDelete(t1));
            t2 = terminal(Model=otherModel);
            testCase.addTeardown(@() safeDelete(t2));

            testCase.verifyEqual(numel(terminal.list()), before + 2);
        end

        function testCloseAllAcrossMultipleModels(testCase)
            % terminal.closeAll() should clean up terminals docked to
            % different models.
            otherModel = sprintf('terminal_test_%08x', randi(2^32 - 1));
            new_system(otherModel);
            open_system(otherModel);
            pause(1);
            testCase.addTeardown(@() safeCloseSystem(otherModel));

            terminal(Model=testCase.ModelName);
            terminal(Model=otherModel);

            testCase.verifyGreaterThanOrEqual(numel(terminal.list()), 2);
            terminal.closeAll();
            pause(0.5);
            testCase.verifyEmpty(terminal.list());
        end

        function testClosingModelInvalidatesTerminal(testCase)
            % Closing the host model should clean up the docked terminal.
            otherModel = sprintf('terminal_test_%08x', randi(2^32 - 1));
            new_system(otherModel);
            open_system(otherModel);
            pause(1);

            t = terminal(Model=otherModel);
            testCase.verifyTrue(isvalid(t));

            close_system(otherModel, 0);
            pause(1);

            testCase.verifyFalse(isvalid(t));
        end

        function testPlaceSimulinkAfterClosingMostRecentModel(testCase)
            % If model A is opened, then model B, then B is closed,
            % Place="simulink" should dock to A (B should not linger as
            % most recently active).
            otherModel = sprintf('terminal_test_%08x', randi(2^32 - 1));
            new_system(otherModel);
            open_system(otherModel);
            pause(1);

            % otherModel is now most recently active. Close it.
            close_system(otherModel, 0);
            pause(1);

            % testCase.ModelName should now be the only open model.
            t = terminal(Place="simulink");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyTrue(isvalid(t));
        end

        %% --- Edge cases ---

        function testEmptyModelStringStaysInMatlab(testCase)
            % Model="" should not trigger Simulink mode.
            t = terminal(Model="", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Place, "matlab");
        end

        function testWindowStyleWarnsInSimulink(testCase)
            % WindowStyle="normal" issues a warning in Simulink mode — the
            % terminal always docks via the DDG panel.
            testCase.verifyWarning(...
                @() createAndCleanup(testCase, Place="simulink", WindowStyle="normal"), ...
                'Terminal:WindowStyleIgnored');
        end

        function testWindowStyleDockedNoWarningInSimulink(testCase)
            % WindowStyle="docked" (or default) should not warn.
            testCase.verifyWarningFree(...
                @() createAndCleanup(testCase, Place="simulink", WindowStyle="docked"));
        end

        %% --- Tabs tests ---

        function testTabsTrueInSimulink(testCase)
            t = terminal(Place="simulink", Tabs=true);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Place, "simulink");
        end

        function testTabsTrueWithModel(testCase)
            t = terminal(Model=testCase.ModelName, Tabs=true);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Place, "simulink");
        end
    end
end

%% --- Helpers ---

function safeDelete(t)
    if isvalid(t)
        delete(t);
    end
end

function createAndCleanup(testCase, nvArgs)
    arguments
        testCase
        nvArgs.Place
        nvArgs.WindowStyle
    end
    args = namedargs2cell(nvArgs);
    t = terminal(args{:});
    testCase.addTeardown(@() safeDelete(t));
end

function safeCloseSystem(modelName)
    try
        close_system(modelName, 0);
    catch
    end
    mdlFile = [char(modelName) '.slx'];
    if isfile(mdlFile)
        delete(mdlFile);
    end
end
