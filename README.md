# claudionor

Núcleo de um harness para o [Claude Code](https://docs.claude.com/en/docs/claude-code): uma raiz única de onde toda sessão abre, dois perfis de sessão (`ops` e `dev`), comandos de leitura "tipados" que economizam contexto, um tripwire contra alteração silenciosa das instruções do agente e checkpoint automático dos repositórios. Vem com instalador e configurador.

É só o **mecanismo**. Skills, credenciais, URLs e regras do seu domínio ficam com você: o instalador cria os lugares onde elas entram e um modelo para começar.

## Instalar

```bash
git clone https://github.com/OgroMenezes18/claudionor.git
cd claudionor
./instalar.sh            # pergunta raiz, pastas de código e domínios extras
```

Sem perguntas: `./instalar.sh -y --raiz ~/claude --codigo ~/DEV/trabalho:~/DEV/pessoal --dominios nexus.minhaempresa.com`. Todas as opções em `./instalar.sh --help`.

Pode rodar de novo quando quiser: arquivo que muda ganha backup `<arquivo>.bak-<data>`, o bloco do `~/.bashrc` é substituído (não duplica), hooks já registrados não se repetem e os settings existentes são **mesclados**, nunca sobrescritos. O instalador não pede sudo, não grava credencial e não acessa a rede.

**Requisitos:** Linux, bash, `python3` ≥ 3.9, `git`, Claude Code ≥ 2.1.219 (o `strictAllowlist` do perfil `dev` exige). Recomendados: `bubblewrap` e `libseccomp2` (sandbox do perfil `dev` no Linux) e `jq`. Em macOS o sandbox usa outro mecanismo e não foi testado; Windows só via WSL.

## O que é instalado

| Peça | Onde | O que faz |
|---|---|---|
| Lançadores `ops` e `dev` | bloco `claudionor` no `~/.bashrc` | `ops` abre a sessão na raiz. `dev <repo>` abre com o perfil de desenvolvimento e `--add-dir` no repositório. |
| Perfil `dev` | `~/.claude/profiles/dev.json` | Sandbox estrito, rede só em lista (GitHub, PyPI, npm + seus extras), credenciais (`~/.ssh`, `~/.aws`, `~/.config/gh`, `~/.config/claude`) negadas, configuração da raiz somente leitura. |
| Settings de usuário | `~/.claude/settings.json` (mescla) | Hooks do tripwire (`PreToolUse`) e do checkpoint (`Stop`). Opcional: desliga skills, plugins e conectores sincronizados do claude.ai. |
| Settings de projeto | `<raiz>/.claude/settings.json` (mescla) | Modelo padrão, lista de modelos permitidos e a barra de status. |
| Comandos tipados | `<raiz>/.claude/bin/tipado.py` + symlinks em `~/.local/bin` | Despachante estilo busybox para comandos de leitura enxutos. |
| Tripwire | `~/.claude/hooks/tripwire.sh` + `tripwire-review` | Vigia a superfície de instrução do repositório aberto no `dev`. |
| Checkpoint | `~/.local/bin/ckpt` | Checkpoints e autosave em repositórios git, sem reescrever histórico. |
| Barra de status | `<raiz>/.claude/statusline.py` | Modelo, % de contexto, custo da sessão e uso do plano. |
| `CLAUDE.md` | `<raiz>/CLAUDE.md` (só se não existir) | Modelo com Contexto, Sistemas, regras e o catálogo de comandos gerado. |
| Modelo de skill | `<raiz>/.claude/skills/_modelo/` | Esqueleto de skill de acesso (`SKILL.md` + script que lê a credencial). |

## Como funciona

### Uma raiz, dois perfis

Toda sessão abre da mesma pasta (a raiz), que concentra a configuração. O que muda entre as sessões é a **postura**, não o diretório. `ops` é a sessão de operação e análise: consulta sistemas, lê chamados, roda os comandos tipados. `dev <repo>` é para construir software: sandbox, rede em lista, credenciais fora de alcance e escrita restrita ao repositório. A consequência é proposital: **dentro do `dev` não há `git push` nem `gh`** (sem `~/.ssh` nem token). Commit no `dev`; push e PR no `ops`. Se o build precisar de um host novo, acrescente em `allowedDomains` (ou reinstale com `--dominios`) em vez de desligar o `strictAllowlist`.

`dev` aceita nome do repositório (procura nas pastas de código, na ordem) ou caminho.

### Comandos tipados

Saída bruta de API é o que mais consome contexto, e ela é relida a cada turno. O `tipado.py` é um único arquivo que se comporta como vários comandos conforme o nome do symlink que o chamou. Cada comando chama o script da skill (dono da credencial e da API) e imprime só o que interessa, em linhas ou TSV, **sempre avisando quando corta**. `--full` devolve o bruto.

O claudionor traz o despachante e as utilidades (`opcoes`, `corta`, `tabela`, `cache_json`, `rodape`…), sem nenhum comando registrado. Para criar um:

1. Copie `.claude/skills/_modelo` para `.claude/skills/<serviço>/` e adapte o script.
2. Registre no `tipado.py`: em `ATALHOS`, se o script já imprime texto enxuto, ou como função `cmd_<nome>` em `COMANDOS`, se precisa formatar JSON. Há um modelo comentado na seção "como estender" do arquivo.
3. `tipado --links` cria os symlinks; `tipado --claude-md <raiz>/CLAUDE.md` atualiza o catálogo entre os marcadores `<!-- tipado:inicio -->` e `<!-- tipado:fim -->`.

A regra no `CLAUDE.md` ("para LER, chame o comando pelo nome") é o que faz o agente preferir o comando enxuto.

### Tripwire

Vigia por hash a **superfície de instrução** do repositório aberto no `dev`: `.claude/**`, `.specify/**`, `scripts/**`, `CLAUDE.md`, `AGENTS.md`, `.cursorrules`. Não vigia código: o que muda o tempo todo geraria aprovação no automático, que não protege nada.

O modelo é *trust-on-first-use*, como o `known_hosts` do ssh: na primeira vez grava o baseline e avisa; igual ao baseline, fica mudo (custo zero de contexto); diferente, bloqueia a **ação** (`Edit`, `Write`, `Bash`) com `exit 2`. Leitura e busca continuam liberadas, para dar para investigar sem sair da sessão. A aprovação é fora da sessão, de propósito, porque quem aprova é você e não o agente:

```bash
tripwire-review <repo>             # o que mudou + varredura de padrões de alto sinal
tripwire-review <repo> --aprovar   # grava o novo baseline
```

Falha aberta: qualquer erro interno do hook sai 0. Sessões `ops` não são afetadas (o hook só age com `CLAUDE_TRIPWIRE_DIR`, que a função `dev` exporta).

### Checkpoint (`ckpt`)

Fica fora de qualquer repositório, então sobrevive a qualquer volta. Nenhum comando reescreve histórico nem faz push: toda volta é um commit novo. `ckpt save`, `list`, `status`, `diff`, `back`, `to <ref>`, `undo`. A rede automática (`ckpt watch` no repositório) grava snapshots numa branch `autosave` sem tocar em HEAD, index ou árvore; o hook `Stop` chama `ckpt auto-all` ao fim de cada turno. `ckpt --help` lista tudo.

## Depois de instalar

1. Abra um terminal novo (ou `source ~/.bashrc`).
2. Preencha `<raiz>/CLAUDE.md`: quem você é, os sistemas que o agente consulta, as regras.
3. Credenciais: um arquivo por serviço em `~/.config/claude/<serviço>.env`, `chmod 600`. **Nunca** versione nem compartilhe.
4. Em cada repositório que quiser com rede de segurança: `ckpt watch`.
5. Primeira sessão `dev`: rode `/sandbox` para conferir o painel.

### Verificação

| Teste | Esperado |
|---|---|
| `ops` → `/status` | Settings de projeto e de usuário carregadas |
| `ops` → `/mcp` | Nenhum servidor sincronizado do claude.ai (se escolheu o corte) |
| `dev <repo>` → `/sandbox` | Sandbox ativo, rede em lista |
| `dev <repo>` → pedir para ler `~/.ssh/config` | Negado |
| `dev <repo>` → `curl https://example.com` | Negado pela rede |
| `dev <repo>` → primeira edição | Tripwire grava o baseline e avisa |
| Alterar `<repo>/.claude/settings.json` e tentar editar | Bloqueado até `tripwire-review <repo> --aprovar` |

## O que não vem (de propósito)

Credenciais, memória, transcrições, baselines do tripwire e `settings.local.json` são pessoais: cada um gera os seus. Skills de domínio e o `autoMode.environment` também ficam com quem usa. O instalador não remove nada; para desfazer, apague o bloco `# >>> claudionor >>>` do `~/.bashrc`, os dois hooks em `~/.claude/settings.json` e os arquivos da tabela acima (os backups `.bak-<data>` estão ao lado de cada um).

## Estrutura do repositório

```
instalar.sh                 instalador e configurador
nucleo/
  bin/tipado.py             despachante dos comandos tipados
  bin/ckpt                  checkpoint
  hooks/tripwire.sh         hook PreToolUse
  hooks/tripwire-review.sh  revisão e aprovação, fora da sessão
  statusline.py             barra de status
modelos/
  dev.json                  perfil dev (@@RAIZ@@, @@HOME@@, @@DOMINIOS@@)
  settings.projeto.json     settings da raiz
  bashrc.sh                 lançadores ops e dev
  CLAUDE.md                 modelo do contexto da raiz
  skill-exemplo/            esqueleto de skill de acesso
```
