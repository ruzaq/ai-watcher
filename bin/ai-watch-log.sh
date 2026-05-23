#!/bin/bash
# Opens an xterm with a live tail of the AI Watcher log.
# Idempotent: if the viewer is already running, just exits.

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/ai-watch-lib.sh"

ai_check_deps xterm || exit 1
mkdir -p "$AI_LOG_DIR"
touch "$AI_LOG_FILE"

# Pokud už xterm s tail na náš log běží, nic nedělej
if pgrep -f "tail -n 200 -f $AI_LOG_FILE" >/dev/null; then
    exit 0
fi

exec xterm -title "AI Watcher Log" \
      -geometry 100x30 \
      -fa "DejaVu Sans Mono" -fs 10 \
      -e "tail -n 200 -f '$AI_LOG_FILE'"
