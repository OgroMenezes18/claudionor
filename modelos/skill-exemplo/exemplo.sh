#!/usr/bin/env bash
# Modelo de script de skill de acesso: lê a credencial, chama a API, imprime JSON.
# O tipado.py formata; este script só fala com a API.
set -euo pipefail
ENV="$HOME/.config/claude/exemplo.env"
[ -f "$ENV" ] || { echo "falta $ENV (ver SKILL.md)" >&2; exit 2; }
# shellcheck disable=SC1090
source "$ENV"
: "${EXEMPLO_URL:?defina EXEMPLO_URL em $ENV}" "${EXEMPLO_TOKEN:?defina EXEMPLO_TOKEN em $ENV}"

api() { curl -fsS -H "Authorization: Bearer $EXEMPLO_TOKEN" "$EXEMPLO_URL$1"; }

case "${1:-}" in
  search) api "/search?q=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "${2:?termo}")" ;;
  get)    api "/items/${2:?id}" ;;
  *)      echo "uso: exemplo.sh search <termo> | get <id>" >&2; exit 1 ;;
esac
