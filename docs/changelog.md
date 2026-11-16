# Histórico de versões

O número da versão fica em `config/version` no `project.godot` e aparece na tela inicial e no menu.
A entrada mais nova fica no topo.

## 0.6.0 — 16/11/2026

**Armas, braços e caçadores aliados em alto detalhe, 100% gerados por código.**

O que mudou para o jogador:

- As 5 armas foram refeitas em alto detalhe: madeira com veio, metal, luneta com lente, serrilhado no punho.
  Cada uma tem silhueta própria (.22 leve de mira aberta, 12 de bomba, .308 de ferrolho, .30-06 semiautomático,
  .338 com luneta grande e freio de boca).
- Braços novos em 1ª pessoa: manga cáqui e luvas, segurando cada arma, com animação de ferrolho, bomba e recarga.
- A arma aparece maior e mais perto na tela (campo de visão próprio da arma), sem mudar a mira.
- Os caçadores aliados da caçada com amigos foram refeitos: colete e boné na cor do jogador, roupa de campo,
  versões das armas novas na mão, poses de andar, agachar, mirar, recarregar e cair.

Detalhes técnicos: orçamento da arma em 1ª pessoa ≤ 12 000 triângulos com braços (§7.3) e do caçador aliado
≤ 5 000 (§7.11). Cada arma é montada em 60–136 ms no desktop na entrada da caçada (cache depois).

## 0.5.0 — 15/11/2026

**Novo modo na caçada com amigos: Horda Javali.**

O que mudou para o jogador:

- Na sala, o anfitrião escolhe o modo: "Contrato" (como antes) ou "Horda Javali". Vale com 1 a 4 caçadores.
- Na horda, os caçadores defendem o celeiro da sede em Mato Grosso. Javalis chegam em 8 ondas, cada vez
  maiores, a última com o cachaço alfa, e correm direto para o milho. Ninguém foge: machos e alfa investem
  contra quem chega perto.
- Vitória: abater todas as ondas. Derrota: o estoque de milho do celeiro chega a 0% ou todos os caçadores morrem.
- Todas as armas ficam disponíveis (teclas 1 a 5; no celular, o botão Trocar passa por todas) e a munição de
  reserva é infinita.
- HUD de horda: "Celeiro 87%", "Javalis no celeiro!", "Onda 3/8", anúncio de cada onda e marcador do celeiro
  no minimapa e na bússola. O milho do celeiro diminui à vista conforme é comido.
- O abate paga menos que na campanha, a vitória paga um bônus de defesa e a horda não libera contratos.
- O modo contrato, no solo e com amigos, não mudou.

O que mudou no projeto:

- Contrato do modo em `docs/horda.md`; dados em `data/horde.json`.
- `HordeDirector` (novo) planeja e libera as ondas; o `CropManager` vira o estoque do celeiro em modo horda;
  a IA dos javalis ganhou 7 desvios só para a horda.
- Rede: byte de modo no fim de `L_LOBBY`/`L_START`; evento novo `EV_HORDE_WAVE`; o protocolo continua 1.
- Assets procedurais: `barn_corn` (5 estágios), sons `horde_wave_start`/`horde_wave_clear`, ícone `barn`.

## 0.4.10 — 15/11/2026

**Rolagem por arraste nos menus no celular.**

O que mudou para o jogador:

- No celular, as listas dos menus (lobby, Mapas, Preparação, Loja, Resultado, Doação, Configurações) rolam
  arrastando o dedo em qualquer ponto, inclusive em cima de botões e cartões. Antes só rolava pela barra.
- Um toque simples continua acionando o botão; um arraste não aciona nada. Arrasto rápido desliza um pouco
  depois de soltar.
- Nos controles de volume, arrastar para o lado muda o volume e arrastar para cima ou para baixo rola a lista.
- No computador nada mudou.

O que mudou no projeto:

- `src/ui/common/touch_scroll_container.gd` (novo): ScrollContainer com arraste por toque; `UiKit.scroll_list()`
  passa a usá-lo, sem mudar a assinatura.
- `README.md`: como rodar a versão Web localmente, no celular pela rede e com o servidor de salas local.

## 0.4.9 — 15/11/2026

**Reconexão na caçada com amigos.**

O que mudou para o jogador:

- Se a internet de um jogador cair no meio da caçada, ele não sai mais da partida: aparece "Reconectando…",
  o caçador fica parado e o jogo tenta voltar sozinho por até 30 segundos. Ao voltar, aparece
  "Conexão restabelecida." e ele continua com os mesmos javalis, a mesma lavoura e o mesmo placar.
