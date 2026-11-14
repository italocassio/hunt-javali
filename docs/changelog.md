# Histórico de versões

O número da versão fica em `config/version` no `project.godot` e aparece na tela inicial e no menu.
A entrada mais nova fica no topo.

## 0.4.0 — 14/11/2026

**Jogar com amigos (beta): caçada cooperativa de 2 a 4 jogadores.**

O que mudou para o jogador:

- Botão novo no menu, "Jogar com amigos (beta)". Um jogador cria a sala e recebe um código de 5 letras e
  um link de convite; os amigos entram pelo código ou abrindo o link. Cada um escolhe o próprio equipamento
  e aperta "Pronto"; o anfitrião escolhe o mapa e o contrato e inicia.
- Todos caçam os mesmos javalis. Cada abate paga quem deu o tiro; o bônus do contrato é pago cheio a cada
  jogador. O contrato só avança para quem já o tinha liberado.
- Mais jogadores, mais javalis: ×1,5 com dois, ×2 com três, ×2,5 com quatro.
- Derrota se a lavoura acabar ou se todos os caçadores caírem. Quem cai assiste a um aliado até o fim.
- Aliados aparecem no mapa com a cor de cada um (laranja, azul, amarelo, roxo), no minimapa e na bússola.
- Se o anfitrião sair, a caçada termina para todos e os abates de cada um são pagos.
- Cães ainda não vão para a caçada com amigos (em breve). O modo solo não mudou.

O que mudou no projeto:

- Servidor de salas em `server/` (Cloudflare Workers + Durable Objects, plano gratuito), publicado em
  `wss://javali-salas.acpw01.workers.dev/ws`. Os jogadores se conectam direto por WebRTC; quando não dá,
  o tráfego passa pelo servidor.
- Autoload novo `Net` (`src/net/`), configuração em `data/net.json`, bloco `coop` em `data/game.json`.
- Plano e protocolo em `docs/multiplayer.md`; contrato 1.1 em `docs/arquitetura.md`.
- Suítes novas: `tests/net_test.tscn`, `tests/net_unit.tscn`, `tests/web/coop_probe.py`.

## 0.3.4 — 12/11/2026

**Drone batedor vira item básico e todo jogador ganha 3.**

Motivo: jogadores relataram dificuldade para encontrar os javalis. O drone revela todos os javalis no
minimapa por 10 s; os que estão fora do alcance do minimapa aparecem na borda, indicando a direção.

O que mudou para o jogador:

| | Antes | Agora |
|---|---|---|
| Preço do drone | 30 de ouro | 400 de dinheiro |
| Drones por caçada | 2 | 3 |
| Drones no início do jogo | 0 | 3, já equipados |

- Quem já tinha save recebe 3 drones uma única vez, na primeira vez que abrir a versão nova. Eles são
  somados aos que o jogador já tinha, até o limite de 9 por consumível.
- Nesse caso o drone é equipado sozinho se houver slot de item livre. Com os 3 slots ocupados, os drones
  vão para o inventário e o jogador equipa na tela de preparação.
- O uso na caçada não mudou: selecionar o drone no cinto de itens e usar.

O que mudou no projeto:

- `data/equipment.json`: `scout_drone` com `price 400`, `currency money`, `max_per_hunt 3`.
- `data/game.json`: `economy.start_items` passa a `{"medkit": 1, "scout_drone": 3}`.
- Save na versão 2. A migração 1 → 2 (`SaveService._migrate_v1_to_v2`) concede a quantidade definida em
  `economy.start_items.scout_drone`; o save migrado é gravado na hora, então a concessão não se repete.
- Para mudar o preço ou a quantidade inicial, basta editar os dois arquivos de dados acima. Mudar a
  quantidade inicial não dá drones de novo a quem já está na versão 2 do save.
- Contrato atualizado em `docs/arquitetura.md` (resumo do jogo, §6.3, dados de exemplo e §10).

## 0.3.3

Mostra o número da versão na tela inicial e no menu.

## 0.3.2

Controles de toque no padrão de shooter mobile.

## 0.3.1

Corrige os controles de toque no celular.

## 0.3

Jogo mais difícil.
