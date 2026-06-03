%% Getting Started with Terminal
% Terminal embeds a full system terminal inside the MATLAB Desktop.
% Run shell commands, git, docker, and CLI tools without leaving MATLAB.

%% Opening a Terminal
% Create a docked terminal with one line:

t = terminal();

%% Named Terminals
% Give each terminal a descriptive name so you can tell them apart in
% the MATLAB Desktop tab bar.

t1 = terminal(Name="Build");
t2 = terminal(Name="Git");

%% Floating Windows
% Open a terminal in its own undocked window instead of the desktop.

t = terminal(WindowStyle="normal");

%% Custom Shell
% By default the terminal uses your system shell ($SHELL on Unix,
% %COMSPEC% on Windows). Override it with the Shell argument.

% Linux/macOS examples:
t = terminal(Shell="zsh");
t = terminal(Shell="/bin/bash");

% Windows examples:
% t = terminal(Shell="powershell.exe");
% t = terminal(Shell="wsl.exe");

%% Color Themes
% Terminal follows the MATLAB Desktop theme by default. Choose a preset
% theme or change themes on the fly.

t = terminal(Theme="dracula");
t.Theme = "nord";                  % switch to a different theme

%%
% List all available preset themes:

terminal.themes()

%%
% Set a persistent default theme for all new terminals:

terminal.setDefaultTheme("dracula")

%% AI Agent Integration
% Set up full agent integration with MathWorks Agentic Toolkits.
% Terminal downloads the MCP server, shares the MATLAB session,
% and registers with your AI coding agent (Claude, Copilot, Codex, etc.).

% Interactive wizard (first run)
t = terminal(Agentic=true);

%%
% Or skip the wizard by specifying your agent directly:

t = terminal(Agent="claude");
t = terminal(Agent="claude", Toolkits=["matlab","simulink"]);

%%
% If your agent CLI has a non-standard path:

t = terminal(Agent="claude", AgentCLI="devai launch claude");

%% Embedding in an Existing Figure
% Pass a figure or panel as the first argument to embed a terminal
% inside your own UI layout.

fig = uifigure("Name", "My App");
t = terminal(fig);

%% Managing Running Terminals
% List all open terminals and close them programmatically.

terminals = terminal.list();    % returns handles to all running terminals
terminal.closeAll();            % closes every terminal

%% Checking the Version
% Display the installed toolbox version:

terminal.version()

%% Updating
% Check for a newer release on GitHub and update interactively:

terminal.update()

%% Cleaning Up
% Close a single terminal by deleting its handle. The server process
% and figure window are cleaned up automatically.

t = terminal();
% ... use the terminal ...
delete(t);

%% Next Steps
%
% * Type |help terminal| at the command prompt for full API documentation.
% * Visit the project repository for source code and issue tracking.
