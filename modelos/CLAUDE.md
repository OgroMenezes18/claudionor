# Workspace — Configuração Global

Este diretório é a **raiz da sessão**: toda sessão do Claude Code abre daqui (`ops` ou `dev <repo>`), e é aqui que mora a configuração — skills, permissões, regras.

## Contexto

<!-- Quem é você, onde trabalha, em que domínio. Uma linha por item. -->
- Empresa / time:
- O que faço:

## Sistemas e documentação

<!-- URLs dos sistemas que o agente vai consultar (chamados, wiki, repositórios, chat). -->
| Sistema | Para quê | URL |
|---------|----------|-----|
|         |          |     |

## Estrutura

```
@@RAIZ@@/               ← raiz da sessão: SEMPRE lançar daqui
├── CLAUDE.md           ← este arquivo
└── .claude/
    ├── settings.json   ← modelo, statusLine
    ├── bin/            ← comandos tipados (tipado.py + symlinks)
    └── skills/         ← skills (uma pasta por skill)
```

Repositórios de código ficam FORA da raiz, em: @@CODIGO@@

## Regras de operação (obrigatórias)

1. **Skill nova vai para `./.claude/skills/`.** A `description` decide quando ela dispara: escreva **quando usar** e **quando NÃO usar**.
2. **Configuração mora na raiz.** Tudo que muda o comportamento da sessão pertence a `.claude/` desta pasta.
3. **Código fica fora daqui.** Para trabalhar num repositório: `dev <repo>` (sandbox + `--add-dir`). Commit no `dev`; push e PR no `ops`.
4. **Credencial nunca no repositório nem na conversa.** Um arquivo por serviço em `~/.config/claude/<serviço>.env`, `chmod 600`. Nunca imprimir o conteúdo.
5. **Leitura passa pelo comando tipado.** Para LER, chame o comando pelo nome (está no PATH), sem `cd` nem caminho do `.sh`. A saída já é enxuta e avisa quando corta; `--full` devolve o bruto. Escrita continua pelo `.sh` da skill.
6. **Checkpoint antes de mudança estrutural.** Repositórios vigiados pelo `ckpt` têm rede automática; o que não é git precisa de backup manual.

## Comandos tipados

Gerado por `tipado --claude-md @@RAIZ@@/CLAUDE.md` — não editar à mão.

<!-- tipado:inicio -->
```
(nenhum comando registrado ainda)
```
<!-- tipado:fim -->
