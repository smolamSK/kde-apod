#!/usr/bin/env bash
# Install (or update) apod-wallpaper for the current user: script, config, systemd
# user units and the Plasma panel widget. No root needed; safe to run again.
#
#   ./install.sh [--api-key KEY] [--add-to-panel]
set -euo pipefail
cd "$(dirname "$(realpath "$0")")"

WIDGET_ID=org.smolam.apodwallpaper
BIN=$HOME/.local/bin
CONF=${XDG_CONFIG_HOME:-$HOME/.config}/apod-wallpaper.conf
UNITS=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user

api_key=${APOD_API_KEY:-}
add_to_panel=0
while (( $# )); do
    case $1 in
        --api-key) api_key=${2:?--api-key needs a value}; shift ;;
        --api-key=*) api_key=${1#*=} ;;
        --add-to-panel) add_to_panel=1 ;;
        -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

say() { printf '\e[1m==>\e[0m %s\n' "$*"; }
die() { printf '\e[31merror:\e[0m %s\n' "$*" >&2; exit 1; }

# --- Requirements ----------------------------------------------------------------
command -v plasmashell >/dev/null && command -v kpackagetool6 >/dev/null ||
    die "KDE Plasma 6 is required (plasmashell and kpackagetool6 not found)"
[[ $(plasmashell --version 2>/dev/null) =~ \ 6\. ]] || die "KDE Plasma 6 is required, found: $(plasmashell --version 2>&1)"

missing=()
for c in curl jq kscreen-doctor kwriteconfig6 gdbus notify-send flock shuf udevadm systemctl; do
    command -v "$c" >/dev/null || missing+=("$c")
done
command -v magick >/dev/null || command -v convert >/dev/null || missing+=(magick)
if (( ${#missing[@]} )); then
    echo "Missing commands: ${missing[*]}" >&2
    . /etc/os-release 2>/dev/null || true
    case " ${ID:-} ${ID_LIKE:-} " in
        *" fedora "*|*" rhel "*) hint="sudo dnf install ImageMagick jq curl libnotify" ;;
        *" arch "*)              hint="sudo pacman -S --needed imagemagick jq curl libnotify" ;;
        *" debian "*|*" ubuntu "*) hint="sudo apt install imagemagick jq curl libnotify-bin" ;;
        *" suse "*|*" opensuse "*) hint="sudo zypper install ImageMagick jq curl libnotify-tools" ;;
        *) hint="install ImageMagick, jq, curl and libnotify (notify-send) with your package manager" ;;
    esac
    die "install the missing packages first, e.g.: $hint"
fi

# --- Files -----------------------------------------------------------------------
say "Installing the script to $BIN/apod-wallpaper"
install -Dm755 bin/apod-wallpaper "$BIN/apod-wallpaper"

if [[ -f $CONF ]]; then
    say "Keeping existing settings in $CONF"
else
    say "Creating settings file $CONF"
    install -Dm644 config/apod-wallpaper.conf "$CONF"
fi
if [[ -n $api_key ]]; then
    say "Saving NASA API key to $CONF"
    grep -v -E '^#?API_KEY=' "$CONF" >"$CONF.tmp" || true
    printf 'API_KEY=%s\n' "$api_key" >>"$CONF.tmp"
    mv "$CONF.tmp" "$CONF"
fi

say "Installing systemd user units to $UNITS"
install -d "$UNITS"
install -m644 systemd/apod-wallpaper.service systemd/apod-wallpaper.timer \
    systemd/apod-wallpaper-watch.service "$UNITS/"

say "Installing the panel widget ($WIDGET_ID)"
if kpackagetool6 -t Plasma/Applet -s "$WIDGET_ID" >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -u plasmoid >/dev/null
else
    kpackagetool6 -t Plasma/Applet -i plasmoid >/dev/null
fi

# --- Services --------------------------------------------------------------------
say "Enabling the daily timer and the monitor watcher"
systemctl --user daemon-reload
systemctl --user enable apod-wallpaper.service >/dev/null 2>&1
systemctl --user enable --now apod-wallpaper.timer apod-wallpaper-watch.service >/dev/null 2>&1
systemctl --user restart apod-wallpaper-watch.service

say "Setting today's wallpaper (this downloads the picture)"
if ! systemctl --user start apod-wallpaper.service; then
    echo "  Couldn't set the wallpaper yet; see: journalctl --user -u apod-wallpaper" >&2
    echo "  It will be retried at the next login and every day at 07:00." >&2
fi

# --- Panel -----------------------------------------------------------------------
on_panel() {
    gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
        --method org.kde.PlasmaShell.evaluateScript \
        "print(panels().some(function (p) { return p.widgets('$WIDGET_ID').length > 0; }))" 2>/dev/null |
        grep -q true
}
if on_panel; then
    say "The widget is already on your panel"
elif (( add_to_panel )); then
    say "Adding the widget to your panel"
    gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
        --method org.kde.PlasmaShell.evaluateScript \
        "var p = panels()[0]; if (p) p.addWidget('$WIDGET_ID');" >/dev/null
else
    say "To add the widget: right-click the panel > Add Widgets… > search \"APOD Wallpaper\""
    echo "    (or run ./install.sh --add-to-panel)"
fi

if ! grep -q -E '^API_KEY=' "$CONF" || grep -q -E '^API_KEY=DEMO_KEY' "$CONF"; then
    echo
    echo "Tip: the shared DEMO_KEY is rate-limited. Get a free NASA API key at https://api.nasa.gov"
    echo "     and run: ./install.sh --api-key YOUR_KEY"
fi
say "Done"
