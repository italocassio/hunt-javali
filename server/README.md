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

## Reentrada na caçada (F8)

Contrato em `docs/multiplayer.md` §4.7.2. O servidor continua sem estado próprio: o mapa de quem pode
voltar mora no anexo (`meta`) do socket do anfitrião e sobrevive à hibernação.

- `{"t":"lock","locked":true,"tokens":{"2":123456,"3":987654}}`: o anfitrião tranca a sala e lista o token de
  cada slot que pode reentrar (chaves `"2"`..`"4"`, valores inteiros de 1 a 4294967295). Cada `lock` substitui
  o mapa; `locked:false` ou `tokens` ausente apaga. Revogar um slot é reenviar o `lock` sem ele. Formato
  errado: `bad_request` (4400).
- `…/ws?t=join&code=…&v=…&proto=1&name=…&want=<id>&tok=<token>&ep=<época>`: com `tok` ≠ 0 o `join` é uma
  reentrada. Entra no id `want` se a sala está trancada e o token é o daquele slot, sem passar por
  `in_progress` nem `room_full`. Qualquer outro caso: `bad_token`, close **4401**. `ep` (0..15) é só repassado
  no `peer_joined`. `tok` ausente, vazio ou `0` é a entrada normal de sempre.
- Se ainda existe uma conexão viva naquele id (celular com o socket meio-aberto), ela recebe
  `{"t":"error","code":"replaced"}` e é fechada com **4411**; ninguém recebe `peer_left` por ela.
- `peer_joined` leva `ep` (0 na entrada normal). `peer_left` leva `"clean":true` só quando o cliente saiu com
  `{"t":"leave"}`; socket que apenas fechou sai sem `clean` (o anfitrião guarda o slot durante a carência).
- Ordem dos erros na entrada: `room_not_found`, `expired`, `version_mismatch`; depois, com `tok`: `bad_token`;
  sem `tok`: `in_progress`, `room_full`.

`bun test` cobre isso nos dois modos (estável e hibernação) e `check.js` tem o roteiro de reentrada.

O servidor é publicado **antes** do jogo: com o servidor antigo, um cliente novo não recebe `clean` e toda
saída explícita vira 45 s de "está reconectando…" (risco R18 do contrato). Depois de publicar, rode o
`check.js` contra a produção antes de subir a versão do jogo.

## Publicar

    bun x wrangler deploy

Precisa de `wrangler login` feito e de um subdomínio `workers.dev` registrado na conta
(painel do Cloudflare, Workers, Onboarding). A origem aceita fica em `ALLOWED_ORIGINS` no `wrangler.toml`.

Observação: `wrangler dev` não funciona sob Bun (o Miniflare responde 503); use `bun server.js` para o
desenvolvimento local.

URL de produção: `wss://javali-salas.acpw01.workers.dev/ws`
