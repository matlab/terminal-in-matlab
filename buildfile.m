function plan = buildfile
import matlab.buildtool.tasks.*

plan = buildplan(localfunctions);

plan("clean") = CleanTask;
plan("check") = CodeIssuesTask;

plan("test:unit") = TestTask( ...
    fullfile("toolbox", "tests", "TestTerminalUnit.m"), ...
    SourceFiles=["toolbox/*.m", "toolbox/+terminaltools/*", "toolbox/+internal/*.m"]);
plan("test:simulink") = TestTask( ...
    fullfile("toolbox", "tests", "TestTerminalInSimulink.m"), ...
    SourceFiles=["toolbox/*.m", "toolbox/+terminaltools/*", "toolbox/+internal/*.m"]);
plan("test:integration") = TestTask( ...
    fullfile("toolbox", "tests", "TestTerminalIntegration.m"), ...
    SourceFiles=["toolbox/*.m", "toolbox/+terminaltools/*", "toolbox/+internal/*.m"]);

plan("package").Inputs = "toolbox";
plan("package").Outputs = fullfile("dist", "Terminal.mltbx");

plan.DefaultTasks = ["check", "test", "package"];
end

function packageTask(~, version)
% Create toolbox
arguments
    ~
    version (1,1) string = "0.2.0"
end

p = path;
cleanUp = onCleanup(@()path(p));
addpath("build");

package(version);
end
