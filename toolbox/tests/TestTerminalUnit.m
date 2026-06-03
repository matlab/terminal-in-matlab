% Copyright 2026 The MathWorks, Inc.

classdef TestTerminalUnit < matlab.unittest.TestCase
    %TESTTERMINALUNIT Unit tests for Terminal APIs that do not require a
    %   running server or display (no uifigure).

    methods (Test)
        %% --- version / terminalVersion ---

        function testVersionReturnsString(testCase)
            v = terminal.version();
            testCase.verifyClass(v, 'string');
        end

        function testVersionNonEmpty(testCase)
            v = terminal.version();
            testCase.verifyNotEmpty(v);
        end

        function testVersionMatchesterminalVersion(testCase)
            testCase.verifyEqual(terminal.version(), string(terminalVersion()));
        end

        function testDevVersionFormat(testCase)
            % In a source checkout, version should be "0.0.0-dev".
            v = terminal.version();
            testCase.verifyTrue(strlength(v) > 0);
        end

        %% --- themes ---

        function testThemesReturnsList(testCase)
            names = terminal.themes();
            testCase.verifyClass(names, 'string');
            testCase.verifyTrue(numel(names) >= 3, ...
                'Expected at least 3 themes');
        end

        function testThemesContainsAuto(testCase)
            names = terminal.themes();
            testCase.verifyTrue(ismember("auto", names));
        end

        function testThemesContainsBuiltins(testCase)
            names = terminal.themes();
            expected = ["dark", "light", "dracula", "monokai", "nord"];
            for i = 1:numel(expected)
                testCase.verifyTrue(ismember(expected(i), names), ...
                    sprintf('Missing theme: %s', expected(i)));
            end
        end

        function testThemesContainsAllPresets(testCase)
            names = terminal.themes();
            expected = ["auto", "dark", "light", "dracula", "monokai", ...
                "solarized_dark", "solarized_light", "nord", ...
                "gruvbox_dark", "one_dark", "tokyo_night", "catppuccin_mocha"];
            for i = 1:numel(expected)
                testCase.verifyTrue(ismember(expected(i), names), ...
                    sprintf('Missing theme: %s', expected(i)));
            end
        end

        function testThemesNoDuplicates(testCase)
            names = terminal.themes();
            testCase.verifyEqual(numel(names), numel(unique(names)), ...
                'Theme list contains duplicates');
        end

        %% --- setDefaultTheme / getDefaultTheme ---

        function testDefaultThemeRoundTrip(testCase)
            % Save original.
            original = terminal.getDefaultTheme();
            cleanup = onCleanup(@() terminal.setDefaultTheme(original));

            terminal.setDefaultTheme("dracula");
            testCase.verifyEqual(string(terminal.getDefaultTheme()), "dracula");

            terminal.setDefaultTheme("auto");
            testCase.verifyEqual(string(terminal.getDefaultTheme()), "auto");
        end

        function testSetDefaultThemeInvalidErrors(testCase)
            testCase.verifyError(...
                @() terminal.setDefaultTheme("nonexistent-theme"), ...
                'Terminal:InvalidTheme');
        end

        function testSetDefaultThemeStruct(testCase)
            original = terminal.getDefaultTheme();
            cleanup = onCleanup(@() terminal.setDefaultTheme(original));

            custom = struct('background', '#112233', 'foreground', '#aabbcc');
            terminal.setDefaultTheme(custom);
            result = terminal.getDefaultTheme();
            testCase.verifyTrue(isstruct(result));
            testCase.verifyEqual(result.background, '#112233');
        end

        function testSetDefaultThemeAllPresets(testCase)
            % Verify every preset can be set as default.
            original = terminal.getDefaultTheme();
            cleanup = onCleanup(@() terminal.setDefaultTheme(original));

            names = terminal.themes();
            for i = 1:numel(names)
                terminal.setDefaultTheme(names(i));
                got = string(terminal.getDefaultTheme());
                testCase.verifyEqual(got, names(i), ...
                    sprintf('Round-trip failed for theme: %s', names(i)));
            end
        end

        function testGetDefaultThemeReturnsAutoByDefault(testCase)
            % If no preference set, default is "auto".
            original = terminal.getDefaultTheme();
            cleanup = onCleanup(@() terminal.setDefaultTheme(original));

            if ispref('terminal', 'Theme')
                rmpref('terminal', 'Theme');
            end
            testCase.verifyEqual(terminal.getDefaultTheme(), "auto");
        end

        %% --- list / closeAll (empty state) ---

        function testListReturnsArray(testCase)
            terminals = terminal.list();
            testCase.verifyTrue(isempty(terminals) || isa(terminals, 'terminal'));
        end

        function testCloseAllEmptyNoError(testCase)
            % closeAll on empty list should not error.
            terminal.closeAll();
        end

        %% --- internal.TerminalThemes ---

        function testThemeValidateAcceptsAllPresets(testCase)
            names = terminal.themes();
            for i = 1:numel(names)
                % Should not throw.
                internal.TerminalThemes.validate(names(i));
            end
        end

        function testThemeValidateRejectsUnknown(testCase)
            testCase.verifyError(...
                @() internal.TerminalThemes.validate("nonexistent"), ...
                'Terminal:InvalidTheme');
        end

        function testThemeValidateRejectsNumber(testCase)
            testCase.verifyError(...
                @() internal.TerminalThemes.validate(42), ...
                'Terminal:InvalidTheme');
        end

        function testThemeValidateRejectsLogical(testCase)
            testCase.verifyError(...
                @() internal.TerminalThemes.validate(true), ...
                'Terminal:InvalidTheme');
        end

        function testThemeValidateRejectsCellArray(testCase)
            testCase.verifyError(...
                @() internal.TerminalThemes.validate({'dark'}), ...
                'Terminal:InvalidTheme');
        end

        function testThemeValidateAcceptsStruct(testCase)
            custom = struct('background', '#000000', 'foreground', '#ffffff');
            internal.TerminalThemes.validate(custom); % Should not throw.
        end

        function testThemeValidateAcceptsAllColorFields(testCase)
            % Build a struct with every valid field.
            custom = struct( ...
                'background', '#000000', 'foreground', '#ffffff', ...
                'cursor', '#aaaaaa', 'cursorAccent', '#bbbbbb', ...
                'selectionBackground', '#cccccc', ...
                'black', '#000001', 'red', '#ff0000', ...
                'green', '#00ff00', 'yellow', '#ffff00', ...
                'blue', '#0000ff', 'magenta', '#ff00ff', ...
                'cyan', '#00ffff', 'white', '#ffffff', ...
                'brightBlack', '#111111', 'brightRed', '#ff1111', ...
                'brightGreen', '#11ff11', 'brightYellow', '#ffff11', ...
                'brightBlue', '#1111ff', 'brightMagenta', '#ff11ff', ...
                'brightCyan', '#11ffff', 'brightWhite', '#eeeeee');
            internal.TerminalThemes.validate(custom); % Should not throw.
        end

        function testThemeValidateRejectsBadStructField(testCase)
            bad = struct('notAField', '#000000');
            testCase.verifyError(...
                @() internal.TerminalThemes.validate(bad), ...
                'Terminal:InvalidTheme');
        end

        function testThemeValidateRejectsBadHex(testCase)
            bad = struct('background', 'not-hex');
            testCase.verifyError(...
                @() internal.TerminalThemes.validate(bad), ...
                'Terminal:InvalidTheme');
        end

        function testThemeValidateRejectsShortHex(testCase)
            bad = struct('background', '#fff');
            testCase.verifyError(...
                @() internal.TerminalThemes.validate(bad), ...
                'Terminal:InvalidTheme');
        end

        function testThemeValidateRejectsNoHash(testCase)
            bad = struct('background', 'ff0000');
            testCase.verifyError(...
                @() internal.TerminalThemes.validate(bad), ...
                'Terminal:InvalidTheme');
        end

        function testThemeValidateRejectsUppercaseOnlyInStruct(testCase)
            % '#FF0000' should be accepted (regex allows a-fA-F).
            custom = struct('background', '#FF0000');
            internal.TerminalThemes.validate(custom); % Should not throw.
        end

        function testThemeResolveAutoReturnsStruct(testCase)
            config = internal.TerminalThemes.resolve("auto");
            testCase.verifyTrue(isstruct(config));
            testCase.verifyTrue(isfield(config, 'background'));
            testCase.verifyTrue(isfield(config, 'foreground'));
            testCase.verifyTrue(isfield(config, 'isDark'));
            testCase.verifyTrue(isfield(config, 'fontSize'));
            testCase.verifyTrue(isfield(config, 'fontFamily'));
        end

        function testThemeResolvePresetsHaveRequiredFields(testCase)
            names = terminal.themes();
            for i = 1:numel(names)
                config = internal.TerminalThemes.resolve(names(i));
                testCase.verifyTrue(isfield(config, 'background'), ...
                    sprintf('Theme "%s" missing background', names(i)));
                testCase.verifyTrue(isfield(config, 'foreground'), ...
                    sprintf('Theme "%s" missing foreground', names(i)));
                testCase.verifyTrue(isfield(config, 'isDark'), ...
                    sprintf('Theme "%s" missing isDark', names(i)));
                testCase.verifyTrue(isfield(config, 'fontSize'), ...
                    sprintf('Theme "%s" missing fontSize', names(i)));
                testCase.verifyTrue(isfield(config, 'fontFamily'), ...
                    sprintf('Theme "%s" missing fontFamily', names(i)));
            end
        end

        function testThemeResolveDarkIsDark(testCase)
            config = internal.TerminalThemes.resolve("dark");
            testCase.verifyTrue(config.isDark);
        end

        function testThemeResolveLightIsNotDark(testCase)
            config = internal.TerminalThemes.resolve("light");
            testCase.verifyFalse(config.isDark);
        end

        function testThemeResolveSolarizedLightIsNotDark(testCase)
            config = internal.TerminalThemes.resolve("solarized-light");
            testCase.verifyFalse(config.isDark);
        end

        function testThemeResolveCustomMergesOverDark(testCase)
            custom = struct('background', '#ff0000');
            config = internal.TerminalThemes.resolve(custom);
            testCase.verifyEqual(config.background, '#ff0000');
            % Should inherit foreground from dark defaults.
            testCase.verifyTrue(isfield(config, 'foreground'));
            testCase.verifyEqual(config.foreground, '#d4d4d4');
        end

        function testThemeResolveCustomMultipleFields(testCase)
            custom = struct('background', '#111111', 'foreground', '#eeeeee', ...
                'cursor', '#aabbcc');
            config = internal.TerminalThemes.resolve(custom);
            testCase.verifyEqual(config.background, '#111111');
            testCase.verifyEqual(config.foreground, '#eeeeee');
            testCase.verifyEqual(config.cursor, '#aabbcc');
        end

        function testThemeResolveDraculaColors(testCase)
            config = internal.TerminalThemes.resolve("dracula");
            testCase.verifyEqual(config.background, '#282a36');
            testCase.verifyEqual(config.foreground, '#f8f8f2');
            testCase.verifyTrue(config.isDark);
        end

        function testThemeResolveMonokaiColors(testCase)
            config = internal.TerminalThemes.resolve("monokai");
            testCase.verifyEqual(config.background, '#272822');
            testCase.verifyEqual(config.foreground, '#f8f8f2');
            testCase.verifyTrue(config.isDark);
        end

        function testThemeResolveNordColors(testCase)
            config = internal.TerminalThemes.resolve("nord");
            testCase.verifyEqual(config.background, '#2e3440');
            testCase.verifyTrue(config.isDark);
        end

        function testThemeResolveHyphenatedName(testCase)
            % Themes with hyphens (e.g., "solarized-dark") should resolve.
            config = internal.TerminalThemes.resolve("solarized-dark");
            testCase.verifyEqual(config.background, '#002b36');
        end

        function testThemeResolveAllPresetsHaveAnsiColors(testCase)
            % Full presets (not dark/light) should have ANSI color fields.
            fullPresets = ["dracula", "monokai", "solarized_dark", ...
                "solarized_light", "nord", "gruvbox_dark", "one_dark", ...
                "tokyo_night", "catppuccin_mocha"];
            ansiFields = ["black", "red", "green", "yellow", "blue", ...
                "magenta", "cyan", "white"];
            for i = 1:numel(fullPresets)
                config = internal.TerminalThemes.resolve(fullPresets(i));
                for j = 1:numel(ansiFields)
                    testCase.verifyTrue(isfield(config, ansiFields(j)), ...
                        sprintf('Theme "%s" missing %s', fullPresets(i), ansiFields(j)));
                end
            end
        end

        function testThemeResolveFontSizeIsPositive(testCase)
            config = internal.TerminalThemes.resolve("dark");
            testCase.verifyGreaterThan(config.fontSize, 0);
        end

        function testThemeResolveFontSizeScaling(testCase)
            % Verify font size is scaled correctly for the current platform.
            s = settings;
            ptSize = s.matlab.fonts.codefont.Size.ActiveValue;
            config = internal.TerminalThemes.resolve("dark");
            if ismac
                % macOS: font size passes through as-is (Apple convention).
                testCase.verifyEqual(config.fontSize, ptSize, ...
                    'On macOS, font size should equal the MATLAB setting directly.');
            else
                % Windows/Linux: points converted to CSS pixels via 96/72.
                testCase.verifyEqual(config.fontSize, round(ptSize * 96 / 72), ...
                    'On Windows/Linux, font size should be converted via 96/72.');
            end
        end

        function testThemeResolveFontFamilyContainsMonospace(testCase)
            config = internal.TerminalThemes.resolve("dark");
            testCase.verifyTrue(contains(config.fontFamily, 'monospace'));
        end

        function testThemeResolveFontFamilyIncludesUserFont(testCase)
            % The resolved font family should start with the user's code font.
            try
                s = settings;
                userFont = char(s.matlab.fonts.codefont.Name.ActiveValue);
            catch
                % Cannot read font name — skip this test.
                testCase.assumeFail('Could not read code font name from MATLAB settings.');
            end
            config = internal.TerminalThemes.resolve("dark");
            testCase.verifyTrue(startsWith(config.fontFamily, ['''' userFont '''']), ...
                sprintf('fontFamily should start with user font "%s", got: %s', ...
                userFont, config.fontFamily));
        end

        function testThemeResolveFontFamilyHasFallbacks(testCase)
            % Even with a user font prepended, the fallback chain must remain.
            config = internal.TerminalThemes.resolve("dark");
            testCase.verifyTrue(contains(config.fontFamily, 'Consolas'), ...
                'fontFamily should contain Consolas as fallback.');
            testCase.verifyTrue(contains(config.fontFamily, 'DejaVu Sans Mono'), ...
                'fontFamily should contain DejaVu Sans Mono as fallback.');
        end

        function testThemeResolveIsDarkMatchesBackground(testCase)
            % Light backgrounds should have isDark=false.
            lightThemes = ["light", "solarized_light"];
            for i = 1:numel(lightThemes)
                config = internal.TerminalThemes.resolve(lightThemes(i));
                testCase.verifyFalse(config.isDark, ...
                    sprintf('Theme "%s" should not be dark', lightThemes(i)));
            end

            % Dark backgrounds should have isDark=true.
            darkThemes = ["dark", "dracula", "monokai", "nord", ...
                "gruvbox_dark", "one_dark", "tokyo_night", "catppuccin_mocha"];
            for i = 1:numel(darkThemes)
                config = internal.TerminalThemes.resolve(darkThemes(i));
                testCase.verifyTrue(config.isDark, ...
                    sprintf('Theme "%s" should be dark', darkThemes(i)));
            end
        end
    end
end
