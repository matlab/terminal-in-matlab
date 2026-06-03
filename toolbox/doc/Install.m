%[text] # Install Terminal in MATLAB
%[text] This script downloads and installs the latest release of Terminal from GitHub.
%[text] ## What to expect:
%[text] - If Terminal is already installed, the current version is shown and you are asked whether to continue. Press Enter to proceed or type "n" to cancel.
%[text] - The script downloads Terminal.mltbx from the latest GitHub release.
%[text] - Any existing Terminal installation is uninstalled first.
%[text] - The downloaded toolbox is installed using matlab.addons.install.
%[text] - The temporary .mltbx file is deleted after installation.
%[text] - A Terminal window opens so you can start using it right away. \
%[text] ## Requirements:
%[text] - Internet access (to reach github.com)
%[text] - MATLAB R2024b or later \
%%
%[text] ## Check for an existing installation
addons = matlab.addons.installedAddons;
terminalAddon = addons(addons.Name == "Terminal", :);
if ~isempty(terminalAddon)
    disp("Terminal " + terminalAddon.Version + " is already installed.");
    reply = input("Re-install with the latest version? [Y/n]: ", "s");
    if strtrim(lower(reply)) == "n"
        disp("Installation cancelled.");
        return
    end
    disp("Uninstalling Terminal " + terminalAddon.Version + "...");
    matlab.addons.uninstall("Terminal");
end
%%
%[text] ## Download the latest release
url = "https://github.com/matlab/terminal-in-matlab/releases/latest/download/Terminal.mltbx";
mltbxFile = fullfile(tempdir, "Terminal.mltbx");

disp("Downloading Terminal.mltbx from GitHub...");
websave(mltbxFile, url);

disp("Download complete.");

disp("Installing terminal...");
matlab.addons.install(mltbxFile);
delete(mltbxFile);
disp("Terminal " + terminal.version() + " installed successfully.");
%%
%[text] ## Open a Terminal
edit(fullfile(fileparts(which("terminal.m")), "doc","GettingStarted.mlx"))
cd(userpath)
terminal();

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline","rightPanelPercent":42.5}
%---
