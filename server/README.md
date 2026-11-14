# Servidor de salas (multiplayer)

Sala, sinalização WebRTC e relay binário. Contrato em `docs/multiplayer.md` (seções 4 e 5).

- `rooms.js`: lógica de uma sala, neutra de runtime (sem estado, sem imports).
- `server.js`: entrada local em Bun. `worker.js` + `wrangler.toml`: entrada de produção (Cloudflare Workers + Durable Objects).
- `config.js`: limites. `check.js`: roteiro de conferência do protocolo. `rooms.test.js`: testes.

Todos os comandos rodam a partir de `server/`. Sem dependências npm.

## Rodar local

    bun server.js --port 8787        # ws://localhost:8787/ws

## Testar

    bun test                                         # lógica, sem rede
    bun check.js ws://localhost:8787/ws              # protocolo contra um servidor no ar
    bun check.js wss://javali-salas.acpw01.workers.dev/ws --origin https://italocassio.github.io --idle 30

`--idle N` espera N segundos com a sala aberta e confere que ela continua repassando (hibernação).
Contra produção, `--origin` é obrigatório (sem ele o servidor responde 403).

## Publicar

    bun x wrangler deploy

Precisa de `wrangler login` feito e de um subdomínio `workers.dev` registrado na conta
(painel do Cloudflare, Workers, Onboarding). A origem aceita fica em `ALLOWED_ORIGINS` no `wrangler.toml`.

Observação: `wrangler dev` não funciona sob Bun (o Miniflare responde 503); use `bun server.js` para o
desenvolvimento local.

URL de produção: `wss://javali-salas.acpw01.workers.dev/ws`
