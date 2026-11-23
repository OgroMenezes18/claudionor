# >>> claudionor >>>
# Gerado pelo instalar.sh do claudionor. Reinstalar substitui este bloco inteiro.
export PATH="$HOME/.local/bin:$PATH"
CLAUDIONOR_RAIZ="@@RAIZ@@"
CLAUDIONOR_CODIGO="@@CODIGO@@"   # pastas de repositórios, separadas por ':'

# ops — operação e análise: abre a sessão na raiz, sem sandbox.
alias ops='cd "$CLAUDIONOR_RAIZ" && claude'

# dev <repo|caminho> — construção de software: sandbox, rede em lista,
# credenciais negadas, escrita só no repositório e tripwire ligado.
dev() {
  [ -n "$1" ] || { echo "uso: dev <repo|caminho>   (procura em: $CLAUDIONOR_CODIGO)"; return 1; }
  local alvo="" base bases
  if [ -d "$1" ]; then
    alvo=$(cd "$1" && pwd)
  else
    IFS=':' read -r -a bases <<< "$CLAUDIONOR_CODIGO"
    for base in "${bases[@]}"; do
      [ -d "$base/$1" ] && { alvo="$base/$1"; break; }
    done
  fi
  [ -n "$alvo" ] || { echo "repositório não encontrado: $1   (procurei em: $CLAUDIONOR_CODIGO)"; return 1; }
  cd "$CLAUDIONOR_RAIZ" && CLAUDE_TRIPWIRE_DIR="$alvo" claude \
    --settings "$HOME/.claude/profiles/dev.json" \
    --add-dir "$alvo"
}
# <<< claudionor <<<
