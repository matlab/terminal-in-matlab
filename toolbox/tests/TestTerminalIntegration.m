% Copyright 2026 The MathWorks, Inc.

classdef TestTerminalIntegration < matlab.unittest.TestCase
    %TESTTERMINALINTEGRATION Integration tests for Terminal that require a
    %   display (uifigure) and the bundled server binary.

    properties (Access = private)
        Terminals = terminal.empty  % track instances for cleanup
    end

    methods (TestClassSetup)
        function checkPrerequisites(testCase)
            % Skip the entire class if we cannot create a terminal.
            % This covers: no display, no server binary, no uifigure, etc.
            try
                t = terminal(WindowStyle="normal");
                pause(1);  % let server start
                delete(t);
            catch me
                testCase.assumeFail(sprintf( ...
                    'Cannot create Terminal (%s) — skipping integration tests.', ...
                    me.message));
            end
        end
    end

    methods (TestMethodTeardown)
        function closeTerminals(testCase) %#ok<MANU>
            % Clean up any terminals opened during the test.
            terminal.closeAll();
            pause(0.5);
        end
    end

    %% --- Constructor tests ---

    methods (Test)
        function testDefaultConstructor(testCase)
            t = terminal();
            testCase.addTeardown(@() safeDelete(t));
            testCase.Terminals(end+1) = t;
            testCase.verifyClass(t, 'terminal');
            testCase.verifyEqual(t.Place, "matlab");
        end

        function testConstructorWithName(testCase)
            t = terminal(Name="Build");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
        end

        function testConstructorNormal(testCase)
            t = terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
        end

        function testConstructorDocked(testCase)
            t = terminal(WindowStyle="docked");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
        end

        function testConstructorWithTheme(testCase)
            t = terminal(Theme="dracula");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
            testCase.verifyEqual(t.Theme, "dracula");
        end

        function testConstructorWithShell(testCase)
            if ispc
                shell = "cmd.exe";
            else
                shell = "/bin/bash";
            end
            t = terminal(Shell=shell);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
            testCase.verifyEqual(t.Shell, shell);
        end

        function testConstructorAllOptions(testCase)
            if ispc
                shell = "cmd.exe";
            else
                shell = "/bin/bash";
            end
            t = terminal(Name="Full", WindowStyle="normal", ...
                Shell=shell, Theme="monokai");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
            testCase.verifyEqual(t.Theme, "monokai");
            testCase.verifyEqual(t.Shell, shell);
        end

        function testConstructorInvalidShell(testCase)
            testCase.verifyError(...
                @() terminal(Shell="/no/such/shell_xyz"), ...
                'Terminal:ShellNotFound');
        end

        function testConstructorInvalidTheme(testCase)
            testCase.verifyError(...
                @() terminal(Theme="nonexistent-theme-xyz"), ...
                'Terminal:InvalidTheme');
        end

        function testConstructorInvalidWindowStyle(testCase)
            testCase.verifyError(...
                @() terminal(WindowStyle="invalid"), ...
                'MATLAB:validators:mustBeMember');
        end

        function testConstructorWithParent(testCase)
            fig = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(fig));
            t = terminal(fig);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
        end

        function testConstructorWithPanel(testCase)
            fig = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(fig));
            panel = uipanel(fig, 'Position', [10 10 400 300]);
            t = terminal(panel);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
        end

        %% --- Lifecycle tests ---

        function testDeleteCleansUp(testCase)
            t = terminal(WindowStyle="normal");
            testCase.verifyTrue(isvalid(t));
            delete(t);
            testCase.verifyFalse(isvalid(t));
        end

        function testMultipleTerminals(testCase)
            t1 = terminal(Name="Term1", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t1));
            t2 = terminal(Name="Term2", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t2));

            terminals = terminal.list();
            testCase.verifyGreaterThanOrEqual(numel(terminals), 2);
        end

        function testCloseAll(testCase)
            terminal(Name="CloseMe1", WindowStyle="normal");
            terminal(Name="CloseMe2", WindowStyle="normal");
            testCase.verifyGreaterThanOrEqual(numel(terminal.list()), 2);

            terminal.closeAll();
            pause(0.5);
            testCase.verifyEmpty(terminal.list());
        end

        function testListReflectsCreationAndDeletion(testCase)
            before = numel(terminal.list());
            t = terminal(WindowStyle="normal");
            testCase.verifyEqual(numel(terminal.list()), before + 1);
            delete(t);
            testCase.verifyEqual(numel(terminal.list()), before);
        end

        %% --- Theme tests ---

        function testLiveThemeChange(testCase)
            t = terminal(Theme="dark", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Theme, "dark");

            t.Theme = "monokai";
            testCase.verifyEqual(t.Theme, "monokai");
        end

        function testLiveThemeChangeAllPresets(testCase)
            t = terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));

            names = terminal.themes();
            for i = 1:numel(names)
                t.Theme = names(i);
                testCase.verifyEqual(string(t.Theme), names(i), ...
                    sprintf('Failed to set theme to %s', names(i)));
            end
        end

        function testLiveThemeChangeCustomStruct(testCase)
            t = terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));

            custom = struct('background', '#ff0000', 'foreground', '#00ff00');
            t.Theme = custom;
            testCase.verifyTrue(isstruct(t.Theme));
        end

        function testConstructorWithDefaultTheme(testCase)
            % Verify that the default theme preference is used.
            original = terminal.getDefaultTheme();
            testCase.addTeardown(@() terminal.setDefaultTheme(original));

            terminal.setDefaultTheme("nord");
            t = terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(string(t.Theme), "nord");
        end

        function testConstructorThemeOverridesDefault(testCase)
            original = terminal.getDefaultTheme();
            testCase.addTeardown(@() terminal.setDefaultTheme(original));

            terminal.setDefaultTheme("nord");
            t = terminal(Theme="dracula", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Theme, "dracula");
        end

        %% --- Tabs tests ---

        function testTabsDefaultFalse(testCase)
            t = terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
        end

        function testTabsTrue(testCase)
            t = terminal(WindowStyle="normal", Tabs=true);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'terminal');
        end

        function testTabsTrueWithAllOptions(testCase)
            if ispc
                shell = "cmd.exe";
            else
                shell = "/bin/bash";
            end
            t = terminal(Name="Tabbed", WindowStyle="normal", ...
                Shell=shell, Theme="monokai", Tabs=true);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Theme, "monokai");
            testCase.verifyEqual(t.Shell, shell);
        end
    end
end

function safeDelete(t)
    if isvalid(t)
        delete(t);
    end
end
