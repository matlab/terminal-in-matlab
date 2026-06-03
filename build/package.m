% Copyright 2026 The MathWorks, Inc.

function package(toolboxVersion)
%PACKAGE Build the Terminal.mltbx toolbox package.
%
%   package()          — build using the version in terminalVersion.m
%   package("1.2.0")   — build with an explicit version string
%
% Examples:
%   >> run('build/package.m')                  % local dev build
%   >> package("1.2.0")                        % CI release build

    arguments
        toolboxVersion (1,1) string = ""
    end

    projectDir = fileparts(fileparts(mfilename('fullpath')));
    toolboxDir = fullfile(projectDir, 'toolbox');
    distDir = fullfile(projectDir, 'dist');
    if ~isfolder(distDir)
        mkdir(distDir);
    end
    outputFile = fullfile(distDir, 'Terminal.mltbx');

    % --- Step 1: Resolve version ---
    if toolboxVersion == ""
        addpath(toolboxDir);
        toolboxVersion = terminalVersion();
    end
    if startsWith(toolboxVersion, 'v')
        toolboxVersion = extractAfter(toolboxVersion, 1);
    end
    fprintf('Version: %s\n', toolboxVersion);

    % Derive a numeric toolbox version. MATLAB's ToolboxOptions only
    % accepts Major.Minor.Patch[.Build] — no prerelease suffixes.
    % Map "-mcp" to .999 (internal MCP builds) and any other suffix
    % (e.g. "-rc1", "-beta") to .1.
    matlabVersion = toolboxVersion;
    hyphenIdx = strfind(matlabVersion, '-');
    if ~isempty(hyphenIdx)
        base = extractBefore(matlabVersion, hyphenIdx(1));
        suffix = extractAfter(matlabVersion, hyphenIdx(1));
        if suffix == "mcp"
            matlabVersion = base + ".999";
        else
            matlabVersion = base + ".1";
        end
    end

    % Stamp terminalVersion.m with the full version (including suffix).
    versionFile = fullfile(toolboxDir, 'terminalVersion.m');
    fid = fopen(versionFile, 'w');
    fprintf(fid, 'function v = terminalVersion()\n');
    fprintf(fid, '%%TERMINALVERSION Return the installed toolbox version.\n');
    fprintf(fid, '    v = "%s";\n', toolboxVersion);
    fprintf(fid, 'end\n');
    fclose(fid);

    % --- Step 2: Bundle web assets into .mat ---
    % packageToolbox silently drops .html/.css/.js files, so we embed them
    % in a .mat file that terminal.m extracts at runtime.
    run(fullfile(projectDir, 'build', 'build_assets.m'));

    % --- Step 3: Build .mltbx ---
    opts = matlab.addons.toolbox.ToolboxOptions(toolboxDir, ...
        '9e8f4a2b-3c1d-4e5f-a6b7-8c9d0e1f2a3b');

    opts.ToolboxName = 'Terminal';
    opts.ToolboxVersion = matlabVersion;
    opts.Summary = 'Embedded system terminal for MATLAB';
    opts.Description = ['Run system commands, git, docker, and CLI tools ' ...
        'directly inside the MATLAB Desktop. ' ...
        'Supports multiple tabs, MATLAB theme integration, ' ...
        'and docked or floating windows.'];
    opts.AuthorName = 'The MathWorks, Inc.';
    opts.AuthorEmail = 'support@mathworks.com';
    opts.MinimumMatlabRelease = 'R2024b';
    opts.MaximumMatlabRelease = '';
    opts.ToolboxMatlabPath = toolboxDir;
    opts.ToolboxImageFile = fullfile(toolboxDir, 'images', 'matlab-terminal.jpeg');
    opts.ToolboxGettingStartedGuide = fullfile(toolboxDir, 'doc', 'GettingStarted.mlx');
    opts.AppGalleryFiles = fullfile(toolboxDir, 'openTerminal.m');
    opts.OutputFile = outputFile;

    matlab.addons.toolbox.packageToolbox(opts);
    fprintf('Packaged: %s\n', outputFile);
end
