#!/bin/bash
# Shared library for AI Watcher scripts.
# Source via:  source "$(dirname "${BASH_SOURCE[0]}")/ai-watch-lib.sh"

# ── Paths ──────────────────────────────────────────────────────────────────
# Auto-discovered install dir = directory containing this library file.
# Lets the suite live anywhere (~/bin, ~/bin/ai-watcher, /opt/..., etc.).
AI_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_ENV_FILE="$HOME/.config/ai-watcher/env"
AI_CONFIG_FILE="$HOME/.config/ai-watcher/config"
AI_LOG_DIR="$HOME/.local/share/ai-watcher"
AI_LOG_FILE="$AI_LOG_DIR/log.log"

# ── Load user preferences (non-secret) ─────────────────────────────────────
# Idempotent: skipped silently if the config file doesn't exist.
ai_load_config() {
    if [ -f "$AI_CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$AI_CONFIG_FILE"
    fi
}

# ── Hlášení chyb ───────────────────────────────────────────────────────────
# Pošle hlášku na stderr, do logu, a (pokud existují) přes zenity + notify-send.
ai_error() {
    local msg="$*"
    mkdir -p "$AI_LOG_DIR"
    {
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo "  $(date '+%Y-%m-%d %H:%M:%S')   ❌ CHYBA"
        echo "════════════════════════════════════════════════════════════"
        echo "$msg"
    } >> "$AI_LOG_FILE"

    echo "$msg" >&2
    command -v zenity >/dev/null 2>&1 && zenity --error --width=500 --text="$msg" 2>/dev/null &
    command -v notify-send >/dev/null 2>&1 && notify-send -u critical "AI Watcher" "${msg:0:200}"
}

# ── Dependency check ───────────────────────────────────────────────────────
# Arguments: list of APT package names this script needs.
# Always also checks for the Python anthropic module.
ai_check_deps() {
    local missing=()
    local pkg
    for pkg in "$@"; do
        # Package → executable mapping (usually identical)
        local cmd="$pkg"
        case "$pkg" in
            libnotify-bin) cmd="notify-send" ;;
            python3-pip)   cmd="pip3" ;;
        esac
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$pkg")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        if ! sudo -n apt-get install -y "${missing[@]}" >/dev/null 2>&1; then
            ai_error "Missing packages: ${missing[*]}. Install via: sudo apt install ${missing[*]}"
            return 1
        fi
    fi

    # Python anthropic module — ensure pip is available first
    if ! python3 -c "import anthropic" 2>/dev/null; then
        if ! command -v pip3 >/dev/null 2>&1; then
            if ! sudo -n apt-get install -y python3-pip >/dev/null 2>&1; then
                ai_error "pip3 is missing. Install via: sudo apt install python3-pip"
                return 1
            fi
        fi
        if ! python3 -m pip install --user --quiet --break-system-packages anthropic >/dev/null 2>&1; then
            ai_error "Python module 'anthropic' is missing. Install via: python3 -m pip install --user anthropic"
            return 1
        fi
    fi

    return 0
}

# ── Setup API klíče – interaktivní průvodce ────────────────────────────────
# Otevře dialog s instrukcemi, na požádání vyrobí šablonu a otevře editor.
_ai_open_editor() {
    local file="$1"
    local editor
    for editor in mousepad gedit kate xed pluma leafpad gnome-text-editor xdg-open; do
        if command -v "$editor" >/dev/null 2>&1; then
            setsid "$editor" "$file" </dev/null >/dev/null 2>&1 &
            return 0
        fi
    done
    return 1
}

_ai_create_template() {
    mkdir -p "$(dirname "$AI_ENV_FILE")"
    if [ ! -f "$AI_ENV_FILE" ]; then
        cat > "$AI_ENV_FILE" <<'EOF'
# AI Watcher – Anthropic API klíč
# Získat na: https://console.anthropic.com/settings/keys
# Nahraď řetězec NAHRADIT-MNE skutečným klíčem (začíná "sk-ant-").
export ANTHROPIC_API_KEY="sk-ant-api03-NAHRADIT-MNE"
EOF
    fi
    chmod 600 "$AI_ENV_FILE"
}

_ai_prompt_setup_key() {
    local title="$1"
    local reason="$2"
    local msg="$reason

Soubor:  $AI_ENV_FILE
Klíč získáš:  https://console.anthropic.com/settings/keys

Chceš otevřít editor s předpřipraveným souborem?
(Pak ulož a znovu stiskni klávesovou zkratku.)"

    if command -v zenity >/dev/null 2>&1; then
        if zenity --question --width=520 --title="$title" --text="$msg" \
                  --ok-label="Otevřít editor" --cancel-label="Zavřít" 2>/dev/null; then
            _ai_create_template
            _ai_open_editor "$AI_ENV_FILE"
        fi
    fi
    # Vždy zaloguj instrukci pro případ že zenity selhal/uživatel zavřel
    ai_error "$title — $reason  Soubor: $AI_ENV_FILE  Klíč: https://console.anthropic.com/settings/keys"
}

