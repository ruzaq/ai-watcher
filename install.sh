#!/bin/bash
# AI Watcher installer.
# Copies scripts to ~/bin, installs missing dependencies, optionally
# registers XFCE keyboard shortcuts.

set -euo pipefail

cd "$(dirname "$0")"
BIN_DIR="$HOME/bin/ai-watcher"
CONFIG_DIR="$HOME/.config/ai-watcher"
ENV_FILE="$CONFIG_DIR/env"
CONFIG_FILE="$CONFIG_DIR/config"

echo "═══════════════════════════════════════════════════════════"
echo "  AI Watcher – install"
echo "═══════════════════════════════════════════════════════════"
echo

# 1) System packages
echo "▸ Checking system packages (scrot, xterm, zenity, xdotool)..."
MISSING=()
for pkg in scrot xterm zenity xdotool; do
    command -v "$pkg" >/dev/null 2>&1 || MISSING+=("$pkg")
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "  Missing: ${MISSING[*]}"
    echo "  Installing via apt..."
    sudo apt-get update -qq
    sudo apt-get install -y "${MISSING[@]}"
else
    echo "  ✓ All present"
fi

# 2) Python anthropic module
echo
echo "▸ Checking Python anthropic module..."
if python3 -c "import anthropic" 2>/dev/null; then
    echo "  ✓ Available"
else
    echo "  Installing via pip..."
    pip install --user --break-system-packages anthropic
fi

# 3) Copy scripts
echo
echo "▸ Copying scripts to $BIN_DIR ..."
mkdir -p "$BIN_DIR"
for f in bin/*.sh bin/*.py; do
    cp "$f" "$BIN_DIR/"
    chmod +x "$BIN_DIR/$(basename "$f")"
    echo "  ✓ $(basename "$f")"
done

# 4) Configuration directory + API key template
echo
echo "▸ Preparing configuration..."
mkdir -p "$CONFIG_DIR"

if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" <<'EOF'
# AI Watcher – Anthropic API key
# Get yours at: https://console.anthropic.com/settings/keys
# Replace NAHRADIT-MNE with your real key (it starts with "sk-ant-").
export ANTHROPIC_API_KEY="sk-ant-api03-NAHRADIT-MNE"
EOF
    chmod 600 "$ENV_FILE"
    echo "  ✓ Created template: $ENV_FILE"
    echo "    !!! Add your API key before first use."
    echo "    Get one at: https://console.anthropic.com/settings/keys"
else
    chmod 600 "$ENV_FILE"
    echo "  ✓ $ENV_FILE already exists (kept)"
fi

# Optional preferences (language, model, custom system prompt)
if [ ! -f "$CONFIG_FILE" ] && [ -f config.example ]; then
    cp config.example "$CONFIG_FILE"
    echo "  ✓ Copied config.example to $CONFIG_FILE"
    echo "    Edit it to change language (default: English) or other prefs."
fi

# 5) XFCE shortcuts (optional)
echo
if command -v xfconf-query >/dev/null 2>&1 && [ "${XDG_CURRENT_DESKTOP:-}" = "XFCE" ]; then
    read -r -p "▸ Register XFCE keyboard shortcuts? [y/N] " yn
    if [[ "$yn" =~ ^[yYaA]$ ]]; then
        # Super+A = window (default question), Super+Shift+A = desktop
        # Super+Q = window (custom question), Super+Shift+Q = desktop
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>a" \
            -n -t string -s "$BIN_DIR/ai-watch.sh --window" 2>/dev/null || \
            xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>a" \
            -s "$BIN_DIR/ai-watch.sh --window"
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Shift><Super>a" \
            -n -t string -s "$BIN_DIR/ai-watch.sh" 2>/dev/null || \
            xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Shift><Super>a" \
            -s "$BIN_DIR/ai-watch.sh"
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>q" \
            -n -t string -s "$BIN_DIR/ai-ask.sh --window" 2>/dev/null || \
            xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>q" \
            -s "$BIN_DIR/ai-ask.sh --window"
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Shift><Super>q" \
            -n -t string -s "$BIN_DIR/ai-ask.sh" 2>/dev/null || \
            xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Shift><Super>q" \
            -s "$BIN_DIR/ai-ask.sh"
        echo "  ✓ Registered: Super+A, Super+Shift+A, Super+Q, Super+Shift+Q"
    else
        echo "  Skipped. Register manually under Settings → Keyboard."
    fi
else
    echo "▸ Not running XFCE – skipping shortcut registration."
    echo "  For other DEs, bind these manually:"
    echo "    $BIN_DIR/ai-watch.sh [--window]"
    echo "    $BIN_DIR/ai-ask.sh   [--window]"
fi

echo
echo "═══════════════════════════════════════════════════════════"
echo "  Done!"
echo "═══════════════════════════════════════════════════════════"
echo
echo "Next steps:"
echo "  1. If you haven't yet: put your API key into $ENV_FILE"
echo "  2. (Optional) Change reply language or model in $CONFIG_FILE"
echo "  3. Press a shortcut – on first use the key is validated against the"
echo "     Claude API (one-off, ~2s)."
echo
echo "The log viewer opens automatically on the first shortcut press."
echo "Manually: $BIN_DIR/ai-watch-log.sh"