- Os outros veem "<Nome> está reconectando…" e "<Nome> voltou.". Enquanto está fora, o caçador do aliado
  fica parado e os javalis o ignoram. O anfitrião guarda o lugar por 45 segundos.
- Se não der para voltar a tempo, a partida termina para ele como antes, com os abates pagos.
- Com "Mostrar quadros por segundo" ligado, a caçada com amigos mostra também o tráfego de rede
  (envio e recebimento em kB/s e quantos aliados estão em conexão direta ou via servidor).
- Só funciona sem recarregar a página. O modo solo não mudou.

O que mudou no projeto:

- Servidor de salas (`server/rooms.js`, publicado): entrada de volta com `tok` e `ep` na sala trancada,
  erros `bad_token` (4401) e `replaced` (4411), `lock` com os tokens, `clean` no `peer_left`.
- `src/net/`: reconexão com sonda, tentativas e época do enlace; `Net.is_reconnecting()`, `get_traffic()`.
- `src/hunt/`: carência do slot no anfitrião, `EV_FULL_SYNC` (diário de eventos repetido na volta).
- `data/net.json`: `peer_timeout_s` 45, `rejoin_timeout_s` 30, `rejoin_backoff_s`, `rejoin_probe_s`.
- Contrato em `docs/multiplayer.md` §4.7. Testes novos: `relay_rejoin` e `rejoin` no `tests/net_test.tscn`,
  sandbox `net_sync` no `tests/net_unit.tscn`, cenário `rejoin` no `tests/web/coop_probe.py`.

## 0.4.8 — 14/11/2026

**Cães na caçada com amigos.**

O que mudou para o jogador:

- No modo "Jogar com amigos", cada jogador pode levar o próprio cão. A lista da sala mostra a arma e o cão de
  cada um.
- "Pega!" e "Volta!" comandam só o seu cão, e só você vê os avisos dele. Quando qualquer cão marca um javali,
  a marca aparece para todos.
- O abate feito pelo cão paga o dono do cão.
- Se o dono cai, o cão fica parado esperando; se o dono sai da partida, o cão sai junto.
- O modo solo não mudou.

O que mudou no projeto:

- `src/dogs/dog.gd` com dono (`owner_slot`) e `command()` público; réplica nova `src/dogs/dog_puppet.gd`.
- `hunt_controller.gd`, `hunt_host_sync.gd`, `hunt_replica.gd`: um cão por jogador no anfitrião, seção `DOG`
  do snapshot, comandos e marcações pela rede.
- `src/net/net_session.gd`: o cão de cada jogador trafega no resumo de equipamento.
- Teste novo: cenário `dogs` no `tests/net_test.tscn` e sandbox `net_dogs` no `tests/net_unit.tscn`.

## 0.4.7 — 14/11/2026

**Contador de FPS na caçada.**

O que mudou para o jogador:

- A opção "Mostrar quadros por segundo" das configurações agora funciona: com ela ligada, aparece o número
  de FPS no canto superior esquerdo da tela, abaixo da vida. Dá para ligar e desligar a qualquer momento,
  inclusive com o jogo pausado.

O que mudou no projeto:

- Causa do bug: a configuração `show_fps` era salva, mas nenhum código do HUD a lia.
- Novo `src/hud/fps_counter.gd` (`FpsCounter`, um `Label`): lê `Profile.get_setting("show_fps")`, segue
  `GameEvents.settings_changed`, atualiza a cada 0,5 s e não processa nada enquanto está oculto.
- `src/hud/hud.gd`: cria o contador e o coloca no canto superior esquerdo.
- `src/hud/debug/hud_net_test.gd`: 8 verificações novas para o contador.

## 0.4.6 — 14/11/2026

**Som do cerrado novo, sem cigarras.**

O que mudou para o jogador:

- O som ambiente do cerrado foi refeito: agora é só brisa no capim e pássaros distantes, sem o barulho
  de cigarra que irritava. O volume voltou ao normal (igual ao do vento).

O que mudou no projeto:

- `assets/audio/sfx/amb_cerrado_loop.mp3` regerado (ElevenLabs) com o prompt novo de
  `assets/audio/sfx_prompts.json`.
- `src/hunt/hunt_controller.gd`: removida a constante `AMBIENCE_DB_BY_ID` da 0.4.5; os dois loops
  voltam a tocar em `AMBIENCE_DB` (-6 dB).

