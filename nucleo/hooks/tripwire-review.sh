#!/usr/bin/env bash
# tripwire-review — mostra o que mudou na superfície de instrução de um repositório,
# varre padrões de alto sinal e, com --aprovar, grava o novo baseline.
#
#   tripwire-review <dir>              # relatório (read-only)
#   tripwire-review <dir> --aprovar    # relatório + grava o baseline
#
# Roda FORA da sessão do Claude, de propósito: quem aprova é você, não o agente.

set -o pipefail
DIR="${1:-}"; MODO="${2:-}"
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "uso: tripwire-review <dir> [--aprovar]"; exit 1; }
DIR=$(cd "$DIR" && pwd)

STATE="$HOME/.claude/tripwire"
KEY=$(printf '%s' "$DIR" | sha256sum | cut -c1-16)
BASE="$STATE/$KEY.hash"; MANI="$STATE/$KEY.manifesto"
mkdir -p "$STATE"

manifesto() {
  find "$DIR/.claude" "$DIR/.specify" "$DIR/scripts" \
       "$DIR/CLAUDE.md" "$DIR/AGENTS.md" "$DIR/.cursorrules" \
       -type f 2>/dev/null \
    | LC_ALL=C sort | tr '\n' '\0' | xargs -0 -r sha256sum 2>/dev/null
}

CUR=$(manifesto)
HASH=$(printf '%s' "$CUR" | sha256sum | cut -c1-64)

echo "── superfície de instrução: $DIR"
echo "   $(printf '%s\n' "$CUR" | grep -c .) arquivo(s) · hash ${HASH:0:16}"
echo

NOVOS=""; MUDADOS=""
if [ -f "$MANI" ]; then
  ANT=$(cat "$MANI")
  NOVOS=$(comm -13 <(printf '%s\n' "$ANT" | awk '{ $1=""; print substr($0,2) }' | sort) \
                   <(printf '%s\n' "$CUR" | awk '{ $1=""; print substr($0,2) }' | sort))
  SUMIRAM=$(comm -23 <(printf '%s\n' "$ANT" | awk '{ $1=""; print substr($0,2) }' | sort) \
                     <(printf '%s\n' "$CUR" | awk '{ $1=""; print substr($0,2) }' | sort))
  MUDADOS=$(comm -13 <(printf '%s\n' "$ANT" | sort) <(printf '%s\n' "$CUR" | sort) \
            | awk '{ $1=""; print substr($0,2) }' | grep -Fxv -f <(printf '%s\n' "$NOVOS") 2>/dev/null)
  [ -n "$NOVOS" ]    && { echo "NOVOS:";     printf '%s\n' "$NOVOS"    | sed 's|^|   + |'; echo; }
  [ -n "$MUDADOS" ]  && { echo "ALTERADOS:"; printf '%s\n' "$MUDADOS"  | sed 's|^|   ~ |'; echo; }
  [ -n "$SUMIRAM" ]  && { echo "REMOVIDOS:"; printf '%s\n' "$SUMIRAM"  | sed 's|^|   - |'; echo; }
  [ -z "$NOVOS$MUDADOS$SUMIRAM" ] && echo "Nada mudou desde o último baseline."
else
  echo "Sem baseline anterior — esta é a primeira revisão."
  NOVOS=$(printf '%s\n' "$CUR" | awk '{ $1=""; print substr($0,2) }')
fi

ALVOS=$(printf '%s\n%s\n' "$NOVOS" "$MUDADOS" | grep -v '^$')
if [ -n "$ALVOS" ]; then
  echo "── varredura de padrões (nos arquivos novos e alterados)"
  ACHOU=0
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    h=$(grep -nEI \
      'curl|wget|\bnc\b|base64 -d|eval |\$\(|`.*`|/\.ssh|/\.aws|\.config/claude|settings\.local\.json|settings\.json|PreToolUse|PostToolUse|SessionStart|UserPromptSubmit|EXECUTE_COMMAND|rm -rf|chmod \+x' \
      "$f" 2>/dev/null | head -6)
    if [ -n "$h" ]; then
      ACHOU=1; echo "   ${f#$DIR/}"; printf '%s\n' "$h" | sed 's|^|      |'
    fi
    # caracteres invisíveis / homoglifos
    if LC_ALL=C grep -qP '[\x{200b}-\x{200f}\x{2060}-\x{206f}]' "$f" 2>/dev/null; then
      ACHOU=1; echo "   ${f#$DIR/}"; echo "      !! caractere invisível (largura zero) no arquivo"
    fi
  done <<< "$ALVOS"
  [ "$ACHOU" = 0 ] && echo "   nada de alto sinal."
  echo
fi

if [ "$MODO" = "--aprovar" ]; then
  printf '%s\n' "$HASH" > "$BASE"
  printf '%s\n' "$CUR"  > "$MANI"
  rm -f "${TMPDIR:-/tmp}"/tripwire-"$KEY"-* 2>/dev/null
  echo "APROVADO. Baseline gravado (${HASH:0:16})."
else
  echo "Read-only. Para aprovar:  tripwire-review \"$DIR\" --aprovar"
fi
