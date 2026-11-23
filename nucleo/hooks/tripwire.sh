#!/usr/bin/env bash
# tripwire — vigia a "superfície de instrução" do repositório aberto numa sessão `dev`.
#
# Superfície = todo arquivo que instrui o agente ou que o harness executa:
#   .claude/**  .specify/**  scripts/**  CLAUDE.md  AGENTS.md  .cursorrules
#
# Modelo: trust-on-first-use, igual ao known_hosts do ssh.
#   1a vez num repo  -> grava o baseline e avisa (não bloqueia)
#   igual ao baseline -> silêncio absoluto (não entra no contexto, custo zero em token)
#   diferente        -> exit 2, bloqueia a AÇÃO e manda rodar a revisão
#
# Princípio: FALHA ABERTA. Qualquer erro interno sai 0. Um tripwire com bug não pode
# derrubar a sessão — só bloqueia quando há divergência comprovada.
#
# Escapes: `disableAllHooks: true` nas settings, ou apagar o baseline em ~/.claude/tripwire/.

cat >/dev/null 2>&1   # drena o JSON do hook; este script não depende dele

DIR="${CLAUDE_TRIPWIRE_DIR:-}"
[ -n "$DIR" ] || exit 0
[ -d "$DIR" ] || exit 0

STATE="$HOME/.claude/tripwire"
KEY=$(printf '%s' "$DIR" | sha256sum 2>/dev/null | cut -c1-16)
[ -n "$KEY" ] || exit 0
BASE="$STATE/$KEY.hash"
MANI="$STATE/$KEY.manifesto"
SEEN="${TMPDIR:-/tmp}/tripwire-$KEY-$PPID"

[ -f "$SEEN" ] && exit 0   # já conferido nesta sessão

manifesto() {
  find "$DIR/.claude" "$DIR/.specify" "$DIR/scripts" \
       "$DIR/CLAUDE.md" "$DIR/AGENTS.md" "$DIR/.cursorrules" \
       -type f 2>/dev/null \
    | LC_ALL=C sort | tr '\n' '\0' | xargs -0 -r sha256sum 2>/dev/null
}

CUR=$(manifesto)
HASH=$(printf '%s' "$CUR" | sha256sum 2>/dev/null | cut -c1-64)
[ -n "$HASH" ] || exit 0

mkdir -p "$STATE" 2>/dev/null || exit 0

if [ ! -f "$BASE" ]; then
  printf '%s\n' "$HASH" > "$BASE" 2>/dev/null || exit 0
  printf '%s\n' "$CUR"  > "$MANI" 2>/dev/null
  : > "$SEEN" 2>/dev/null
  n=$(printf '%s\n' "$CUR" | grep -c . 2>/dev/null)
  echo "tripwire: baseline gravado para $(basename "$DIR") — $n arquivo(s) de instrução." >&2
  exit 0
fi

if [ "$HASH" = "$(cat "$BASE" 2>/dev/null)" ]; then
  : > "$SEEN" 2>/dev/null
  exit 0
fi

echo "TRIPWIRE: a superfície de instrução de '$(basename "$DIR")' mudou desde a última aprovação." >&2
echo "Ação bloqueada. Num terminal, rode:  tripwire-review \"$DIR\"" >&2
echo "Leitura e busca seguem liberadas — dá para investigar o que mudou sem sair da sessão." >&2
exit 2
