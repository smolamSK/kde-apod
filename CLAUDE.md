# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A KDE Plasma 6 wallpaper tool for NASA's Astronomy Picture of the Day. Everything happens in one bash script, `bin/apod-wallpaper`. The systemd user units (`systemd/`) and the Plasma panel widget (`plasmoid/`) only call its subcommands. There is no build step and no test suite.

## Development

- **The units and the widget run the installed copy** (`~/.local/bin/apod-wallpaper`), not the repo. After editing, run `./install.sh` to copy the script, units and widget. Existing settings are kept, and the run sets today's wallpaper.
- Running the script straight from the repo works too, e.g. `bin/apod-wallpaper update --date 2026-09-25` or `bin/apod-wallpaper status`. `update`, `latest`, `random` and `apply` change the real desktop and lock-screen wallpaper and can send a notification. `status` and `help` are read-only.
- Syntax check: `bash -n bin/apod-wallpaper install.sh uninstall.sh`. The script has shellcheck directives, but shellcheck isn't installed on this machine.
- QML: `/usr/lib64/qt6/bin/qmllint plasmoid/contents/ui/main.qml`. To try the widget without the panel: `plasmoidviewer -a plasmoid`.
- Logs: `journalctl --user -u apod-wallpaper -u apod-wallpaper-watch`.
- `./uninstall.sh --dry-run` prints what it would remove.

## Architecture

### Fetch pipeline (`show`)
`candidates` → `entries` → `resolve` → `download` → `set_entry`. `show` tries at most the first 5 candidates.
- `candidates`:
  - `latest`: the last 11 days, newest first, so a video day falls back to the most recent photo.
  - `random`: one shuffled 30-day window since `RANDOM_SINCE`.
  - A specific date.
- **The APOD API is unreliable since APOD moved to science.nasa.gov.** It returns placeholder entries (title "NASA Science", logo URL); the `NEEDS_PAGE` jq filter matches these. When the API fails completely, `entries` emits `{"date": ...}` stubs. `resolve` replaces both kinds with `page_entry`, which scrapes `science.nasa.gov/apod/?date=…` with jq regexes into the API's JSON shape. Those regexes depend on the page's markup (`og:title` "APOD: YYYY Month D", `h1.display-48`, `media-detail-hero__description`). Check them first when page fallback breaks.
- `download` tries `hdurl` first. If that fails, it falls back to `url` and caches it as `orig-DATE-sd.*`, so a later run still upgrades to HD. `set_entry` doesn't count the sd→HD swap as a new picture, so no second notification is sent.
- When nothing could be fetched, `show` re-applies the current image and returns 1. `latest`/`random` only write the `mode` file on success.
- Retries: each request retries for up to `RETRY_MAX`. That is 15 minutes in background runs, and systemd's `TimeoutStartSec` stops the whole run after 15 minutes. The widget's `latest`/`random` commands lower `RETRIES`/`RETRY_DELAY`/`RETRY_MAX` to about 20 seconds per request, and wait at most 60 seconds for the lock (`lock 60`) when a background run holds it.
- `fetch` only keeps a download that ImageMagick can read, so a Wi-Fi login page or error page never becomes the wallpaper. `cmd_apply` skips any monitor whose render failed, rather than pointing Plasma at a missing file.

### `set -e` depends on the call path
`set -e` is on in `update` and `apply`, where the call chain is plain, so any failing command aborts the run, even deep inside `set_entry` or `render`. `latest`/`random` call `show … && echo … >mode`, and bash turns `set -e` off inside that whole call. The same code can therefore abort in one path and carry on in the other.
- Guard commands that are expected to fail with `|| true` or an explicit `||` branch, e.g. `cur=$(cat "$CACHE/current" 2>/dev/null) || true` (there is no `current` on the first run).
- Handle real failures explicitly instead of relying on `set -e`.
- Don't use `((n++))` for counters: it returns 1 when `n` was 0.

### Rendering and applying (`cmd_apply`)
- Monitors come from `kscreen-doctor -j`, using the native size of the current mode. Width and height are swapped when the rotation is 2 or 8.
- `render` picks a mode from the aspect-ratio mismatch: at most `FIT_THRESHOLD` crops to fill, anything larger shows the whole image over a blurred copy. ImageMagick 6 and 7 are both supported through `$IM` (`magick` or `convert`).
- Desktops are set through `org.kde.PlasmaShell.evaluateScript` and matched to monitors by their screen's top-left `x,y`.
- The lock screen is set with `kwriteconfig6` in `kscreenlockerrc`, using the render for the primary (lowest-priority-number) monitor.

### State in `~/.local/share/apod-wallpaper/`
| File | Contents |
|---|---|
| `mode` | `latest` or `random` |
| `current` | Path of the current original |
| `changed` | Date of the last picture change. Random mode doesn't reshuffle on a later login the same day. |
| `meta.json` | The APOD entry |
| `.lock` | `flock` lock for every command that writes |
| `orig-DATE[-sd].ext` | Downloaded originals |
| `render-KEY-OUTPUT-WxH.jpg` | Per-monitor renders |

- Each render has a unique name per image, monitor and size so Plasma never shows a stale cached file. `KEY` is the original's basename without `orig-`, or `custom-<md5>` for `apply --image`.
- `cmd_status`, `prune` and `fetch` all find renders through this naming scheme. If you change it, change all three.
- `status` and `help` must not create the cache directory.

### Contracts between files
- **Widget ↔ script.**
  - The widget polls `apod-wallpaper status` (JSON: `meta.json` plus `mode`, `image`, `credit`, `page`) and runs `latest`/`random`.
  - When a command fails, the widget shows the first `apod-wallpaper: ` line on stderr (without the prefix) that isn't progress, as decided by a regex in `main.qml` (`no picture fetched`, `downloading`, `trying …`, `is under Npx`, …). If the script fell back to the APOD website, the widget looks after the `trying the APOD website instead` line first, because the API error has been dealt with by then. Lines from curl and ImageMagick are ignored. Write failure messages in plain language. If you add a progress message, add it to that regex, or it can show up as the error.
- **install.sh ↔ script.** `install.sh` greps the installed script's `help` output for `shared DEMO_KEY` to decide whether to show the API-key tip.
- **The config is `source`d by bash.** For that reason `install.sh` only accepts alphanumeric API keys and writes them quoted.
- **Help text comes from header comments.** `help` (and `--help` in both install scripts) prints the file's leading comment block. To add or change a subcommand, edit the header comment, the `case` dispatch, and the README's "Command line" section.
- **Settings are listed in three places.** Every setting has its default at the top of the script, a commented line in `config/apod-wallpaper.conf`, and a row in the README's Configuration table. Keep them in sync.
- **Required commands are listed twice.** The `need` list in the dispatch and the requirement check in `install.sh` should match.
- **Widget IDs.** The widget ID is `io.github.smolamsk.apodwallpaper`. `install.sh` migrates panels from the first-release ID `org.smolam.apodwallpaper`, and `uninstall.sh` removes both.

## Conventions

- Each function in the script starts with a `# name ARGS — what it returns/does` comment. Comments explain why, not what.
- Fetching writes to a `.part` file and then `mv`s it into place, so a failed run never leaves a broken cached image.
- User-facing text (README, log messages, notifications) is plain language without jargon.