## 0.4.5 — 14/11/2026

**Som do cerrado mais baixo na caçada.**

O que mudou para o jogador:

- O som ambiente do cerrado (cigarras, pássaros e brisa) ficou bem mais baixo durante a caçada, para não
  irritar. O som do vento continua como estava.

O que mudou no projeto:

- `src/hunt/hunt_controller.gd`: constante nova `AMBIENCE_DB_BY_ID` com o volume de `amb_cerrado_loop`
  (-15 dB, antes -6 dB como o vento). Para ajustar, basta mudar esse número.

## 0.4.4 — 14/11/2026

**A música continua tocando em todas as telas de menu até a caçada começar.**

O que mudou para o jogador:

- A música orquestral agora toca também no mapa, na preparação, na loja, na doação e nas configurações,
  além do menu e do lobby. Ela não reinicia ao trocar de tela e some com um fade ao começar a caçada.
- A tela de resultado fica sem música, para a vinheta de vitória ou derrota ser ouvida.

O que mudou no projeto:

- Só dados e teste: `music.scenes` em `data/game.json` ganhou as telas de menu; `tests/unit/test_music.gd` e
  a §7.8, §9.1 e a regra de telas de `docs/arquitetura.md` acompanham. Nenhum código mudou.

## 0.4.3 — 14/11/2026

**Música orquestral no menu e no lobby.**

O que mudou para o jogador:

- Uma música orquestral heroica e tensa (cordas graves, caixa de marcha, tambores e metais) toca no menu
  principal e no lobby do "Jogar com amigos". Ela segue sem reiniciar de uma tela para a outra e some com
  um fade ao sair, por exemplo ao escolher o mapa ou entrar na caçada.
- O volume da música acompanha o volume de ambiente nas configurações.

O que mudou no projeto:

- Faixa `assets/audio/music/music_menu.mp3` (90 s, instrumental, gerada com ElevenLabs). `Sfx` ganhou
  `play_music`, `stop_music` e `is_music_playing` (tocador próprio, fora do pool de efeitos, no barramento
  `Ambience`, carga sob demanda, loop).
- O `Router.goto` decide onde toca, a partir do bloco novo `music` de `data/game.json` (faixa, cenas,
  volume e fades). Novo `Router.scene_has_music`. Contrato na §7.8, §6.6 e §9.1 de `docs/arquitetura.md`.
- `check_scripts` isenta também `assets/audio/music/`. Teste novo em `tests/unit/test_music.gd`.

## 0.4.2 — 14/11/2026

**Javali mais realista: guincho, morte e bufada de alerta.**

O que mudou para o jogador:

- Novos sons do javali: o guincho ao ser atingido, o som da morte e a bufada de alerta foram refeitos
  para soar como um javali selvagem de verdade (e não como um porco doméstico). A morte agora é um
  grunhido fraco e uma expiração que some, sem grito dramático.

O que mudou no projeto:

- Só arquivos de som: `boar_squeal`, `boar_death` e `boar_snort_alert` em `assets/audio/sfx/`, com os
  prompts novos em `assets/audio/sfx_prompts.json`. `boar_snort_alert` passou de 0,7 s para 1,0 s.
  Nenhum código nem contrato mudou.

## 0.4.1 — 14/11/2026

**Sons de verdade: tiros, javalis, cães, passos, ambiente e interface.**

O que mudou para o jogador:

- Os 47 efeitos sonoros passam a ser gravações realistas (tiros de cada calibre, recarga, passos, javali,
  cães, vento, cerrado, sons de interface e as vinhetas de vitória e derrota), no lugar dos sons sintéticos.
- O grunhido de ataque e o som de morte do javali foram refeitos para soar mais como um animal de verdade.

O que mudou no projeto:

- Sons gerados com ElevenLabs a partir de `assets/audio/sfx_prompts.json` e guardados em
  `assets/audio/sfx/<id>.mp3`. São a única exceção à regra de arte 100% procedural.
- `Sfx` carrega os MP3 no `_ready` (~35 ms em desktop, 2,2 MB). A síntese procedural continua como
  reserva para qualquer id sem arquivo. API e ids não mudaram.
- `default_bus_layout.tres` declara os barramentos `SFX`, `Ambience` e `UI`, para o som não sumir na Web.
- `check_scripts` isenta `res://assets/audio/sfx/` da proibição de binários. Contrato na §7.8 de
  `docs/arquitetura.md`.

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
