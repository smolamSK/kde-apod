#!/usr/bin/env bash
# Remove apod-wallpaper for the current user. Settings and downloaded pictures are
# kept unless --purge is given. The current wallpaper stays until you pick another.
#
#   ./uninstall.sh [--purge] [--dry-run]
set -euo pipefail

WIDGET_IDS=(io.github.smolamsk.apodwallpaper org.smolam.apodwallpaper)   # current and first-release IDs
CONF=${XDG_CONFIG_HOME:-$HOME/.config}/apod-wallpaper.conf
CACHE=${XDG_DATA_HOME:-$HOME/.local/share}/apod-wallpaper
UNITS=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user

purge=0 dry=0
for arg; do
    case $arg in
        --purge) purge=1 ;;
        --dry-run) dry=1 ;;
        -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

run() { if (( dry )); then echo "would run: $*"; else "$@"; fi; }

# Remove the widget from panels first, so Plasma doesn't keep a broken placeholder.
run gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
    --method org.kde.PlasmaShell.evaluateScript \
    "panels().forEach(function (p) { ['${WIDGET_IDS[0]}', '${WIDGET_IDS[1]}'].forEach(function (id) {
        p.widgets(id).forEach(function (w) { w.remove(); }); }); });" || true
run systemctl --user disable --now apod-wallpaper.timer apod-wallpaper-watch.service apod-wallpaper.service || true
run rm -f "$UNITS/apod-wallpaper.service" "$UNITS/apod-wallpaper.timer" "$UNITS/apod-wallpaper-watch.service"
run systemctl --user daemon-reload
for id in "${WIDGET_IDS[@]}"; do
    if kpackagetool6 -t Plasma/Applet -s "$id" >/dev/null 2>&1; then run kpackagetool6 -t Plasma/Applet -r "$id"; fi
done
run rm -f "$HOME/.local/bin/apod-wallpaper"
if (( purge )); then
    run rm -rf "$CONF" "$CACHE"
else
    echo "Kept settings ($CONF) and pictures ($CACHE); use --purge to remove them."
fi
(( dry )) && echo "(dry run: nothing was changed)" || echo "apod-wallpaper removed. Your current wallpaper stays until you choose another one."
