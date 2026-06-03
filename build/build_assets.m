% Copyright 2026 The MathWorks, Inc.

% build_assets.m — Bundle web assets and server binary into a .mat.
%
% Run from the matlab-terminal project root:
%   >> run('build/build_assets.m')
%
% This creates toolbox/web_assets.mat containing all files that
% packageToolbox silently drops (.html, .css, .js, binaries).

projectDir = fileparts(fileparts(mfilename('fullpath')));
toolboxDir = fullfile(projectDir, 'toolbox');

files = {
    'html/index.html'
    'html/terminal.css'
    'html/lib/xterm/xterm.js'
    'html/lib/xterm/xterm.css'
    'html/lib/xterm/addon-fit.js'
    'html/lib/xterm/addon-serialize.js'
};

% Add server binaries for all available platforms.
platforms = {'glnxa64', 'maci64', 'maca64', 'win64'};
binaryBaseName = 'matlab-terminal-server';
binaryPaths = struct();
foundAny = false;
for p = 1:numel(platforms)
    plat = platforms{p};
    bn = binaryBaseName;
    if strcmp(plat, 'win64')
        bn = [bn, '.exe']; %#ok<AGROW>
    end
    bp = fullfile(projectDir, 'dist', plat, bn);
    if isfile(bp)
        files{end+1} = ['bin/matlab-terminal-server/', plat, '/', bn]; %#ok<SAGROW>
        binaryPaths.(plat) = bp;
        foundAny = true;
    end
end
if ~foundAny
    warning('build_assets:NoBinary', ...
        'No server binaries found in dist/<arch>/ for any platform.');
end

assets = struct();
for i = 1:numel(files)
    rel = files{i};
    % Resolve source path: bin/ files come from dist/<arch>/, others from toolbox/.
    if startsWith(rel, 'bin/')
        parts = strsplit(rel, '/');
        plat = parts{3};
        src = binaryPaths.(plat);
    else
        src = fullfile(toolboxDir, rel);
    end
    % Use fread for binary-safe reading.
    fid = fopen(src, 'r');
    data = fread(fid, '*uint8');
    fclose(fid);
    key = regexprep(rel, '[/.\\-]', '_');
    assets.(key) = struct('path', rel, 'data', data, 'executable', startsWith(rel, 'bin/'));
    fprintf('  packed: %s (%d bytes)\n', rel, numel(data));
end

outFile = fullfile(toolboxDir, 'web_assets.mat');
save(outFile, 'assets', '-v7.3');
fprintf('Saved: %s\n', outFile);
