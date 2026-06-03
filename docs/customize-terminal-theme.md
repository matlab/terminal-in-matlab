# Customize Terminal Theme

By default, Terminal uses the MATLAB® desktop theme, light or dark, and updates automatically when the MATLAB theme changes. You can also use preset themes or specify your own theme. 

  | Light                                  | Dark                                 |
  | -------------------------------------- | ------------------------------------ |
  | ![Light theme](../images/theme-light.png) | ![Dark theme](../images/theme-dark.png) |


## Use a Preset Theme

```matlab
t = terminal(Theme="dracula");
```

Change the theme on an existing terminal:

```matlab
t.Theme = "nord";
```

## Available Themes

| Preset               | Description                                |
| -------------------- | ------------------------------------------ |
| `"auto"`             | Follows the MATLAB Desktop theme (default) |
| `"light"`            | Light theme (white background)             |
| `"dark"`             | Dark theme (VS Code–style)                 |
| `"dracula"`          | Dracula                                    |
| `"monokai"`          | Monokai                                    |
| `"solarized-dark"`   | Solarized Dark                             |
| `"solarized-light"`  | Solarized Light                            |
| `"nord"`             | Nord                                       |
| `"gruvbox-dark"`     | Gruvbox Dark                               |
| `"one-dark"`         | Atom One Dark                              |
| `"tokyo-night"`      | Tokyo Night                                |
| `"catppuccin-mocha"` | Catppuccin Mocha                           |

List all available presets programmatically:

```matlab
terminal.themes()
```

## Use Custom Themes

Pass a struct with color fields to define a custom theme. Only include the fields you want to customize. Any field you omit inherits its value from the built-in `"dark"` preset.

```matlab
% Only override background and foreground; all other colors come from "dark"
myTheme = struct( ...
    'background',  '#1a1a2e', ...
    'foreground',  '#e0e0e0');
t = terminal(Theme=myTheme);
```

A more complete example with cursor and selection colors:

```matlab
myTheme = struct( ...
    'background',  '#1a1a2e', ...
    'foreground',  '#e0e0e0', ...
    'cursor',      '#ff6b6b', ...
    'selectionBackground', '#3a3a5e');
t = terminal(Theme=myTheme);
```

For full control over the ANSI color palette, include any of the 16 standard color fields. These control how programs like `ls`, `git`, and shell prompts render colored output:

```matlab
myTheme = struct( ...
    'background',  '#1a1a2e', ...
    'foreground',  '#e0e0e0', ...
    'cursor',      '#ff6b6b', ...
    'selectionBackground', '#3a3a5e', ...
    'black',       '#1a1a2e', ...
    'red',         '#ff6b6b', ...
    'green',       '#a8cc8c', ...
    'yellow',      '#dbab79', ...
    'blue',        '#71bef2', ...
    'magenta',     '#d290e4', ...
    'cyan',        '#66c2cd', ...
    'white',       '#e0e0e0', ...
    'brightBlack', '#545862', ...
    'brightRed',   '#ff8a8a', ...
    'brightGreen', '#b5d4a0', ...
    'brightYellow','#e8c48d', ...
    'brightBlue',  '#84cbf5', ...
    'brightMagenta','#dca4ea', ...
    'brightCyan',  '#79d2da', ...
    'brightWhite', '#f0f0f0');
t = terminal(Theme=myTheme);
```

### Supported Fields

All fields are optional. Values must be `'#rrggbb'` hex color strings.

| Field                 | Description                                | Default (from `"dark"` preset) |
| --------------------- | ------------------------------------------ | ------------------------------ |
| `background`          | Terminal background                        | `'#1e1e1e'`                    |
| `foreground`          | Default text color                         | `'#d4d4d4'`                    |
| `cursor`              | Cursor color                               | `'#aeafad'`                    |
| `cursorAccent`        | Cursor text color (character under cursor) | Same as `background`           |
| `selectionBackground` | Selected text highlight                    | `'#264f78'`                    |
| `black`               | ANSI black (color 0)                       | xterm.js default               |
| `red`                 | ANSI red (color 1)                         | xterm.js default               |
| `green`               | ANSI green (color 2)                       | xterm.js default               |
| `yellow`              | ANSI yellow (color 3)                      | xterm.js default               |
| `blue`                | ANSI blue (color 4)                        | xterm.js default               |
| `magenta`             | ANSI magenta (color 5)                     | xterm.js default               |
| `cyan`                | ANSI cyan (color 6)                        | xterm.js default               |
| `white`               | ANSI white (color 7)                       | xterm.js default               |
| `brightBlack`         | ANSI bright black (color 8)                | xterm.js default               |
| `brightRed`           | ANSI bright red (color 9)                  | xterm.js default               |
| `brightGreen`         | ANSI bright green (color 10)               | xterm.js default               |
| `brightYellow`        | ANSI bright yellow (color 11)              | xterm.js default               |
| `brightBlue`          | ANSI bright blue (color 12)                | xterm.js default               |
| `brightMagenta`       | ANSI bright magenta (color 13)             | xterm.js default               |
| `brightCyan`          | ANSI bright cyan (color 14)                | xterm.js default               |
| `brightWhite`         | ANSI bright white (color 15)               | xterm.js default               |


## Set Default Theme

Set a default theme that applies to all new terminals and persists across MATLAB sessions:

```matlab
terminal.setDefaultTheme("dracula")
```

New terminals use this theme unless your override them with the `Theme` argument:

```matlab
t1 = terminal();                  % uses "dracula"
t2 = terminal(Theme="nord");      % overrides to "nord"
```

Query and reset the default:

```matlab
terminal.getDefaultTheme()        % returns "dracula"
terminal.setDefaultTheme("auto")  % reset to follow MATLAB theme
```

---

Copyright 2026 The MathWorks, Inc.

---

