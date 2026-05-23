#!/bin/bash
# AI Watcher uninstaller.
# Removes scripts from ~/bin/ai-watcher and XFCE shortcuts. Data in
# ~/.config and ~/.local is left intact (API key, log) – delete manually
# if desired.

set -u

BIN_DIR="$HOME/bin/ai-watcher"

echo "▸ Removing scripts from $BIN_DIR..."
for f in ai-watch.sh ai-watch-lib.sh ai-watch-log.sh ai-ask.sh ai_watcher.py; do
    if [ -e "$BIN_DIR/$f" ]; then
        rm -f "$BIN_DIR/$f"
        echo "  ✓ $f"
    fi
done
# Remove the directory if it's now empty
rmdir "$BIN_DIR" 2>/dev/null && echo "  ✓ removed empty $BIN_DIR"

echo
if command -v xfconf-query >/dev/null 2>&1; then
    echo "▸ Removing XFCE shortcuts..."
    for sc in "<Super>a" "<Shift><Super>a" "<Super>q" "<Shift><Super>q"; do
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$sc" -r 2>/dev/null && \
            echo "  ✓ $sc"
    done
fi

echo
echo "Kept (delete manually if you wish):"
echo "  $HOME/.config/ai-watcher/        # API key + preferences"
echo "  $HOME/.local/share/ai-watcher/   # log + key marker"

# Kill running viewer
pkill -f "tail -n 200 -f $HOME/.local/share/ai-watcher/log.log" 2>/dev/null

echo
echo "Uninstall done."
