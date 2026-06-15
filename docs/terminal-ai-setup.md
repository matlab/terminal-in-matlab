
# Set Up AI Agents

This guide explains how to connect Terminal to an AI coding agent. The setup installs:

- The [MATLAB MCP Core Server](https://github.com/matlab/matlab-mcp-core-server)
- Skills from [MATLAB Agentic Toolkit](https://github.com/matlab/matlab-agentic-toolkit) and [Simulink Agentic Toolkit](https://github.com/matlab/simulink-agentic-toolkit)

and registers Terminal with your chosen agent.

## Quick Start

```matlab
% Interactive wizard — asks which agent and toolkits you want
t = terminal(Agentic=true);

% Or skip the wizard by specifying everything directly
t = terminal(Agent="claude");
t = terminal(Agent="copilot");
t = terminal(Agent="codex");
t = terminal(Agent="gemini", Toolkits=["matlab","simulink"]);
```

## How It Works

Terminal uses a single additive workflow. The first call runs full setup; subsequent calls detect what changed and only apply the difference.

| Call | Behavior |
| ---- | -------- |
| `terminal(Agentic=true)` | First run: wizard. Later: reconnects session only. |
| `terminal(Agent="claude")` | First run: skips wizard. Later: no-op if already using Claude. |
| `terminal(Toolkits=["matlab","simulink"])` | Adds any toolkit not already installed. Agent comes from saved preferences. |
| `terminal(Agent="gemini")` | Switches agent. Existing toolkits are preserved. |
| `terminal(Agent="gemini", Toolkits=["matlab","simulink"])` | Switches agent and adds any missing toolkits in one step. |

You do not need to reset or uninstall anything to change agents or add toolkits. Just call `terminal(...)` with what you want and the setup handles the rest.

## Supported Agents

| Agent | How Terminal registers |
| ----- | --------------------- |
| Claude | Runs `claude mcp add` via CLI |
| Copilot | Writes to `~/.copilot/mcp-config.json` |
| Codex | Runs `codex mcp add` via CLI (falls back to `~/.codex/config.json`) |
| Gemini | Writes to `~/.gemini/settings.json` |
| Amp | Writes to `~/.config/amp/settings.json` |

### Custom Agent CLI (Claude and Codex)

Claude and Codex require running CLI commands during setup (e.g., `claude mcp add`, `codex mcp add`) because they do not use a static JSON configuration file. Copilot, Gemini, and Amp are configured by writing directly to their settings files, so they do not need a CLI path.

If your agent binary has a non-standard name or path, use the `AgentCLI` option so Terminal can find it:

```matlab
t = terminal(Agent="claude", AgentCLI="/usr/local/bin/claude-dev");
t = terminal(Agent="codex", AgentCLI="/usr/local/bin/codex-dev");
```

The custom CLI path is persisted in `config.json` and reused on subsequent runs. This option is ignored for agents that use config-file registration.

If the CLI command fails or is not found on `PATH`, Terminal falls back to writing the configuration file directly (`~/.claude.json` for Claude, `~/.codex/config.json` for Codex). No manual intervention is required.

## Toolkits

By default, Terminal installs the MATLAB toolkit. If Simulink is installed in the running MATLAB, the Simulink toolkit is also included automatically. You can override this by specifying toolkits explicitly:

```matlab
t = terminal(Toolkits="matlab");                    % MATLAB only
t = terminal(Toolkits=["matlab","simulink"]);       % both
```

Terminal downloads the toolkit, rebuilds the merged extension file, and re-registers with your agent automatically.

### Update Toolkits

```matlab
terminal.updateAgenticToolkit()            % update all installed toolkits
terminal.updateAgenticToolkit("matlab")    % update MATLAB toolkit only
terminal.updateAgenticToolkit("simulink")  % update Simulink toolkit only
```

## Additional MCP Tools

Terminal adds these read-only editor tools to the MCP server, giving agents visibility into your MATLAB editor state:

| Tool | Description |
| ---- | ----------- |
| `matlab_editor_list` | List all files open in the editor with modification status |
| `matlab_editor_active` | Get the active file, cursor position, and selected text |
| `matlab_editor_selection` | Get the currently highlighted text |
| `matlab_editor_read` | Read contents of an open file (reflects unsaved edits) |

## Inspect and Reset

View the current saved configuration:

```matlab
terminal.agentOptions()
```

To wipe all saved state and start fresh:

```matlab
terminal.resetAgentOptions()
```

This clears MATLAB preferences and deletes `config.json`. The next `terminal(Agentic=true)` call re-runs the wizard from scratch.

---

Copyright 2026 The MathWorks, Inc.

---
