function v = terminalVersion()
%TERMINALVERSION Return the installed toolbox version.
%
%   The default value below is used for local development. During the
%   build process, build/package.m overwrites this file with the release
%   version (derived from the git tag or an explicit argument).
%   Do not edit the version string here — it will be replaced at build time.
    v = "0.0.0-dev";
end
