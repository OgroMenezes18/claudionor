#!/usr/bin/env bash
# claudionor — instalador e configurador do núcleo do harness para o Claude Code.
#
#   ./instalar.sh                      pergunta tudo (Enter aceita o padrão)
#   ./instalar.sh -y                   aceita todos os padrões, sem perguntar
#   ./instalar.sh --raiz ~/claude --codigo ~/DEV/trabalho:~/DEV/pessoal \
#                 --dominios nexus.minhaempresa.com --sem-corte-nuvem
#
# Opções:
#   --raiz DIR          raiz da sessão (de onde o Claude Code é sempre aberto)
#   --codigo DIRS       pastas de repositórios, separadas por ':'
#   --dominios LISTA    domínios extras liberados na rede do perfil dev (vírgula)
#   --sem-corte-nuvem   não desliga a sincronização de skills/plugins/conectores do claude.ai
#   --forcar            sobrescreve um tipado.py já existente (com backup)
#   -y, --sim           não pergunta; usa padrões e o que vier nas opções
#
# Pode rodar de novo quantas vezes quiser: arquivo que muda ganha backup
# <arquivo>.bak-<data>, o bloco do ~/.bashrc é substituído, hooks não duplicam.
# Nada aqui pede sudo, grava credencial ou acessa a rede.
set -euo pipefail

AQUI=$(cd "$(dirname "$0")" && pwd)
DATA=$(date +%Y%m%d-%H%M%S)

RAIZ="" CODIGO="" DOMINIOS="" CORTE=1 FORCAR=0 SIM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --raiz)            RAIZ="${2:?--raiz precisa de valor}"; shift 2 ;;
    --codigo)          CODIGO="${2:?--codigo precisa de valor}"; shift 2 ;;
    --dominios)        DOMINIOS="${2-}"; shift 2 ;;
    --sem-corte-nuvem) CORTE=0; shift ;;
    --forcar)          FORCAR=1; shift ;;
    -y|--sim)          SIM=1; shift ;;
    -h|--help)         awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "opção desconhecida: $1   (./instalar.sh --help)" >&2; exit 1 ;;
  esac
done

# ------------------------------------------------------------------ saída ---
if [ -t 1 ]; then B=$'\033[1m'; V=$'\033[32m'; A=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'
else B="" V="" A="" R="" D="" N=""; fi
titulo() { printf '\n%s== %s%s\n' "$B" "$1" "$N"; }
ok()     { printf '  %s✓%s %s\n' "$V" "$N" "$1"; }
aviso()  { printf '  %s!%s %s\n' "$A" "$N" "$1"; }
falha()  { printf '  %s✗%s %s\n' "$R" "$N" "$1"; }
morre()  { falha "$1"; exit 1; }

pergunta() {   # pergunta VAR "texto" "padrão"
  local var="$1" txt="$2" pad="$3" resp=""
  if [ -n "${!var}" ] || [ "$SIM" = 1 ]; then
    [ -n "${!var}" ] || printf -v "$var" '%s' "$pad"
    return
  fi
  read -r -p "  $txt [${pad}]: " resp </dev/tty || true
  printf -v "$var" '%s' "${resp:-$pad}"
}

sim_nao() {    # sim_nao "texto" padrão(s|n) → 0 = sim
  local txt="$1" pad="$2" resp=""
  [ "$SIM" = 1 ] && { [ "$pad" = s ]; return; }
  read -r -p "  $txt [$([ "$pad" = s ] && echo S/n || echo s/N)]: " resp </dev/tty || true
  resp=${resp:-$pad}
  [[ "$resp" =~ ^[sSyY] ]]
}

expande() { local p="${1/#\~/$HOME}"; printf '%s' "${p%/}"; }

# Copia src → dst; se dst existe e é diferente, guarda backup antes.
instala() {    # instala SRC DST MODO
  local src="$1" dst="$2" modo="$3"
  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    ok "igual, mantido: ${dst/#$HOME/\~}"; return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    cp -P "$dst" "$dst.bak-$DATA"
    aviso "backup: ${dst/#$HOME/\~}.bak-$DATA"
  fi
  install -m "$modo" "$src" "$dst"
  ok "instalado: ${dst/#$HOME/\~}"
}

# ------------------------------------------------------------ pré-requisitos ---
titulo "Pré-requisitos"
[ "$(uname -s)" = Linux ] || aviso "feito e testado em Linux; em macOS o sandbox do perfil dev usa outro mecanismo (testar)."
for c in python3 git; do
  command -v "$c" >/dev/null || morre "falta $c (obrigatório)"