# ── Načtení a validace API klíče ───────────────────────────────────────────
ai_load_env() {
    # 1) Soubor neexistuje
    if [ ! -f "$AI_ENV_FILE" ]; then
        _ai_prompt_setup_key "Chybí API klíč" \
            "AI Watcher nemá nakonfigurovaný ANTHROPIC_API_KEY."
        return 1
    fi

    # 2) Permissions check (auto-fix na 600 — klíč je tajný)
    if [ "$(stat -c '%a' "$AI_ENV_FILE" 2>/dev/null)" != "600" ]; then
        chmod 600 "$AI_ENV_FILE" 2>/dev/null
    fi

    # shellcheck source=/dev/null
    source "$AI_ENV_FILE"

    # 3) Klíč není nastaven nebo je to ještě šablona
    if [ -z "$ANTHROPIC_API_KEY" ] || [[ "$ANTHROPIC_API_KEY" == *NAHRADIT-MNE* ]]; then
        _ai_prompt_setup_key "Neplatný API klíč" \
            "V souboru je šablona/prázdná hodnota — doplň skutečný klíč."
        return 1
    fi

    # 4) Formát: Anthropic klíče začínají sk-ant-
    if [[ ! "$ANTHROPIC_API_KEY" =~ ^sk-ant- ]]; then
        _ai_prompt_setup_key "Špatný formát API klíče" \
            "Klíč musí začínat 'sk-ant-'. Aktuálně začíná: '${ANTHROPIC_API_KEY:0:10}...'"
        return 1
    fi

    # 5) Live ověření – jen jednou pro daný klíč (porovnání hash markeru)
    _ai_verify_key_once || return 1

    return 0
}

# ── Live ověření klíče proti Claude API ────────────────────────────────────
# Běží jen když se hash klíče liší od posledně ověřeného (tj. po změně klíče).
_ai_verify_key_once() {
    local hash marker="$AI_LOG_DIR/verified-key.sha256"
    hash=$(printf %s "$ANTHROPIC_API_KEY" | sha256sum | cut -d' ' -f1)

    if [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$hash" ]; then
        return 0  # už ověřeno, přeskoč
    fi

    mkdir -p "$AI_LOG_DIR"
    {
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo "  $(date '+%Y-%m-%d %H:%M:%S')   🔑 Ověřuji nový API klíč..."
        echo "════════════════════════════════════════════════════════════"
    } >> "$AI_LOG_FILE"
    command -v notify-send >/dev/null 2>&1 && \
        notify-send "AI Watcher" "Ověřuji nový API klíč..." 2>/dev/null

    local output rc
    output=$(python3 - <<'PY' 2>&1
import os, sys
try:
    import anthropic
    c = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    c.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=5,
        messages=[{"role": "user", "content": "ping"}],
    )
    sys.exit(0)
except anthropic.AuthenticationError as e:
    print(f"AUTH: {e}", file=sys.stderr); sys.exit(2)
except anthropic.PermissionDeniedError as e:
    print(f"PERM: {e}", file=sys.stderr); sys.exit(3)
except Exception as e:
    print(f"ERR: {type(e).__name__}: {e}", file=sys.stderr); sys.exit(1)
PY
)
    rc=$?

    case $rc in
        0)
            echo "$hash" > "$marker"
            chmod 600 "$marker"
            echo "✓ API klíč ověřen" >> "$AI_LOG_FILE"
            command -v notify-send >/dev/null 2>&1 && \
                notify-send "AI Watcher" "✓ API klíč ověřen" 2>/dev/null
            return 0
            ;;
        2)
            ai_error "API klíč byl Anthropic API odmítnut (401 authentication). Klíč v $AI_ENV_FILE není platný. $output"
            ;;
        3)
            ai_error "API klíč nemá oprávnění k modelu (403). Detail: $output"
            ;;
        *)
            ai_error "Ověření API klíče selhalo (síť? API down?). $output"
            ;;
    esac
    return 1
}

# ── Auto-start log vieweru ─────────────────────────────────────────────────
ai_start_viewer() {
    setsid "$AI_INSTALL_DIR/ai-watch-log.sh" </dev/null >/dev/null 2>&1 &
}

# ── Získání titulku aktivního okna ─────────────────────────────────────────
# Vrací prázdný řetězec pokud xdotool selže nebo titulek je nedostupný.
ai_active_window_title() {
    command -v xdotool >/dev/null 2>&1 || return 0
    xdotool getactivewindow getwindowname 2>/dev/null || true
}
