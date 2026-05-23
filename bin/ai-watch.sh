#!/bin/bash
# AI Watcher – screenshot + Claude query (default question).
# Usage: ai-watch.sh [--window]
# Output is appended to ~/.local/share/ai-watcher/log.log; viewer auto-starts.

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/ai-watch-lib.sh"

ai_check_deps scrot xterm xdotool || exit 1
ai_load_env                       || exit 1
ai_load_config
mkdir -p "$AI_LOG_DIR"
ai_start_viewer

MODE="desktop"
TITLE_ARG=()
if [[ "$*" == *--window* ]]; then
    MODE="aktivní okno"
    TITLE=$(ai_active_window_title)
    [ -n "$TITLE" ] && TITLE_ARG=(--title "$TITLE")
fi

{
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')   režim: $MODE"
    [ -n "${TITLE:-}" ] && echo "  🪟 $TITLE"
    echo "════════════════════════════════════════════════════════════"
    python3 -u "$AI_INSTALL_DIR/ai_watcher.py" --tichy "${TITLE_ARG[@]}" "$@" 2>&1
} >> "$AI_LOG_FILE"