done
python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' || morre "python3 ≥ 3.9 é obrigatório"
ok "python3 $(python3 -c 'import platform; print(platform.python_version())'), git $(git --version | awk '{print $3}')"
command -v claude >/dev/null && ok "claude $(claude --version 2>/dev/null | awk '{print $1}')" \
  || aviso "claude não está no PATH — instale o Claude Code antes de usar (o resto se instala igual)."
command -v bwrap >/dev/null && ok "bubblewrap (sandbox do perfil dev)" \
  || aviso "bubblewrap ausente: o perfil dev não terá sandbox em Linux (apt install bubblewrap libseccomp2)."
command -v jq >/dev/null || aviso "jq ausente: as skills costumam usar (apt install jq)."

# ---------------------------------------------------------------- parâmetros ---
titulo "Configuração"
pergunta RAIZ     "Raiz da sessão (de onde o Claude Code sempre abre)" "~/claude"
pergunta CODIGO   "Pastas de repositórios (separe por ':')"            "~/DEV"
[ "$SIM" = 1 ] || [ -n "$DOMINIOS" ] || \
  pergunta DOMINIOS "Domínios extras para a rede do perfil dev (vírgula; Enter = nenhum)" ""
RAIZ=$(expande "$RAIZ")
CODIGO=$(IFS=':'; out=""; for d in $CODIGO; do out="${out:+$out:}$(expande "$d")"; done; printf '%s' "$out")
case "$RAIZ" in /*) ;; *) morre "a raiz precisa ser um caminho absoluto: $RAIZ" ;; esac
if [ "$SIM" = 0 ] && [ "$CORTE" = 1 ]; then
  sim_nao "Desligar skills/plugins/conectores sincronizados do claude.ai (tudo local)?" s || CORTE=0
fi
printf '  %sraiz%s     %s\n  %scódigo%s   %s\n  %sdomínios%s %s\n  %snuvem%s    %s\n' \
  "$D" "$N" "$RAIZ" "$D" "$N" "$CODIGO" "$D" "$N" "${DOMINIOS:-(nenhum extra)}" \
  "$D" "$N" "$([ "$CORTE" = 1 ] && echo 'sincronização do claude.ai desligada' || echo 'mantida como está')"
[ "$SIM" = 1 ] || sim_nao "Seguir com a instalação?" s || { echo "  cancelado."; exit 0; }

# Parâmetros para os renderizadores em Python (sem interpolar em código).
export CLAUDIONOR_RAIZ="$RAIZ" CLAUDIONOR_CODIGO="$CODIGO" CLAUDIONOR_DOMINIOS="$DOMINIOS" \
       CLAUDIONOR_CORTE="$CORTE" CLAUDIONOR_HOME="$HOME"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

render() {     # render MODELO SAIDA — troca @@RAIZ@@ @@CODIGO@@ @@HOME@@ @@DOMINIOS@@
  python3 -I - "$1" "$2" <<'PY'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
base = ["github.com", "api.github.com", "raw.githubusercontent.com", "codeload.github.com",
        "objects.githubusercontent.com", "pypi.org", "files.pythonhosted.org",
        "registry.npmjs.org", "*.npmjs.org"]
extra = [d.strip() for d in os.environ["CLAUDIONOR_DOMINIOS"].split(",") if d.strip()]
atual = os.path.join(os.environ["CLAUDIONOR_HOME"], ".claude/profiles/dev.json")
if not extra and os.path.exists(atual):   # reinstalação sem --dominios: mantém os extras de antes
    try:
        extra = json.load(open(atual))["sandbox"]["network"]["allowedDomains"]
    except Exception:
        extra = []
dominios = base + [d for d in extra if d not in base]
txt = open(src).read()
for k, v in {"@@RAIZ@@": os.environ["CLAUDIONOR_RAIZ"],
             "@@CODIGO@@": os.environ["CLAUDIONOR_CODIGO"],
             "@@HOME@@": os.environ["CLAUDIONOR_HOME"],
             "@@DOMINIOS@@": json.dumps(dominios, indent=8).replace("\n]", "\n      ]")}.items():
    txt = txt.replace(k, v)
if dst.endswith(".json"):
    json.loads(txt)   # falha aqui se o modelo gerar JSON inválido
open(dst, "w").write(txt)
PY
}

# -------------------------------------------------------------------- pastas ---
titulo "Pastas"
mkdir -p "$RAIZ/.claude/bin" "$RAIZ/.claude/skills" "$HOME/.claude/hooks" \
         "$HOME/.claude/profiles" "$HOME/.claude/tripwire" "$HOME/.config/ckpt" "$HOME/.local/bin"
mkdir -p "$HOME/.config/claude" && chmod 700 "$HOME/.config/claude"
IFS=':' read -r -a _pastas <<< "$CODIGO"
for d in "${_pastas[@]}"; do [ -d "$d" ] || { mkdir -p "$d"; aviso "criada: ${d/#$HOME/\~}"; }; done
ok "raiz, ~/.claude/{hooks,profiles,tripwire}, ~/.config/{claude,ckpt}, ~/.local/bin"

# -------------------------------------------------------------------- núcleo ---
titulo "Núcleo"
TIPADO="$RAIZ/.claude/bin/tipado.py"
if [ -f "$TIPADO" ] && ! cmp -s "$AQUI/nucleo/bin/tipado.py" "$TIPADO" && [ "$FORCAR" = 0 ]; then
  aviso "já existe um tipado.py diferente em ${TIPADO/#$HOME/\~} — mantido (os comandos registrados nele"
  aviso "seriam perdidos). Para trocar pelo do claudionor: --forcar (faz backup)."
else
  instala "$AQUI/nucleo/bin/tipado.py" "$TIPADO" 755
fi
python3 -I "$TIPADO" --links "$HOME/.local/bin" >/dev/null 2>&1 \
  && ok "comandos tipados ligados em .claude/bin e ~/.local/bin" \
  || aviso "tipado.py existente não tem --links: ligue os symlinks como antes."
instala "$AQUI/nucleo/statusline.py"              "$RAIZ/.claude/statusline.py"          755
instala "$AQUI/nucleo/bin/ckpt"                   "$HOME/.local/bin/ckpt"               755
instala "$AQUI/nucleo/hooks/tripwire.sh"          "$HOME/.claude/hooks/tripwire.sh"        755
instala "$AQUI/nucleo/hooks/tripwire-review.sh"   "$HOME/.claude/hooks/tripwire-review.sh" 755
ln -sfn "$HOME/.claude/hooks/tripwire-review.sh" "$HOME/.local/bin/tripwire-review"
ok "tripwire-review no PATH"
[ -d "$RAIZ/.claude/skills/_modelo" ] || { cp -r "$AQUI/modelos/skill-exemplo" "$RAIZ/.claude/skills/_modelo"
  ok "modelo de skill em .claude/skills/_modelo (copie e renomeie para criar uma)"; }

# ------------------------------------------------------------------ settings ---
titulo "Settings"
render "$AQUI/modelos/dev.json" "$TMP/dev.json"
instala "$TMP/dev.json" "$HOME/.claude/profiles/dev.json" 644

# Mescla: acrescenta o que falta, nunca apaga o que a pessoa já tem.
mescla() {     # mescla ARQUIVO MODO(projeto|usuario) MODELO_RENDERIZADO
  local arq="$1"
  [ -f "$arq" ] && cp "$arq" "$arq.bak-$DATA"
  python3 -I - "$@" <<'PY'
import json, os, sys
arq, modo = sys.argv[1], sys.argv[2]
try:
    atual = json.load(open(arq)) if os.path.exists(arq) and os.path.getsize(arq) else {}
except json.JSONDecodeError as e:
    sys.exit(f"JSON inválido em {arq}: {e} — corrija e rode de novo")
mudou = []
if modo == "projeto":
    for k, v in json.load(open(sys.argv[3])).items():
        if k not in atual:
            atual[k] = v; mudou.append(k)
else:
    hooks = atual.setdefault("hooks", {})
    novos = {
        "PreToolUse": {"matcher": "Edit|Write|NotebookEdit|Bash", "hooks": [{
            "type": "command", "command": "\"$HOME/.claude/hooks/tripwire.sh\"",
            "timeout": 10, "statusMessage": "tripwire"}]},
        "Stop": {"hooks": [{
            "type": "command",
            "command": "[ -x \"$HOME/.local/bin/ckpt\" ] && \"$HOME/.local/bin/ckpt\" auto-all >/dev/null 2>&1 || true",
            "timeout": 10, "statusMessage": "checkpoint automatico"}]},
    }
    for evento, grupo in novos.items():
        lista = hooks.setdefault(evento, [])
        chave = "tripwire.sh" if evento == "PreToolUse" else "ckpt\" auto-all"
        if not any(chave in h.get("command", "") for g in lista for h in g.get("hooks", [])):
            lista.append(grupo); mudou.append(f"hook {evento}")
    if os.environ["CLAUDIONOR_CORTE"] == "1":
        for k, v in {"syncClaudeAiSkills": False, "syncClaudeAiPlugins": False,
                     "disableClaudeAiConnectors": True}.items():
            if atual.get(k) != v:
                atual[k] = v; mudou.append(k)
json.dump(atual, open(arq, "w"), ensure_ascii=False, indent=2)
open(arq, "a").write("\n")
print(", ".join(mudou) if mudou else "")
PY
}
render "$AQUI/modelos/settings.projeto.json" "$TMP/projeto.json"
m=$(mescla "$RAIZ/.claude/settings.json" projeto "$TMP/projeto.json")
ok "projeto ${RAIZ/#$HOME/\~}/.claude/settings.json: ${m:-nada a acrescentar}"
m=$(mescla "$HOME/.claude/settings.json" usuario)
ok "usuário ~/.claude/settings.json: ${m:-nada a acrescentar}"
for f in "$RAIZ/.claude/settings.json" "$HOME/.claude/settings.json"; do
  [ -f "$f.bak-$DATA" ] && cmp -s "$f" "$f.bak-$DATA" && rm -f "$f.bak-$DATA"
done

# ----------------------------------------------------------------- CLAUDE.md ---
titulo "CLAUDE.md"
if [ -f "$RAIZ/CLAUDE.md" ]; then
  if grep -q '<!-- tipado:inicio -->' "$RAIZ/CLAUDE.md"; then
    python3 -I "$TIPADO" --claude-md "$RAIZ/CLAUDE.md" >/dev/null 2>&1 || true
    ok "existente, catálogo de comandos atualizado"
  else
    aviso "existente, mantido. Para o catálogo automático, inclua os marcadores (ver modelos/CLAUDE.md)."
  fi
else
  render "$AQUI/modelos/CLAUDE.md" "$RAIZ/CLAUDE.md"
  ok "criado a partir do modelo — preencha Contexto e Sistemas"
fi

# ------------------------------------------------------------------- bashrc ---
titulo "Lançadores (~/.bashrc)"
render "$AQUI/modelos/bashrc.sh" "$TMP/bloco.sh"
bash -n "$TMP/bloco.sh" || morre "bloco do bashrc gerado com erro de sintaxe"
RC="$HOME/.bashrc"; touch "$RC"
python3 -I - "$RC" "$TMP/bloco.sh" <<'PY'
import re, sys
rc, bloco = sys.argv[1], open(sys.argv[2]).read().rstrip("\n")
txt = open(rc).read()
ini, fim = "# >>> claudionor >>>", "# <<< claudionor <<<"
if ini in txt and fim in txt:
    txt = re.sub(re.escape(ini) + r".*?" + re.escape(fim), lambda _: bloco, txt, flags=re.S)
else:
    txt = txt.rstrip("\n") + "\n\n" + bloco + "\n"
open(rc, "w").write(txt)
PY
ok "bloco claudionor em ~/.bashrc (aliases ops e dev)"

# -------------------------------------------------------------- verificação ---
titulo "Verificação"
erros=0
for f in "$HOME/.claude/settings.json" "$RAIZ/.claude/settings.json" "$HOME/.claude/profiles/dev.json"; do
  python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" && ok "JSON válido: ${f/#$HOME/\~}" \
    || { falha "JSON inválido: $f"; erros=1; }
done
for f in "$HOME/.local/bin/ckpt" "$HOME/.claude/hooks/tripwire.sh" "$HOME/.claude/hooks/tripwire-review.sh"; do
  bash -n "$f" || { falha "sintaxe: $f"; erros=1; }
done
python3 -I "$TIPADO" --catalogo >/dev/null && ok "tipado responde" || { falha "tipado não roda"; erros=1; }
CLAUDE_TRIPWIRE_DIR="" bash "$HOME/.claude/hooks/tripwire.sh" </dev/null && ok "tripwire mudo fora do dev" \
  || { falha "tripwire deveria sair 0 sem CLAUDE_TRIPWIRE_DIR"; erros=1; }
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) aviso "~/.local/bin ainda não está no PATH desta janela (o bloco do bashrc resolve)";; esac
[ "$erros" = 0 ] || morre "instalação terminou com erro — veja acima"

titulo "Pronto"
cat <<EOF
  1. Abra um terminal novo (ou: source ~/.bashrc).
  2. ${B}ops${N}            — sessão de operação na raiz (${RAIZ/#$HOME/\~})
     ${B}dev <repo>${N}     — sessão de desenvolvimento com sandbox (procura em ${CODIGO//$HOME/\~})
  3. Preencha ${RAIZ/#$HOME/\~}/CLAUDE.md (Contexto e Sistemas).
  4. Para a rede automática de checkpoint num repositório:  cd <repo> && ckpt watch
  5. Skill nova: copie .claude/skills/_modelo, registre o comando no tipado.py,
     rode  tipado --links  e  tipado --claude-md ${RAIZ/#$HOME/\~}/CLAUDE.md
  Primeira sessão dev: rode /sandbox para conferir o painel.
EOF
