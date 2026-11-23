---
name: exemplo
description: Consulta o serviço EXEMPLO via REST API com curl, sem MCP. Autenticação por ~/.config/claude/exemplo.env. Use quando o usuário pedir para buscar ou ler itens do EXEMPLO. NÃO use para escrever/alterar nada no EXEMPLO (a skill é só leitura) nem para outros serviços.
---

# exemplo

> Modelo de skill de ACESSO do claudionor. Copie a pasta para `<raiz>/.claude/skills/<nome>/`, troque "exemplo" pelo serviço e apague esta nota.

**Leitura rápida:** `exemplo_busca "<termo>"` (comando tipado; ver `tipado --catalogo`).

## Credencial

`~/.config/claude/exemplo.env` (`chmod 600`, criar com `umask 177`):

```
EXEMPLO_URL=https://api.exemplo.com
EXEMPLO_TOKEN=...
```

## Comandos

```bash
exemplo.sh search "<termo>"   # JSON bruto da busca
exemplo.sh get <id>           # JSON bruto de um item
```

## Armadilhas

- (anote aqui o que a API faz de surpreendente: paginação, teto silencioso, campo que mente)
