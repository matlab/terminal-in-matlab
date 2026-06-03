classdef (Sealed) terminal < handle
    %TERMINAL Embeds a system terminal inside a MATLAB figure using uihtml.
    %
    %   t = terminal()                    — docked terminal with default name
    %   t = terminal(Name="Build")        — docked terminal with custom name
    %   t = terminal(WindowStyle="normal") — undocked terminal in its own window
    %   t = terminal(Agent="claude")       — full agent integration with MathWorks toolkits
    %   t = terminal(Place="simulink")    — dock terminal in Simulink editor
    %   t = terminal(Model="MyModel")     — dock terminal in specific Simulink model
    %   delete(t)                         — closes the terminal and kills the server
    %
    %   Name-Value Arguments:
    %     Name        - Title of the terminal window (default: "Terminal")
    %     WindowStyle - "docked" (default) or "normal"
    %     Shell       - Shell program to run. Can be a name on PATH or an
    %                   absolute path. Default: system shell ($SHELL on
    %                   Unix, %COMSPEC% on Windows).
    %
    %                   Common values by platform:
    %                     Linux/macOS: "bash", "zsh", "sh", "fish",
    %                                  "/bin/bash", "/usr/bin/zsh"
    %                     Windows:     "cmd.exe", "powershell.exe", "pwsh.exe",
    %                                  "wsl.exe"
    %     Theme       - Color theme. Default: "auto" (follows MATLAB light/dark).
    %                   Built-in: "light", "dark"
    %                   Presets:  "dracula", "monokai", "solarized-dark",
    %                             "solarized-light", "nord", "gruvbox-dark",
    %                             "one-dark", "tokyo-night", "catppuccin-mocha"
    %                   Custom:   struct with fields: background, foreground,
    %                             cursor, selectionBackground, and ANSI colors
    %                             (black, red, green, ..., brightWhite)
    %     Agentic     - Full agent integration with MathWorks Agentic Toolkits.
    %                   Sets up the MCP Core Server, downloads the MATLAB and/or
    %                   Simulink Agentic Toolkits, and registers with your AI
    %                   agent. First run prompts a setup wizard; preferences are
    %                   saved for subsequent runs. Default: false.
    %     Agent       - "claude"|"amp"|"gemini"
    %                   Skips the wizard. Implies Agentic=true.
    %     Toolkits    - ["matlab"] or ["matlab","simulink"] (default includes
    %                   Simulink when installed), or ["simulink"] alone
    %                   Which agentic toolkits to enable.
    %     AgentCLI    - Custom command to invoke the agent CLI. Use when the
    %                   agent binary has a non-standard name or path.
    %                   Example: "devai launch claude" or "/usr/local/bin/my-claude"
    %                   Saved in config.json for subsequent runs.
    %     Place       - "matlab" (default) or "simulink". When "simulink",
    %                   docks the terminal in the Simulink editor as a panel.
    %                   Requires a Simulink model to be open.
    %     Model       - Name of the Simulink model to dock the terminal in.
    %                   Implies Place="simulink". If multiple models share a
    %                   prefix, exact match is preferred.
    %     Tabs        - Enable multi-tab UI with tab bar and + button.
    %                   Default: false. Set to true for multiple terminal
    %                   sessions in a single window.
    %
    %   Static methods:
    %     terminal.version()  — return the installed toolbox version string
    %     terminal.list()     — return handles to all running terminals
    %     terminal.closeAll() — close all running terminals
    %     terminal.update()          — update to the latest stable release from GitHub
    %     terminal.update("1.2.0")  — install a specific version (release candidates too)
    %     terminal.versions()       — list available releases on GitHub
    %     terminal.themes()   — list available theme names
    %     terminal.setDefaultTheme("dracula") — set default for new terminals
    %     terminal.getDefaultTheme()          — get current default theme
    %     terminal.verify()         — verify binary integrity against GitHub release
    %     terminal.test()          — run the built-in test suite with report
    %     terminal.agentOptions()            — show saved agent/toolkit config
    %     terminal.resetAgentOptions()      — clear preferences, re-run wizard
    %     terminal.updateAgenticToolkit()   — update installed agentic toolkit(s)
    %     terminal.updateMCPServer()         — update MCP server binary to latest
    %
    %   Examples:
    %     t = terminal();
    %     t = terminal(Name="Git", WindowStyle="normal");
    %     t = terminal(Shell="zsh");
    %     t = terminal(Shell="powershell.exe");
    %     t = terminal(Theme="dracula");
    %     t = terminal(Theme="solarized-light");
    %     t.Theme = "monokai";    % change theme after creation
    %     terminal.setDefaultTheme("dracula");  % persist across sessions
    %     terminal.getDefaultTheme();
    %     t = terminal(Agent="claude");
    %     t = terminal(Agent="claude", Toolkits=["matlab","simulink"]);
    %     t = terminal(Agent="claude", AgentCLI="devai launch claude");
    %     t = terminal(Agentic=true);  % interactive wizard
    %     t = terminal(Place="simulink");          % dock in active Simulink model
    %     t = terminal(Model="MyController");      % dock in specific model
    %     t = terminal(Tabs=true);    % enable multi-tab UI
    %     terminal.resetAgentOptions();
    %     delete(t);
    %     terminal.update();
    %     terminal.update("0.8.0-rc1");
    %     terminal.versions();
    %     terminal.verify();

    % Copyright 2026 The MathWorks, Inc.


    properties (Access = private)
        ServerProcess   % struct with fields: pid (double), port (double)
        HTMLComponent   % uihtml handle
        AuthToken       % random hex auth string
        ParentFigure    % figure or uifigure handle
        ServerBinary    % absolute path to the Go binary
        PollTimer       % timer object for polling server output
        PollSeq         % last sequence number received from server
        BaseURL         % server base URL
        ReadOpts        % cached weboptions for webread
        WriteOpts       % cached weboptions for webwrite
        OutQueue cell = {}  % queued messages from JS to send to server (legacy only)
        UseEvents logical = false  % true if R2023a+ event API is available
        ThemeConfig        % cached theme config for re-init on HTML reload
        MCPCommand         % command to pre-populate in the first terminal session
        InitTimer          % one-shot timer for deferred post-constructor init
        MCPTimer           % one-shot timer for delayed MCP hint
        ThemePollCount double = 0  % tick counter for periodic theme check
        LastFigureColor    % cached groot DefaultFigureColor for change detection
        ConsecutivePollFailures double = 0  % poll failure counter for server death detection
        IsRestarting logical = false  % true while server restart is in progress
        DDGComponent           % GLUE2.DDGComponent handle (Simulink mode only)
        DDGStudio              % DAS.Studio handle (Simulink mode only)
        SimulinkURL string = ""  % URL for DDG webbrowser widget
        Tabs logical = false  % whether multi-tab UI is enabled
    end

    properties (SetAccess = private)
        Shell string        % shell program for new sessions (empty = server default)
        Place string = "matlab"  % "matlab" or "simulink"
    end

    properties
        Theme = "auto"      % "auto" | "light" | "dark" | preset name | struct
    end

    properties (Constant, Access = private)
        DEFAULT_IDLE_TIMEOUT = 30   % seconds
        SERVER_BINARY_NAME = 'matlab-terminal-server'
        POLL_INTERVAL = 0.1         % 100ms polling interval
        THEME_CHECK_TICKS = 50     % check theme every 50 ticks (5 seconds)
        TOOLBOX_ID = '9e8f4a2b-3c1d-4e5f-a6b7-8c9d0e1f2a3b'
        GITHUB_REPO = 'matlab/terminal-in-matlab'
        MCP_SERVER_BINARY = 'matlab-mcp-core-server'
        MCP_SERVER_REPO = 'matlab/matlab-mcp-core-server'
        MCP_MIN_SERVER_VERSION = '0.10.0'
        % Agentic Toolkit constants
        AGENTIC_MATLAB_REPO = 'matlab/matlab-agentic-toolkit'
        AGENTIC_SIMULINK_REPO = 'matlab/simulink-agentic-toolkit'
        AGENTIC_SUPPORTED_AGENTS = ["claude","amp","gemini"]
    end

    methods
        function obj = terminal(parent, options)
            %TERMINAL Construct a terminal instance.
            arguments
                parent = []
                options.Name (1,1) string = "Terminal"
                options.WindowStyle (1,1) string {mustBeMember(options.WindowStyle, ["docked", "normal"])} = "docked"
                options.Shell (1,1) string = ""
                options.Theme = missing
                options.Place (1,1) string {mustBeMember(options.Place, ["matlab", "simulink"])} = "matlab"
                options.Model (1,1) string = ""
                options.Agentic (1,1) logical = false
                options.Agent (1,1) string = ""
                options.Toolkits (1,:) string = string.empty
                options.AgentCLI (1,1) string = ""
                options.Tabs (1,1) logical = false
            end

            % --- Model implies Place="simulink" ---
            if options.Model ~= ""
                options.Place = "simulink";
            end

            % Warn if WindowStyle is explicitly set in Simulink mode.
            if options.Place == "simulink" && options.WindowStyle ~= "docked"
                warning('Terminal:WindowStyleIgnored', ...
                    'WindowStyle="%s" is not supported when Place="simulink". The terminal will dock in the Simulink editor.', ...
                    options.WindowStyle);
            end

            obj.Place = lower(options.Place);
            obj.Shell = options.Shell;
            obj.Tabs = options.Tabs;

            % Use saved default theme if not explicitly provided.
            if ismissing(options.Theme)
                options.Theme = terminal.getDefaultTheme();
            end
            internal.TerminalThemes.validate(options.Theme);
            obj.Theme = options.Theme;

            % --- Validate shell if specified, resolve default if not ---
            if obj.Shell ~= ""
                terminal.validateShell(obj.Shell);
            else
                obj.Shell = terminal.defaultShell();
            end

            % --- Agentic: full agent integration with toolkits ---
            if options.Agent ~= "" || ~isempty(options.Toolkits)
                options.Agentic = true;
            end
            if options.Agentic
                config = terminal.readAgenticConfig();

                isFirstRun = ~isfield(config, 'mcpServerVersion') ...
                    || ~isfield(config, 'toolkits');

                % First-run only: install MCP server and MATLAB-side components.
                if isFirstRun
                    serverBin = terminal.ensureMCPServerBinary(config);
                    terminal.runSetupMatlabIfNeeded(serverBin);
                end

                % Always: share the MATLAB session.
                % If shareMATLABSession is missing (toolbox uninstalled or new
                % MATLAB release), attempt to reinstall it.
                if isempty(which('shareMATLABSession'))
                    if ~exist('serverBin', 'var')
                        serverBin = terminal.ensureMCPServerBinary(config);
                    end
                    terminal.runSetupMatlabIfNeeded(serverBin);
                end
                try
                    shareMATLABSession();
                catch me
                    error('Terminal:MCPShareFailed', ...
                        'Failed to share MATLAB session:\n  %s', me.message);
                end
                fprintf('MATLAB session shared for AI agent access.\n\n');

                % Resolve requested agent and toolkits.
                % Priority: explicit option > config > wizard/default.
                if options.Agent ~= ""
                    requestedAgent = options.Agent;
                elseif isfield(config, 'agent')
                    requestedAgent = string(config.agent);
                else
                    requestedAgent = "";
                end

                if ~isempty(options.Toolkits)
                    requestedToolkits = options.Toolkits;
                elseif isfield(config, 'toolkits')
                    requestedToolkits = string(fieldnames(config.toolkits))';
                else
                    requestedToolkits = terminal.defaultToolkits();
                end

                % No agent configured — run the interactive wizard.
                if requestedAgent == ""
                    wizardOpts = terminal.agenticWizard(options.Toolkits);
                    requestedAgent = string(wizardOpts.Agent);
                    requestedToolkits = string(wizardOpts.Toolkits);
                end

                % Validate agent choice.
                if requestedAgent ~= ""
                    terminal.validateAgentOptions(struct( ...
                        'Agent', requestedAgent, 'Toolkits', {requestedToolkits}));
                end

                % Detect what changed relative to saved config.
                if isFirstRun
                    newToolkits = requestedToolkits;
                    needsSetup = true;
                else
                    savedToolkits = string(fieldnames(config.toolkits));
                    savedAgent = "";
                    if isfield(config, 'agent'), savedAgent = string(config.agent); end
                    newToolkits = setdiff(requestedToolkits, savedToolkits);
                    agentChanged = requestedAgent ~= "" && savedAgent ~= requestedAgent;
                    needsSetup = ~isempty(newToolkits) || agentChanged;
                end

                if needsSetup && requestedAgent ~= ""
                    % Ensure MCP server binary is available.
                    if ~exist('serverBin', 'var')
                        serverBin = terminal.ensureMCPServerBinary(config);
                    end

                    % Download toolkits (only force-download new ones).
                    toolkitPaths = struct();
                    toolkitVersions = struct();
                    toolkitSources = struct();
                    for tk = requestedToolkits
                        [toolkitPaths.(tk), toolkitVersions.(tk), toolkitSources.(tk)] = ...
                            terminal.ensureAgenticToolkit(tk, ismember(tk, newToolkits));
                    end

                    % Initialize Simulink toolkit if active.
                    if ismember("simulink", requestedToolkits)
                        terminal.initializeSimulinkToolkit(toolkitPaths.simulink);
                    end

                    % Collect extension files and register with agent.
                    extensionFiles = terminal.collectExtensionFiles(requestedToolkits, toolkitPaths);
                    terminal.mergeMarketplace(toolkitPaths);

                    if options.AgentCLI ~= "" && requestedAgent ~= "claude"
                        warning('Terminal:AgentCLIIgnored', ...
                            'AgentCLI is only supported for Agent="claude". It will be ignored.');
                        options.AgentCLI = "";
                    end
                    agentCLI = terminal.resolveAgentCLI( ...
                        requestedAgent, options.AgentCLI, config);
                    obj.MCPCommand = terminal.buildAgentRegistration( ...
                        requestedAgent, serverBin, extensionFiles, toolkitPaths, agentCLI);

                    % Persist state to config.json.
                    config.agent = char(requestedAgent);
                    if options.AgentCLI ~= ""
                        config.agentCLI = options.AgentCLI;
                    end
                    if isFirstRun
                        config.mcpServerVersion = terminal.parseMCPVersion(serverBin);
                        try
                            mlVer = char(matlabRelease.Release);
                        catch
                            mlVer = ['R' version('-release')];
                        end
                        config.matlab = struct('root', matlabroot, 'version', mlVer);
                        config.sessionMode = 'existing';
                    end
                    if ~isfield(config, 'toolkits')
                        config.toolkits = struct();
                    end
                    for tk = requestedToolkits
                        ver = toolkitVersions.(tk);
                        src = toolkitSources.(tk);
                        if ver == ""
                            ver = "unknown";
                        end
                        if src == ""
                            src = "release";
                        end
                        config.toolkits.(char(tk)) = struct( ...
                            'version', char(ver), 'source', char(src));
                    end
                    terminal.writeAgenticConfig(config);
                else
                    % No changes needed — just init Simulink if active.
                    if isfield(config, 'toolkits') ...
                            && ismember("simulink", string(fieldnames(config.toolkits)))
                        toolkitPath = fullfile(terminal.agenticInstallRoot(), 'simulink');
                        if isfolder(toolkitPath)
                            terminal.initializeSimulinkToolkit(toolkitPath);
                        end
                    end
                end
            end

            % --- Auth token (32-char hex, cryptographically random) ---
            obj.AuthToken = terminal.generateToken();

            % --- Extract bundled assets if needed ---
            terminal.extractWebAssets();

            % --- Locate the server binary ---
            obj.ServerBinary = terminal.findBinary();
            if isempty(obj.ServerBinary)
                error('Terminal:BinaryNotFound', ...
                    ['Server binary "%s" not found.\n' ...
                     'The toolbox installation may be corrupted.\n' ...
                     'Run  terminal.update()  to reinstall.'], ...
                    terminal.SERVER_BINARY_NAME);
            end

            % --- Locate web assets ---
            htmlDir = fullfile(terminal.toolboxDir(), 'html');
            htmlFile = fullfile(htmlDir, 'index.html');
            if ~isfile(htmlFile)
                error('Terminal:HTMLNotFound', ...
                    'Could not find index.html at:\n  %s', htmlFile);
            end

            % --- Build environment info ---
            matlabPid = num2str(feature('getpid'));
            matlabRoot = matlabroot;

            % --- Start the server process ---
            readyFile = [tempname, '.txt'];
            args = sprintf('--env "MATLAB_PID=%s" --env "MATLAB_ROOT=%s" --ready-file "%s"', ...
                matlabPid, matlabRoot, readyFile);

            % In Simulink mode, serve HTML directly from the Go server.
            if obj.Place == "simulink"
                args = sprintf('%s --static-dir "%s"', args, htmlDir);
            end

            % Forward LANG so the PTY inherits the user's locale.
            lang = getenv('LANG');
            if ~isempty(lang)
                args = sprintf('%s --env "LANG=%s"', args, lang);
            end

            % Pass the token via environment variable so it is not visible
            % in the process list (ps, tasklist, /proc/*/cmdline).
            setenv('MATLAB_TERMINAL_TOKEN', obj.AuthToken);

            logFile = [tempname, '.log'];
            if ispc
                % Windows: use a temp batch file to run in background.
                batFile = [tempname, '.bat'];
                fid = fopen(batFile, 'w');
                fprintf(fid, '@"%s" %s > "%s" 2>&1\n', obj.ServerBinary, args, logFile);
                fclose(fid);
                system(sprintf('start "" /b cmd /c call "%s"', batFile));
            else
                % Use /bin/sh explicitly — MATLAB's system() inherits
                % the user's login shell, and tcsh/csh don't support
                % the 2>&1 redirection syntax.
                cmd = sprintf('"%s" %s > "%s" 2>&1 &', obj.ServerBinary, args, logFile);
                system(sprintf('/bin/sh -c ''%s''', cmd));
            end

            % Clear the env var so it's not inherited by other processes.
            setenv('MATLAB_TERMINAL_TOKEN', '');

            % Wait for the server to write PID and PORT to the ready file.
            % The server writes and closes this file immediately, so there
            % is no file locking conflict on Windows.
            serverPid = [];
            port = [];
            maxWait = 5;
            elapsed = 0;
            while elapsed < maxWait
                pause(0.2);
                elapsed = elapsed + 0.2;
                if isfile(readyFile)
                    raw = fileread(readyFile);
                    pidTok = regexp(raw, 'PID:(\d+)', 'tokens', 'once');
                    portTok = regexp(raw, 'PORT:(\d+)', 'tokens', 'once');
                    if ~isempty(pidTok)
                        serverPid = str2double(pidTok{1});
                    end
                    if ~isempty(portTok)
                        port = str2double(portTok{1});
                        break;
                    end
                end
            end

            % Clean up temp files.
            if isfile(readyFile), delete(readyFile); end
            if ispc && exist('batFile', 'var') && isfile(batFile)
                delete(batFile);
            end

            if isempty(port)
                if ~isempty(serverPid)
                    terminal.killProcess(serverPid);
                end
                % Read server log for diagnostics.
                serverLog = '';
                if isfile(logFile)
                    try
                        serverLog = fileread(logFile);
                    catch
                    end
                    delete(logFile);
                end
                if serverLog ~= ""
                    error('Terminal:NoPort', ...
                        'Server did not report a port within %d seconds.\nServer output:\n%s', ...
                        maxWait, serverLog);
                else
                    error('Terminal:NoPort', ...
                        'Server did not report a port within %d seconds.', maxWait);
                end
            end

            obj.ServerProcess = struct('pid', serverPid, 'port', port);
            obj.BaseURL = sprintf('http://127.0.0.1:%d', port);
            obj.PollSeq = 0;

            % --- Branch: Simulink DDG panel vs MATLAB uihtml ---
            if obj.Place == "simulink"
                obj.initSimulinkPanel(options.Name, options.Model);
            else
                obj.initMATLABPanel(parent, options, htmlFile);
            end
        end

        function set.Theme(obj, value)
            internal.TerminalThemes.validate(value);
            obj.Theme = value; %#ok<MCSUP>
            % Push live update if already initialized.
            if ~isempty(obj.ThemeConfig) %#ok<MCSUP>
                newConfig = internal.TerminalThemes.resolve(value);
                obj.ThemeConfig = newConfig; %#ok<MCSUP>
                obj.sendToJS(struct('type', 'theme', 'theme', newConfig)); %#ok<MCSUP>
            end
        end

        function dlg = getDialogSchema(obj)
            %GETDIALOGSCHEMA DDG callback — returns webbrowser widget schema.
            %   Called by the GLUE2.DDGComponent framework when rendering the
            %   Simulink panel. Only relevant when Place="simulink".
            src.Type                        = 'webbrowser';
            src.Tag                         = 'Terminal_SimulinkWebview';
            src.Url                         = char(obj.SimulinkURL);
            src.DialogRefresh               = true;
            src.DisableContextMenu          = false;
            src.EnableInspectorInContextMenu = true;
            src.EnableInspectorOnLoad       = false;

            dlg.Items           = {src};
            dlg.DialogTag       = 'Terminal_SimulinkDialog';
            dlg.DialogTitle     = '';
            dlg.EmbeddedButtonSet = {''};
            dlg.MinMaxButtons   = 1;
            dlg.IsScrollable    = false;
        end

        function delete(obj)
            %DELETE Clean up: stop timer, kill server, close figure.
            terminal.registry('remove', obj);
            if ~isempty(obj.InitTimer) && isvalid(obj.InitTimer)
                stop(obj.InitTimer);
                delete(obj.InitTimer);
            end
            if ~isempty(obj.PollTimer) && isvalid(obj.PollTimer)
                stop(obj.PollTimer);
                delete(obj.PollTimer);
            end
            if ~isempty(obj.MCPTimer) && isvalid(obj.MCPTimer)
                stop(obj.MCPTimer);
                delete(obj.MCPTimer);
            end
            if ~isempty(obj.ServerProcess) && isstruct(obj.ServerProcess) ...
                    && isfield(obj.ServerProcess, 'pid') && ~isnan(obj.ServerProcess.pid)
                terminal.killProcess(obj.ServerProcess.pid);
            end
            % Simulink mode: destroy DDG component (removes panel from editor).
            if ~isempty(obj.DDGComponent)
                try
                    if ~isempty(obj.DDGStudio)
                        obj.DDGStudio.destroyComponent(obj.DDGComponent);
                    end
                catch
                end
                obj.DDGComponent = [];
            end
            if ~isempty(obj.ParentFigure) && isvalid(obj.ParentFigure)
                if isprop(obj.ParentFigure, 'CloseRequestFcn')
                    obj.ParentFigure.CloseRequestFcn = '';
                end
                delete(obj.ParentFigure);
            end
        end
    end

    methods (Access = private)
        function initMATLABPanel(obj, parent, options, htmlFile)
            %INITMATLABPANEL Standard uihtml-based terminal in a MATLAB figure.

            % --- Parent container ---
            if isempty(parent)
                parent = uifigure('Name', options.Name, ...
                    'Position', [100 100 800 500]);
                try
                    parent.WindowStyle = options.WindowStyle;
                catch
                    if options.WindowStyle == "docked"
                        warning('Terminal:DockNotSupported', ...
                            'Docked window style is not supported in this MATLAB release. Using normal window.');
                    end
                end
            end
            obj.ParentFigure = parent;

            % Pre-create weboptions to avoid re-parsing every call.
            obj.ReadOpts = weboptions('HeaderFields', {'Authorization', obj.AuthToken}, ...
                'Timeout', 2, 'ContentType', 'json');
            obj.WriteOpts = weboptions('HeaderFields', {'Authorization', obj.AuthToken}, ...
                'MediaType', 'application/json', 'Timeout', 2);

            % --- Read MATLAB theme / font settings ---
            themeConfig = internal.TerminalThemes.resolve(obj.Theme);
            themeConfig.tabs = obj.Tabs;

            if isprop(parent, 'AutoResizeChildren')
                parent.AutoResizeChildren = 'off';
            end

            obj.HTMLComponent = uihtml(parent);
            obj.HTMLComponent.Position = [0 0 parent.Position(3) parent.Position(4)];
            obj.HTMLComponent.HTMLSource = htmlFile;

            % Auto-resize.
            obj.ParentFigure.SizeChangedFcn = @(~,~) set(obj.HTMLComponent, ...
                'Position', [0 0 obj.ParentFigure.Position(3) obj.ParentFigure.Position(4)]);

            % Clean up when figure is closed.
            if isprop(obj.ParentFigure, 'CloseRequestFcn')
                obj.ParentFigure.CloseRequestFcn = @(~,~) delete(obj);
            end

            % Register this instance.
            terminal.registry('add', obj);

            % Use a one-shot timer to initialize AFTER the constructor returns.
            % This prevents DataChangedFcn from firing during construction.
            obj.InitTimer = timer('StartDelay', 1.5, ...
                'TimerFcn', @(t,~) obj.deferredInit(t, themeConfig));
            start(obj.InitTimer);
        end

        function initSimulinkPanel(obj, panelTitle, modelName)
            %INITSIMULINKPANEL Dock terminal in Simulink editor via DDG webbrowser.
            %   The Go server serves index.html via --static-dir. The DDG
            %   webbrowser loads it with ?port=&token=&tls=0 params, triggering
            %   the WebSocketTransport path in JS (MATLAB not in data path).

            % Get Simulink Studio (specific model or most recently active).
            studio = [];
            try
                studios = DAS.Studio.getAllStudiosSortedByMostRecentlyActive;
                if modelName ~= ""
                    % First pass: exact match (title is "ModelName - Simulink").
                    exactTitle = modelName + " - Simulink";
                    for i = 1:numel(studios)
                        if studios(i).getStudioTitle() == exactTitle
                            studio = studios(i);
                            break;
                        end
                    end
                    % Second pass: prefix match (most recently active).
                    if isempty(studio)
                        for i = 1:numel(studios)
                            if startsWith(studios(i).getStudioTitle(), modelName)
                                studio = studios(i);
                                break;
                            end
                        end
                    end
                    if isempty(studio)
                        openModels = strings(1, numel(studios));
                        for j = 1:numel(studios)
                            t = studios(j).getStudioTitle();
                            openModels(j) = extractBefore(t, ' - Simulink');
                            if ismissing(openModels(j))
                                openModels(j) = string(t);
                            end
                        end
                        error('Terminal:ModelNotFound', ...
                            'No Simulink editor found for model "%s".\nOpen models: %s', ...
                            modelName, strjoin(openModels, ', '));
                    end
                elseif ~isempty(studios)
                    studio = studios(1);
                end
            catch ME
                if startsWith(ME.identifier, 'Terminal:')
                    rethrow(ME);
                end
                error('Terminal:SimulinkNotAvailable', ...
                    'Simulink is not available: %s\nOpen a Simulink model first.', ME.message);
            end
            if isempty(studio)
                error('Terminal:NoOpenSimulinkModel', ...
                    'No Simulink model is open. Open a model first, then run terminal(Place="simulink").');
            end
            obj.DDGStudio = studio;

            % Destroy existing terminal component if present.
            componentId = 'Terminal_SimulinkPanel';
            try
                comps = studio.getAllComponents();
                for i = 1:numel(comps)
                    if strcmp(comps{i}.getName(), componentId)
                        studio.destroyComponent(comps{i});
                        break;
                    end
                end
            catch
            end

            % Build the URL served by the Go server's --static-dir.
            themeConfig = internal.TerminalThemes.resolve(obj.Theme);
            themeConfig.tabs = obj.Tabs;
            themeJson = urlencode(jsonencode(themeConfig));
            serverUrl = sprintf('http://127.0.0.1:%d/static/index.html?port=%d&token=%s&tls=0&theme=%s&shell=%s', ...
                obj.ServerProcess.port, obj.ServerProcess.port, obj.AuthToken, themeJson, urlencode(obj.Shell));
            % Store schema source data for getDialogSchema.
            obj.SimulinkURL = serverUrl;

            % Create and dock the DDG component.
            component = GLUE2.DDGComponent(studio, componentId, obj);
            component.DestroyOnHide = false;
            component.AllowMinimize = true;
            studio.registerComponent(component);
            component.setPreferredSize(600, 400);
            studio.moveComponentToDock(component, char(panelTitle), 'Right', 'Tabbed');
            obj.DDGComponent = component;

            % Clean up when the panel is destroyed by the Studio.
            try
                addlistener(component, 'ObjectBeingDestroyed', @(~,~) delete(obj));
            catch
            end

            % Register this instance.
            terminal.registry('add', obj);

            % Monitor sessions — close panel when all tabs exit.
            % In Simulink mode, data flows over WebSocket (MATLAB not in path),
            % so we need a lightweight timer to detect when all sessions end.
            obj.ReadOpts = weboptions('HeaderFields', {'Authorization', obj.AuthToken}, ...
                'Timeout', 2, 'ContentType', 'json');
            obj.PollTimer = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'StartDelay', 2, ...
                'Period', 1, ...
                'TimerFcn', @(~,~) obj.checkAllExited(), ...
                'ErrorFcn', @(~,~) []);
            start(obj.PollTimer);
        end

        function deferredInit(obj, initTimer, themeConfig)
            %DEFERREDINIT Called after constructor returns to avoid reentrant callbacks.
            stop(initTimer);
            delete(initTimer);
            obj.InitTimer = [];

            if ~isvalid(obj)
                return;
            end

            obj.ThemeConfig = themeConfig;
            obj.UseEvents = ~isMATLABReleaseOlderThan('R2023a');

            if obj.UseEvents
                % R2023a+: event-based API — no data loss, no buffering needed.
                obj.HTMLComponent.HTMLEventReceivedFcn = @(~, event) obj.onHTMLEvent(event);
                sendEventToHTMLSource(obj.HTMLComponent, 'init', themeConfig);
            else
                % Legacy: Data channel (last-write-wins).
                obj.HTMLComponent.DataChangedFcn = @(src, ~) obj.onJSMessage(src);
                obj.HTMLComponent.Data = struct('type', 'init', 'theme', themeConfig);
            end

            % Snapshot the current figure color for theme change detection.
            try
                obj.LastFigureColor = get(groot, 'defaultFigureColor');
            catch
                obj.LastFigureColor = [];
            end

            % Start polling for server output.
            obj.PollTimer = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', obj.POLL_INTERVAL, ...
                'TimerFcn', @(~,~) obj.pollOutput(), ...
                'ErrorFcn', @(~,~) []);
            start(obj.PollTimer);
        end

        function checkThemeChanged(obj)
            %CHECKTHEMECHANGED Compare current figure color to cached value.
            try
                c = get(groot, 'defaultFigureColor');
            catch
                return;
            end
            if isequal(c, obj.LastFigureColor)
                return;
            end
            obj.LastFigureColor = c;
            newConfig = internal.TerminalThemes.resolve(obj.Theme);
            obj.ThemeConfig = newConfig;
            obj.sendToJS(struct('type', 'theme', ...
                'theme', newConfig));
        end

        function onHTMLEvent(obj, event)
            %ONHTMLEVENT Handle events from JS via the R2023a+ event API.
            %   Still queued for the poll timer to avoid concurrent webwrite
            %   calls, but no JS-side data loss since events don't overwrite.
            msg = event.HTMLEventData;
            msg.type = event.HTMLEventName;
            obj.OutQueue{end+1} = msg;
        end

        function onJSMessage(obj, src)
            %ONJSMESSAGE Handle messages from JS via the legacy Data channel.
            %   Queues messages for the poll timer to process, avoiding
            %   concurrent webread/webwrite calls.
            msg = src.Data;
            if ~isstruct(msg) || ~isfield(msg, 'type')
                return;
            end
            obj.OutQueue{end+1} = msg;
        end

        function pollOutput(obj)
            %POLLOUTPUT Process queued JS messages, then poll for output.
            try
                % Skip normal polling while a restart is in progress.
                if obj.IsRestarting
                    return;
                end

                % --- Periodic theme change detection (only in auto mode) ---
                if ~isstruct(obj.Theme) && string(obj.Theme) == "auto"
                    obj.ThemePollCount = obj.ThemePollCount + 1;
                    if obj.ThemePollCount >= obj.THEME_CHECK_TICKS
                        obj.ThemePollCount = 0;
                        obj.checkThemeChanged();
                    end
                end

                % --- Drain outbound queue (JS -> server) ---
                if ~isempty(obj.OutQueue)
                    if obj.UseEvents
                        % R2023a+: drain all — event API doesn't overwrite.
                        queue = obj.OutQueue;
                        obj.OutQueue = {};
                        for i = 1:numel(queue)
                            obj.processJSMessage(queue{i});
                        end
                    else
                        % Legacy: one at a time, then return so JS can
                        % read the response before Data is overwritten.
                        msg = obj.OutQueue{1};
                        obj.OutQueue(1) = [];
                        obj.processJSMessage(msg);
                        return;
                    end
                end

                % --- Poll for server output ---
                url = sprintf('%s/api/poll?since=%d', obj.BaseURL, obj.PollSeq);
                resp = webread(url, obj.ReadOpts);
                obj.ConsecutivePollFailures = 0;
                if isfield(resp, 'messages') && ~isempty(resp.messages)
                    msgs = resp.messages;
                    hasExited = false;
                    if iscell(msgs)
                        for i = 1:numel(msgs)
                            m = msgs{i};
                            if m.seq > obj.PollSeq
                                obj.PollSeq = m.seq;
                            end
                            if strcmp(m.type, 'exited')
                                hasExited = true;
                            end
                        end
                        obj.sendToJS(struct('type', 'batch', 'messages', {msgs}));
                    elseif isstruct(msgs)
                        for i = 1:numel(msgs)
                            if msgs(i).seq > obj.PollSeq
                                obj.PollSeq = msgs(i).seq;
                            end
                            if strcmp(msgs(i).type, 'exited')
                                hasExited = true;
                            end
                        end
                        obj.sendToJS(struct('type', 'batch', 'messages', {msgs}));
                    end
                    if hasExited
                        obj.checkAllExited();
                    end
                end
            catch
                obj.ConsecutivePollFailures = obj.ConsecutivePollFailures + 1;
                if obj.ConsecutivePollFailures >= 50
                    obj.tryRestartServer();
                end
            end
        end

        function tryRestartServer(obj)
            %TRYRESTARTSERVER Detect dead server and relaunch it.
            %   Called after 5 consecutive poll failures. Checks if the
            %   server PID is still alive; if not, relaunches the binary
            %   and lets the existing ready/init flow create fresh sessions.
            obj.IsRestarting = true;
            obj.ConsecutivePollFailures = 0;

            % Check if server process is still alive.
            if ~isempty(obj.ServerProcess) && isstruct(obj.ServerProcess) ...
                    && isfield(obj.ServerProcess, 'pid') && ~isnan(obj.ServerProcess.pid)
                if terminal.isProcessAlive(obj.ServerProcess.pid)
                    % Server is alive but unresponsive — don't restart.
                    obj.IsRestarting = false;
                    return;
                end
            end

            % Show restarting overlay in JS.
            obj.sendToJS(struct('type', 'restarting'));

            % Relaunch the server binary.
            try
                matlabPid = num2str(feature('getpid'));
                matlabRoot = matlabroot;
                readyFile = [tempname, '.txt'];
                args = sprintf('--env "MATLAB_PID=%s" --env "MATLAB_ROOT=%s" --ready-file "%s"', ...
                    matlabPid, matlabRoot, readyFile);

                lang = getenv('LANG');
                if ~isempty(lang)
                    args = sprintf('%s --env "LANG=%s"', args, lang);
                end

                setenv('MATLAB_TERMINAL_TOKEN', obj.AuthToken);

                logFile = [tempname, '.log'];
                if ispc
                    batFile = [tempname, '.bat'];
                    fid = fopen(batFile, 'w');
                    fprintf(fid, '@"%s" %s > "%s" 2>&1\n', obj.ServerBinary, args, logFile);
                    fclose(fid);
                    system(sprintf('start "" /b cmd /c call "%s"', batFile));
                else
                    cmd = sprintf('"%s" %s > "%s" 2>&1 &', obj.ServerBinary, args, logFile);
                    system(sprintf('/bin/sh -c ''%s''', cmd));
                end

                setenv('MATLAB_TERMINAL_TOKEN', '');

                % Wait for the server to write PID and PORT.
                serverPid = [];
                port = [];
                maxWait = 5;
                elapsed = 0;
                while elapsed < maxWait
                    pause(0.2);
                    elapsed = elapsed + 0.2;
                    if isfile(readyFile)
                        raw = fileread(readyFile);
                        pidTok = regexp(raw, 'PID:(\d+)', 'tokens', 'once');
                        portTok = regexp(raw, 'PORT:(\d+)', 'tokens', 'once');
                        if ~isempty(pidTok)
                            serverPid = str2double(pidTok{1});
                        end
                        if ~isempty(portTok)
                            port = str2double(portTok{1});
                            break;
                        end
                    end
                end

                if isfile(readyFile), delete(readyFile); end
                if ispc && exist('batFile', 'var') && isfile(batFile)
                    delete(batFile);
                end

                if isempty(port)
                    if ~isempty(serverPid)
                        terminal.killProcess(serverPid);
                    end
                    obj.IsRestarting = false;
                    return;
                end

                obj.ServerProcess = struct('pid', serverPid, 'port', port);
                obj.BaseURL = sprintf('http://127.0.0.1:%d', port);
                obj.PollSeq = 0;

                % Update weboptions with same auth token.
                obj.ReadOpts = weboptions('HeaderFields', {'Authorization', obj.AuthToken}, ...
                    'Timeout', 2, 'ContentType', 'json');
                obj.WriteOpts = weboptions('HeaderFields', {'Authorization', obj.AuthToken}, ...
                    'MediaType', 'application/json', 'Timeout', 2);
            catch
                obj.IsRestarting = false;
                return;
            end

            obj.IsRestarting = false;

            % Send init directly — the page didn't reload so setup()
            % won't fire. The 'restarting' handler already reset
            % initialized=false and disposed old tabs.
            initData = obj.ThemeConfig;
            if obj.UseEvents
                sendEventToHTMLSource(obj.HTMLComponent, 'init', initData);
            else
                obj.HTMLComponent.Data = struct('type', 'init', 'theme', initData);
            end
        end

        function processJSMessage(obj, msg)
            %PROCESSJSMESSAGE Execute a single queued JS message.
            switch msg.type
                case 'ready'
                    % HTML page (re)loaded — re-send init so JS can start.
                    % Query the server for existing sessions so JS can
                    % reconnect instead of creating new tabs.
                    initData = obj.ThemeConfig;
                    try
                        url = [obj.BaseURL, '/api/sessions'];
                        resp = webread(url, obj.ReadOpts);
                        if isfield(resp, 'ids') && ~isempty(resp.ids)
                            if ischar(resp.ids) || isstring(resp.ids)
                                ids = {char(resp.ids)};
                            else
                                ids = resp.ids;
                            end
                            initData.existingSessionIds = ids;
                            % Fetch scrollback for each session.
                            scrollbacks = struct();
                            for k = 1:numel(ids)
                                sid = ids{k};
                                try
                                    sbUrl = sprintf('%s/api/scrollback?id=%s', obj.BaseURL, sid);
                                    sbResp = webread(sbUrl, obj.ReadOpts);
                                    if isfield(sbResp, 'serialized')
                                        scrollbacks.(sid) = struct('serialized', sbResp.serialized);
                                    elseif isfield(sbResp, 'data')
                                        scrollbacks.(sid) = sbResp.data;
                                    end
                                catch
                                end
                            end
                            initData.scrollbacks = scrollbacks;
                        end
                    catch
                        % Server may not be ready yet — JS will create a
                        % new tab as usual.
                    end
                    if obj.UseEvents
                        sendEventToHTMLSource(obj.HTMLComponent, 'init', initData);
                    else
                        obj.HTMLComponent.Data = struct('type', 'init', 'theme', initData);
                    end
                case 'create'
                    createReq = struct('cols', 80, 'rows', 24, 'shell', obj.Shell);
                    resp = obj.serverPost('/api/create', createReq);
                    if ~isempty(resp) && isfield(resp, 'id')
                        obj.sendToJS(struct('type', 'created', 'id', resp.id));
                        % Pre-populate MCP registration command in the
                        % first session. Delayed so the shell prompt is
                        % ready. Sent without a newline — user hits Enter.
                        if ~isempty(obj.MCPCommand)
                            sid = resp.id;
                            cmd = obj.MCPCommand;
                            obj.MCPCommand = [];  % only for the first session
                            obj.MCPTimer = timer('StartDelay', 1.0, ...
                                'TimerFcn', @(t,~) obj.sendMCPHint(t, sid, cmd));
                            start(obj.MCPTimer);
                        end
                    end
                case 'input'
                    obj.serverPost('/api/input', struct('id', msg.id, 'data', msg.data));
                case 'resize'
                    obj.serverPost('/api/resize', struct('id', msg.id, 'cols', msg.cols, 'rows', msg.rows));
                case 'close'
                    obj.serverPost('/api/close', struct('id', msg.id));
                case 'state'
                    obj.serverPost('/api/state', struct('id', msg.id, 'state', msg.data));
                case 'paste'
                    text = clipboard('paste');
                    if ~isempty(text)
                        obj.serverPost('/api/input', struct('id', msg.id, 'data', text));
                    end
            end
        end

        function checkAllExited(obj)
            %CHECKALLEXITED Close window if server has no active sessions.
            try
                url = [obj.BaseURL, '/api/sessions'];
                resp = webread(url, obj.ReadOpts);
                if resp.count > 0
                    return;  % Other sessions still active.
                end
            catch
                % Server gone — close anyway.
            end
            fig = obj.ParentFigure;
            closeTimer = timer('StartDelay', 0.5, ...
                'TimerFcn', @(t,~) terminal.deferredClose(t, obj, fig));
            start(closeTimer);
        end

        function resp = serverPost(obj, endpoint, data)
            %SERVERPOST Send a POST request to the Go server.
            url = [obj.BaseURL, endpoint];
            resp = webwrite(url, data, obj.WriteOpts);
        end

        function sendMCPHint(obj, tmr, sessionId, cmd)
            %SENDMCPHINT Pre-populate MCP registration command in a session.
            stop(tmr);
            delete(tmr);
            obj.MCPTimer = [];
            if ~isvalid(obj)
                return;
            end
            try
                obj.serverPost('/api/input', struct('id', sessionId, 'data', cmd));
            catch
            end
        end

        function sendToJS(obj, msg)
            %SENDTOJS Send a message to JS.
            if isempty(obj.HTMLComponent) || ~isvalid(obj.HTMLComponent)
                return;
            end
            if obj.UseEvents
                sendEventToHTMLSource(obj.HTMLComponent, msg.type, msg);
            else
                obj.HTMLComponent.Data = msg;
            end
        end
    end

    methods (Static)
        function v = version()
            %VERSION Return the installed toolbox version string.
            %
            %   v = terminal.version()
            v = terminalVersion();
        end

        function terminals = list()
            %LIST Return handles to all running terminal instances.
            %
            %   terminals = terminal.list()
            %
            %   Returns a (possibly empty) array of terminal handles.
            terminals = terminal.registry('get');
        end

        function opts = agentOptions()
            %AGENTOPTIONS Display saved agentic configuration.
            %
            %   terminal.agentOptions()
            %
            %   Shows the configured agent and toolkits.
            config = terminal.readAgenticConfig();
            if ~isfield(config, 'agent')
                fprintf('No agent options configured. Run terminal(Agentic=true) to set up.\n');
                opts = [];
                return
            end
            toolkits = string.empty;
            if isfield(config, 'toolkits')
                toolkits = reshape(string(fieldnames(config.toolkits)), 1, []);
            end
            opts = struct('Agent', string(config.agent), 'Toolkits', {toolkits});
            if nargout == 0
                fprintf('  Agent:    %s\n', string(opts.Agent));
                fprintf('  Toolkits: %s\n', strjoin(toolkits, ", "));
                clear opts
            end
        end

        function resetAgentOptions()
            %RESETAGENTOPTIONS Clear saved agent preferences.
            %
            %   terminal.resetAgentOptions()
            %
            %   Next call to terminal(Agentic=true) will re-run the setup wizard.
            %   Installed toolkits and MCP server are preserved.
            config = terminal.readAgenticConfig();
            fieldsToRemove = intersect(fieldnames(config), {'agent', 'agentCLI'});
            if ~isempty(fieldsToRemove)
                config = rmfield(config, fieldsToRemove);
                terminal.writeAgenticConfig(config);
            end
            fprintf('Agent options cleared. Next terminal(Agent=...) will re-run setup.\n');
        end

        function updateAgenticToolkit(toolkit)
            %UPDATEAGENTICTOOLKIT Update installed agentic toolkit(s) to latest.
            %
            %   terminal.updateAgenticToolkit()            % update all
            %   terminal.updateAgenticToolkit("matlab")    % update MATLAB only
            %   terminal.updateAgenticToolkit("simulink")  % update Simulink only
            arguments
                toolkit string = ""
            end
            if toolkit == ""
                % Update all installed toolkits.
                baseDir = terminal.agenticInstallRoot();
                if isfolder(fullfile(baseDir, 'matlab'))
                    terminal.updateSingleToolkit("matlab");
                end
                if isfolder(fullfile(baseDir, 'simulink'))
                    terminal.updateSingleToolkit("simulink");
                end
            else
                terminal.updateSingleToolkit(toolkit);
            end
        end

        function updateMCPServer()
            %UPDATEMCPSERVER Update the MCP server binary to the latest release.
            %
            %   terminal.updateMCPServer()

            serverBin = terminal.mcpBinaryPath();

            % Check current version.
            currentVer = '';
            if isfile(serverBin)
                currentVer = terminal.parseMCPVersion(serverBin);
            end

            % Fetch latest release directly (no fallback — user wants the latest).
            url = sprintf('https://api.github.com/repos/%s/releases/latest', ...
                terminal.MCP_SERVER_REPO);
            try
                opts = weboptions('ContentType', 'json', 'Timeout', 15);
                release = webread(url, opts);
            catch me
                error('Terminal:MCPUpdateFailed', ...
                    'Unable to check for updates:\n  %s\n  Try again later.', me.message);
            end
            latestVer = strrep(release.tag_name, 'v', '');

            if ~isempty(currentVer) && terminal.compareVersions(currentVer, latestVer) >= 0
                fprintf('MCP server is already up to date (v%s).\n', currentVer);
                return;
            end

            if ~isempty(currentVer)
                fprintf('Updating MCP server from v%s to %s...\n', currentVer, release.tag_name);
            else
                fprintf('Downloading MCP server %s...\n', release.tag_name);
            end

            % Determine platform asset name.
            arch = computer('arch');
            switch arch
                case 'glnxa64', assetSuffix = '-glnxa64';
                case 'maca64',  assetSuffix = '-maca64';
                case 'maci64',  assetSuffix = '-maci64';
                case 'win64',   assetSuffix = '-win64.exe';
                otherwise
                    error('Terminal:UnsupportedPlatform', ...
                        'Unsupported platform: %s', arch);
            end

            assetName = [terminal.MCP_SERVER_BINARY assetSuffix];
            binaryURL = terminal.findMCPAsset(release, assetName);
            if isempty(binaryURL)
                error('Terminal:MCPDownloadFailed', ...
                    'No binary asset "%s" found in release %s.', assetName, release.tag_name);
            end

            % Remove existing binary (handle Windows locking).
            if isfile(serverBin)
                try
                    delete(serverBin);
                catch
                    if ispc
                        try
                            movefile(serverBin, [serverBin '.old'], 'f');
                        catch
                            error('Terminal:BinaryLocked', ...
                                ['Cannot replace the MCP server binary because it is in use.\n' ...
                                 'Close any running coding agent sessions and try again.']);
                        end
                    else
                        error('Terminal:BinaryDeleteFailed', ...
                            'Cannot remove existing binary: %s', serverBin);
                    end
                end
            end

            % Download.
            binDir = fileparts(serverBin);
            if ~isfolder(binDir)
                mkdir(binDir);
            end
            fprintf('  Downloading %s %s for %s...\n', ...
                terminal.MCP_SERVER_BINARY, release.tag_name, arch);
            try
                websave(serverBin, binaryURL);
            catch me
                error('Terminal:MCPDownloadFailed', 'Download failed:\n  %s', me.message);
            end

            % Make executable and strip quarantine on macOS.
            if ~ispc
                system(sprintf('chmod +x "%s"', serverBin));
                if ismac
                    system(sprintf('xattr -d com.apple.quarantine "%s" 2>/dev/null', serverBin));
                end
            end
            fprintf('MCP server updated to %s at:\n  %s\n', release.tag_name, serverBin);
        end

        function closeAll()
            %CLOSEALL Close all running terminal instances.
            %
            %   terminal.closeAll()
            terminals = terminal.list();
            for i = 1:numel(terminals)
                delete(terminals(i));
            end
        end

        function names = themes()
            %THEMES List available built-in theme names.
            %
            %   terminal.themes()
            names = internal.TerminalThemes.list();
        end

        function setDefaultTheme(theme)
            %SETDEFAULTTHEME Set the default theme for new terminal instances.
            %
            %   terminal.setDefaultTheme("dracula")
            %   terminal.setDefaultTheme("auto")      — reset to default
            %
            %   The default theme persists across MATLAB sessions. New
            %   terminals use this theme unless overridden with Theme=.
            internal.TerminalThemes.validate(theme);
            if isstruct(theme)
                setpref('terminal', 'Theme', theme);
            else
                setpref('terminal', 'Theme', string(theme));
            end
        end

        function theme = getDefaultTheme()
            %GETDEFAULTTHEME Return the current default theme.
            %
            %   terminal.getDefaultTheme()
            if ispref('terminal', 'Theme')
                theme = getpref('terminal', 'Theme');
            else
                theme = "auto";
            end
        end

        function update(version)
            %UPDATE Check for and install a toolbox version from GitHub.
            %
            %   terminal.update()          — update to the latest stable release
            %   terminal.update("1.2.0")   — install a specific version
            %   terminal.update("v1.2.0")  — "v" prefix is accepted
            %   terminal.update("1.2.0-rc1") — release candidates work too
            %
            %   When called without arguments, only releases marked as
            %   "Latest" on GitHub are considered (pre-releases and drafts
            %   are skipped). To install a pre-release, specify its version
            %   explicitly.
            arguments
                version (1,1) string = ""
            end

            disp('Checking for updates...');

            if version == ""
                release = terminal.fetchLatestRelease();
            else
                release = terminal.fetchRelease(version);
            end

            targetVersion = terminal.tagToVersion(release.tag_name);
            installedVersion = string(terminal.version());

            fprintf('  Installed version: %s\n', installedVersion);
            fprintf('  Target version:    %s\n', targetVersion);

            % Find the .mltbx asset in the release.
            mltbxURL = terminal.findMltbxAsset(release);

            % Ask for confirmation.
            if targetVersion == installedVersion
                disp('Already up to date.');
                reply = input('Reinstall current version? (y/n): ', 's');
            else
                reply = input(sprintf('Update from %s to %s? (y/n): ', ...
                    installedVersion, targetVersion), 's');
            end
            if ~strcmpi(reply, 'y')
                disp('Update cancelled.');
                return;
            end

            % Step 1: Download BEFORE uninstalling (safe ordering).
            disp('Step 1/5: Downloading release...');
            tmpFile = fullfile(tempdir, 'Terminal.mltbx');
            try
                websave(tmpFile, mltbxURL);
            catch me
                error('Terminal:UpdateFailed', ...
                    'Download failed (installed version unchanged):\n  %s', me.message);
            end

            % Step 2: Close all open terminals.
            disp('Step 2/5: Closing all open terminals...');
            terminal.closeAll();

            % Step 3: Remove runtime artifacts before uninstall.
            % Remove files we created at runtime so the uninstaller only
            % deals with the original .mltbx contents and doesn't fail on
            % busy files (e.g., running binaries, NFS lock files).
            disp('Step 3/5: Clearing any cached assets...');
            cleanupDirs = {
                fullfile(terminal.toolboxDir(), 'bin')
                fullfile(terminal.toolboxDir(), 'html')
            };
            cleanupFiles = {
                fullfile(terminal.toolboxDir(), '.extracted')
                fullfile(terminal.toolboxDir(), 'merged-extension-tools.json')
            };
            for i = 1:numel(cleanupDirs)
                if isfolder(cleanupDirs{i})
                    try rmdir(cleanupDirs{i}, 's'); catch, end
                end
            end
            for i = 1:numel(cleanupFiles)
                if isfile(cleanupFiles{i})
                    try delete(cleanupFiles{i}); catch, end
                end
            end

            % Step 4: Uninstall current toolbox.
            disp('Step 4/5: Uninstalling current version...');
            try
                matlab.addons.uninstall(terminal.TOOLBOX_ID);
            catch
                % May fail if running from source or not installed as toolbox.
            end

            % Step 5: Install the new version.
            disp('Step 5/5: Installing new version...');
            try
                matlab.addons.install(tmpFile);
            catch me
                fprintf(2, 'Installation failed. The .mltbx is saved at:\n  %s\n', tmpFile);
                fprintf(2, 'You can install it manually: matlab.addons.install("%s")\n', tmpFile);
                error('Terminal:UpdateFailed', ...
                    'Installation failed:\n  %s', me.message);
            end
            delete(tmpFile);
            rehash toolboxcache;

            fprintf('Successfully updated Terminal to version %s.\n', targetVersion);
        end

        function versions()
            %VERSIONS List available terminal releases on GitHub.
            %
            %   terminal.versions()
            %
            %   Displays a table of available releases with version,
            %   date, and whether each is a pre-release or the latest.

            url = sprintf('https://api.github.com/repos/%s/releases', ...
                terminal.GITHUB_REPO);
            try
                opts = weboptions('ContentType', 'json', 'Timeout', 10);
                releases = webread(url, opts);
            catch me
                error('Terminal:VersionsFailed', ...
                    'Could not reach GitHub:\n  %s', me.message);
            end

            if isempty(releases)
                disp('No releases found.');
                return;
            end

            installedVersion = string(terminal.version());
            fprintf('  Installed: %s\n\n', installedVersion);
            fprintf('  %-14s %-12s %s\n', 'VERSION', 'DATE', 'LABEL');
            fprintf('  %-14s %-12s %s\n', '-------', '----', '-----');

            for i = 1:numel(releases)
                if iscell(releases)
                    r = releases{i};
                else
                    r = releases(i);
                end
                v = terminal.tagToVersion(r.tag_name);
                % Parse date from ISO 8601 published_at.
                dateStr = extractBefore(string(r.published_at), 'T');

                labels = {};
                if isfield(r, 'prerelease') && r.prerelease
                    labels{end+1} = 'pre-release'; %#ok<AGROW>
                end
                if v == installedVersion
                    labels{end+1} = 'installed'; %#ok<AGROW>
                end
                label = strjoin(labels, ', ');
                fprintf('  %-14s %-12s %s\n', v, dateStr, label);
            end

            % Identify which is the "Latest" release (what update() would pick).
            try
                latestUrl = sprintf('https://api.github.com/repos/%s/releases/latest', ...
                    terminal.GITHUB_REPO);
                latest = webread(latestUrl, opts);
                latestV = terminal.tagToVersion(latest.tag_name);
                fprintf('\n  Latest stable release: %s\n', latestV);
            catch
            end
        end

        function verify()
            %VERIFY Verify the installed server binary against the GitHub release.
            %
            %   terminal.verify()
            %
            %   Checks the SHA-256 hash of the installed server binary against
            %   the checksums published on the matching GitHub release. If
            %   slsa-verifier is available on the system PATH, also performs
            %   full SLSA provenance verification.

            v = terminal.version();
            if v == "0.0.0-dev"
                fprintf('Skipping verification: running from source (version 0.0.0-dev).\n');
                return;
            end

            % Ensure assets are extracted (needed on fresh install).
            terminal.extractWebAssets();

            % Locate the installed binary.
            binaryPath = terminal.findBinary();
            if isempty(binaryPath)
                fprintf(2, 'Server binary not found. Cannot verify.\n');
                return;
            end
            fprintf('Installed version: %s\n', v);
            fprintf('Binary path:       %s\n\n', binaryPath);

            % Compute local SHA-256.
            localHash = terminal.sha256file(binaryPath);
            fprintf('Local SHA-256:     %s\n', localHash);

            % Determine expected asset name for this platform.
            arch = computer('arch');
            switch arch
                case 'glnxa64', assetName = 'matlab-terminal-server-glnxa64';
                case 'maci64',  assetName = 'matlab-terminal-server-maci64';
                case 'maca64',  assetName = 'matlab-terminal-server-maca64';
                case 'win64',   assetName = 'matlab-terminal-server-win64.exe';
                otherwise
                    fprintf(2, 'Unknown platform: %s\n', arch);
                    return;
            end

            % Fetch checksums.txt from the matching GitHub release.
            tag = "v" + v;
            checksumsURL = sprintf( ...
                'https://github.com/%s/releases/download/%s/checksums.txt', ...
                terminal.GITHUB_REPO, tag);
            fprintf('Fetching checksums from %s release...\n', tag);
            try
                raw = webread(checksumsURL, weboptions('ContentType', 'text', 'Timeout', 10));
            catch me
                fprintf(2, 'Could not fetch checksums.txt from release %s:\n  %s\n', tag, me.message);
                fprintf(2, 'The release may not include checksums (added in v0.11.0).\n');
                return;
            end

            % Parse checksums.txt (format: "<hash>  <filename>" per line).
            lines = splitlines(string(raw));
            expectedHash = '';
            for i = 1:numel(lines)
                line = strtrim(lines(i));
                if line == ""
                    continue;
                end
                parts = split(line);
                if numel(parts) >= 2 && parts(2) == assetName
                    expectedHash = parts(1);
                    break;
                end
            end

            if expectedHash == ""
                fprintf(2, 'No checksum found for %s in release %s.\n', assetName, tag);
                return;
            end

            fprintf('Expected SHA-256:  %s\n\n', expectedHash);

            if strcmpi(localHash, expectedHash)
                fprintf('PASS: SHA-256 checksum matches the GitHub release.\n');
            else
                fprintf(2, 'FAIL: SHA-256 mismatch!\n');
                fprintf(2, '  Local:    %s\n', localHash);
                fprintf(2, '  Expected: %s\n', expectedHash);
                fprintf(2, 'The installed binary does not match the published release.\n');
                return;
            end

            % Find or offer to download slsa-verifier.
            verifierBin = terminal.findOrInstallSLSAVerifier();
            if isempty(verifierBin)
                return;
            end

            % Download provenance attestation and binary to a temp dir for verification.
            fprintf('\nRunning SLSA provenance verification...\n');
            tmpDir = fullfile(tempdir, 'terminal-verify');
            if isfolder(tmpDir)
                rmdir(tmpDir, 's');
            end
            mkdir(tmpDir);

            try
                provenanceURL = sprintf( ...
                    'https://github.com/%s/releases/download/%s/multiple.intoto.jsonl', ...
                    terminal.GITHUB_REPO, tag);
                provenancePath = fullfile(tmpDir, 'multiple.intoto.jsonl');
                websave(provenancePath, provenanceURL);

                binaryURL = sprintf( ...
                    'https://github.com/%s/releases/download/%s/%s', ...
                    terminal.GITHUB_REPO, tag, assetName);
                binaryDst = fullfile(tmpDir, assetName);
                websave(binaryDst, binaryURL);

                cmd = sprintf( ...
                    '"%s" verify-artifact --provenance-path "%s" --source-uri github.com/%s --source-tag %s "%s" 2>&1', ...
                    verifierBin, provenancePath, terminal.GITHUB_REPO, tag, binaryDst);
                [st, output] = system(cmd);
                if st == 0
                    fprintf('PASS: SLSA provenance verification succeeded.\n');
                    fprintf('%s\n', strtrim(output));
                else
                    fprintf(2, 'FAIL: SLSA provenance verification failed.\n');
                    fprintf(2, '%s\n', strtrim(output));
                end
            catch me
                fprintf(2, 'SLSA verification error: %s\n', me.message);
            end

            % Clean up.
            try
                rmdir(tmpDir, 's');
            catch
            end
        end

        function results = test()
            %TEST Run the terminal test suite and produce a report.
            %
            %   terminal.test()
            %
            %   Discovers and runs all test classes in the toolbox tests/
            %   folder. Unit tests run everywhere; integration tests that
            %   need a display or server binary are skipped automatically
            %   when those resources are unavailable.
            %
            %   Produces an HTML report in a test-results/ folder and
            %   prints a summary to the command window.
            %
            %   results = terminal.test()   — also returns the TestResult array

            testsDir = fullfile(terminal.toolboxDir(), 'tests');

            fprintf('\n<strong>Terminal Test Suite v%s</strong>\n\n', terminal.version());

            % Discover all test classes.
            suite = matlab.unittest.TestSuite.fromFolder(testsDir);
            fprintf('Found %d tests in %s\n\n', numel(suite), testsDir);

            % Build runner with plugins.
            runner = matlab.unittest.TestRunner.withTextOutput('Verbosity', 3);

            % HTML report if available (R2020b+).
            reportDir = fullfile(pwd, 'test-results');
            try
                plugin = matlab.unittest.plugins.HTMLReportPlugin.producingReport(reportDir);
                if ~isfolder(reportDir)
                    mkdir(reportDir);
                end
                runner.addPlugin(plugin);
                hasReport = true;
            catch
                hasReport = false;
            end

            % Run.
            results = runner.run(suite);

            % Summary.
            nPassed = nnz([results.Passed]);
            nFailed = nnz([results.Failed]);
            nIncomplete = nnz([results.Incomplete]);
            nTotal = numel(results);

            fprintf('\n<strong>Results: %d/%d passed', nPassed, nTotal);
            if nFailed > 0
                fprintf(', %d failed', nFailed);
            end
            if nIncomplete > 0
                fprintf(', %d skipped', nIncomplete);
            end
            fprintf('</strong>\n');

            if hasReport
                fprintf('Report: <a href="matlab:web(''%s'',''-browser'')">%s</a>\n', ...
                    fullfile(reportDir, 'index.html'), reportDir);
            end
            fprintf('\n');

            if nargout == 0
                clear results
            end
        end
    end

    methods (Static, Access = private)
        function setAgentOptions(opts)
            %SETAGENTOPTIONS Save agent preferences to config.json.
            terminal.validateAgentOptions(opts);
            config = terminal.readAgenticConfig();
            config.agent = char(string(opts.Agent));
            if ~isfield(config, 'toolkits')
                config.toolkits = struct();
            end
            for tk = reshape(string(opts.Toolkits), 1, [])
                if ~isfield(config.toolkits, char(tk))
                    config.toolkits.(char(tk)) = struct( ...
                        'version', 'unknown', 'source', 'release');
                end
            end
            terminal.writeAgenticConfig(config);
        end

        function opts = getAgentOptions()
            %GETAGENTOPTIONS Retrieve saved agent preferences from config.json.
            config = terminal.readAgenticConfig();
            if ~isfield(config, 'agent')
                error('Terminal:NoAgentOptions', ...
                    'No saved agent options. Run terminal(Agent="claude") to configure.');
            end
            toolkits = string.empty;
            if isfield(config, 'toolkits')
                toolkits = reshape(string(fieldnames(config.toolkits)), 1, []);
            end
            opts = struct('Agent', string(config.agent), 'Toolkits', {toolkits});
        end


        function p = toolboxDir()
            %TOOLBOXDIR Return the directory containing terminal.m.
            %   All runtime artifacts (extracted assets, downloaded binaries,
            %   agentic toolkits) are stored relative to this directory.
            p = fileparts(mfilename('fullpath'));
        end

        function root = agenticInstallRoot()
            %AGENTICINSTALLROOT Return the shared agentic toolkit install root.
            %   ~/.matlab/agentic-toolkits/ — compatible with setupAgenticToolkit.
            root = fullfile(terminal.userHome(), '.matlab', 'agentic-toolkits');
        end

        function config = readAgenticConfig()
            %READAGENTICCONFIG Read config.json from the install root.
            %   Returns empty struct if not found.
            configFile = fullfile(terminal.agenticInstallRoot(), 'config.json');
            if isfile(configFile)
                config = jsondecode(fileread(configFile));
            else
                config = struct();
            end
        end

        function writeAgenticConfig(config)
            %WRITEAGENTICCONFIG Write config.json to the install root.
            installRoot = terminal.agenticInstallRoot();
            if ~isfolder(installRoot)
                mkdir(installRoot);
            end
            config.lastUpdated = char(datetime('now', ...
                'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z''', 'TimeZone', 'UTC'));
            configFile = fullfile(installRoot, 'config.json');
            fid = fopen(configFile, 'w');
            if fid == -1
                warning('Terminal:ConfigWriteFailed', ...
                    'Cannot write config: %s', configFile);
                return;
            end
            cleanupObj = onCleanup(@() fclose(fid));
            fwrite(fid, jsonencode(config, 'PrettyPrint', true));
        end


        function binPath = mcpBinaryPath()
            %MCPBINARYPATH Return the path for the MCP server binary.
            %   ~/.matlab/agentic-toolkits/bin/matlab-mcp-core-server[.exe]
            binDir = fullfile(terminal.agenticInstallRoot(), 'bin');
            if ispc
                binPath = fullfile(binDir, 'matlab-mcp-core-server.exe');
            else
                binPath = fullfile(binDir, 'matlab-mcp-core-server');
            end
        end

        function runSetupMatlabIfNeeded(serverBin)
            %RUNSETUPMATLABIFNEEDED Install MATLAB-side MCP components via --setup-matlab.
            %   Replaces the old .mltbx download/install approach.
            %   Skips if shareMATLABSession is already available.

            if ~isempty(which('shareMATLABSession'))
                return;
            end

            if ~isfile(serverBin)
                warning('Terminal:BinaryNotFound', ...
                    'MCP server binary not found at %s. Cannot run --setup-matlab.', serverBin);
                return;
            end

            if ispc
                stdinNull = '<nul';
            else
                stdinNull = '</dev/null';
            end
            cmd = sprintf('"%s" --setup-matlab --matlab-root="%s" %s 2>&1', ...
                serverBin, matlabroot, stdinNull);
            fprintf('Installing MATLAB MCP Core Server Toolbox...\n This may take a minute — please wait.\n');
            [status, output] = system(cmd);
            if status ~= 0
                warning('Terminal:SetupMatlabWarning', ...
                    'MCP server binary exited with code %d:\n  %s', ...
                    status, strtrim(output));
            end

            % Add the newly installed toolbox to the path so we don't
            % need a MATLAB restart. The binary may report a non-zero exit
            % code yet still install the toolbox successfully, so always
            % check the expected location.
            toolboxesDir = fileparts(fileparts(which('terminal')));
            listing = dir(toolboxesDir);
            names = {listing.name};
            matches = ~cellfun(@isempty, regexp(names, '^MATLAB[_ ]MCP[_ ]Core[_ ]Server[_ ]Toolbox'));
            if any(matches)
                matched = names(matches);
                mcpToolboxDir = fullfile(toolboxesDir, matched{1});
                addpath(mcpToolboxDir);
                fprintf('MATLAB MCP Core Server Toolbox installed.\n');
            else
                error('Terminal:SetupMatlabFailed', ...
                    'Unable to install the MATLAB MCP Core Server Toolbox.\n  The MCP server binary at:\n    %s\n  exited with code %d:\n    %s', ...
                    serverBin, status, strtrim(output));
            end
        end

        function serverBin = ensureMCPServerBinary(config)
            %ENSUREMCPSERVERBINARY Find or download the MCP server binary.
            %   Installs to ~/.matlab/agentic-toolkits/bin/.
            %   Handles Windows binary locking and macOS quarantine.

            if nargin < 1
                config = struct();
            end

            serverBin = terminal.mcpBinaryPath();
            binDir = fileparts(serverBin);

            % Clean up stale .old file from previous Windows rename.
            oldPath = [serverBin '.old'];
            if isfile(oldPath)
                delete(oldPath);
            end

            % Check managed location.
            if isfile(serverBin)
                if terminal.checkMCPServerVersion(serverBin)
                    return;
                end
                % Version too old — fall through to download.
            end

            % Check system PATH.
            binaryName = terminal.MCP_SERVER_BINARY;
            if ispc
                binaryName = [binaryName '.exe'];
            end
            if ispc
                [status, result] = system(sprintf('where %s 2>nul', binaryName));
            else
                [status, result] = system(sprintf('which %s 2>/dev/null', binaryName));
            end
            if status == 0
                found = strtrim(result);
                lines = splitlines(found);
                found = lines{1};
                if terminal.checkMCPServerVersion(found)
                    serverBin = found;
                    return;
                end
            end

            % Not found or too old — download.
            fprintf('MCP server binary not found at:\n  %s\n', serverBin);
            reply = input('Download it now? (y/n) [y]: ', 's');
            if isempty(reply), reply = 'y'; end
            if ~strcmpi(reply, 'y')
                error('Terminal:MCPBinaryRequired', ...
                    'MCP server binary is required for Agentic mode.');
            end
            fprintf('Downloading MCP server binary...\n');

            % Determine platform asset name.
            arch = computer('arch');
            switch arch
                case 'glnxa64', assetSuffix = '-glnxa64';
                case 'maca64',  assetSuffix = '-maca64';
                case 'maci64',  assetSuffix = '-maci64';
                case 'win64',   assetSuffix = '-win64.exe';
                otherwise
                    error('Terminal:UnsupportedPlatform', ...
                        'Unsupported platform: %s', arch);
            end

            release = terminal.fetchMCPRelease();
            assetName = [terminal.MCP_SERVER_BINARY assetSuffix];
            binaryURL = terminal.findMCPAsset(release, assetName);
            if isempty(binaryURL)
                error('Terminal:MCPDownloadFailed', ...
                    'No binary asset "%s" found in release %s.', assetName, release.tag_name);
            end

            % Skip download if config shows we already have this version.
            latestVer = strrep(release.tag_name, 'v', '');
            if isfield(config, 'mcpServerVersion') && ~isempty(config.mcpServerVersion)
                if terminal.compareVersions(config.mcpServerVersion, latestVer) >= 0 && isfile(serverBin)
                    return;
                end
            end

            % Remove existing binary (handle Windows locking).
            if isfile(serverBin)
                try
                    delete(serverBin);
                catch
                    if ispc
                        try
                            movefile(serverBin, [serverBin '.old'], 'f');
                        catch
                            error('Terminal:BinaryLocked', ...
                                ['Cannot replace the MCP server binary because it is in use.\n' ...
                                 'Close any running coding agent sessions and try again.']);
                        end
                    else
                        error('Terminal:BinaryDeleteFailed', ...
                            'Cannot remove existing binary: %s', serverBin);
                    end
                end
            end

            % Download.
            if ~isfolder(binDir)
                mkdir(binDir);
            end
            fprintf('  Downloading %s %s for %s...\n', ...
                terminal.MCP_SERVER_BINARY, release.tag_name, arch);
            try
                websave(serverBin, binaryURL);
            catch me
                error('Terminal:MCPDownloadFailed', 'Download failed:\n  %s', me.message);
            end

            % Make executable and strip quarantine on macOS.
            if ~ispc
                system(sprintf('chmod +x "%s"', serverBin));
                if ismac
                    system(sprintf('xattr -d com.apple.quarantine "%s" 2>/dev/null', serverBin));
                end
            end
            fprintf('  MCP server binary installed at: %s\n\n', serverBin);
        end

        function ok = checkMCPServerVersion(serverBin)
            %CHECKMCPSERVERVERSION Check binary meets minimum version.
            %   Returns true if the version is acceptable, false if too old.
            ok = false;
            try
                stdinNull = terminal.stdinRedirect();
                [status, output] = system(sprintf('"%s" --version %s', serverBin, stdinNull));
                if status ~= 0
                    ok = true;  % Don't block on version check failure.
                    return;
                end
                tokens = regexp(strtrim(output), '(\d+\.\d+\.\d+)', 'tokens', 'once');
                if isempty(tokens)
                    ok = true;
                    return;
                end
                ver = tokens{1};
                if terminal.compareVersions(ver, terminal.MCP_MIN_SERVER_VERSION) >= 0
                    ok = true;
                else
                    fprintf('MCP server binary at "%s" is version %s (minimum: %s).\n', ...
                        serverBin, ver, terminal.MCP_MIN_SERVER_VERSION);
                end
            catch
                ok = true;  % Don't block on unexpected errors.
            end
        end

        function ver = parseMCPVersion(serverBin)
            %PARSEMCPVERSION Parse the version string from the MCP server binary.
            ver = '';
            try
                stdinNull = terminal.stdinRedirect();
                [status, output] = system(sprintf('"%s" --version %s', serverBin, stdinNull));
                if status == 0
                    tokens = regexp(strtrim(output), '(\d+\.\d+\.\d+)', 'tokens', 'once');
                    if ~isempty(tokens)
                        ver = tokens{1};
                    end
                end
            catch
            end
        end

        function result = compareVersions(a, b)
            %COMPAREVERSIONS Compare two semver strings. Returns -1, 0, or 1.
            partsA = sscanf(a, '%d.%d.%d')';
            partsB = sscanf(b, '%d.%d.%d')';
            for i = 1:3
                if partsA(i) < partsB(i), result = -1; return; end
                if partsA(i) > partsB(i), result =  1; return; end
            end
            result = 0;
        end

        function release = fetchMCPRelease()
            %FETCHMCPRELEASE Fetch the latest MCP Core Server release from GitHub.
            %   On rate-limit or network failure, returns a synthetic release
            %   struct using the minimum supported version and direct download URLs.
            persistent cachedRelease
            if ~isempty(cachedRelease)
                release = cachedRelease;
                return;
            end
            url = sprintf('https://api.github.com/repos/%s/releases/latest', ...
                terminal.MCP_SERVER_REPO);
            try
                opts = weboptions('ContentType', 'json', 'Timeout', 15);
                release = webread(url, opts);
                cachedRelease = release;
            catch me
                if contains(me.message, 'rate limit', 'IgnoreCase', true)
                    % GitHub API rate-limited — fall back to direct download
                    % URLs using the minimum supported version.
                    warning('Terminal:GitHubAPIUnavailable', ...
                        ['GitHub API rate limit exceeded.\n' ...
                         '  Falling back to minimum supported version v%s.\n' ...
                         '  Run terminal.updateMCPServer() later to get the latest.'], ...
                        terminal.MCP_MIN_SERVER_VERSION);
                    release = terminal.buildFallbackMCPRelease();
                    cachedRelease = release;
                else
                    error('Terminal:MCPDownloadFailed', ...
                        'Could not reach GitHub for MCP Core Server:\n  %s', me.message);
                end
            end
        end

        function release = buildFallbackMCPRelease()
            %BUILDFALLBACKMCPRELEASE Construct a synthetic release struct for direct download.
            tag = ['v' terminal.MCP_MIN_SERVER_VERSION];
            baseURL = sprintf('https://github.com/%s/releases/download/%s/', ...
                terminal.MCP_SERVER_REPO, tag);
            bin = terminal.MCP_SERVER_BINARY;
            platforms = {'glnxa64', 'maca64', 'maci64', 'win64'};
            suffixes  = {'-glnxa64', '-maca64', '-maci64', '-win64.exe'};
            assets = struct('name', {}, 'browser_download_url', {});
            for i = 1:numel(platforms)
                assets(i).name = [bin suffixes{i}];
                assets(i).browser_download_url = [baseURL bin suffixes{i}];
            end
            release.tag_name = tag;
            release.assets = assets;
        end

        function url = findMCPAsset(release, namePattern)
            %FINDMCPASSET Find a release asset URL by name pattern.
            url = '';
            for i = 1:numel(release.assets)
                if endsWith(release.assets(i).name, namePattern)
                    url = release.assets(i).browser_download_url;
                    return;
                end
            end
        end

        % ===============================================================
        % Agentic Toolkit Methods
        % ===============================================================

        function cli = resolveAgentCLI(agent, agentCLIOption, config)
            %RESOLVEAGENTCLI Return the CLI command for an agent.
            %   Priority: explicit AgentCLI option > saved config > default.
            if agentCLIOption ~= ""
                cli = agentCLIOption;
            elseif isfield(config, 'agentCLI') && config.agentCLI ~= ""
                cli = string(config.agentCLI);
            else
                switch string(agent)
                    case "claude", cli = "claude";
                    case "codex",  cli = "codex";
                    otherwise,     cli = "";
                end
            end
        end

        function validateAgentOptions(opts)
            %VALIDATEAGENTOPTIONS Validate an AgentOptions struct.
            if ~isstruct(opts)
                error('Terminal:InvalidAgentOptions', 'AgentOptions must be a struct.');
            end
            if ~isfield(opts, 'Agent')
                error('Terminal:InvalidAgentOptions', 'AgentOptions must have an Agent field.');
            end
            if ~isfield(opts, 'Toolkits')
                error('Terminal:InvalidAgentOptions', 'AgentOptions must have a Toolkits field.');
            end
            agent = string(opts.Agent);
            if ~ismember(agent, terminal.AGENTIC_SUPPORTED_AGENTS)
                error('Terminal:InvalidAgentOptions', ...
                    'Unsupported agent "%s".\nSupported: %s', ...
                    agent, strjoin(terminal.AGENTIC_SUPPORTED_AGENTS, ", "));
            end
            toolkits = string(opts.Toolkits);
            valid = ["matlab", "simulink"];
            bad = toolkits(~ismember(toolkits, valid));
            if ~isempty(bad)
                error('Terminal:InvalidAgentOptions', ...
                    'Unsupported toolkit "%s".\nSupported: %s', ...
                    bad(1), strjoin(valid, ", "));
            end
        end

        function opts = agenticWizard(explicitToolkits)
            %AGENTICWIZARD Interactive first-run setup for Agentic=true.
            %   agenticWizard() — ask agent + toolkits
            %   agenticWizard(toolkits) — ask agent only, use provided toolkits
            arguments
                explicitToolkits (1,:) string = string.empty
            end

            fprintf('\n');
            fprintf('Agentic Toolkit Setup\n');
            fprintf('======================\n\n');

            % --- Agent selection ---
            agents = ["claude", "amp", "gemini"];
            labels = ["Claude Code", "Sourcegraph Amp", "Gemini CLI"];
            fprintf('Which AI agent are you using?\n');
            for i = 1:numel(agents)
                fprintf('  [%d] %s\n', i, labels(i));
            end
            reply = input(sprintf('  Select [1]: '), 's');
            if isempty(reply)
                idx = 1;
            else
                idx = str2double(reply);
            end
            if isnan(idx) || idx < 1 || idx > numel(agents) || floor(idx) ~= idx
                error('Terminal:InvalidSelection', 'Invalid selection.');
            end
            agent = agents(idx);
            fprintf('  Selected: %s\n\n', labels(idx));

            % --- Toolkit selection ---
            if ~isempty(explicitToolkits)
                toolkits = explicitToolkits;
                fprintf('Toolkits: %s\n\n', strjoin(toolkits, ", "));
            else
                fprintf('Which toolkits do you want to enable?\n');
                fprintf('  [1] MATLAB (testing, debugging, code review, apps, Live Scripts)\n');
                fprintf('  [2] Simulink (model building, testing, MBD workflows)\n');
                fprintf('  [3] Both\n');
                defaultTk = numel(terminal.defaultToolkits());
                if defaultTk == 2
                    defaultIdx = 3;
                else
                    defaultIdx = 1;
                end
                reply = input(sprintf('  Select [%d]: ', defaultIdx), 's');
                if isempty(reply)
                    tkIdx = defaultIdx;
                else
                    tkIdx = str2double(reply);
                end
                switch tkIdx
                    case 1, toolkits = "matlab";
                    case 2, toolkits = "simulink";
                    case 3, toolkits = ["matlab", "simulink"];
                    otherwise
                        error('Terminal:InvalidSelection', 'Invalid selection.');
                end
                fprintf('  Selected: %s\n\n', strjoin(toolkits, ", "));
            end

            opts = struct('Agent', agent, 'Toolkits', {toolkits});
            terminal.setAgentOptions(opts);

            fprintf('Preferences saved. Run terminal.resetAgentOptions() to reconfigure.\n');
            fprintf('For future use, skip the wizard with:\n');
            if numel(toolkits) == 1 && toolkits == "matlab"
                fprintf('  terminal(Agent="%s")\n\n', agent);
            else
                fprintf('  terminal(Agent="%s", Toolkits=[%s])\n\n', ...
                    agent, strjoin("""" + toolkits + """", ","));
            end
        end

        function toolkits = defaultToolkits()
            %DEFAULTTOOLKITS Return default toolkits based on installed products.
            %   Returns ["matlab","simulink"] if Simulink is installed,
            %   otherwise returns "matlab".
            if ~isempty(ver('simulink'))
                toolkits = ["matlab", "simulink"];
            else
                toolkits = "matlab";
            end
        end

        function [toolkitPath, installedVersion, installedSource] = ensureAgenticToolkit(toolkit, forceUpdate)
            %ENSUREAGENTICTOOLKIT Ensure an agentic toolkit is installed.
            %   Downloads from GitHub releases if not found or if forceUpdate.
            %   Installs to ~/.matlab/agentic-toolkits/<toolkit>/.
            %   Returns the toolkit path, installed version tag, and source
            %   ("release" or "main").
            arguments
                toolkit (1,1) string {mustBeMember(toolkit, ["matlab","simulink"])}
                forceUpdate (1,1) logical = false
            end

            baseDir = terminal.agenticInstallRoot();
            toolkitPath = fullfile(baseDir, toolkit);
            installedVersion = "";
            installedSource = "";

            if isfolder(toolkitPath) && ~forceUpdate
                return;
            end

            switch toolkit
                case "matlab"
                    repo = terminal.AGENTIC_MATLAB_REPO;
                    displayName = 'MATLAB Agentic Toolkit';
                case "simulink"
                    repo = terminal.AGENTIC_SIMULINK_REPO;
                    displayName = 'Simulink Agentic Toolkit';
            end

            if ~forceUpdate
                fprintf('%s not found.\n', displayName);
                reply = input(sprintf('Download and install it now? (y/n) [y]: '), 's');
                if isempty(reply), reply = 'y'; end
                if ~strcmpi(reply, 'y')
                    error('Terminal:AgenticToolkitNotInstalled', ...
                        '%s is required.\n\nInstall from:\n  <a href="https://github.com/%s">https://github.com/%s</a>', ...
                        displayName, repo, repo);
                end
            end

            % Fetch latest release.
            apiURL = sprintf('https://api.github.com/repos/%s/releases/latest', repo);
            webOpts = weboptions('ContentType', 'json', 'Timeout', 15);
            release = [];
            try
                release = webread(apiURL, webOpts);
            catch me
                if contains(me.message, 'rate limit', 'IgnoreCase', true)
                    warning('Terminal:GitHubAPIUnavailable', ...
                        ['GitHub API rate limit exceeded.\n' ...
                         '  Downloading %s from main branch instead.\n' ...
                         '  Run terminal.updateAgenticToolkit("%s") later to get the latest release.'], ...
                        displayName, toolkit);
                else
                    error('Terminal:AgenticDownloadFailed', ...
                        'Could not reach GitHub for %s:\n  %s', displayName, me.message);
                end
            end

            % Determine download URL: prefer release zip asset, fall back
            % to release zipball, or main branch archive if API unavailable.
            downloadURL = '';
            if ~isempty(release)
                fprintf('Downloading %s %s...\n', displayName, release.tag_name);
                if isfield(release, 'assets') && ~isempty(release.assets)
                    for i = 1:numel(release.assets)
                        if endsWith(release.assets(i).name, '.zip')
                            downloadURL = release.assets(i).browser_download_url;
                            break;
                        end
                    end
                end
                if isempty(downloadURL)
                    downloadURL = release.zipball_url;
                end
            else
                fprintf('Downloading %s from main branch...\n', displayName);
                downloadURL = sprintf('https://github.com/%s/archive/refs/heads/main.zip', repo);
            end

            % Download to temp file.
            tmpZip = fullfile(tempdir, sprintf('terminal-%s-toolkit.zip', toolkit));
            try
                websave(tmpZip, downloadURL, webOpts);
            catch me
                error('Terminal:AgenticDownloadFailed', ...
                    'Download failed:\n  %s', me.message);
            end

            % Extract to a temp directory first, then move into place.
            tmpExtract = fullfile(tempdir, sprintf('terminal-%s-extract', toolkit));
            if isfolder(tmpExtract)
                rmdir(tmpExtract, 's');
            end
            unzip(tmpZip, tmpExtract);
            delete(tmpZip);

            % GitHub zipballs extract to a single subdirectory (e.g., "matlab-matlab-agentic-toolkit-abc1234").
            % Zip assets may extract directly. Find the content root.
            contents = dir(tmpExtract);
            contents = contents(~ismember({contents.name}, {'.', '..'}));
            if numel(contents) == 1 && contents(1).isdir
                extractedRoot = fullfile(tmpExtract, contents(1).name);
            else
                extractedRoot = tmpExtract;
            end

            % Remove existing destination (may be junction/symlink from prior install).
            if isfolder(toolkitPath)
                if ispc
                    [~, ~] = system(sprintf('rmdir /s /q "%s"', toolkitPath));
                else
                    [result, ~] = system(sprintf('test -L "%s"', toolkitPath));
                    if result == 0
                        delete(toolkitPath);
                    else
                        rmdir(toolkitPath, 's');
                    end
                end
            end
            if ~isfolder(baseDir)
                mkdir(baseDir);
            end
            movefile(extractedRoot, toolkitPath);

            % Clean up temp extraction dir.
            if isfolder(tmpExtract)
                rmdir(tmpExtract, 's');
            end

            if ~isempty(release)
                installedVersion = string(release.tag_name);
                installedSource = "release";
                fprintf('%s %s installed at:\n  %s\n\n', displayName, release.tag_name, toolkitPath);
            else
                installedSource = "main";
                fprintf('%s installed at:\n  %s\n\n', displayName, toolkitPath);
            end
        end

        function updateSingleToolkit(toolkit)
            %UPDATESINGLETOOLKIT Check latest version and update if needed.
            switch toolkit
                case "matlab"
                    repo = terminal.AGENTIC_MATLAB_REPO;
                    displayName = 'MATLAB Agentic Toolkit';
                case "simulink"
                    repo = terminal.AGENTIC_SIMULINK_REPO;
                    displayName = 'Simulink Agentic Toolkit';
            end

            % Get currently installed version from config.
            config = terminal.readAgenticConfig();
            currentVersion = "";
            if isfield(config, 'toolkits') && isfield(config.toolkits, char(toolkit))
                tkInfo = config.toolkits.(char(toolkit));
                if isfield(tkInfo, 'version')
                    currentVersion = string(tkInfo.version);
                end
            end

            % Fetch latest release version from GitHub.
            apiURL = sprintf('https://api.github.com/repos/%s/releases/latest', repo);
            webOpts = weboptions('ContentType', 'json', 'Timeout', 15);
            try
                release = webread(apiURL, webOpts);
            catch me
                error('Terminal:AgenticUpdateFailed', ...
                    'Could not check for %s updates:\n  %s', displayName, me.message);
            end
            latestVersion = string(release.tag_name);

            % Skip if already at latest.
            if currentVersion == latestVersion
                fprintf('%s is already at %s.\n', displayName, latestVersion);
                return;
            end

            % Download and install.
            [~, installedVersion, installedSource] = terminal.ensureAgenticToolkit(toolkit, true);

            % Persist the new version to config.json.
            config = terminal.readAgenticConfig();
            if ~isfield(config, 'toolkits')
                config.toolkits = struct();
            end
            ver = installedVersion;
            src = installedSource;
            if ver == "", ver = "unknown"; end
            if src == "", src = "release"; end
            config.toolkits.(char(toolkit)) = struct( ...
                'version', char(ver), 'source', char(src));
            terminal.writeAgenticConfig(config);
        end

        function initializeSimulinkToolkit(toolkitPath)
            %INITIALIZESIMULINKTOOLKIT Run satk_initialize for Simulink tools.
            initFile = fullfile(toolkitPath, 'satk_initialize.p');
            if ~isfile(initFile)
                warning('Terminal:SimulinkInitMissing', ...
                    'satk_initialize not found in:\n  %s', toolkitPath);
                return;
            end
            addpath(toolkitPath);
            fprintf('Initializing Simulink Agentic Toolkit...\n');
            try
                satk_initialize();
                fprintf('Simulink Agentic Toolkit initialized.\n\n');
            catch me
                warning('Terminal:SimulinkInitFailed', ...
                    'satk_initialize failed:\n  %s', me.message);
            end
        end

        function files = collectExtensionFiles(toolkits, toolkitPaths)
            %COLLECTEXTENSIONFILES Collect extension file paths for --extension-file.
            %   Returns a cell array of paths. The MCP server v0.10.0+
            %   supports multiple --extension-file flags natively.

            files = {};

            % Terminal's editor tools.
            editorToolsFile = fullfile( ...
                fileparts(which('terminaltools.matlab_editor_list')), ...
                'matlab-editor-tools.json');
            if isfile(editorToolsFile)
                files{end+1} = editorToolsFile;
            end

            % Simulink tools if selected.
            toolkits = string(toolkits);
            if ismember("simulink", toolkits) && isfield(toolkitPaths, 'simulink')
                simToolsFile = fullfile(toolkitPaths.simulink, 'tools', 'tools.json');
                if isfile(simToolsFile)
                    files{end+1} = simToolsFile;
                else
                    warning('Terminal:SimulinkToolsMissing', ...
                        'Simulink tools.json not found at:\n  %s', simToolsFile);
                end
            end
        end

        function mergeMarketplace(toolkitPaths)
            %MERGEMARKETPLACE Build merged .claude-plugin/marketplace.json.
            %   Concatenates plugin entries from each toolkit's marketplace
            %   manifest into a single file at the install root.

            installRoot = terminal.agenticInstallRoot();
            plugins = {};

            toolkitNames = fieldnames(toolkitPaths);
            for i = 1:numel(toolkitNames)
                tkName = toolkitNames{i};
                tkPath = toolkitPaths.(tkName);
                mpFile = fullfile(tkPath, '.claude-plugin', 'marketplace.json');
                if ~isfile(mpFile)
                    continue;
                end
                try
                    manifest = jsondecode(fileread(mpFile));
                catch
                    continue;
                end
                if ~isfield(manifest, 'plugins')
                    continue;
                end

                tkPlugins = manifest.plugins;
                if isstruct(tkPlugins) && numel(tkPlugins) > 1
                    tkPlugins = num2cell(tkPlugins);
                elseif isstruct(tkPlugins)
                    tkPlugins = {tkPlugins};
                end

                % Rewrite relative source paths to resolve from install root.
                for j = 1:numel(tkPlugins)
                    p = tkPlugins{j};
                    if isfield(p, 'source') && startsWith(p.source, './')
                        p.source = ['./' tkName '/' extractAfter(p.source, './')];
                    end
                    tkPlugins{j} = p;
                end
                plugins = [plugins; tkPlugins(:)]; %#ok<AGROW>
            end

            if isempty(plugins)
                return;
            end

            merged = struct( ...
                'x_schema', 'https://anthropic.com/claude-code/marketplace.schema.json', ...
                'name', 'matlab-agentic-toolkits', ...
                'owner', struct('name', 'MathWorks'), ...
                'plugins', {plugins});

            outDir = fullfile(installRoot, '.claude-plugin');
            if ~isfolder(outDir)
                mkdir(outDir);
            end

            jsonStr = jsonencode(merged, 'PrettyPrint', true);
            jsonStr = strrep(jsonStr, '"x_schema"', '"$schema"');

            fid = fopen(fullfile(outDir, 'marketplace.json'), 'w');
            if fid ~= -1
                cleanupObj = onCleanup(@() fclose(fid));
                fwrite(fid, jsonStr);
            end
        end

        function cmd = buildAgentRegistration(agent, serverBin, extensionFiles, toolkitPaths, agentCLI)
            %BUILDAGENTREGISTRATION Register the MCP server with the chosen agent.
            %   For CLI agents (codex): returns a shell command to pre-populate.
            %   For all others: writes config directly, returns empty.

            agent = string(agent);
            if nargin < 5, agentCLI = ""; end

            % Common server args for all agents.
            serverArgs = {};
            for i = 1:numel(extensionFiles)
                serverArgs{end+1} = sprintf('--extension-file=%s', extensionFiles{i}); %#ok<AGROW>
            end

            cmd = "";
            switch agent
                case "claude"
                    terminal.registerClaude(serverBin, serverArgs, agentCLI);
                    terminal.installGlobalSkills(toolkitPaths);

                case "codex"
                    codexCmd = 'codex';
                    if agentCLI ~= "", codexCmd = char(agentCLI); end
                    quotedArgs = cellfun(@(a) sprintf('"%s"', a), serverArgs, ...
                        'UniformOutput', false);
                    argsStr = strjoin(quotedArgs, ' ');
                    cmd = sprintf('%s mcp add matlab -- "%s" %s', codexCmd, serverBin, argsStr);
                    terminal.installGlobalSkills(toolkitPaths);
                    fprintf('Run the command above in the terminal to register.\n\n');


                case "copilot"
                    terminal.writeAgentConfig(agent, serverBin, serverArgs, toolkitPaths);
                    terminal.installGlobalSkills(toolkitPaths);

                case "gemini"
                    terminal.writeAgentConfig(agent, serverBin, serverArgs, toolkitPaths);
                    terminal.installGlobalSkills(toolkitPaths);

                case "cursor"
                    terminal.writeAgentConfig(agent, serverBin, serverArgs, toolkitPaths);

                case "amp"
                    terminal.writeAgentConfig(agent, serverBin, serverArgs, toolkitPaths);
            end

            terminal.printSetupSummary(agent, toolkitPaths);

        end

        function writeAgentConfig(agent, serverBin, serverArgs, toolkitPaths)
            %WRITEAGENTCONFIG Write MCP server config for config-file agents.
            %   Uses targeted JSON patching (patchJsonKey) to surgically
            %   update only the keys we manage, preserving all other user
            %   settings and avoiding issues with dotted keys that
            %   jsondecode cannot represent.

            agent = string(agent);
            serverBin = strrep(char(serverBin), '\', '/');

            % Determine config file path and MCP servers key per agent.
            home = terminal.userHome();
            switch agent
                case "copilot"
                    if ismac
                        configFile = fullfile(home, 'Library', ...
                            'Application Support', 'Code', 'User', 'mcp.json');
                    elseif ispc
                        configFile = fullfile(getenv('APPDATA'), ...
                            'Code', 'User', 'mcp.json');
                    else
                        configFile = fullfile(home, '.config', ...
                            'Code', 'User', 'mcp.json');
                    end
                    mcpKey = 'servers';
                case "gemini"
                    configFile = fullfile(home, '.gemini', 'settings.json');
                    mcpKey = 'mcpServers';
                case "cursor"
                    configFile = fullfile(home, '.cursor', 'mcp.json');
                    mcpKey = 'mcpServers';
                case "amp"
                    configFile = fullfile(home, '.config', 'amp', 'settings.json');
                    mcpKey = 'amp.mcpServers';
            end

            % Read existing config or start fresh.
            configDir = fileparts(configFile);
            if ~isfolder(configDir)
                mkdir(configDir);
            end
            if isfile(configFile)
                rawJSON = fileread(configFile);
            else
                rawJSON = '{}';
            end

            % Build the MATLAB MCP server entry.
            mcpEntry = struct( ...
                'command', serverBin, ...
                'args', {serverArgs} ...
            );
            if agent == "copilot"
                mcpEntry.type = 'stdio';
            end

            % Patch the MCP servers key with the matlab entry.
            mcpServersJSON = jsonencode(struct('matlab', mcpEntry), 'PrettyPrint', true);
            rawJSON = terminal.patchJsonKey(rawJSON, mcpKey, mcpServersJSON);

            % Amp-specific: write mcpPermissions and skills path.
            if agent == "amp"
                rawJSON = terminal.patchAmpPermissions(rawJSON, serverBin);
                rawJSON = terminal.patchAmpSkillsPath(rawJSON, toolkitPaths);
            end

            fid = fopen(configFile, 'w');
            fwrite(fid, rawJSON);
            fclose(fid);

            fprintf('Wrote MCP server config to:\n  %s\n', configFile);
        end

        function json = patchAmpPermissions(json, mcpCommand)
            %PATCHAMPPERMISSIONS Write amp.mcpPermissions with allow rule.
            %   Amp injects default reject-all rules on startup, so we must
            %   always include an allow rule for the MATLAB MCP server.

            mcpCommand = strrep(mcpCommand, '\', '/');
            mcpPermsJSON = sprintf([ ...
                '[\n' ...
                '    {\n' ...
                '      "action": "allow",\n' ...
                '      "matches": {\n' ...
                '        "command": "%s"\n' ...
                '      }\n' ...
                '    },\n' ...
                '    {\n' ...
                '      "action": "reject",\n' ...
                '      "matches": {\n' ...
                '        "command": "*"\n' ...
                '      }\n' ...
                '    },\n' ...
                '    {\n' ...
                '      "action": "reject",\n' ...
                '      "matches": {\n' ...
                '        "url": "*"\n' ...
                '      }\n' ...
                '    }\n' ...
                '  ]'], mcpCommand);
            json = terminal.patchJsonKey(json, 'amp.mcpPermissions', mcpPermsJSON);
        end

        function json = patchAmpSkillsPath(json, toolkitPaths)
            %PATCHAMPSKILLSPATH Write amp.skills.path from toolkit locations.

            skillsPaths = string.empty;
            if isfield(toolkitPaths, 'matlab')
                skillsPaths(end+1) = fullfile(toolkitPaths.matlab, 'skills-catalog');
            end
            if isfield(toolkitPaths, 'simulink')
                skillsPaths(end+1) = fullfile(toolkitPaths.simulink, 'skills-catalog');
            end
            if ~isempty(skillsPaths)
                sep = ':';
                if ispc, sep = ';'; end
                skillsPathStr = strjoin(skillsPaths, sep);
                json = terminal.patchJsonKey(json, 'amp.skills.path', ...
                    jsonencode(char(skillsPathStr)));
            end
        end

        function json = patchJsonKey(json, key, valueJSON)
            %PATCHJSONKEY Replace or insert a top-level JSON key's value.
            %   Finds "key": <value> in the JSON text and replaces the
            %   value. If the key doesn't exist, inserts it before the
            %   closing brace.

            quotedKey = ['"' key '"'];

            % Try to find and replace existing key.
            % Match "key" : <value> where value can be object/array/string/etc.
            pattern = ['"' regexptranslate('escape', key) '"\s*:\s*'];
            loc = regexp(json, pattern, 'start', 'once');

            if ~isempty(loc)
                % Find the colon after the key.
                colonIdx = regexp(json(loc:end), ':', 'start', 'once') + loc - 1;
                % Find the start of the value (skip whitespace).
                valStart = regexp(json(colonIdx+1:end), '\S', 'start', 'once') + colonIdx;
                % Find the end of the value.
                valEnd = terminal.findJsonValueEnd(json, valStart);
                % Replace the value.
                json = [json(1:valStart-1) valueJSON json(valEnd+1:end)];
            else
                % Insert before the last closing brace.
                lastBrace = find(json == '}', 1, 'last');
                % Check if there are existing keys (need a comma).
                beforeBrace = strtrim(json(1:lastBrace-1));
                if endsWith(beforeBrace, '{')
                    insertion = sprintf('  %s: %s\n', quotedKey, valueJSON);
                else
                    insertion = sprintf(',\n  %s: %s\n', quotedKey, valueJSON);
                end
                json = [json(1:lastBrace-1) insertion json(lastBrace:end)];
            end
        end

        function endIdx = findJsonValueEnd(json, startIdx)
            %FINDJSONVALUEEND Find the end index of a JSON value.
            ch = json(startIdx);
            if ch == '{' || ch == '['
                % Find matching brace/bracket, accounting for nesting.
                if ch == '{', openCh = '{'; closeCh = '}';
                else,         openCh = '['; closeCh = ']';
                end
                depth = 1;
                idx = startIdx + 1;
                inStr = false;
                while idx <= length(json) && depth > 0
                    c = json(idx);
                    if c == '"' && (idx == 1 || json(idx-1) ~= '\')
                        inStr = ~inStr;
                    elseif ~inStr
                        if c == openCh, depth = depth + 1;
                        elseif c == closeCh, depth = depth - 1;
                        end
                    end
                    idx = idx + 1;
                end
                endIdx = idx - 1;
            elseif ch == '"'
                % String value — find closing quote.
                idx = startIdx + 1;
                while idx <= length(json)
                    if json(idx) == '"' && json(idx-1) ~= '\'
                        break;
                    end
                    idx = idx + 1;
                end
                endIdx = idx;
            else
                % Number, boolean, null — ends at comma, brace, or newline.
                endMatch = regexp(json(startIdx:end), '[,}\]\s]', 'start', 'once');
                if isempty(endMatch)
                    endIdx = length(json);
                else
                    endIdx = startIdx + endMatch - 2;
                end
            end
        end

        function registerClaude(serverBin, serverArgs, agentCLI)
            %REGISTERCLAUDE Register MCP server and plugins with Claude Code.
            %   Uses `claude mcp add-json` if CLI is on PATH, otherwise
            %   writes ~/.claude.json directly.

            serverBin = strrep(char(serverBin), '\', '/');
            nullDev = terminal.nullRedirect();
            stdinNull = terminal.stdinRedirect();

            if nargin < 3, agentCLI = ""; end

            % Resolve the claude CLI command.
            if agentCLI ~= ""
                claudeCmd = char(agentCLI);
            else
                claudeCmd = 'claude';
            end

            % Check if claude CLI is available.
            if agentCLI ~= ""
                % Custom CLI provided — trust it, verify with a quick call.
                [cliStatus, ~] = system(sprintf('%s --version %s', claudeCmd, nullDev));
            elseif ispc
                [cliStatus, ~] = system(sprintf('where %s %s', claudeCmd, nullDev));
            else
                [cliStatus, ~] = system(sprintf('which %s %s', claudeCmd, nullDev));
            end

            entry = struct('command', serverBin, 'args', {serverArgs});
            entryJSON = jsonencode(entry);

            if cliStatus == 0
                % Remove stale entry first.
                system(sprintf('%s mcp remove -s user matlab %s', claudeCmd, nullDev));

                % Register via CLI.
                if ispc
                    cmd = sprintf('%s mcp add-json -s user matlab "%s" %s', ...
                        claudeCmd, strrep(entryJSON, '"', '\"'), stdinNull);
                else
                    cmd = sprintf('%s mcp add-json -s user matlab ''%s'' %s', ...
                        claudeCmd, entryJSON, stdinNull);
                end
                [status, output] = system(cmd);
                if status ~= 0
                    warning('Terminal:ClaudeConfigFailed', ...
                        'Failed to configure Claude Code:\n  %s\nFalling back to direct file write.', ...
                        strtrim(output));
                    terminal.writeClaudeJson(entry);
                else
                    fprintf('Claude Code: MCP server registered (via %s mcp add-json)\n', claudeCmd);
                end
            else
                % CLI not available — write ~/.claude.json directly.
                terminal.writeClaudeJson(entry);
            end

            % Register plugins from merged marketplace manifest.
            installRoot = terminal.agenticInstallRoot();
            manifestFile = fullfile(installRoot, '.claude-plugin', 'marketplace.json');
            if cliStatus == 0 && isfile(manifestFile)
                manifest = jsondecode(fileread(manifestFile));
                if isfield(manifest, 'plugins') && isfield(manifest, 'name')
                    marketplaceName = manifest.name;

                    % Register marketplace.
                    system(sprintf('%s plugin marketplace add "%s" --scope user %s', ...
                        claudeCmd, strrep(installRoot, '\', '/'), stdinNull));

                    plugins = manifest.plugins;
                    if isstruct(plugins)
                        plugins = num2cell(plugins);
                    end
                    for i = 1:numel(plugins)
                        pluginId = sprintf('%s@%s', plugins{i}.name, marketplaceName);
                        system(sprintf('%s plugin uninstall "%s" --scope user %s', claudeCmd, pluginId, nullDev));
                        [st, output] = system(sprintf('%s plugin install "%s" --scope user %s', claudeCmd, pluginId, stdinNull));
                        if st == 0
                            fprintf('Claude Code: installed plugin %s\n', pluginId);
                        else
                            warning('Terminal:PluginInstallFailed', ...
                                'Failed to install plugin %s:\n  %s', pluginId, strtrim(output));
                        end
                    end
                end
            end
        end

        function writeClaudeJson(entry)
            %WRITECLAUDEJSON Write mcpServers.matlab to ~/.claude.json.
            home = terminal.userHome();
            configFile = fullfile(home, '.claude.json');
            if isfile(configFile)
                config = jsondecode(fileread(configFile));
            else
                config = struct();
            end
            if ~isfield(config, 'mcpServers')
                config.mcpServers = struct();
            end
            config.mcpServers.matlab = entry;
            fid = fopen(configFile, 'w');
            if fid == -1
                error('Terminal:ConfigWriteFailed', 'Cannot write config: %s', configFile);
            end
            cleanupObj = onCleanup(@() fclose(fid));
            fwrite(fid, jsonencode(config, 'PrettyPrint', true));
            fprintf('Claude Code: wrote MCP config to %s\n', configFile);
        end

        function installGlobalSkills(toolkitPaths)
            %INSTALLGLOBALSKILLS Create symlinks in ~/.agents/skills/.
            %   Links each skill directory (containing manifest.yaml) from
            %   the toolkit so agents like Codex, Copilot, and Gemini can
            %   discover them globally. Removes stale links pointing into
            %   our install root that are no longer in the current skill set.

            home = terminal.userHome();
            skillsDir = fullfile(home, '.agents', 'skills');

            if ~isfolder(skillsDir)
                mkdir(skillsDir);
            end

            installRoot = terminal.agenticInstallRoot();
            toolkitNames = fieldnames(toolkitPaths);
            linkedSkills = {};

            for i = 1:numel(toolkitNames)
                tkPath = toolkitPaths.(toolkitNames{i});
                manifests = dir(fullfile( ...
                    tkPath, 'skills-catalog', '*', '*', 'manifest.yaml'));
                for j = 1:numel(manifests)
                    skillDir = manifests(j).folder;
                    [~, skillName] = fileparts(skillDir);
                    linkPath = fullfile(skillsDir, skillName);

                    % Remove existing link/junction before creating new one.
                    if ispc
                        system(sprintf('rmdir "%s" 2>nul', linkPath));
                        system(sprintf( ...
                            'mklink /J "%s" "%s" >nul 2>&1', ...
                            linkPath, skillDir));
                    else
                        system(sprintf( ...
                            'ln -sfn "%s" "%s"', skillDir, linkPath));
                    end

                    linkedSkills{end+1} = skillName; %#ok<AGROW>
                end
            end

            % Remove stale links pointing into our install root.
            terminal.removeStaleSkillLinks(skillsDir, linkedSkills, installRoot);

            if ~isempty(linkedSkills)
                fprintf('Skills installed (%d symlinks in %s)\n', ...
                    numel(linkedSkills), skillsDir);
            end
        end

        function removeStaleSkillLinks(skillsDir, keepNames, installRoot)
            %REMOVESTALESKILLLINKS Remove symlinks/junctions that point into
            %   installRoot but are not in keepNames. Leaves user-created links alone.

            if ispc
                [status, output] = system(sprintf('dir /b "%s" 2>nul', skillsDir));
            else
                [status, output] = system(sprintf('ls -A "%s" 2>/dev/null', skillsDir));
            end
            if status ~= 0 || isempty(strtrim(output))
                return;
            end
            names = splitlines(strtrim(output));
            names = names(~cellfun('isempty', names));

            for i = 1:numel(names)
                if ismember(names{i}, keepNames)
                    continue;
                end
                entryPath = fullfile(skillsDir, names{i});

                % Check if this link points into our install root.
                isOurs = false;
                if ispc
                    [st, out] = system(sprintf('fsutil reparsepoint query "%s" 2>nul', entryPath));
                    if st == 0 && contains(out, strrep(installRoot, '/', '\'))
                        isOurs = true;
                    end
                else
                    [st, target] = system(sprintf('readlink "%s" 2>/dev/null', entryPath));
                    if st == 0 && startsWith(strtrim(target), installRoot)
                        isOurs = true;
                    end
                end

                if isOurs
                    if ispc
                        system(sprintf('rmdir "%s" 2>nul', entryPath));
                    else
                        system(sprintf('rm -f "%s"', entryPath));
                    end
                end
            end
        end

        function printSetupSummary(agent, toolkitPaths)
            %PRINTSETUPSUMMARY Print what was configured and how to undo.

            agent = string(agent);
            home = terminal.userHome();
            toolkits = string(fieldnames(toolkitPaths));

            fprintf('\nSetup complete.\n');
            fprintf('  Agent:    %s\n', agent);
            fprintf('  Toolkits: %s\n', strjoin(toolkits, ", "));

            fprintf('\nTo undo this setup:\n');

            switch agent
                case "claude"
                    fprintf('  claude mcp remove -s user matlab\n');
                    toolkitNames = fieldnames(toolkitPaths);
                    for i = 1:numel(toolkitNames)
                        tkPath = toolkitPaths.(toolkitNames{i});
                        mpFile = fullfile(tkPath, ...
                            '.claude-plugin', 'marketplace.json');
                        if ~isfile(mpFile)
                            continue;
                        end
                        try
                            mp = jsondecode(fileread(mpFile));
                        catch
                            continue;
                        end
                        if ~isfield(mp, 'plugins') || ~isfield(mp, 'name')
                            continue;
                        end
                        for j = 1:numel(mp.plugins)
                            fprintf('  claude plugin uninstall %s@%s\n', ...
                                mp.plugins(j).name, mp.name);
                        end
                    end

                case "codex"
                    fprintf('  codex mcp remove matlab\n');
                    terminal.printSkillsUndoHint(home);

                case "copilot"
                    fprintf('  Remove "matlab" from "servers" in:\n');
                    if ismac
                        copilotConfig = fullfile(home, 'Library', ...
                            'Application Support', 'Code', 'User', 'mcp.json');
                    elseif ispc
                        copilotConfig = fullfile(getenv('APPDATA'), ...
                            'Code', 'User', 'mcp.json');
                    else
                        copilotConfig = fullfile(home, '.config', ...
                            'Code', 'User', 'mcp.json');
                    end
                    fprintf('    %s\n', copilotConfig);
                    terminal.printSkillsUndoHint(home);

                case "gemini"
                    fprintf('  Remove "matlab" from "mcpServers" in:\n');
                    fprintf('    %s\n', fullfile(home, '.gemini', 'settings.json'));
                    terminal.printSkillsUndoHint(home);

                case "cursor"
                    fprintf('  Remove "matlab" from "mcpServers" in:\n');
                    fprintf('    %s\n', fullfile(home, '.cursor', 'mcp.json'));
                    fprintf('  Note: Cursor does not support global skills.\n');
                    fprintf('  MCP tools are available but toolkit skills\n');
                    fprintf('  require opening Cursor from the toolkit directory.\n');

                case "amp"
                    fprintf('  Remove "matlab" from "amp.mcpServers" in:\n');
                    fprintf('    %s\n', fullfile(home, '.config', 'amp', 'settings.json'));
                    fprintf('  Remove "amp.skills.path" if no longer needed.\n');
            end

            fprintf('\n');
        end

        function printSkillsUndoHint(home)
            %PRINTSKILLSUNDOHINT Print undo command for global skill symlinks.
            skillsDir = fullfile(home, '.agents', 'skills');
            if ispc
                fprintf('  Remove skill symlinks from:\n');
                fprintf('    %s\n', skillsDir);
            else
                fprintf('  rm -f %s/matlab-* %s/simulink-*\n', ...
                    skillsDir, skillsDir);
            end
        end

        function home = userHome()
            %USERHOME Return the user's home directory.
            if ispc
                home = getenv('USERPROFILE');
            else
                home = getenv('HOME');
            end
        end

        function r = stdinRedirect()
            %STDINREDIRECT Platform-appropriate stdin/stderr redirect for system() calls.
            %   Prevents binary invocations from hanging in MATLAB's system().
            if ispc
                r = '<nul 2>nul';
            else
                r = '</dev/null 2>/dev/null';
            end
        end

        function r = nullRedirect()
            %NULLREDIRECT Platform-appropriate output suppression for system() calls.
            if ispc
                r = '>nul 2>nul';
            else
                r = '>/dev/null 2>/dev/null';
            end
        end

        function result = registry(action, obj)
            %REGISTRY Persistent store for tracking Terminal instances.
            persistent instances
            if isempty(instances)
                instances = terminal.empty;
            end
            switch action
                case 'add'
                    instances(end+1) = obj;
                case 'remove'
                    instances(instances == obj) = [];
                case 'get'
                    % Prune deleted handles before returning.
                    instances(~isvalid(instances)) = [];
                    result = instances;
                    return;
            end
            result = terminal.empty;
        end

        function htmlDir = extractWebAssets()
            %EXTRACTWEBASSETS Extract web assets from web_assets.mat to a cache dir.
            %   packageToolbox drops .html/.css/.js files, so we bundle them
            %   in a .mat file and extract at runtime.
            cacheRoot = terminal.toolboxDir();
            cacheDir = fullfile(cacheRoot, 'html');
            stampFile = fullfile(cacheRoot, '.extracted');

            matFile = fullfile(cacheRoot, 'web_assets.mat');
            if ~isfile(matFile)
                % Running from source — no .mat file needed.
                htmlDir = cacheDir;
                return;
            end

            % Re-extract if the .mat file is newer than our stamp,
            % meaning a new toolbox version was installed.
            matInfo = dir(matFile);
            needsExtract = true;
            if isfile(stampFile)
                stampInfo = dir(stampFile);
                needsExtract = matInfo.datenum > stampInfo.datenum;
            end

            if ~needsExtract
                htmlDir = cacheDir;
                return;
            end

            % Newer MATLAB versions may install toolboxes read-only.
            % Fix folder permissions upfront so rmdir and file writes succeed.
            if isMATLABReleaseOlderThan("R2026a")
                fileattrib(fullfile(cacheRoot, '*'), '+w', '', 's');
            else
                perms = filePermissions(cacheRoot);
                setPermissions(perms, "Writable", true, PermissionsTarget="folders");
            end

            % Clear previously extracted assets before re-extracting.
            % Only remove html/ and the server binary directory.
            serverBinDir = fullfile(cacheRoot, 'bin', 'matlab-terminal-server');
            if isfolder(cacheDir), rmdir(cacheDir, 's'); end
            if isfolder(serverBinDir), rmdir(serverBinDir, 's'); end

            fprintf('Extracting Terminal assets to:\n  %s\n', cacheRoot);

            terminal.extractToDir(cacheRoot, matFile);

            % Strip macOS quarantine from the extracted server binary.
            % Downloaded .mltbx files inherit com.apple.quarantine, which
            % causes Gatekeeper to block the unsigned binary.
            if ismac
                [~, ~] = system(sprintf('xattr -cr "%s"', serverBinDir));
            end

            % Touch stamp file so we know this extraction is current.
            fid = fopen(stampFile, 'w');
            fclose(fid);

            htmlDir = cacheDir;
        end

        function extractToDir(cacheRoot, matFile)
            %EXTRACTTODIR Write web_assets.mat contents to disk.
            S = load(matFile, 'assets');
            arch = computer('arch');
            fields = fieldnames(S.assets);
            warnState = warning('off', 'MATLAB:MKDIR:CreatedFolderInPackage');
            cleanupObj = onCleanup(@() warning(warnState)); %#ok<NASGU>
            for i = 1:numel(fields)
                entry = S.assets.(fields{i});
                % Skip binaries for other platforms.
                if entry.executable && ~contains(entry.path, arch)
                    continue;
                end
                dst = fullfile(cacheRoot, entry.path);
                dstDir = fileparts(dst);
                if ~isfolder(dstDir)
                    mkdir(dstDir);
                end
                fid = fopen(dst, 'w');
                fwrite(fid, entry.data);
                fclose(fid);
                if entry.executable && ~ispc
                    system(sprintf('chmod +x "%s"', dst));
                end
            end
        end

        function deferredClose(tmr, obj, fig)
            stop(tmr);
            delete(tmr);
            delete(obj);
            if ~isempty(fig) && isvalid(fig)
                close(fig);
            end
        end

        function binaryPath = findBinary()
            binaryName = terminal.SERVER_BINARY_NAME;
            if ispc
                binaryName = [binaryName, '.exe'];
            end

            % Check dist/<arch>/ directory (development builds).
            arch = computer('arch');
            candidate = fullfile(fileparts(terminal.toolboxDir()), 'dist', arch, binaryName);
            if isfile(candidate)
                binaryPath = candidate;
                return;
            end

            % Check toolbox bin/ directory (extracted from web_assets.mat).
            candidate = fullfile(terminal.toolboxDir(), 'bin', 'matlab-terminal-server', arch, binaryName);
            if isfile(candidate)
                binaryPath = candidate;
                return;
            end

            if ispc
                [st, result] = system(sprintf('where "%s" 2>nul', binaryName));
            else
                [st, result] = system(sprintf('which "%s" 2>/dev/null', binaryName));
            end
            if st == 0
                binaryPath = strtrim(result);
                lines = splitlines(binaryPath);
                binaryPath = lines{1};
                return;
            end

            binaryPath = '';
        end

        function shell = defaultShell()
            %DEFAULTSHELL Return the system default shell (mirrors server logic).
            if ispc
                shell = string(getenv('COMSPEC'));
                if shell == ""
                    shell = "cmd.exe";
                end
            else
                shell = string(getenv('SHELL'));
                if shell == ""
                    shell = "/bin/sh";
                end
            end
        end

        function validateShell(shell)
            %VALIDATESHELL Error if the given shell is not found on the system.
            if isfile(shell)
                return;  % Absolute path exists.
            end
            % Check if it's on PATH.
            if ispc
                [st, ~] = system(sprintf('where "%s" >nul 2>&1', shell));
            else
                [st, ~] = system(sprintf('which "%s" >/dev/null 2>&1', shell));
            end
            if st ~= 0
                if ispc
                    common = 'cmd.exe, powershell.exe, pwsh.exe, wsl.exe';
                else
                    common = 'bash, zsh, sh, fish';
                end
                error('Terminal:ShellNotFound', ...
                    'Shell "%s" not found.\nCommon shells for this platform: %s', ...
                    shell, common);
            end
        end

        function killProcess(pid)
            %KILLPROCESS Terminate a process by PID (cross-platform).
            if ispc
                system(sprintf('taskkill /PID %d /F >nul 2>&1', pid));
            else
                system(sprintf('kill %d 2>/dev/null', pid));
            end
        end

        function alive = isProcessAlive(pid)
            %ISPROCESSALIVE Check if a process is still running (cross-platform).
            if ispc
                [st, ~] = system(sprintf('tasklist /FI "PID eq %d" /NH 2>nul | findstr /R "^[0-9]" >nul 2>&1', pid));
            else
                [st, ~] = system(sprintf('kill -0 %d 2>/dev/null', pid));
            end
            alive = (st == 0);
        end

        function verifierBin = findOrInstallSLSAVerifier()
            %FINDORINSTALLSLSAVERIFIER Locate slsa-verifier or offer to download it.
            %   Returns the path to the binary, or '' if unavailable.
            binaryName = 'slsa-verifier';
            if ispc
                binaryName = [binaryName '.exe'];
            end

            % Check managed install location first.
            installDir = fullfile(terminal.toolboxDir(), 'bin');
            candidate = fullfile(installDir, binaryName);
            if isfile(candidate)
                verifierBin = candidate;
                return;
            end

            % Check system PATH.
            if ispc
                [st, result] = system(sprintf('where %s 2>nul', binaryName));
            else
                [st, result] = system(sprintf('which %s 2>/dev/null', binaryName));
            end
            if st == 0
                verifierBin = strtrim(splitlines(string(result)));
                verifierBin = char(verifierBin(1));
                return;
            end

            % Not found — offer to download.
            arch = computer('arch');
            switch arch
                case 'glnxa64', assetPattern = 'linux-amd64';
                case 'maci64',  assetPattern = 'darwin-amd64';
                case 'maca64',  assetPattern = 'darwin-arm64';
                case 'win64',   assetPattern = 'windows-amd64.exe';
                otherwise
                    fprintf(2, 'Unsupported platform: %s\n', arch);
                    verifierBin = '';
                    return;
            end

            fprintf('\nslsa-verifier not found on PATH or in %s.\n', installDir);
            fprintf('  Source:      https://github.com/slsa-framework/slsa-verifier/releases\n');
            fprintf('  Install to:  %s\n\n', candidate);
            reply = input('Download slsa-verifier for SLSA provenance verification? (y/n) [y]: ', 's');
            if isempty(reply), reply = 'y'; end
            if ~strcmpi(reply, 'y')
                fprintf('Skipping SLSA provenance check.\n');
                verifierBin = '';
                return;
            end

            % Fetch latest release from slsa-verifier repo.
            try
                opts = weboptions('ContentType', 'json', 'Timeout', 10);
                release = webread( ...
                    'https://api.github.com/repos/slsa-framework/slsa-verifier/releases/latest', opts);
            catch me
                fprintf(2, 'Could not fetch slsa-verifier release: %s\n', me.message);
                verifierBin = '';
                return;
            end

            % Find the matching asset.
            downloadURL = '';
            for i = 1:numel(release.assets)
                name = string(release.assets(i).name);
                if contains(name, assetPattern) && ~contains(name, '.sig') && ~contains(name, '.pem') && ~contains(name, '.intoto')
                    downloadURL = release.assets(i).browser_download_url;
                    break;
                end
            end
            if downloadURL == ""
                fprintf(2, 'No slsa-verifier binary found for %s.\n', arch);
                verifierBin = '';
                return;
            end

            % Download.
            if ~isfolder(installDir)
                mkdir(installDir);
            end
            fprintf('Downloading slsa-verifier %s...\n', release.tag_name);
            try
                websave(candidate, downloadURL);
            catch me
                fprintf(2, 'Download failed: %s\n', me.message);
                verifierBin = '';
                return;
            end

            if ~ispc
                system(sprintf('chmod +x "%s"', candidate));
                if ismac
                    system(sprintf('xattr -d com.apple.quarantine "%s" 2>/dev/null', candidate));
                end
            end
            fprintf('Installed slsa-verifier at:\n  %s\n', candidate);
            verifierBin = candidate;
        end

        function release = fetchLatestRelease()
            %FETCHLATESTRELEASE Fetch the latest stable release from GitHub.
            %   Uses the /releases/latest endpoint, which excludes
            %   pre-releases and drafts.
            url = sprintf('https://api.github.com/repos/%s/releases/latest', ...
                terminal.GITHUB_REPO);
            try
                opts = weboptions('ContentType', 'json', 'Timeout', 10);
                release = webread(url, opts);
            catch me
                error('Terminal:UpdateFailed', ...
                    'Could not reach GitHub:\n  %s', me.message);
            end
        end

        function release = fetchRelease(version)
            %FETCHRELEASE Fetch a specific release by version tag.
            version = string(version);
            if ~startsWith(version, 'v')
                tag = "v" + version;
            else
                tag = version;
            end
            url = sprintf('https://api.github.com/repos/%s/releases/tags/%s', ...
                terminal.GITHUB_REPO, tag);
            try
                opts = weboptions('ContentType', 'json', 'Timeout', 10);
                release = webread(url, opts);
            catch me
                error('Terminal:UpdateFailed', ...
                    'Release "%s" not found on GitHub:\n  %s', tag, me.message);
            end
        end

        function v = tagToVersion(tag)
            %TAGTOVERSION Strip leading "v" from a tag name.
            v = string(tag);
            if startsWith(v, 'v')
                v = extractAfter(v, 1);
            end
        end

        function mltbxURL = findMltbxAsset(release)
            %FINDMLTBXASSET Find the .mltbx download URL in a release.
            mltbxURL = '';
            assets = release.assets;
            for i = 1:numel(assets)
                if iscell(assets)
                    asset = assets{i};
                else
                    asset = assets(i);
                end
                if endsWith(asset.name, '.mltbx')
                    mltbxURL = asset.browser_download_url;
                    break;
                end
            end
            if isempty(mltbxURL)
                v = terminal.tagToVersion(release.tag_name);
                error('Terminal:UpdateFailed', ...
                    'No .mltbx file found in release %s.', v);
            end
        end

        function token = generateToken()
            %GENERATETOKEN Generate a 32-char hex auth token.
            %   Uses /dev/urandom (Unix) or PowerShell (Windows) for
            %   cryptographic randomness, falling back to randi if needed.
            token = '';
            try
                if ispc
                    [status, token] = system('powershell -c "[guid]::NewGuid().ToString(''N'')"');
                    if status == 0
                        token = strtrim(token);
                    else
                        token = '';
                    end
                else
                    fid = fopen('/dev/urandom', 'r');
                    if fid ~= -1
                        bytes = fread(fid, 16, '*uint8');
                        fclose(fid);
                        token = sprintf('%02x', bytes);
                    end
                end
            catch
            end
            if strlength(token) ~= 32
                token = sprintf('%04x', randi(65535, 1, 8));
            end
        end

        function hash = sha256file(filepath)
            %SHA256FILE Compute the SHA-256 hex digest of a file.
            if ispc
                [st, out] = system(sprintf('certutil -hashfile "%s" SHA256', filepath));
                if st == 0
                    lines = splitlines(strtrim(out));
                    % certutil outputs: header, hash, footer
                    hash = strtrim(strrep(lines{2}, ' ', ''));
                    return;
                end
            else
                [st, out] = system(sprintf('sha256sum "%s"', filepath));
                if st == 0
                    parts = split(strtrim(out));
                    hash = char(parts(1));
                    return;
                end
            end
            error('Terminal:HashFailed', ...
                'Could not compute SHA-256 hash for:\n  %s', filepath);
        end

    end
end
