#!/bin/bash
# AI Watcher with a user-supplied question (via zenity dialog).
# Usage: ai-ask.sh [--window]
# Step order: screenshot FIRST, dialog AFTER — otherwise --focused would
# capture the dialog instead of the target window.

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/ai-watch-lib.sh"

ai_check_deps scrot xterm zenity xdotool || exit 1
ai_load_env                              || exit 1
ai_load_config
mkdir -p "$AI_LOG_DIR"
ai_start_viewer

# 1) Screenshot + titulek – cílové okno má fokus
TMP=$(mktemp -u --suffix=.png)
MODE="desktop"
TITLE=""
TITLE_ARG=()
if [[ "$*" == *--window* ]]; then
    MODE="aktivní okno"
    TITLE=$(ai_active_window_title)
    [ -n "$TITLE" ] && TITLE_ARG=(--title "$TITLE")
    scrot --focused "$TMP" 2>/dev/null
else
    scrot "$TMP" 2>/dev/null
fi

if [ ! -s "$TMP" ]; then
    ai_error "Screenshot selhal (prázdný soubor)."
    rm -f "$TMP"
    exit 1
fi

# 2) Dotaz přes zenity – fokus už nehraje roli
OTAZKA=$(zenity --entry \
    --title="AI Watcher – dotaz" \
    --text="Co se chceš zeptat? (režim: $MODE)" \
    --width=600)
RC=$?

if [ $RC -ne 0 ] || [ -z "$OTAZKA" ]; then
    rm -f "$TMP"
    exit 0
fi

# 3) Pošli Pythonu, výstup do logu
{
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')   režim: $MODE"
    [ -n "$TITLE" ] && echo "  🪟 $TITLE"
    echo "  ❓  $OTAZKA"
    echo "════════════════════════════════════════════════════════════"
    python3 -u "$AI_INSTALL_DIR/ai_watcher.py" --tichy --image "$TMP" --otazka "$OTAZKA" "${TITLE_ARG[@]}" 2>&1
} >> "$AI_LOG_FILE"

rm -f "$TMP"
