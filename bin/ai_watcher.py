#!/usr/bin/env python3
"""
AI Watcher – kouká přes rameno na libovolné GUI okno.
Použití:
    python3 ai_watcher.py                  # screenshot celé obrazovky
    python3 ai_watcher.py --window         # screenshot aktivního okna
    python3 ai_watcher.py --loop 10        # opakuje každých 10 sekund
    python3 ai_watcher.py --otazka "Co mám udělat dál?"
"""

import anthropic
import base64
import subprocess
import sys
import time
import argparse
import tempfile
import os
from pathlib import Path

# ── Configuration (sourced from ~/.config/ai-watcher/{env,config}) ──────────
API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
LANG = os.environ.get("AI_LANG", "English")
MODEL = os.environ.get("AI_MODEL", "claude-sonnet-4-6")
DEFAULT_QUESTION = os.environ.get(
    "AI_DEFAULT_QUESTION",
    "What do you see? What should I do next?",
)

# Custom prompt wins over the language-based default
SYSTEM_PROMPT = os.environ.get("AI_SYSTEM_PROMPT") or f"""You are an experienced Linux administrator and programmer.
The user sends you a screenshot of what they're currently doing on their Linux desktop.
Look at the screen and:
- Briefly describe what you see
- Suggest the next step or point out a problem
- If you see an error, explain the cause and a solution
Reply in {LANG}, concise and practical."""

# ── Screenshot ────────────────────────────────────────────────────────────────
def screenshot(window_only: bool = False) -> bytes:
    # scrot 1.8 tiše odmítne přepsat existující soubor — vytvoříme jen jméno
    fd, tmp = tempfile.mkstemp(suffix=".png")
    os.close(fd)
    os.unlink(tmp)

    # Zajistíme DISPLAY proměnnou pro případ spuštění z cronu/ssh
    env = os.environ.copy()
    if "DISPLAY" not in env:
        env["DISPLAY"] = ":0"

    try:
        if window_only:
            result = subprocess.run(["scrot", "--focused", tmp], check=True, env=env,
                                    capture_output=True, text=True)
        else:
            result = subprocess.run(["scrot", tmp], check=True, env=env,
                                    capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"scrot selhal: {e.stderr}") from e

    if not Path(tmp).exists() or Path(tmp).stat().st_size == 0:
        raise RuntimeError("Screenshot je prázdný — zkontroluj zda běží X server a DISPLAY je správně nastaven")

    data = Path(tmp).read_bytes()
    os.unlink(tmp)
    return data

# ── Claude API ────────────────────────────────────────────────────────────────
def ask_claude(image_bytes: bytes, otazka: str = "", title: str = "") -> str:
    client = anthropic.Anthropic(api_key=API_KEY)

    b64 = base64.standard_b64encode(image_bytes).decode("utf-8")

    user_content = []
    if title:
        user_content.append({"type": "text", "text": f"[Titulek okna: {title}]"})
    user_content.append({
        "type": "image",
        "source": {"type": "base64", "media_type": "image/png", "data": b64},
    })
    user_content.append({"type": "text", "text": otazka or DEFAULT_QUESTION})

    msg = client.messages.create(
        model=MODEL,
        max_tokens=1000,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_content}],
    )
    return msg.content[0].text

# ── Notifikace (volitelné) ─────────────────────────────────────────────────────
def notify(text: str):
    try:
        subprocess.run(
            ["notify-send", "--icon=dialog-information", "AI Watcher", text[:200]],
            check=False,
        )
    except FileNotFoundError:
        pass  # notify-send není nainstalován, nevadí

# ── Hlavní logika ─────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="AI kouká přes rameno")
    parser.add_argument("--window", action="store_true", help="Screenshot jen aktivního okna")
    parser.add_argument("--loop", type=int, default=0, metavar="SEKUND",
                        help="Opakuj každých N sekund (0 = jednou)")
    parser.add_argument("--otazka", type=str, default="",
                        help="Konkrétní otázka k obrazovce")
    parser.add_argument("--tichy", action="store_true",
                        help="Bez notifikací, jen terminál")
    parser.add_argument("--image", type=str, default="",
                        help="Použij existující PNG místo nového screenshotu")
    parser.add_argument("--title", type=str, default="",
                        help="Titulek okna (kontext pro AI)")
    args = parser.parse_args()

    if not API_KEY:
        print("❌  Chybí ANTHROPIC_API_KEY")
        print("    Nastav ho: export ANTHROPIC_API_KEY='sk-ant-...'")
        sys.exit(1)

    def jedna_iterace():
        if args.image:
            img = Path(args.image).read_bytes()
        else:
            print("📸  Snímám obrazovku...", flush=True)
            img = screenshot(window_only=args.window)

        print("🤖  Ptám se Claude...", flush=True)
        odpoved = ask_claude(img, args.otazka, args.title)

        print("\n" + "─" * 60)
        print(odpoved)
        print("─" * 60 + "\n")

        if not args.tichy:
            notify(odpoved)

    if args.loop > 0:
        print(f"🔄  Spouštím smyčku každých {args.loop}s  (Ctrl+C pro ukončení)")
        while True:
            jedna_iterace()
            time.sleep(args.loop)
    else:
        jedna_iterace()

if __name__ == "__main__":
    main()
