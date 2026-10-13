# Repository Guidelines

## Project Structure & Module Organization

- `bin/apod-wallpaper`: Bash CLI containing fetching, caching, rendering, notifications, and wallpaper updates.
- `plasmoid/contents/ui/main.qml`: Plasma 6 panel widget; `plasmoid/metadata.json` defines its package metadata.
- `systemd/`: user service, daily timer, and monitor hotplug watcher.
- `config/apod-wallpaper.conf`: commented configuration defaults.
- `install.sh` / `uninstall.sh`: per-user installation and removal.
- `README.md` documents usage; `screenshot.png` illustrates the widget. `CLAUDE.md` describes architecture and cross-file contracts.

There is no build step or dedicated test directory. Downloaded images and state live in `~/.local/share/apod-wallpaper/`.

## Build, Test, and Development Commands

- `bash -n bin/apod-wallpaper install.sh uninstall.sh`: check Bash syntax.
- `bin/apod-wallpaper help` and `bin/apod-wallpaper status`: inspect usage and state without changing wallpaper.
- `/usr/lib64/qt6/bin/qmllint plasmoid/contents/ui/main.qml`: lint QML where Qt tools are installed at this path.
- `plasmoidviewer -a plasmoid`: preview the widget in a Plasma development environment.
- `./install.sh`: install edited files, preserve settings, enable services, and update the wallpaper. Services and the widget use the installed script.
- `./uninstall.sh --dry-run`: preview removal.
- `journalctl --user -u apod-wallpaper -u apod-wallpaper-watch`: inspect runtime logs.

## Coding Style & Naming Conventions

Use four-space indentation. Follow Bash `snake_case` function/local names, uppercase configuration constants, and QML `camelCase` properties/functions. Document script helpers with `# name ARGS — purpose` comments. Quote shell expansions and handle failures explicitly: Bash `set -e` behaves differently inside conditional call chains.

No formatter is configured. Preserve existing ShellCheck directives; use ShellCheck when available. Keep user-facing messages plain and actionable.

## Testing Guidelines

No automated framework or coverage threshold exists. Run syntax checks and manually exercise affected commands on Plasma 6. Wallpaper-changing commands (`update`, `latest`, `random`, `apply`) affect the desktop and lock screen. For relevant changes, verify first-run behavior, download fallbacks, monitor fitting, and widget errors. Record commands and outcomes in the PR.

## Commit & Pull Request Guidelines

Use concise imperative subjects matching history, such as “Fix first-run failure” or “Fall back to the standard-size image.” Keep commits focused. PRs should explain behavior changes, link relevant issues, report validation, and include screenshots for widget changes.

## Configuration & Integration

Keep setting defaults, the configuration template, and README synchronized. Subcommand changes also require header help and dispatch updates. Preserve the widget’s status JSON contract. Configuration is sourced as Bash; retain API-key validation and keep personal keys out of commits.
