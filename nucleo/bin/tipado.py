#!/usr/bin/python3 -I
"""Comandos tipados — chamada curta e saída enxuta para as skills de consulta.

Um único arquivo, despachado pelo nome com que foi chamado (estilo busybox):
cada comando é um symlink para este arquivo. Credencial e chamada à API ficam
nos scripts das skills (skills/<nome>/<nome>.sh); aqui só se escolhe o que
entra no contexto do modelo.

Regra comum a todos: a saída padrão é enxuta e diz quando cortou; `--full`
devolve o bruto do script, sem filtro nenhum.

    tipado --catalogo              lista os comandos com a assinatura
    tipado --nomes                 só os nomes (um por linha)
    tipado --links [DIR]           cria/atualiza os symlinks em bin/ e em DIR
                                   (padrão ~/.local/bin)
    tipado --claude-md ARQUIVO     reescreve o catálogo entre os marcadores
                                   <!-- tipado:inicio --> e <!-- tipado:fim -->
    tipado <comando> [args]        o mesmo que chamar o symlink

Para acrescentar um comando, veja a seção "como estender" no fim do arquivo.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from zoneinfo import ZoneInfo

BIN = os.path.dirname(os.path.realpath(__file__))
SKILLS = os.path.join(os.path.dirname(BIN), "skills")
CACHE = os.path.expanduser("~/.cache/claude-tipado")
SP = ZoneInfo(os.environ.get("TIPADO_TZ", "America/Sao_Paulo"))   # fuso de exibição


# ---------------------------------------------------------------- utilidades ---

def die(msg: str, code: int = 1) -> None:
    print(f"erro: {msg}", file=sys.stderr)
    sys.exit(code)


def skill(*partes: str) -> str:
    """Caminho de um script de skill: skill('jira', 'jira.sh')."""
    return os.path.join(SKILLS, *partes)


def run(cmd: list[str], env: dict | None = None) -> str:
    """Roda o script da skill; se falhar, repassa o erro e o código de saída."""
    p = subprocess.run(cmd, capture_output=True, text=True,
                       env={**os.environ, **(env or {})})
    if p.returncode != 0:
        sys.stderr.write(p.stderr or p.stdout)
        sys.exit(p.returncode)
    return p.stdout


def run_json(cmd: list[str], env: dict | None = None):
    out = run(cmd, env)
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        die(f"resposta não é JSON: {out[:300]}")


def corta(s: str, n: int) -> str:
    """Corta em n caracteres e AVISA quanto ficou de fora."""
    s = s.strip()
    return s if n <= 0 or len(s) <= n else s[:n].rstrip() + f" […+{len(s) - n}]"


def linha(s: str) -> str:
    """Achata texto multilinha numa linha só (⏎ marca a quebra)."""
    return re.sub(r"\s*\n\s*", " ⏎ ", s.strip())


def opcoes(argv: list[str], flags: dict[str, object]) -> tuple[list[str], dict]:
    """Separa --flag [valor] dos posicionais. flags = {nome: padrão}; bool não leva valor."""
    pos, op = [], dict(flags)
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and a[2:] in flags:
            k = a[2:]
            if isinstance(flags[k], bool):
                op[k] = True
            else:
                i += 1
                if i >= len(argv):
                    die(f"{a} precisa de valor")
                op[k] = type(flags[k])(argv[i])
        else:
            pos.append(a)
        i += 1
    return pos, op


def cache_json(nome: str, idade_max: int, carregar):
    """Guarda em ~/.cache/claude-tipado/<nome> o que muda pouco (diretórios, campos)."""
    os.makedirs(CACHE, mode=0o700, exist_ok=True)
    arq = os.path.join(CACHE, nome)
    if os.path.exists(arq) and time.time() - os.path.getmtime(arq) < idade_max:
        with open(arq) as f:
            return json.load(f)
    dado = carregar()
    with open(arq, "w") as f:
        json.dump(dado, f, ensure_ascii=False)
    return dado


def celula(v) -> str:
    if v is None:
        return ""
    if isinstance(v, float):
        return f"{v:.6g}"
    if isinstance(v, (list, dict)):
        return json.dumps(v, ensure_ascii=False, separators=(",", ":"))
    return linha(str(v))


def tabela(colunas: list[str], linhas: list[list], larg: int = 300) -> str:
    """TSV com cabeçalho; cada célula cortada em `larg` caracteres."""
    out = ["\t".join(colunas)]
    out += ["\t".join(corta(celula(x), larg) for x in r) for r in linhas]
    return "\n".join(out)


def data_curta(s: str | None) -> str:
    """ISO 8601 -> "29/09/26 11:05". Com offset, mantém a hora local; com Z (UTC), converte para SP."""
    if not s or len(s) < 16:
        return s or ""
    if s.endswith("Z"):
        return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(SP).strftime("%d/%m/%y %H:%M")
    return f"{s[8:10]}/{s[5:7]}/{s[2:4]} {s[11:16]}"


def html_texto(html: str) -> str:
    """HTML (inclusive storage do Confluence) -> texto com títulos, listas e tabelas legíveis."""
    from html.parser import HTMLParser

    class P(HTMLParser):
        def __init__(self):
            super().__init__(convert_charrefs=True)
            self.out, self.pilha = [], []

        def handle_starttag(self, tag, attrs):
            a = dict(attrs)
            if tag in ("p", "div", "br", "tr"):
                self.out.append("\n")
            elif re.fullmatch(r"h[1-6]", tag):
                self.out.append("\n" + "#" * int(tag[1]) + " ")
            elif tag == "li":
                self.out.append("\n- ")
            elif tag in ("td", "th"):
                self.out.append(" | ")
            elif tag == "ac:structured-macro":
                self.out.append(f"\n[{a.get('ac:name', 'macro')}] ")
            elif tag == "ri:page":
                self.out.append(a.get("ri:content-title", ""))
            elif tag == "ri:attachment":
                self.out.append(f"[anexo {a.get('ri:filename', '')}]")
            elif tag == "a" and a.get("href"):
                self.pilha.append((a["href"], len(self.out)))
            if tag == "ac:parameter":
                self.out.append("(")

        def handle_endtag(self, tag):
            if tag == "a" and self.pilha:
                href, ini = self.pilha.pop()
                if href not in "".join(self.out[ini:]):      # texto do link já é a URL
                    self.out.append(f" ({href})")
            elif tag == "ac:parameter":
                self.out.append(") ")
            elif re.fullmatch(r"h[1-6]|p|table|ul|ol", tag):
                self.out.append("\n")

        def handle_data(self, data):
            self.out.append(data)

        def unknown_decl(self, data):                   # <![CDATA[ ... ]]> de bloco de código
            self.out.append("\n" + data.removeprefix("CDATA[") + "\n")

    p = P()
    p.feed(html or "")
    t = re.sub(r"[ \t]+\n", "\n", "".join(p.out))
    return re.sub(r"\n{3,}", "\n\n", t).strip()


def rodape(total: int, mostrados: int, dica: str = "--limite N") -> str:
    cab = f"# {total} linhas"
    if total > mostrados:
        cab += f", mostrando {mostrados} ({dica})"
    return cab


# ------------------------------------------------------------ como estender ---
#
# Comandos de uma conexão moram NA SKILL: skills/<nome>/tipado_cmds.py, com os
# dicionários COMANDOS e ATALHOS no mesmo formato dos daqui. O arquivo é
# carregado na partida e enxerga todas as utilidades acima (die, run, opcoes,
# tabela, data_curta, html_texto…) mais SKILL_DIR, a pasta da própria skill.
# Assim cada conexão é autocontida: copiou a pasta, ganhou os comandos.
#
# Há dois jeitos de registrar um comando.
#
# 1) ATALHO — o script da skill já imprime texto enxuto; o atalho só tira o
#    caminho e o `cd` da chamada. Entrada:
#       "nome": ("pasta/script.sh", [prefixo de args], {env extra}, "assinatura  — o que faz")
#
# 2) COMANDO — o script devolve JSON grande e aqui se escolhe o que mostrar.
#    Escreva uma função cmd_<nome>(argv) cuja docstring é a assinatura que vai
#    para o catálogo, e registre em COMANDOS. Modelo:
#
#    def cmd_exemplo_busca(argv):
#        """exemplo_busca "<termo>" [--limite N] [--full]  — id, data e título"""
#        pos, op = opcoes(argv, {"limite": 20, "full": False})
#        if len(pos) != 1:
#            die('uso: exemplo_busca "<termo>" [--limite N] [--full]')
#        script = os.path.join(SKILL_DIR, "exemplo.sh")   # num tipado_cmds.py
#        if op["full"]:
#            sys.stdout.write(run([script, "search", pos[0]]))
#            return
#        itens = run_json([script, "search", pos[0]]).get("items") or []
#        linhas = [[i.get("id"), i.get("updated"), i.get("title")] for i in itens[: op["limite"]]]
#        print(tabela(["id", "data", "titulo"], linhas, 120))
#        print(rodape(len(itens), len(linhas)))
#
# Depois:  tipado --links   (cria o symlink)  e
#          tipado --claude-md <raiz>/CLAUDE.md   (atualiza o catálogo).
#
# Regras que mantêm o ganho de token:
#   - nunca imprimir JSON bruto fora do --full;
#   - todo corte avisa ("[…+N]", "mostrando X de Y");
#   - número redondo no total (100, 1000…) costuma ser teto da API: avise.

ATALHOS: dict[str, tuple[str, list[str], dict, str]] = {
    # "gmail_busca": ("gmail/gmail.sh", ["search"], {}, 'gmail_busca "<query>" [max]  — id | data | de | assunto'),
}

COMANDOS: dict = {
    # "exemplo_busca": cmd_exemplo_busca,
}


# ------------------------------------------------- comandos vindos das skills ---

def carregar_skills() -> None:
    """Mescla o COMANDOS/ATALHOS de cada skills/*/tipado_cmds.py. Skill com erro avisa e é pulada."""
    if not os.path.isdir(SKILLS):
        return
    base = {k: v for k, v in globals().items()
            if not k.startswith("__") and k not in ("COMANDOS", "ATALHOS")}
    for nome in sorted(os.listdir(SKILLS)):
        arq = os.path.join(SKILLS, nome, "tipado_cmds.py")
        if not os.path.isfile(arq):
            continue
        ns = dict(base, __name__=f"tipado_{nome}", __file__=arq,
                  SKILL_DIR=os.path.dirname(os.path.realpath(arq)))
        try:
            with open(arq) as f:
                exec(compile(f.read(), arq, "exec"), ns)
        except Exception as e:  # uma skill quebrada não derruba os outros comandos
            print(f"aviso: {arq} não carregou ({type(e).__name__}: {e})", file=sys.stderr)
            continue
        for k, v in (ns.get("ATALHOS") or {}).items():
            # caminho do atalho é relativo à própria skill
            ATALHOS[k] = (os.path.join(nome, v[0]), *v[1:])
        COMANDOS.update(ns.get("COMANDOS") or {})


carregar_skills()


# ---------------------------------------------------------------- despacho ---

def catalogo() -> list[str]:
    linhas = [fn.__doc__.strip() for fn in COMANDOS.values()]
    linhas += [a[3] for a in ATALHOS.values()]
    return linhas


def nomes() -> list[str]:
    return [*COMANDOS, *ATALHOS]


def criar_links(destino: str) -> None:
    alvo = os.path.realpath(__file__)
    os.makedirs(destino, exist_ok=True)
    for pasta in (BIN, destino):
        for n in ["tipado", *nomes()]:
            lnk = os.path.join(pasta, n)
            if os.path.lexists(lnk):
                if not os.path.islink(lnk):
                    print(f"pulado (arquivo de verdade, não symlink): {lnk}", file=sys.stderr)
                    continue
                os.remove(lnk)
            os.symlink("tipado.py" if pasta == BIN else os.path.join(BIN, n), lnk)
    # remove symlinks órfãos de comandos que saíram do registro
    validos = {"tipado", *nomes()}
    for pasta in (BIN, destino):
        for n in os.listdir(pasta):
            lnk = os.path.join(pasta, n)
            if n in validos or not os.path.islink(lnk):
                continue
            real = os.path.realpath(lnk)
            if real == alvo and pasta == BIN:
                os.remove(lnk)
            elif pasta == destino and os.path.dirname(os.readlink(lnk)) == BIN:
                os.remove(lnk)
    print(f"{len(nomes())} comando(s) ligados em {BIN} e {destino}")


def atualizar_claude_md(arq: str) -> None:
    ini, fim = "<!-- tipado:inicio -->", "<!-- tipado:fim -->"
    with open(arq) as f:
        txt = f.read()
    if ini not in txt or fim not in txt:
        die(f"{arq} não tem os marcadores {ini} / {fim}")
    corpo = "\n".join(catalogo()) or "(nenhum comando registrado ainda)"
    bloco = f"{ini}\n```\n{corpo}\n```\n{fim}"
    novo = re.sub(re.escape(ini) + r".*?" + re.escape(fim), lambda _: bloco, txt, flags=re.S)
    with open(arq, "w") as f:
        f.write(novo)
    print(f"catálogo atualizado em {arq} ({len(catalogo())} comando(s))")


def atalho(nome: str, argv: list[str]) -> None:
    script, prefixo, env, _ = ATALHOS[nome]
    caminho = skill(script)
    if not os.path.exists(caminho):
        die(f"script da skill não encontrado: {caminho}")
    os.execve(caminho, [caminho] + prefixo + argv, {**os.environ, **env})


def main() -> None:
    nome = os.path.basename(sys.argv[0]).removesuffix(".py")
    argv = sys.argv[1:]
    if nome == "tipado":
        if argv[:1] == ["--catalogo"]:
            print("\n".join(catalogo()) or "(nenhum comando registrado ainda)")
            return
        if argv[:1] == ["--nomes"]:
            print("\n".join(nomes()))
            return
        if argv[:1] == ["--links"]:
            criar_links(os.path.expanduser(argv[1] if len(argv) > 1 else "~/.local/bin"))
            return
        if argv[:1] == ["--claude-md"]:
            if len(argv) < 2:
                die("uso: tipado --claude-md <arquivo>")
            atualizar_claude_md(argv[1])
            return
        if not argv or argv[0] in ("-h", "--help"):
            print(__doc__.strip())
            return
        if argv[0] not in COMANDOS and argv[0] not in ATALHOS:
            die(f"comando desconhecido: {argv[0]}  (tipado --catalogo)")
        nome, argv = argv[0], argv[1:]
    if nome in ATALHOS:
        if argv[:1] in (["-h"], ["--help"]):
            print(ATALHOS[nome][3])
            return
        atalho(nome, argv)
    fn = COMANDOS.get(nome)
    if not fn:
        die(f"comando desconhecido: {nome}")
    if argv[:1] in (["-h"], ["--help"]):
        print(fn.__doc__.strip())
        return
    fn(argv)


if __name__ == "__main__":
    main()
