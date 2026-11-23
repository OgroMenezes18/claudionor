#!/usr/bin/env python3
# Statusline global — status de consumo (contexto, custo e plano Pro/Max).
# Recebe o JSON da sessao via stdin. Ver: https://code.claude.com/docs/en/statusline
import sys, json

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    RESET = "\033[0m"; DIM = "\033[2m"; YELLOW = "\033[33m"
    GREEN = "\033[32m"; ORANGE = "\033[38;5;208m"; RED = "\033[31m"

    model = (data.get("model") or {}).get("display_name") or "?"
    cw = data.get("context_window") or {}
    pct = int(cw.get("used_percentage") or 0)
    cost = (data.get("cost") or {}).get("total_cost_usd") or 0

    # Barra de contexto (10 blocos) colorida por faixa de consumo
    filled = min(10, pct // 10)
    bar = "▓" * filled + "░" * (10 - filled)
    ctx_color = RED if pct >= 80 else ORANGE if pct >= 50 else GREEN

    parts = [
        f"{DIM}[{model}]{RESET}",
        f"{ctx_color}{bar}{RESET} {pct}% ctx",
        f"{DIM}|{RESET} 💰 {YELLOW}${cost:.2f}{RESET}",
    ]

    # Plano (aparece para assinantes Pro/Max apos a 1a resposta da sessao)
    rl = data.get("rate_limits") or {}
    def used(win):
        w = rl.get(win) or {}
        v = w.get("used_percentage")
        return None if v is None else int(v)
    rl5, rl7 = used("five_hour"), used("seven_day")
    if rl5 is not None or rl7 is not None:
        plan = f"{DIM}|{RESET} 🔄"
        if rl5 is not None:
            plan += f" 5h {rl5}%"
        if rl7 is not None:
            plan += f" {DIM}·{RESET} 7d {rl7}%"
        parts.append(plan)

    sys.stdout.write(" ".join(parts))

if __name__ == "__main__":
    main()
