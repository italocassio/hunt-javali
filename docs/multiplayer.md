# Caçada ao Javali — Proposta de multiplayer cooperativo

Estado: **proposta, aguardando aprovação do dono do jogo**. Nada aqui vale como contrato até o merge em
`docs/arquitetura.md` (§7 deste documento traz os deltas prontos). Base: código da versão 0.3.4.
Identificadores em inglês; texto do jogador em PT-BR. Referências `arquivo:linha` são do código atual.

---

## 1. Resumo

- Opção nova no menu: **"Jogar com amigos (beta)"**. 2 a 4 caçadores no mesmo contrato, sala privada por
  código de 5 caracteres ou link `?sala=CODIGO`. Sem PvP, sem fogo amigo, sem busca de partida pública.
- Um jogador é o **anfitrião**: o jogo dele simula javalis, cães e lavoura exatamente como no solo. Os outros
  veem réplicas interpoladas e controlam só o próprio caçador.
- Quem atira decide o acerto na própria tela; quem é investido decide o dano na própria tela. Ninguém erra
  "por causa do lag".
- Dinheiro do abate para quem matou; bônus do contrato inteiro para cada um; consumíveis de cada um.
- Caçador morto vira espectador. Derrota: lavoura em 0% ou todos mortos. Anfitrião caiu: a caçada acaba e
  cada um recebe os abates que já tinha feito.
- Conexão: WebRTC direto entre cada cliente e o anfitrião; se o WebRTC não fechar (NAT de 4G), o par usa o
  servidor de salas como ponte. O jogo não sabe por qual caminho os dados vão.
- O servidor de salas roda na nuvem (Cloudflare Workers + Durable Objects, plano gratuito): cuida da sala,
  da sinalização do WebRTC e da ponte de fallback. Se ele estiver indisponível ou a cota diária gratuita
  acabar, não se criam salas novas; o solo nunca depende dele.
- O solo não muda: sem sala ativa nenhum código de rede executa e as 4 suítes atuais passam como hoje.
- Custo de dados por cliente numa sala de 4 no maior contrato: cerca de 30 kbit/s de download (14 MB/hora).
- **Desenho em uma frase:** camada própria de mensagens binárias sobre um enlace por par (relay WebSocket
  desde o primeiro instante, promovido a WebRTC quando o ICE fecha), com simulação autoritativa no anfitrião,
  snapshots a 10 Hz por canal não confiável e eventos por canal confiável.

---

## 2. Decisões

### 2.1 Da coordenação (resumo de uma linha)

| # | Decisão |
|---|---|
| D1 | Co-op PvE, 2–4 jogadores, sala privada por código curto (5 caracteres) + link `?sala=CODIGO`. |
| D2 | Anfitrião autoritativo roda a simulação de hoje; clientes rodam réplicas a ~10 Hz; solo intocado. |
| D3 | Cada cliente é dono do próprio caçador; tiro "favor the shooter" com validação leve no anfitrião; sem anti-cheat. |
| D4 | WebRTC DataChannels em estrela (cliente↔anfitrião), 2 canais por par: confiável/ordenado e não confiável (`maxRetransmits = 0`). |
| D4b | Sem TURN: par cujo ICE não fecha trafega pelo WebSocket do servidor de salas (relay binário cego). |
| D4c | Godot nativo/headless não tem WebRTC: lá o transporte é sempre relay WS ou loopback. Relay é transporte de primeira classe. |
| D5 | Anfitrião caiu = fim para todos (sem migração). Cliente caiu = caçador some, partida segue. |
| D6 | Abate paga quem matou; bônus para todos; progressão só para quem já tinha o contrato; consumíveis por jogador; nº de javalis escala por dados. |
| D7 | Morto vira espectador. Derrota = lavoura 0% ou todos mortos. Vitória = todos os javalis abatidos. |
| D8 | Cada jogador leva o seu cão; anfitrião simula; dono comanda pela rede (fase própria). |
| D9 | Aliado visto por `HunterVisualBase` / `ScenePaths.HUNTER_VISUAL` (asset já entregue). |
| D10 | `server/` em JavaScript: lógica em módulo neutro de runtime (`rooms.js`, `bun test`), entrada de produção Worker + Durable Object, entrada local Bun para desenvolvimento e testes; deploy com `wrangler`. |
| D11 | `config/version` diferente não entra na mesma sala. |
| D12 | Em multiplayer o menu de pausa não pausa a árvore. |
| D13 | Entrada pelo menu "Jogar com amigos (beta)"; fluxo solo inalterado. |
| D14 | Produção em Cloudflare Workers + Durable Objects, plano Free: um objeto por sala faz sala, sinalização e relay de fallback; `wss://` pronto em `*.workers.dev`; WebSocket Hibernation API. |
| D15 | Segurança no Worker: checa `Origin`, limita tamanho e taxa de mensagem, 4 peers por sala, código de sala difícil de adivinhar, sala vazia some; sem estado persistente. |
| D16 | Config do cliente em `data/net.json` (URL de produção e de desenvolvimento, STUN, timeout de ICE, taxas). |

### 2.2 Do arquiteto

**A1 — Camada própria de mensagens binárias, não a API de alto nível do Godot.**
`WebRTCMultiplayerPeer` + RPC/`MultiplayerSynchronizer` não cobre o relay nem os testes nativos (exigiria um
`MultiplayerPeerExtension` em GDScript só para isso), depende de `NodePath` igual nos peers (aqui o anfitrião
tem `Boar` e o cliente tem `BoarPuppet`) e esconde o que vai em cada canal. A camada própria é pequena
(~15 tipos de registro), idêntica nos dois caminhos, testável em headless com loopback, e deixa explícito o
que é estado (descartável) e o que é evento (ordenado). Custo: serialização e interpolação escritas à mão.

**A2 — Rede num pacote novo `src/net/` com autoload `Net`; cada pacote serializa as próprias entidades.**
`src/net` só conhece `src/core` e autoloads: transporta, agrupa, numera e agenda. O Pacote B escreve e lê
javalis, cães, lavoura e ceva; o Pacote A escreve e lê o estado do caçador. A costura é feita por métodos
virtuais novos em `HuntWorld` e `PlayerBase` (§3.6). A e B continuam sem se referenciar e nenhum dos dois
referencia classes de `src/net`. `get_player()` continua sendo "o caçador desta máquina"; a IA passa a usar
`get_hunters()`.

**A3 — Réplica do javali em classe própria leve (`BoarPuppet`), montada em código.**
Não é `boar.tscn` em "modo puppet": o script de IA (1030 linhas, caminho crítico) só ganha a escolha de alvo
entre vários caçadores. A réplica não tem FSM, bando nem RNG; tem as mesmas 4 `HitZone` (o hitscan local
funciona sem mudar `weapon.gd`). Estado contínuo vai no snapshot (7 bytes por javali); momentos únicos
(nascer, ser atingido, golpear, morrer) vão como eventos. Interpolação com 200 ms de atraso, sem extrapolar.
A investida é julgada **na máquina da vítima** contra a réplica que ela vê ("favor the victim").

**A4 — O mapa já é determinístico, com uma exceção real na flora.**
Terreno, props, água, lavoura (índices dos canteiros) são iguais em todos os peers. A flora usa um RNG com
seed fixa, mas a densidade da qualidade gráfica muda quantos sorteios o capim consome antes das árvores:
celular em "low" e desktop em "medium" hoje têm troncos em lugares diferentes. Correção: `build_flora` ganha
um modo de layout sincronizado, usado só em multiplayer (§6.4). A lavoura chega por índice de canteiro.

**A5 — Protocolo de sala/sinalização em JSON (texto) e relay em binário, no mesmo WebSocket.**
O pedido de criar ou entrar vai na URL do WebSocket (é ela que escolhe o Durable Object da sala). O servidor
sorteia o código, numera os peers (anfitrião = 1), impõe a estrela, repassa offer/answer/candidatos sem
interpretar e repassa quadros binários trocando o byte de destino pelo de origem. A lógica é sem estado
próprio: todo o estado da sala mora nas conexões, para sobreviver à hibernação. Especificação em §4 e §5.

**A6 — Lobby numa cena nova (`src/ui/lobby/`), loadout de cada jogador montado localmente.**
Nome do jogador em `settings.player_name` (sem subir a versão do save). O anfitrião escolhe mapa e contrato
entre os que tem; cada jogador ajusta o próprio equipamento num painel reaproveitado da Preparação. Pela
rede só trafega o resumo (arma na mão, cão).

**A7 — Três níveis de teste.** Unidade (codec, enlace com loopback com perda/reordenação, réplica, escala de
javalis, economia) dentro de `unit_tests`; servidor com `bun test` na lógica neutra e `check.js` contra cada
entrada (Bun local, `wrangler dev`, produção); integração com o servidor Bun local em `localhost` e 2–3
processos Godot headless pelo relay (suíte nova `net_test`); Web com dois Chrome
exercitando WebRTC de verdade e o fallback forçado (`tests/web/coop_probe.py`).

---

## 3. Arquitetura

### 3.1 Diagrama

```
                  Cloudflare (*.workers.dev)
                 ┌──────────────────────────┐
  wss://…/ws     │ Worker (rota, Origin)    │
 ┌──────────────►│   └─► Durable Object     │◄──────────────┐
 │  JSON: sala,  │       Room = 1 sala      │  JSON + relay │
 │  sinalização  └──────────────────────────┘  binário      │
 │  binário: relay (só se o ICE não fechar)                 │
 │                                                          │
┌┴────────────────────────┐   WebRTC (DTLS/SCTP, 2 canais) ┌┴─────────────────────────┐
│ ANFITRIÃO (peer 1)      │◄══════════════════════════════►│ CLIENTE (peer 2..4)      │
│ HuntController (HOST)   │   estado  ─ não confiável      │ HuntController (CLIENT)  │
│  BoarSpawner/Boar/Herd  │   eventos ─ confiável          │  HuntReplica             │
│  CropManager (simula)   │                                │   BoarPuppet / DogPuppet │
│  Dog × N                │   H_SNAPSHOT 10 Hz ──────────► │  CropManager (espelho)   │
│  HuntHostSync           │   EV_* ──────────────────────► │  Player (local, dono)    │
│  Player (local)         │ ◄────────────── C_STATE 10 Hz  │  RemoteHunter × (n−1)    │
│  RemoteHunter × (n−1)   │ ◄────────────── C_SHOT, C_*    │                          │
└─────────────────────────┘                                └──────────────────────────┘
   Clientes não falam entre si: o anfitrião reenvia o estado de todos os caçadores no snapshot.
```

### 3.2 Pacotes, donos e regra de dependência

| Pacote | Pastas | Dono | Pode referenciar por tipo | Carrega por caminho |
|---|---|---|---|---|
| A | `src/input`, `src/player`, `src/weapons`, `src/hud` | game-developer | `src/core/*`, autoloads (inclui `Net`) | `assets/*`, `ScenePaths.SETTINGS_PANEL` |
| B | `src/hunt`, `src/world`, `src/boars`, `src/dogs` | game-developer | `src/core/*`, autoloads (inclui `Net`) | `assets/*`, `ScenePaths.PLAYER`, `ScenePaths.REMOTE_HUNTER` |
| **N (novo)** | `src/net` | game-developer | `src/core/*`, autoloads | nada (troca de cena só via `Router`) |
| game-systems | `src/systems`, `src/ui`, `data` | game-systems | `src/core/*`, autoloads, suas classes | `ScenePaths.*` via `Router` |
| art-director | `assets` | art-director | `src/core/*` | — |
| qa-tester | `tests` | qa-tester | tudo | tudo |
| coordenação | `src/core`, `server/`, `project.godot`, `export_presets.cfg` | coordenação | — | — |

Proibido (acréscimos): N referenciar classes de A, B ou systems; A, B, systems ou assets referenciarem
classes de N (usam o autoload `Net` e os tipos de `src/core`). `check_scripts` ganha a regra.

### 3.3 Arquivos novos

```
server/                         coordenação
├── rooms.js                    lógica de uma sala (entrada, sinalização, relay, limites); sem API de Bun, Node nem Workers
├── config.js                   limites (§5.3); módulo sem dependências, importado pelas duas entradas
├── worker.js                   entrada de produção: Worker (rota + Origin) e classe Room (Durable Object)
├── wrangler.toml               nome, binding ROOMS, migração new_sqlite_classes, ALLOWED_ORIGINS
├── server.js                   entrada local Bun (Bun.serve) para desenvolvimento e testes de integração
├── check.js                    conferência do protocolo contra uma URL (local, wrangler dev ou produção)
├── rooms.test.js               bun test
└── README.md                   como rodar, testar e publicar
tools/wscheck.html              coordenação: página de verificação publicada junto do build (F0)
data/net.json                   game-systems (§7.9)
src/core/net_codec.gd           coordenação  class NetCodec
src/core/net_peer_info.gd       coordenação  class NetPeerInfo
src/net/                        Pacote N
├── net.gd                      autoload Net (fachada; sem class_name)
├── net_session.gd              class NetSession: sala, lobby, relógio de ticks, despacho de registros
├── net_signaling.gd            class NetSignaling: WebSocketPeer + JSON de sala/sinalização + quadros de relay
├── net_link.gd                 class NetLink: um par; caminho RELAY/RTC, seq/ack, reordenação, reenvio
├── net_rtc.gd                  class NetRtc: WebRTCPeerConnection + 2 canais (só instanciado no Web)
└── net_loopback.gd             class NetLoopback: par em memória com perda/reordenação configuráveis (testes)
src/player/remote_hunter.gd|.tscn   Pacote A  class RemoteHunter (extends PlayerBase)
src/player/spectator_camera.gd      Pacote A  class SpectatorCamera
src/hunt/hunt_host_sync.gd          Pacote B  class HuntHostSync
src/hunt/hunt_replica.gd            Pacote B  class HuntReplica
src/boars/boar_puppet.gd            Pacote B  class BoarPuppet
src/dogs/dog_puppet.gd              Pacote B  class DogPuppet
src/ui/lobby/lobby.tscn|.gd         game-systems
src/ui/common/loadout_panel.gd      game-systems  class LoadoutPanel (extraído de preparation.gd:143–276)
tests/unit/test_net.gd, tests/net_test.tscn|.gd, tests/net/net_peer.tscn|.gd, tests/web/coop_probe.py   qa-tester
```

### 3.4 Autoload `Net` — `res://src/net/net.gd` — dono: Pacote N

Ordem dos autoloads: `GameEvents`, `Data`, `Profile`, `InputSetup`, `Sfx`, `Router`, **`Net`** (último: usa
`Data`, `Profile`, `Router`). Offline (`Role.OFFLINE`) o autoload fica com `set_process(false)`, não abre
socket e todos os getters devolvem os valores "solo" abaixo. O stub da fase F1 é exatamente esse estado.

```gdscript
enum Role { OFFLINE, HOST, CLIENT }
enum RoomState { NONE, CONNECTING, LOBBY, LOADING, IN_HUNT }
enum Path { NONE, RELAY, RTC }

signal room_state_changed(state: int)                 # RoomState
signal room_error(code: StringName, message: String)  # message já em PT-BR (§6.11)
signal roster_changed()                               # entrou/saiu alguém, pronto, contrato, caminho do enlace
signal hunt_go()                                      # todos carregaram (ou estouraram o prazo): a caçada começa

# --- estado (valor solo entre parênteses) ---
func is_configured() -> bool            # data/net.json tem URL utilizável nesta plataforma
func is_active() -> bool                # (false) true em LOADING/IN_HUNT: a caçada atual é em rede
func is_in_room() -> bool               # (false) true de LOBBY em diante
func is_host() -> bool                  # (false)
func get_role() -> int                  # (Role.OFFLINE)
func get_room_state() -> int            # (RoomState.NONE)
func get_room_code() -> String          # ("")
func get_room_link() -> String          # ("") URL da página + "?sala=CODE"
func get_local_slot() -> int            # (0) slot = id do peer − 1; anfitrião = 0
func get_player_count() -> int          # (1) peers presentes
func get_roster() -> Array[NetPeerInfo] # ([]) ordenado por slot
func get_peer(slot: int) -> NetPeerInfo # (null)
func get_selected_map_id() -> StringName       # (&"")
func get_selected_contract_index() -> int      # (0)
func get_link_path(slot: int) -> int    # (Path.NONE) Path do enlace com aquele peer (HUD/lobby/testes)
func get_hunt_seed() -> int             # (0) 0 fora de sala; semente do L_START, igual em todos os peers
func is_peer_absent(slot: int) -> bool  # (false) ausência curta (peer_absent_s), sem remoção da sala

# --- lobby (game-systems) ---
func create_room() -> void              # nome vem de Profile.get_setting("player_name")
func join_room(code: String) -> void
func leave_room() -> void               # idempotente; fecha tudo e volta a OFFLINE
func set_ready(ready: bool) -> void     # cliente; reenvia o resumo do loadout
func host_select_contract(map_id: StringName, contract_index: int) -> bool   # só anfitrião, só contrato dele desbloqueado
func host_start_hunt() -> bool          # só anfitrião, todos prontos: tranca a sala, envia L_START
func take_url_room_code() -> String     # lê "?sala=" uma única vez ("" depois ou fora do Web)

# --- caçada (Pacote B) ---
func bind_world(world: HuntWorld) -> void    # fim da montagem; Net passa a despachar registros para o mundo
func unbind_world(world: HuntWorld) -> void  # _exit_tree
func flush() -> void                         # envia já os eventos pendentes (fim de caçada)
```

Responsabilidade de `Net` na caçada: a cada tick (acumulado por `delta` de `_process`; prazos por relógio de
parede) o anfitrião monta para cada enlace um quadro de estado (`world.net_write_snapshot`) e um de eventos
(`world.net_take_events`); o cliente monta `C_STATE` (`world.get_player().net_write_state`) e eventos
(`world.net_take_claims`). Na chegada, despacha para `net_apply_snapshot`, `net_apply_event`,
`net_apply_claim` e `get_hunter(slot).net_apply_state`. Registros de caçada recebidos antes de `bind_world`
ficam em fila e são aplicados em ordem.

Ao entrar em `LOADING`, `Net` completa o `Router.get_pending_request()` com `rng_seed` (= `get_hunt_seed()`),
`player_count`, `map_id` e `contract_index`; assim a montagem da caçada é igual nos peers.

### 3.5 Novos sinais do `GameEvents`

| Sinal | Emissor | Ouvintes | Quando |
|---|---|---|---|
| `hunter_joined(slot: int, display_name: String)` | B `HuntController` | A `Hud` | caçador remoto criado na montagem |
| `hunter_left(slot: int)` | B `HuntController` | A `Hud` (mensagem), `SpectatorCamera` | peer saiu ou caiu durante a caçada |
| `hunter_died(slot: int)` | B `HuntController` | A `Hud`, `SpectatorCamera` | qualquer caçador (local ou remoto) morreu |
| `spectate_changed(slot: int)` | A `Player` | A `Hud` | começou/trocou de alvo como espectador (−1 = deixou) |
| `net_stall_changed(stalled: bool)` | `Net` | A `Hud` (faixa "Anfitrião sem resposta…") | cliente ficou `host_stall_warn_s` sem snapshot / voltou |

`player_died()` continua significando "o caçador **desta máquina** morreu". Sinais de cão
(`dog_state_changed`, `dog_health_changed`, `dog_command_executed`) passam a valer só para o cão do jogador
local, em qualquer máquina. `dog_marked_boar` e `bait_placed` valem para o time inteiro.

### 3.6 Tipos em `src/core` (código para o Apêndice A)

**`src/core/net_codec.gd`** (novo)
```gdscript
class_name NetCodec
extends RefCounted
## Wire constants and quantization shared by packages A, B and N. See docs/multiplayer.md section 4.

const PROTOCOL_VERSION: int = 1
const LANE_STATE: int = 0
const LANE_EVENT: int = 1
const FRAME_HEADER_BYTES: int = 5      # lane u8, seq u16, ack u16
const RECORD_HEADER_BYTES: int = 3     # type u8, len u16
const HUNTER_STATE_BYTES: int = 14
const NO_SLOT: int = 255

# Link / lobby (event lane)
const L_READY: int = 0x10
const L_LOBBY: int = 0x11
const L_START: int = 0x12
const L_LOADED: int = 0x13
const L_GO: int = 0x14
const L_NEED_RELAY: int = 0x15
# Host -> client
const H_SNAPSHOT: int = 0x20           # state lane
const EV_BOAR_SPAWN: int = 0x21
const EV_BOAR_HIT: int = 0x22
const EV_BOAR_ATTACK: int = 0x23
const EV_BOAR_DEATH: int = 0x24
const EV_CROP_EATEN: int = 0x25
const EV_BAIT: int = 0x26
const EV_DOG_MARK: int = 0x27
const EV_DOG_CMD: int = 0x28
const EV_MESSAGE: int = 0x29
const EV_HUNT_END: int = 0x2A
const EV_FULL_SYNC: int = 0x2B         # reserved (F8)
# Client -> host
const C_STATE: int = 0x40              # state lane
const C_SHOT: int = 0x41
const C_CHARGE_HIT: int = 0x42
const C_BAIT: int = 0x43
const C_DOG_CMD: int = 0x44

# Hunter state flags
const HF_CROUCH: int = 1
const HF_AIM: int = 2
const HF_SPRINT: int = 4
const HF_ALIVE: int = 8
const HF_RELOAD: int = 16
const HF_UNARMED: int = 32             # binoculars / item in hand

const BOAR_STATES: Array[StringName] = [&"wander", &"to_crop", &"eat", &"to_bait", &"alert", &"flee",
	&"scrape", &"charge", &"recover", &"bayed", &"held", &"dead"]
const DOG_STATES: Array[StringName] = [&"follow", &"seek", &"point", &"bay", &"hold", &"retreat", &"return"]
const ZONES: Array[StringName] = [&"head", &"vital", &"body", &"rear", &"dog"]


static func make_shot_id(slot: int, counter: int) -> int:
	return (slot << 24) | (counter & 0xFFFFFF)


static func shot_slot(shot_id: int) -> int:
	return (shot_id >> 24) & 0xFF


static func put_xz(out: StreamPeerBuffer, rect: Rect2, x: float, z: float) -> void:
	out.put_u16(clampi(roundi((x - rect.position.x) / rect.size.x * 65535.0), 0, 65535))
	out.put_u16(clampi(roundi((z - rect.position.y) / rect.size.y * 65535.0), 0, 65535))


static func get_xz(inp: StreamPeerBuffer, rect: Rect2) -> Vector2:
	var qx: int = inp.get_u16()
	var qz: int = inp.get_u16()
	return Vector2(rect.position.x + float(qx) / 65535.0 * rect.size.x,
		rect.position.y + float(qz) / 65535.0 * rect.size.y)


static func angle_to_u8(rad: float) -> int:
	return posmod(roundi(rad / TAU * 256.0), 256)


static func u8_to_angle(q: int) -> float:
	return float(q) / 256.0 * TAU


static func angle_to_u16(rad: float) -> int:
	return posmod(roundi(rad / TAU * 65536.0), 65536)


static func u16_to_angle(q: int) -> float:
	return float(q) / 65536.0 * TAU


## Wrap-aware "a is newer than b" for u16 sequence numbers.
static func seq_newer(a: int, b: int) -> bool:
	return ((a - b) & 0xFFFF) != 0 and ((a - b) & 0xFFFF) < 0x8000
```
Com mapa de 256 m, posição XZ tem passo de 4 mm; `u8` de ângulo, 1,4°; `u16`, 0,0055°. Todo inteiro em
little-endian (padrão do `StreamPeerBuffer`). Índices de arma, cão, tipo de javali e mapa são a posição do
id em `Data.get_*_ids()` (dados idênticos entre peers, garantidos pela checagem de versão); 255 = nenhum.

**`src/core/net_peer_info.gd`** (novo)
```gdscript
class_name NetPeerInfo
extends RefCounted

var slot: int = 0
var display_name: String = ""
var is_host: bool = false
var ready: bool = false
var loaded: bool = false
var weapon_id: StringName = &""     # weapon in slot 0 of the loadout (lobby display, first visual)
var dog_id: StringName = &""
var path: int = 0                   # Net.Path of the link (host: link to that peer; client: link to host)
```

**Acréscimos em classes existentes** (campos com default: o solo não percebe)

| Arquivo | Acréscimo |
|---|---|
| `hunt_request.gd` | `var player_count: int = 1` |
| `hunt_result.gd` | `enum Outcome { VICTORY, DEFEAT_CROP, DEFEAT_DEATH, ABANDONED, DISCONNECTED }` (valor novo no fim); `var counts_for_progression: bool = true`; `var player_count: int = 1`; `var team_kills: int = 0`; `var scoreboard: Array[Dictionary] = []` (`{slot, name, kills, money}`; vazio no solo). `kills`/`money_from_kills` = só os do jogador local; `boars_total` = do time. |
| `kill_info.gd` | `var killer_slot: int = 0` |
| `hit_info.gd` | `var shooter_slot: int = 0` |
| `scene_paths.gd` | `const LOBBY: String = "res://src/ui/lobby/lobby.tscn"`; `const REMOTE_HUNTER: String = "res://src/player/remote_hunter.tscn"` (`HUNTER_VISUAL` já existe) |
| `hunter_visual_base.gd` | `func play_death(_instant: bool = false) -> void`; `create_fallback()` passa a pintar a cápsula com `slot_color(slot)` em `setup` |
| `game_events.gd` | os 5 sinais de §3.5 |

`player_base.gd` (novos membros; todos virtuais com corpo trivial):
```gdscript
var slot: int = 0

func setup_remote(_slot: int, _display_name: String, _weapon_id: StringName, _world: HuntWorld) -> void:
	pass


func is_local() -> bool:      # false for RemoteHunter
	return true


func is_present() -> bool:    # false while a remote hunter has been silent for net.peer_absent_s: AI ignores it
	return true


func get_display_name() -> String:
	return ""


func net_write_state(_out: StreamPeerBuffer) -> void:   # writes exactly NetCodec.HUNTER_STATE_BYTES
	pass


func net_apply_state(_inp: StreamPeerBuffer) -> void:   # reads exactly NetCodec.HUNTER_STATE_BYTES
	pass
```

`hunt_world.gd` (novos membros):
```gdscript
func get_hunters() -> Array[PlayerBase]:      # every hunter in the world, local first. Solo: [get_player()]
	var out: Array[PlayerBase] = []
	var p: PlayerBase = get_player()
	if p != null:
		out.append(p)
	return out


func get_hunter(_slot: int) -> PlayerBase:    # null if that slot is not in the hunt
	return get_player()


func get_local_slot() -> int:
	return 0


# --- Net seam: bodies are record payloads of docs/multiplayer.md section 4 ---
func net_write_snapshot(_out: StreamPeerBuffer) -> void:      # host: body of H_SNAPSHOT
	pass


func net_apply_snapshot(_inp: StreamPeerBuffer) -> void:      # client
	pass


func net_take_events(_out: StreamPeerBuffer) -> void:         # host: appends queued EV_* records (type, len, body)
	pass


func net_apply_event(_type: int, _inp: StreamPeerBuffer, _length: int) -> void:   # client
	pass


func net_take_claims(_out: StreamPeerBuffer) -> void:         # client: appends queued C_* event records
	pass


func net_apply_claim(_slot: int, _type: int, _inp: StreamPeerBuffer, _length: int) -> void:   # host
	pass


func net_peer_left(_slot: int) -> void:                       # that hunter (and its dog) leaves the world
	pass


func net_connection_lost() -> void:                           # client: ends DISCONNECTED; host: every remote leaves
	pass
```
`Layers` não muda: caçador remoto não tem corpo nem forma de colisão (sem fogo amigo, o raio passa).

### 3.7 Mudanças em APIs existentes (antes → depois)

| Onde | Antes | Depois |
|---|---|---|
| `hunt_world.gd:89` `get_player()` | o único caçador | o caçador **local**; os demais por `get_hunters()` / `get_hunter(slot)` |
| `dog.gd:75` | `setup(p_breed_id, world, spawn_position)` | `setup(p_breed_id, world, spawn_position, p_owner_slot: int = 0)`; `_on_command` vira `command()` público |
| `boar_spawner.gd:34` | `setup(world, parent, contract, spawn_zones)` | igual; o `contract` chega já escalado por `static func scale_groups(groups: Array, player_count: int, coop: Dictionary) -> Array`. `_on_shot_fired` (171) delega a `notify_shot(origin: Vector3, noise_radius_m: float)` público |
| `map_root.gd:276` | `build_flora(density)` | `build_flora(density: float, sync_layout: bool = false)` |
| `crop_manager.gd` | só simula | + `apply_eaten(indices: PackedInt32Array)`, `set_replicated_health(pct: float)`, sinal `patch_eaten(index: int)` |
| `weapon.gd:121` | `shot_id = _next_shot_id` | `shot_id = NetCodec.make_shot_id(Net.get_local_slot(), _next_shot_id)` (solo: mesmo número) |
| `profile.gd:258` | `progressed = result.is_victory()` | `won = result.is_victory()`; `progressed = won and result.counts_for_progression`; `mark_won` e `progression_changed` por `progressed`, `hunts_won` por `won` |
| `pause_overlay.gd:93` | `get_tree().paused = true` | `get_tree().paused = not Net.is_active()`; em rede, `_player.set_input_enabled(false/true)` ao abrir/fechar |
| `Data` | — | `func get_net() -> Dictionary` (data/net.json inteiro); `get_game()["coop"]` |
| `SaveService.DEFAULT_SETTINGS` | 9 chaves | + `"player_name": ""` (String, até `net.name_max_chars`, sem caracteres de controle). `SAVE_VERSION` continua 2 |

---

## 4. Protocolo

### 4.1 Camadas

```
registro   type u8 | len u16 | body[len]                         (§4.5)
quadro     lane u8 | seq u16 | ack u16 | registro*               idêntico nos dois caminhos; ≤ 1100 bytes
caminho    RTC:   canal "state" (não confiável) ou "event" (confiável) → 1 mensagem = 1 quadro
           RELAY: WebSocket binário  [to u8]{len u16, quadro}+  →  servidor  →  [from u8]{len u16, quadro}+
```

### 4.2 Sala e sinalização (WebSocket; pedido na URL, depois quadros de texto JSON)

O pedido de criar ou entrar vai na **query string** da conexão, porque é o Worker que escolhe o Durable
Object da sala antes de existir qualquer mensagem. A entrada Bun local aceita exatamente as mesmas URLs.

| URL (base `net.server_url`) | Parâmetros | Primeira mensagem do servidor |
|---|---|---|
| `…/ws?t=create` | `v` (config/version), `proto` (int), `name` | `{"t":"created","code":"K7QF2","id":1}`. O servidor sorteia o código (5 caracteres, alfabeto sem I, O, 0, 1). Código sorteado já em uso → `error retry` (o cliente tenta de novo, até 3 vezes). |
| `…/ws?t=join` | `code`, `v`, `proto`, `name`, `want` (id desejado ou 0) | `{"t":"joined","code":"K7QF2","id":2,"peers":[{"id":1,"name":"Italo"}]}`; aos demais: `{"t":"peer_joined","id":2,"name":"Ana"}`. Id = `want` se livre, senão o menor livre em 2..4. |

O upgrade é sempre aceito quando a origem é válida; a recusa vem como `error` + close (o navegador não
mostra o motivo de um upgrade negado). Depois da primeira mensagem:

| Cliente → servidor | Campos | Efeito |
|---|---|---|
| `{"t":"signal"}` | `to`, `data` (objeto opaco) | repassa `{"t":"signal","from":<id>,"data":{…}}`. Não-anfitrião só pode `to: 1`. |
| `{"t":"lock"}` | `locked` (bool) | só anfitrião. Sala trancada recusa entrada com `in_progress`. |
| `{"t":"ping"}` | — (texto exato, sem espaços) | `{"t":"pong"}`. No Worker é resposta automática (§5.2): não acorda o objeto. |
| `{"t":"leave"}` | — | igual a fechar o socket |

| Servidor → cliente | Quando |
|---|---|
| `{"t":"peer_left","id":3}` | um cliente fechou/caiu |
| `{"t":"host_left"}` + close 4410 | o anfitrião fechou/caiu: a sala é destruída e todos os sockets fechados |
| `{"t":"error","code":…}` + close | ver tabela abaixo; em `version_mismatch` vem `"host_v":"0.4.0"` |

| `code` de erro | Close | Significado |
|---|---|---|
| `bad_request` | 4400 | parâmetro faltando ou inválido na URL (o upgrade é aceito: `error bad_request` + close 4400, não HTTP 400), JSON inválido, destino proibido |
| `origin_denied` | (HTTP 403, sem upgrade) | `Origin` fora da lista |
| `retry` | 4409 | `create` caiu num código já em uso |
| `room_not_found` | 4404 | código não existe (sala sem anfitrião conectado) |
| `room_full` | 4403 | já tem `max_peers_per_room` |
| `in_progress` | 4423 | sala trancada (caçada em andamento) |
| `version_mismatch` | 4426 | `v` ou `proto` diferente do anfitrião. Motivo do close = `"version_mismatch <host_v>"`: o Godot nativo perde o JSON que chega junto do close, então o cliente resolve o erro pelo código de close |
| `rate_limited` | 4429 | estourou a taxa por conexão |
| `too_big` | 4413 | mensagem acima do limite |
| `expired` | 4408 | sala passou de `room_max_age_s` |

Regras adicionais (implementadas): `signal` ou binário para id fora da sala é descartado em silêncio; destino
proibido (não-anfitrião com `to` ≠ 1) → `bad_request`. O código de sala não diferencia maiúsculas de
minúsculas. `want` fora de 2..4 é ignorado. Ordem dos erros na entrada: `room_not_found`, `expired`,
`version_mismatch`, `in_progress`, `room_full`. Em produção o Worker rejeita requisição sem `Origin` (403); o
servidor Bun local aceita.

Cota diária do plano gratuito esgotada ou serviço fora do ar: a conexão nem abre (ou cai sem código). O
cliente trata os dois casos como `server_unreachable` (§6.11).

`data` de `signal` (o servidor não lê; limite `max_text_bytes`): `{"kind":"offer","sdp":"…"}`,
`{"kind":"answer","sdp":"…"}`, `{"kind":"candidate","media":"0","index":0,"name":"candidate:…"}`.

Negociação WebRTC (só no build Web e com `net.rtc_enabled`): o **cliente** é quem oferta. Ao receber
`joined`, cria `WebRTCPeerConnection.initialize({"iceServers":[{"urls": net.ice_servers}]})` e dois canais
pré-negociados: `create_data_channel("event", {"negotiated": true, "id": 1})` e
`create_data_channel("state", {"negotiated": true, "id": 2, "ordered": false, "maxRetransmits": 0})`; chama
`create_offer()`. O anfitrião, ao receber `peer_joined`, cria a conexão e os mesmos dois canais e espera a
oferta. `session_description_created` → `set_local_description` → `signal`; `ice_candidate_created` →
`signal` (trickle). Cliente nativo nunca oferta: o enlace fica em relay sem nenhum caso especial.

### 4.3 Relay (WebSocket, quadros binários)

Cliente envia `[to u8]` seguido de um ou mais `{len u16, quadro}`; o servidor valida (remetente na sala,
`to` existe, não-anfitrião só `to = 1`, tamanho ≤ `max_binary_bytes`) e entrega a mesma mensagem com o
primeiro byte trocado por `from`. Não há broadcast. O servidor nunca olha os quadros.

**Uma mensagem por tick por direção.** Cada mensagem que chega ao Durable Object gasta cota (§5.4), então no
caminho RELAY o emissor junta o quadro de estado e o quadro de eventos do mesmo tick numa única mensagem
WebSocket, e envia na taxa `net.relay_hz`. Evento urgente (`EV_HUNT_END`) sai na hora. No caminho RTC cada
quadro continua sendo uma mensagem do seu canal. Taxa do relay: média `relay_hz` com rajada de 2
(`RELAY_BURST`).

### 4.4 Enlace (`NetLink`): caminhos, sequência e troca

- Todo enlace nasce em **RELAY** e já funciona (o lobby não espera o ICE). Quando os dois canais ficam
  `STATE_OPEN`, o lado passa a **enviar** por RTC. Receber vale sempre pelos dois caminhos.
- Se os canais não abrirem em `net.ice_timeout_s`, a conexão WebRTC é fechada e o enlace fica em RELAY até o
  fim da sala (é o fallback de D4b: nenhum código de jogo percebe).
- **Pista de estado** (`lane 0`): `seq` cresce por quadro, por direção. O receptor descarta quadro que não
  seja mais novo que o último aceito (`NetCodec.seq_newer`). Ao drenar vários de uma vez (rajada depois de
  um engasgo de TCP no relay), aplica só o snapshot/estado de maior `seq`.
- **Pista de eventos** (`lane 1`): `seq` começa em 1 e cresce por quadro. O receptor entrega em ordem
  estrita, guarda adiantados (janela `net.reliable_window` = 64) e ignora repetidos. `ack` (em todo quadro,
  das duas pistas) = último `seq` de evento entregue em ordem. O emissor guarda os quadros não confirmados.
  Não há reenvio por tempo: os dois caminhos já são confiáveis enquanto vivem.
- **Rebaixamento** (RTC morreu no meio da sala: estado `FAILED`/`CLOSED`, canal fechado, ou
  `net.rtc_stall_s` sem receber por RTC com o WebSocket vivo): o lado volta a enviar por RELAY, reenvia os
  eventos não confirmados e manda `L_NEED_RELAY` para o outro lado fazer o mesmo. Não há nova promoção.
- Janela estourada ou WebSocket do servidor caído sem RTC aberto = enlace perdido (§6.9).
- **Keepalive**: caminho RTC ocioso manda um quadro de ack a cada `rtc_stall_s/3`.
- **Vigia de silêncio**: pausado durante `LOADING` e zerado quando o próprio peer fica sem fazer poll por mais
  de metade de `rtc_stall_s` (aba congelada ou engasgo local; evita rebaixar por culpa própria).

### 4.5 Registros de jogo

Direção: H = anfitrião, C = cliente. Pista: E = eventos (confiável, ordenado), S = estado (descartável).

| Registro | Dir. | Pista | Frequência | Corpo | Bytes |
|---|---|---|---|---|---|
| `L_READY` | C→H | E | ao mudar | `ready u8, weapon0 u8, weapon1 u8, dog u8, token u32` | 8 |
| `L_LOBBY` | H→C | E | ao mudar | `state u8, map u8, contract u8, n u8, n×{slot u8, flags u8 (b0 pronto, b1 anfitrião, b2 carregou, b3 rtc), weapon0 u8, dog u8}` | 4+4n |
| `L_START` | H→C | E | 1× | `map u8, contract u8, rng_seed u32, player_count u8, slots_mask u8, dog[4] u8` | 12 |
| `L_LOADED` | C→H | E | 1× | — | 0 |
| `L_GO` | H→C | E | 1× | — | 0 |
| `L_NEED_RELAY` | ambos | E | raro | — | 0 |
| `H_SNAPSHOT` | H→C | S | `net.snapshot_hz` (10) | ver abaixo | ≤ 286 |
| `C_STATE` | C→H | S | `net.hunter_state_hz` (10) | `HUNTER_STATE` | 14 |
| `EV_BOAR_SPAWN` | H→C | E | por javali | `id u8, type u8, weight u16 (×0,01 kg), xz 2×u16, yaw u8` | 9 |
| `EV_BOAR_HIT` | H→C | E | por acerto aceito | `id u8, zone u8, shot_id u32, damage u16 (×0,1)` | 8 |
| `EV_BOAR_ATTACK` | H→C | E | por investida que acertou | `id u8, victim_slot u8` | 2 |
| `EV_BOAR_DEATH` | H→C | E | por abate | `id u8, xz 2×u16, yaw u8, killer_slot u8, zone u8, flags u8 (b0 um tiro, b1 limpo), reward u32, killed u8, total u8` | 15 |
| `EV_CROP_EATEN` | H→C | E | ≤ 1/tick | `n u8, n×patch u16` | 1+2n |
| `EV_BAIT` | H→C | E | por ceva | `xz 2×u16, duration_s u8` | 5 |
| `EV_DOG_MARK` | H→C | E | por marcação | `owner u8, boar u8, duration (×0,1 s) u8` | 3 |
| `EV_DOG_CMD` | H→C | E | por comando | `owner u8, cmd u8 (0 Pega, 1 Volta)` | 2 |
| `EV_MESSAGE` | H→C | E | raro | `target_slot u8 (255 = todos), msg u8` | 2 |
| `EV_HUNT_END` | H→C | E | 1× | `outcome u8, crop u16 (×0,01 %), duration_s u16, killed u8, total u8, n u8, n×{slot u8, kills u8, money u32}` | 8+6n |
| `C_SHOT` | C→H | E | por disparo | `shot_id u32, weapon u8, origin xz 2×u16, origin_y i16 (cm), n u8, n×{boar u8, zone u8, damage u16 (×0,1), dist u16 (×0,1 m)}` | 12+6n |
| `C_CHARGE_HIT` | C→H | E | por investida sofrida | `boar u8` | 1 |
| `C_BAIT` | C→H | E | por ceva | `xz 2×u16` | 4 |
| `C_DOG_CMD` | C→H | E | por comando | — | 0 |

`msg` de `EV_MESSAGE`: 0 vara entrou, 1 solitário, 2 cachaço (`hunt_controller.gd:13–15`); 3 cão não
farejou, 4 cão recuou, 5 cão pronto (`dog.gd:36–38`). O texto continua no pacote B.

**`HUNTER_STATE` (14 bytes):** `xz 2×u16, y i16 (cm), yaw u16, pitch i8 (graus), speed u8 (×0,05 m/s),
flags u8 (NetCodec.HF_*), weapon u8, health u8 (ceil), shot_seq u8` (contador de disparos: quem recebe
toca `play_fire` + som quando muda).

**`H_SNAPSHOT`:**
```
t_ms u32            relógio de sessão do anfitrião (soma de delta desde L_GO)
crop u16            saúde da lavoura ×0,01 %
killed u8, total u8
flags u8            b0 javalis na lavoura
n_hunters u8        n × { slot u8, HUNTER_STATE }                15 B cada (todos, inclusive o anfitrião;
                                                                  quem recebe ignora o próprio slot)
n_boars u8          n × { id u8, xz 2×u16, yaw u8, st u8 }        7 B cada, só vivos
                      st: b0–3 estado (NetCodec.BOAR_STATES), b4 ferido, b5 comendo no lugar,
                          b6 aproximando para investir, b7 alterna a cada nova investida
n_dogs u8           n × { owner u8, xz 2×u16, yaw u8, st u8, health u8 }   8 B cada
                      st: b0–2 estado (NetCodec.DOG_STATES), b3 recuando, b4 mordendo
```
Altura (Y) de javali e cão não trafega: cada peer calcula pelo próprio heightmap. Velocidade de javali e cão
é derivada do deslocamento interpolado.

### 4.6 Orçamento de banda (sala de 4, contrato 5, teto de 26 javalis vivos, 4 cães)

| Fluxo | Aplicação | No fio (+~85 B de IP/UDP/DTLS/SCTP) | Taxa |
|---|---|---|---|
| Snapshot máximo (9 + 61 + 183 + 33 + cabeçalhos 8) | 294 B | ~380 B | 10 Hz → **3,8 kB/s = 30 kbit/s** por cliente |
| Snapshot típico (2 jogadores, 12 javalis, sem cão) | 134 B | ~220 B | 10 Hz → 2,2 kB/s |
| `C_STATE` | 22 B | ~107 B | 10 Hz → 1,1 kB/s = 9 kbit/s por cliente |
| Eventos (pior segundo: 5 canteiros/tick + tiros) | ~30 B/tick | — | < 0,5 kB/s |

| Papel | Download | Upload | Dados por hora |
|---|---|---|---|
| Cliente | ≤ 4,3 kB/s (35 kbit/s) | ≤ 1,5 kB/s (12 kbit/s) | ~15 MB + ~5 MB |
| Anfitrião (3 clientes) | ≤ 4,5 kB/s | ≤ 13 kB/s (104 kbit/s) | ~16 MB + ~47 MB |

Meta de contrato: **download do cliente ≤ 5 kB/s (40 kbit/s)**, quadro de estado ≤ 1100 bytes (cabe num
pacote; mensagem não confiável fragmentada se perde inteira). Folga existe: subir caçadores para 20 Hz custa
+1,1 kB/s por cliente; mandar só javalis que se moveram economizaria ~40% do snapshot, mas exige linha de
base num canal sem garantia e não compensa a 30 kbit/s. Taxas ficam em `data/net.json`. Pelo relay o custo em
bytes é equivalente (TCP/TLS/WS no lugar de UDP/DTLS/SCTP); o que limita o relay não é banda, é a cota de
mensagens do plano gratuito (§5.4).

---

## 5. Servidor e hospedagem

### 5.1 Arquitetura do `server/`

Três peças: uma lógica neutra e duas entradas finas que só adaptam o runtime.

`rooms.js` (ES module, nenhuma API de Bun, Node ou Workers, nenhum `import`) é a lógica de **uma sala** e
**não guarda estado**: a cada chamada a entrada entrega a lista das conexões vivas da sala. É isso que a
faz sobreviver à hibernação do Durable Object (a memória do objeto some, as conexões e seus anexos ficam)
sem nenhum caso especial, e de quebra a deixa trivial de testar.
```js
// peer = { meta, vol, send(data /* string | Uint8Array */), close(code, reason), setMeta(meta) }
//   meta: sobrevive à hibernação (anexo do WebSocket, ≤ 2 kB)
//         { id, host, name, v, proto, code, locked, born }      locked e born só valem no anfitrião
//   vol:  volátil, pode zerar a qualquer momento                 { tokens, last }  (balde de taxa)
export function parseHello(url)                       // query → { t, code, v, proto, name, want } | null
export function makeCode(config, random)              // código novo para t=create
export function admit(peers, hello, config, now)      // → { meta } | { error, close, extra }
export function welcome(peers, peer)                  // created/joined para ele, peer_joined para os demais
export function onMessage(peers, peer, data, config, now)   // texto: signal/lock/ping/leave; binário: relay
export function onClose(peers, peer)                  // peer_left; se era o anfitrião: host_left + fecha todos
```
Não há temporizador: idade máxima da sala (`room_max_age_s`) é conferida em `admit` e `onMessage`. Nada em
disco, nenhum log de conteúdo.

`worker.js` (produção) e `server.js` (Bun local) fazem o mesmo roteiro: caminho ≠ `/ws` → 404; sem
`Upgrade: websocket` → 426; `Origin` fora da lista → 403; `parseHello` inválido → 400; em `t=create` sorteiam
o código; acham a sala pelo código; aceitam o WebSocket; chamam `admit` e, conforme o resultado, `welcome`
ou `error` + close. Diferença única: onde moram as conexões.

| | `worker.js` (Cloudflare) | `server.js` (Bun local) |
|---|---|---|
| Sala | `env.ROOMS.idFromName(code)` → objeto `Room` | `Map code → Array<peer>` em memória |
| Conexões vivas | `ctx.getWebSockets()` | o array da sala |
| `meta` | `ws.serializeAttachment` / `deserializeAttachment` | campo do objeto |
| `vol` | `WeakMap` na instância (zera ao hibernar: aceitável) | campo do objeto |
| Origem | lista de `ALLOWED_ORIGINS` + localhost | aceita localhost e ausência de `Origin` (clientes Godot nativos não enviam) |
| Uso | produção | desenvolvimento, `net_test`, `coop_probe.py` |

Se o Bun falhar como servidor local no Windows: escrever `server/server_node.js` com `ws`; `rooms.js` e os
testes não mudam.

### 5.2 Produção: Worker + Durable Object

- Classe `Room` com a **WebSocket Hibernation API**: `ctx.acceptWebSocket(server, [String(id)])`, handlers
  `webSocketMessage`, `webSocketClose`, `webSocketError` (os dois últimos chamam `onClose` tirando o socket
  que fechou da lista). Sem `storage`, sem alarmes, sem `setInterval` (temporizador manteria o objeto
  acordado e gastaria duração).
- No construtor: `ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('{"t":"ping"}',
  '{"t":"pong"}'))`: o ping é respondido sem acordar o objeto.
- Sala vazia não deixa rastro: sem conexões e sem storage, o objeto é descartado pela plataforma.
- `wss://` com certificado válido vem do domínio `*.workers.dev`: nada a configurar.

`server/wrangler.toml`:
```toml
name = "javali-salas"
main = "worker.js"
compatibility_date = "2026-11-01"

[[durable_objects.bindings]]
name = "ROOMS"
class_name = "Room"

[[migrations]]
tag = "v1"
new_sqlite_classes = ["Room"]      # o plano Free só tem Durable Objects com backend SQLite

[vars]
ALLOWED_ORIGINS = "https://ORIGEM-DO-GITHUB-PAGES"   # MARCADOR: a coordenação confere no repositório
```
URL de produção: `wss://javali-salas.acpw01.workers.dev/ws` (substitui o marcador `SUBDOMINIO`). O Worker
rejeita requisição sem `Origin` (403); o servidor Bun local aceita.

### 5.3 Limites (`server/config.js`) e segurança (D15)

| Chave | Valor | Para quê |
|---|---|---|
| `ALLOWED_ORIGINS` (em `wrangler.toml`) | origem do GitHub Pages do jogo | única origem aceita em produção, além de `http://localhost:*` e `http://127.0.0.1:*` (testes Web) |
| `max_peers_per_room` | `4` | |
| `max_text_bytes` | `8192` | JSON (SDP tem ~1–2 kB) |
| `max_binary_bytes` | `2300` | 1 byte de rota + até 2 quadros de 1100 com prefixo de tamanho |
| `rate_msgs_per_s` / `rate_burst` | `60` / `120` | balde por conexão; uso legítimo máximo: anfitrião com 3 enlaces em relay = 30/s |
| `room_max_age_s` | `21600` | sala esquecida morre em 6 h (conferido na próxima mensagem ou entrada) |
| `room_code_length` / `room_code_alphabet` | `5` / `"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"` | 33,5 milhões de códigos |
| `max_name_chars` | `12` | nome cortado e sem caracteres de controle |

Outras regras: só upgrade WebSocket em `/ws` (nenhum arquivo servido, nenhuma outra rota); nenhum estado
persistente; mensagem inválida fecha a conexão em vez de responder em laço; sala trancada durante a caçada.

O que **não** dá para ter no Worker: teto global de salas ou de conexões por IP (cada sala é um objeto
isolado; um contador global exigiria estado compartilhado). O teto global de fato é a cota do plano (§5.4).
Código de sala: com 5 caracteres e poucas salas abertas, acertar uma sala no chute é improvável mesmo
gastando a cota do dia inteira em tentativas (100 mil tentativas contra 10 salas abertas ≈ 3% de chance de
acertar uma), e a sala em caçada está trancada. A checagem de `Origin` barra outras páginas, não um script:
alguém determinado consegue esgotar a cota do dia (risco R3).

### 5.4 Cota do plano gratuito e dimensionamento

Limites do plano Free (documentação do Cloudflare): 100.000 requests/dia de Durable Objects; 20 mensagens
WebSocket **de entrada** = 1 request (≈ 2 milhões de mensagens/dia; saída não conta); 13.000 GB-s/dia de
duração (≈ 28 h de objeto acordado por dia, a 128 MB); objeto hibernado não gasta duração; cota estourada =
operações falham até 00:00 UTC (21h de Brasília).

| Uso | Mensagens de entrada no objeto | Requests |
|---|---|---|
| Criar ou entrar numa sala | 1 upgrade | 1 (+ 1 request do Worker) |
| Negociar WebRTC de um par (2 SDP + candidatos) + lobby antes da promoção | ~30–40 | ~2 |
| Ping (a cada `net.ping_s` = 15 s por conexão; contado aqui como se gastasse, não confirmado) | 240/h por conexão | 12/h por conexão |
| **Par em relay** a `net.relay_hz` = 10 (1 mensagem por tick em cada direção; as duas entram no objeto) | **20/s = 72.000/h** | **3.600/h** |

| Cenário | Consumo | Quanto cabe por dia |
|---|---|---|
| Sala de 4 toda em WebRTC | ~48 requests/h, objeto hibernado | ~2.000 horas de sala: a cota não limita |
| 1 par em relay | 3.600 requests/h + objeto acordado | **≈ 27 horas de par em relay por dia** (requests) e ≈ 28 h de sala acordada (duração): os dois tetos coincidem |
| Sala de 4 com os 3 clientes em relay | 10.800 requests/h | ≈ 9 horas de sala por dia |

Ou seja: o plano gratuito sustenta com folga um jogo em que a maioria dos pares fecha WebRTC, e cerca de
27 horas diárias somadas de jogadores em fallback. Baixar `net.relay_hz` para 8 leva a ≈ 35 horas de par
(aí o teto de duração de 28 h de sala passa a mandar). O relay-only (`rtc_enabled: false`) serve para
testes, não para publicar.

Quando a cota acaba: conexões novas falham → o lobby mostra `server_unreachable` (§6.11), sem travar. Em
caçada: pares em WebRTC seguem jogando; pares em relay perdem o enlace e caem nas regras de §6.9 (cliente
termina `DISCONNECTED` com os abates pagos; anfitrião segue). Volta sozinho às 21h de Brasília.

Fora da v1: o Cloudflare oferece TURN gratuito (1.000 GB/mês) com credenciais geradas pelo próprio Worker;
poderia substituir o relay WebSocket para pares em 4G sem gastar a cota de mensagens.

### 5.5 Rodar, testar e publicar

| O quê | Comando (a partir de `server/`) | Observação |
|---|---|---|
| Testes da lógica | `bun test` | `rooms.test.js`, sem rede |
| Servidor local | `bun server.js --port 8787` | é o que `net_test` e `coop_probe.py` sobem, em porta livre |
| Conferir o protocolo | `bun check.js <url> [--origin <origem>]` | mesmo roteiro contra o Bun local, o `wrangler dev` e a produção |
| Worker local | `bun x wrangler dev --port 8788` | NÃO funciona em Bun (Miniflare responde 503): o Worker é verificado publicando e rodando `bun check.js <url de produção>` |
| Publicar | `bun x wrangler deploy` | credencial do `wrangler login` já está salva na máquina |

Estado em 2026-11-13: Bun 1.4.4 instalado; `bun x wrangler` (4.161.0) fez `login` e `whoami` sem Node.
`wrangler deploy` funciona em Bun, sem Node; o subdomínio `workers.dev` é `acpw01`. `wrangler dev` não
funciona em Bun (ver tabela).

O cliente escolhe a URL em `data/net.json`: `server_url` (produção) no build Web publicado;
`dev_server_url` em nativo e em página servida de `localhost`. Enquanto `server_url` contiver o marcador
`SUBDOMINIO`, `Net.is_configured()` devolve `false` no build publicado e o lobby mostra "O modo com amigos
ainda não foi configurado."

---

## 6. Mudanças por sistema

### 6.1 Montagem e papéis (`hunt_controller.gd`)

`HuntController` continua raiz única de `hunt.tscn`. O papel vem de `Net.get_role()` lido uma vez em
`_assemble` (78). OFFLINE = código de hoje, linha por linha.

| Trecho | HOST | CLIENT |
|---|---|---|
| RNG (87–90) | `rng_seed` de `L_START` (nunca 0) | o mesmo seed (lavoura com o mesmo jitter visual) |
| Flora (130) | `build_flora(density, true)` | idem |
| Caçadores (160–173) | `Player` local em `PlayerSpawn` deslocado `(slot − (n−1)/2) × coop.spawn_spacing_m` no eixo direito; `RemoteHunter` para cada outro slot (`AssetLoader.instantiate(ScenePaths.REMOTE_HUNTER)` + `setup_remote`) | idem |
| Cães (176–189) | um `Dog` por slot com cão (`NetPeerInfo.dog_id`), `owner_slot` | `DogPuppet` criado pela réplica ao ver o cão no snapshot |
| Javalis (192–194) | `spawner.setup` com contrato escalado; cria `HuntHostSync` | não chama `spawner.setup`; cria `HuntReplica` |
| Início (205–209) | `Net.bind_world(self)`; espera `Net.hunt_go` com o overlay "Aguardando os outros caçadores…"; depois `spawner.begin()` e `hunt_started` | `Net.bind_world(self)` (Net envia `L_LOADED`); espera `Net.hunt_go`; `hunt_started` |
| Getters de javali (439–472) | `spawner` | `HuntReplica` (mesmas respostas, a partir das réplicas) |
| `debug_*` (509–522) | como hoje | sem efeito |

`HuntHostSync` (nó filho): escuta `spawner`/`Boar.died`/`CropManager.patch_eaten`/ceva/cão, enfileira os
`EV_*`, escreve o snapshot e aplica os `C_*`. `HuntReplica` (`extends Node3D`; as réplicas são filhas dela;
`setup(world: HuntWorld, heightmap: Heightmap, map_rect: Rect2, crop: CropManager)` sem depender de
`HuntController`, para ser testável isolada): cria e move réplicas, aplica eventos, enfileira os `C_*`,
reemite os `GameEvents` locais.

Membros internos novos de B (uso só em `src/hunt`, `src/boars`, `src/world`): `BoarSpawner.boar_added(boar:
Boar)`; `MapRoot.get_flora_positions(id: StringName) -> PackedVector2Array`; `Boar`: sinais `hit_applied(boar,
zone, damage, shot_id)` e `attacked(boar, victim_slot)`, `killer_slot`, `get_hit_zone(zone) -> HitZone`,
`get_yaw() -> float`, `net_state_byte() -> int`, `net_confirm_charge_hit(victim_slot: int) -> bool`, e os
estáticos `make_hit_zones`, `basis_for`, `charge_hits` (§6.3); `HuntController.place_bait(at: Vector3)` e
`get_baits() -> Array[Bait]`; `CropManager.set_replicated_attack(on: bool)`, `is_under_attack() -> bool`,
`get_eaten_indices() -> PackedInt32Array`.

### 6.2 Caçador remoto (Pacote A)

- `RemoteHunter extends PlayerBase`: `collision_layer = 0`, `collision_mask = 0`, sem `CollisionShape3D`,
  nunca chama `move_and_slide`. Filho `Visual` = `ScenePaths.HUNTER_VISUAL` ou
  `HunterVisualBase.create_fallback()`; `Label3D` com o nome, filho de `NameAnchor`, billboard, tamanho
  fixo, `no_depth_test = true`, cor `HunterVisualBase.slot_color(slot)`, oculto além de `coop.name_tag_max_m`.
- `net_apply_state`: guarda as 2 últimas amostras e interpola com `net.hunter_interp_delay_ms` (150);
  atualiza `global_position`, `rotation.y`, `velocity` (lida por `boar.gd:357`), e alimenta o visual:

| Estado recebido | Chamada no `HunterVisualBase` |
|---|---|
| `speed` | `set_locomotion(speed)` todo frame |
| `HF_CROUCH`, `HF_AIM`, `pitch` | `set_crouching`, `set_aiming`, `set_look_pitch(deg_to_rad(pitch))` |
| `weapon` mudou / `HF_UNARMED` | `set_weapon(id)` / `set_weapon(&"")` |
| `shot_seq` mudou | `play_fire()` + `Sfx.play_3d(shot_sfx, get_muzzle().global_position)` |
| `HF_RELOAD` subiu | `play_reload(Data.get_weapon(id)["reload_s"])` |
| `health` caiu | `play_hit()` |
| `HF_ALIVE` caiu | `play_death()` |

- `is_crouching()`, `get_noise_radius()` (mesma regra de `player.gd:246–253` a partir de `speed` e flags),
  `get_eye_position()`, `is_alive()`, `get_health()` respondem pelo último estado. `apply_damage` é no-op (o
  dano é da máquina do dono). `is_present()` fica `false` após `net.peer_absent_s` sem estado.
- `Player.net_write_state` escreve os 14 bytes do próprio estado (`NetCodec.HUNTER_STATE_BYTES`). `player.gd`
  não muda de comportamento. `RemoteHunter.net_write_state` devolve os últimos 14 bytes recebidos: o
  anfitrião reenvia todos os caçadores sem caso especial.
- `setup_remote(slot: int, display_name: String, weapon_id: StringName, world: HuntWorld)` está declarado em
  `PlayerBase` (`src/core/player_base.gd`; no-op nas outras classes) e implementado em `RemoteHunter`.
- Passos de aliado: `RemoteHunter` toca `step_grass` em 3D pela distância percorrida (mesma passada de
  `player.gd:689–695`).

### 6.3 Javalis

**Pontos que presumem jogador único hoje (todos no Pacote B):**

| Arquivo:linha | Hoje | Em rede (anfitrião) |
|---|---|---|
| `boar.gd:343–363` `_perceive` | testa `_world.get_player()` | percorre `get_hunters()` vivos e presentes, do mais próximo ao mais distante; para no primeiro detectado; guarda `_target_hunter` |
| `boar.gd:366–379` `_has_line_of_sight` | um raio | no máximo **um raio por javali por percepção** (só o candidato mais próximo dentro do alcance e do cone) |
| `boar.gd:382–389` `_after_perception` | ameaça = posição do jogador | posição de `_target_hunter` |
| `boar.gd:402–415` `_wants_charge`, `435–448` `_reevaluate` | jogador vivo? | alvo válido; senão o caçador vivo mais próximo; nenhum → `_resume()` |
| `boar.gd:622–638` `_tick_approach`, `693–701` `_tick_scrape` | segue/encara o jogador | segue/encara `_target_hunter`; alvo morreu ou saiu → realvo ou `_resume()` |
| `boar.gd:733–752` `_try_charge_hit` | testa o jogador e aplica dano | testa só caçadores `is_local()`; para os remotos espera `C_CHARGE_HIT` e então `_enter_recover()` + `EV_BOAR_ATTACK` |
| `boar.gd:791–814` `_on_hit_received` | ameaça = posição do jogador | posição de `get_hunter(hit.shooter_slot)`; vira o alvo; guarda `killer_slot` |
| `boar.gd:280–287` `apply_dog_damage` | — | `killer_slot` = dono do cão |
| `boar_spawner.gd:171–180` | só `GameEvents.shot_fired` (tiro local) | também `notify_shot` chamado por `HuntHostSync` a cada `C_SHOT` |
| `boar_spawner.gd:183–197` térmica | jogador local | fica local; `HuntReplica` repete a lógica nas réplicas |
| `boar_herd.gd:65` `get_retreat` | posição do jogador | posição da ameaça que disparou a fuga (sem mudança de assinatura) |

`_target_hunter` nunca é guardado sem validar (`is_instance_valid`, `is_alive()`, `is_present()`).
Custo: com 26 javalis a 5 Hz são ≤ 130 raios/s no pior caso (orçamento atual: 100/s; subir a linha para 130).

**Réplica (`BoarPuppet`, cliente):** raiz `Node3D` + `Visual` + 4 `HitZone`, montados por auxiliares
estáticos extraídos de `boar.gd` sem mudar o comportamento: `Boar.make_hit_zones(parent, boar_id,
body_scale) -> Array[HitZone]` (de 1011–1030), `Boar.basis_for(yaw, up) -> Basis` (de 891–899),
`Boar.charge_hits(pos, dir, body_scale, boar_y, target) -> bool` (geometria de 739–748).
- Interpolação entre os dois snapshots que cercam `t_render = t_anfitrião_estimado −
  net.boar_interp_delay_ms` (200). Sem snapshot mais novo: segura a última pose. Y e inclinação pelo
  heightmap local.
- Do snapshot: `set_locomotion` (deslocamento), `set_eating` (b5), `set_wounded` (b4); transição de estado →
  `play_alert` + `boar_snort_alert`, `play_scrape` + `boar_scrape`, rugido ao entrar em `charge`, guincho do
  leitão ao fugir. Grunhidos de fundo são sorteados localmente (cosmético).
- Eventos: `EV_BOAR_SPAWN` cria; `EV_BOAR_HIT` → `play_hit(zone)` + guincho + `GameEvents.boar_hit` (pulado
  se o tiro é do jogador local, que já previu); `EV_BOAR_ATTACK` → `play_attack`; `EV_BOAR_DEATH` → pose
  final, `HitZone.disable()`, `play_death`, `boar_killed` + `boar_counts_changed`.
- **Tiro:** a `HitZone` da réplica recebe `receive_hit` de `weapon.gd:209` como hoje. `HuntReplica` junta os
  acertos do mesmo `shot_id` e, no `GameEvents.shot_fired` (emitido depois dos bagos, `weapon.gd:127–130`),
  fecha um `C_SHOT`. Na hora do acerto já emite `GameEvents.boar_hit` local (hitmarker imediato) e
  `play_hit`.
- **Validação no anfitrião (`HuntHostSync`):** javali vivo; `damage ≤ weapon.damage`; `n ≤ weapon.pellets`;
  `dist ≤ weapon.max_range_m`; `|distância(javali no anfitrião, origem) − dist| ≤
  net.hit_claim_tolerance_m` (12 m). Passou: monta `HitInfo` (`shooter_slot`, `shot_id`, `zone`, `damage`) e
  chama o mesmo `_on_hit_received`. Todo `C_SHOT` chama `spawner.notify_shot`.
- **Investida:** em `charge`, a réplica roda `Boar.charge_hits` contra o `Player` local; acertou (uma vez por
  investida, pelo bit b7): `player.apply_damage(charge_damage, pos, knockback)` local, `play_attack`,
  `C_CHARGE_HIT`.
- `shot_id` passa a carregar o slot nos 8 bits altos. Quem conta "meu tiro" filtra por
  `NetCodec.shot_slot(shot_id) == world.get_local_slot()`: `hud.gd:537` (hitmarker) e
  `hunt_controller.gd:312` (tiros certeiros). `Boar.is_one_shot` (201) continua correto com vários atiradores.
  O `C_SHOT` de tiro que errou vai com `shot_id = NetCodec.make_shot_id(slot, 0)`. O cliente ignora o campo
  `killed` do snapshot: os abates da equipe vêm de `EV_BOAR_DEATH`.

### 6.4 Mundo e lavoura

| Item | Determinístico entre peers? | Evidência | Ação |
|---|---|---|---|
| Heightmap | sim | `FastNoiseLite` com `terrain_seed` do mapa (`heightmap.gd:24–34`; `mato_grosso_map.tscn:13`), mesmo `.wasm` em todos | nenhuma |
| Props, água, obstáculos | sim | marcadores da cena (`map_root.gd:99–190`) | nenhuma |
| **Flora** | **não, entre qualidades** | um RNG só (`map_root.gd:277–278`); `grass_tuft`/`shrub` mudam de quantidade com a densidade (26, 336–339) e são sorteados antes de `ipe` e `termite_mound` (ordem das chaves em `mato_grosso_map.tscn:15–21`) e antes de todas as `FloraZone` (298–316) | `build_flora(density, sync_layout)`: com `sync_layout`, o laço sorteia sempre a quantidade cheia (densidade 1,0) e só **guarda** as primeiras `round(count × density)` de capim/arbusto. Troncos, cupinzeiros e obstáculos ficam iguais em todos. Solo chama com `false`: layout de hoje |
| Escala/giro da flora | não (visual) | `flora_scatter.gd:93–94` usa o mesmo RNG depois | aceito: colisor do tronco tem raio fixo |
| Canteiros da lavoura | sim (índices) | grade por retângulo (`crop_manager.gd:150–179`) | índice `u16` identifica o canteiro em todos (2555 no Mato Grosso) |
| Jitter dos canteiros | só com o mesmo seed | usa o RNG da caçada (`hunt_controller.gd:138`; `crop_manager.gd:163–167`) | cliente usa o `rng_seed` de `L_START` |
| Nascimento/peso dos javalis | só no anfitrião | `boar_spawner.gd:131–159` | `EV_BOAR_SPAWN` |
| `randf` global em mundo/javali/cão | não existe | busca em `src/{world,hunt,boars,dogs}` | nenhuma |

Lavoura no cliente: o `CropManager` é o mesmo, sem comedores registrados (o `_process` sai em 116).
`EV_CROP_EATEN` → `apply_eaten(indices)` chama `_eat_patch` (220) para cada índice;
`set_replicated_health(pct)` a cada snapshot atualiza a saúde e passa por `_emit_health` (130–140), então
`crop_health_changed` sai com o mesmo passo do solo. `crop_under_attack` é reemitido pela réplica quando o
bit b0 do snapshot muda. No anfitrião, `_eat_patch` emite `patch_eaten(index)` para o `HuntHostSync`.

### 6.5 Cães (fase própria)

| `dog.gd` | Hoje | Em rede |
|---|---|---|
| 97, 174–181 | segue `_world.get_player()` | segue `get_hunter(owner_slot)`; dono morto: fica onde está; dono saiu: cão removido |
| 101–102 | todo cão ouve `GameEvents.dog_command_requested` | só o cão do slot local conecta; os outros recebem `command()` via `C_DOG_CMD` |
| 103–104, 137, 142, 382, 397 | emite sinais de cão no barramento | só o cão do jogador local emite; os demais vão no registro `DOG` do snapshot e o cliente dono reemite |
| 208, 220, 374 | mensagens de HUD | `EV_MESSAGE` endereçado ao dono |
| 336–339 | marca javali | marca vale para o time: `EV_DOG_MARK`; todos emitem `dog_marked_boar` |

Cliente: `DogPuppet` (visual + interpolação; `play_point`, `play_bite`, `set_retreating`, latidos por
temporizador local). `has_dog()`/`get_dog_*` respondem pelo cão do jogador local. Até a fase dos cães, o
lobby mostra "Cães ainda não entram no modo com amigos" e `dog` vai 255.

### 6.6 Itens

| Item | Em rede |
|---|---|
| `corn_bait` | cliente: `item_used` → `C_BAIT`; anfitrião: `_place_bait` (363) + `EV_BAIT`; clientes criam o `Bait` visual e emitem `bait_placed` |
| `scout_drone` | local: revela pelas réplicas (`get_alive_boar_ids`/`get_boar_position` da `HuntReplica`) |
| `thermal_scope` | local: `HuntReplica` destaca réplicas a ≤ `highlight_range_m` |
| `medkit`, `binoculars`, colete, munição | locais, sem rede |

Consumíveis: cada máquina conta os seus pelo `GameEvents.item_used` local (`hunt_controller.gd:319–322`).

### 6.7 HUD e minimapa (Pacote A)

- Minimapa (`minimap.gd:58–66`): `allies: PackedVector3Array` + `ally_colors: PackedColorArray`, pontos na
  cor do slot; preenchidos em `hud.gd:461–505` a partir de `get_hunters()` não locais.
- Mensagem de abate (`hud.gd:545–554`): `kill.killer_slot == local` → texto de hoje; senão, no contexto,
  "<Nome> abateu um javali: Macho, 132 kg" (formato `"<Nome> abateu um javali: <tipo>, <kg> kg"`, que evita
  erro de gênero com Fêmea/Leitão).
- Mensagens: "<Nome> foi abatido!", "<Nome> saiu da caçada", faixa "Anfitrião sem resposta…"
  (`net_stall_changed`), "Assistindo: <Nome>" (`spectate_changed`).
- Fim (`hud.gd:610–625`): `DEFEAT_DEATH` em rede → "Todos os caçadores caíram!"; `DISCONNECTED` →
  "Conexão perdida."
- `window.huntProbe` (`hud.gd:401–416`) ganha `slot`, `role`, `path`, `boars_alive`,
  `allies: [{slot, x, z}]` para os testes Web.

### 6.8 Morte, espectador e fim de caçada

- `Player._die` (`player.gd:814–831`) não muda. Em rede, passados `coop.spectate_delay_s` e havendo aliado
  vivo, o `Player` ativa `SpectatorCamera`: câmera em terceira pessoa a `coop.spectate_distance_m` atrás e
  `coop.spectate_height_m` acima do aliado, olhando na direção do olhar dele; a ação `fire` troca de alvo.
  Painéis de arma somem; lavoura e contagem ficam.
- `hunt_controller.gd:195, 254–255`: o controlador acompanha `is_alive()` de cada caçador e emite
  `hunter_died(slot)`. Condição de derrota vira "todos os caçadores presentes mortos" (no solo, igual ao
  `_player_died` de hoje, na mesma posição da ordem de §8.8 do contrato). `hunter_died(slot)` também é
  emitido no solo, para o caçador local (o HUD ignora o slot local). "Todos presentes mortos" conta quem
  ainda está na caçada; quem está só em silêncio curto vale pelo último estado.
- Só o anfitrião decide o fim (248–261). `_finish` (264–284) enfileira `EV_HUNT_END` e chama `Net.flush()`.
  O cliente, ao receber, roda o mesmo `_finish(outcome)` com a lavoura do evento.
- Pausa > "Desistir": anfitrião ("Encerrar a caçada para todos") → anfitrião `ABANDONED`, `EV_HUNT_END` +
  `Net.flush()`; clientes `ABANDONED` com `counts_for_progression = false` e abates pagos. Cliente ("Sair da
  caçada") → `Net.leave_room()` e resultado local `ABANDONED` com os próprios abates.
- Depois de `hunt.end_delay_s`, cada peer chama `Router.finish_hunt(result)` como hoje. A sala volta a LOBBY
  (o anfitrião destranca) e a tela de resultado oferece "Voltar para a sala".

### 6.9 Quedas, ausências e prazos

| Situação | Detecção | Efeito |
|---|---|---|
| Anfitrião saiu ou caiu | `host_left` do servidor, ou `net.host_timeout_s` (20) sem snapshot | cliente: `net_connection_lost()` → `Outcome.DISCONNECTED`; abates pagos, consumíveis descontados, sem bônus, sem progressão |
| Anfitrião congelado (aba em segundo plano, ligação) | `net.host_stall_warn_s` (2,5) sem snapshot | faixa no HUD; réplicas param; o caçador do cliente segue jogável e seus tiros ficam na fila. Voltou antes de 20 s: segue. Medido na F2: após 5 s de aba congelada o delta de `_process` é ~0,07 s (não carrega o tempo perdido); por isso os prazos usam relógio de parede. Ao acordar de um congelamento da própria máquina, os relógios de silêncio são zerados |
| Cliente saiu ou caiu | `peer_left`, ou `net.peer_timeout_s` (30) sem estado | `net_peer_left(slot)`: caçador e cão dele somem; a caçada segue; se não sobrar vivo, derrota |
| Cliente em silêncio curto | `net.peer_absent_s` (3) | `is_present() = false`: javalis o ignoram |
| Anfitrião perdeu a rede | WebSocket e todos os enlaces caídos | `net_connection_lost()` no anfitrião: remotos saem, ele **segue a caçada sozinho** (não encerra); mensagem "Conexão perdida: você continua sozinho." |
| Servidor de salas indisponível ou cota diária esgotada durante a caçada | WebSocket fechado ou envio falhando | enlaces em RTC continuam; enlaces em relay caem (linhas acima). Sem sala nova até o serviço voltar (a cota renova às 21h de Brasília) |
| Cliente em `LOADING` sem `L_GO` | `net.load_timeout_s` + `net.host_timeout_s` | cliente desiste (`DISCONNECTED`) |
| Reconexão pelo mesmo código | — | **fora da v1.** Sala trancada recusa `join`. Entra na F8 (mesma página, mesmo slot via `want` + `token`, `EV_FULL_SYNC`, `play_death(true)`); recarregar a página perde munição e contagem de consumíveis e exigiria gravar a caçada pendente |

`net_connection_lost()` vem antes de `room_error`. No cliente encerra `DISCONNECTED`; no ANFITRIÃO não
encerra: ele segue sozinho ("Conexão perdida: você continua sozinho."). Cliente removido por silêncio não é avisado:
encerra pelo próprio `host_timeout_s`. A sala destranca quando o anfitrião chama `Net.unbind_world`.

No celular, durante a caçada em rede, pedir `navigator.wakeLock.request("screen")` (falha silenciosa) para a
tela não apagar.

### 6.10 Economia e resultado

- Abate: o anfitrião calcula `Profile.kill_reward` como hoje (`hunt_controller.gd:340`) e envia o valor em
  `EV_BOAR_DEATH`. Cada máquina só acrescenta a `result.kills`/`money_from_kills` os abates com
  `killer_slot` local. `boar_killed` é emitido para todos os abates.
- Bônus: cada peer calcula `Profile.contract_bonus(map, index, crop)` com a lavoura de `EV_HUNT_END`. Valor
  cheio para cada um que estava na sala no fim, vivo ou espectador.
- Progressão: ao montar a caçada em rede, `result.counts_for_progression =
  Profile.is_contract_unlocked(map, index)`. `apply_hunt_result` só marca vencido/desbloqueia com ele
  `true` (§3.7). `result.gd:250–259` mostra, quando `false`: "Este contrato ainda não estava liberado para
  você: os prêmios foram pagos, mas o progresso não avança."
- `HuntRequest`: cada peer monta o seu com `Profile.build_hunt_request(map, index)` (`profile.gd:208`) e
  `Net` preenche `rng_seed`, `player_count`, `map_id` e `contract_index` (§3.4). Loadout, munição e itens
  nunca saem da máquina do dono.
- `Router.finish_hunt` e `apply_hunt_result` continuam sendo o único ponto de crédito, uma vez por máquina.
- Tela de resultado: "Seus abates: 7 · Equipe: 21 de 25", placar por jogador (`scoreboard`), títulos para
  `DISCONNECTED` ("Conexão perdida: a caçada foi encerrada"). `scoreboard`: uma entrada por slot que
  começou a caçada (inclusive quem saiu): `{slot, name, kills, money, weight_kg}`; `money` = só dinheiro de
  abate; vazio no solo. `DISCONNECTED` paga os abates, sem bônus e sem progresso; conta em `hunts_played`,
  não em `hunts_won`.
- Escala de javalis (`BoarSpawner.scale_groups`, função pura): `alvo = round(total_base ×
  coop.boar_count_mult_by_players[n − 1])`. Clona grupos inteiros em ordem (pulando os que têm `alpha`),
  cada clone com `spawn_zone + 1 + volta` e `delay_s = maior delay do contrato + coop.extra_group_delay_s ×
  (ordem do clone)`; o último clone perde membros do fim (nunca o líder) para fechar no alvo. O teto
  `hunt.max_alive_boars` (26) continua valendo: grupos esperam vaga. Exemplo: primeiro contrato (índice 0, 9
  javalis) → 14 e 23 com 2 e 4 jogadores; o maior caso atual é 63 javalis (cabem em ids de 1 byte).
- Medido nas fases F4/F5: snapshot de 254 B com 26 javalis; download do cliente ~3,5–4,6 kB/s (meta 5);
  anfitrião > 100 fps no desktop.

### 6.11 Menus e lobby (game-systems)

Fluxo: `MAIN_MENU` → `%FriendsButton` "Jogar com amigos (beta)" (sempre visível; o portão `?mp=1` / `-- --mp`
foi removido na F6) → `LOBBY`. Link com `?sala=CODIGO`: o Boot (`src/ui/boot/boot.gd`), depois do toque inicial,
lê `Net.take_url_room_code()`; se não vazio, vai ao `LOBBY` guardando o código como meta do `Router`
(`Lobby.INVITE_META`; a API do `Router` não mudou), e o lobby entra na sala sozinho com o nome salvo.

| Estado do lobby | Nós (`%` = nome único) |
|---|---|
| Entrada | `%NameEdit` (grava `player_name`), `%CreateRoomButton`, `%CodeEdit` (5 caracteres, maiúsculas), `%JoinButton`, `%BackButton` → `MAIN_MENU` |
| Conectando | `%StatusLabel`, `%CancelButton` (sempre habilitado) |
| Sala | `%RoomCodeLabel`, `%RoomLinkLabel`, `%CopyLinkButton` (Web: copia `Net.get_room_link()` e mostra "Link copiado!" por `Lobby.COPIED_FEEDBACK_S`; fora do Web copia o código), `Slot_0`…`Slot_3` (`Swatch`, `Info/Name`, `Info/Detail` = arma e "direto"/"via servidor", `Role` = "Anfitrião"/"Pronto"/"Preparando"), `%MapOption` e `Contract_<index>` (só anfitrião; só os contratos desbloqueados dele), `%ContractLabel`, `%HintLabel`, `LoadoutPanel` (`%WeaponSlot0`, `%WeaponSlot1`, `%DogOption`, `Item_<id>`), `%ReadyButton` (cliente), `%StartButton` (anfitrião; habilita só com todos os clientes prontos), `%ShopButton`, `%LeaveButton`, `%MessageLabel` |

`%BackButton` existe só na tela de entrada. O `Net` escolhe o contrato padrão da sala; o lobby só chama
`host_select_contract` quando o anfitrião escolhe outro, e `_begin_hunt` usa `Net.get_hunt_seed()`. O pronto
automático da F2 acabou: o cliente aperta `%ReadyButton`. O `LoadoutPanel` (`src/ui/common/loadout_panel.gd`,
`class_name LoadoutPanel`, `VBoxContainer`; `setup(root: Control, dog_locked_text: String = "")`, sinal
`changed`) é compartilhado com a Preparação (mesmos nós `%`). Cão desabilitado no lobby com "Cães em rede: em
breve." até a F7. Cada peer troca para a caçada ao receber `room_state_changed(LOADING)`. Resultado e loja em
sala: "Voltar à sala" → `LOBBY`; "Menu" chama `Net.leave_room()`.

Espectador e aliados no HUD (F6): ao morrer com aliado vivo, o `Player` cria uma `SpectatorCamera`
(`src/player/spectator_camera.gd`, `class_name SpectatorCamera`, extends `Camera3D`; `begin(local, world,
view_camera)`, `get_target_slot()`, `get_candidates()`, `switch_target()`, `is_active()`); é ela quem emite
`spectate_changed`. `Player.get_spectator()` e `Player.is_spectating()`. Troca de alvo por `fire`, `item_next`
ou `weapon_swap`; a câmera respeita só o terreno (sem colisão com obstáculos). O minimapa ganhou `ally_yaws`,
`ally_down`, `center_color` e `is_in_view()` (arrays paralelos a `allies`/`ally_colors`): aliado vivo = seta na
cor do slot, caído = X, fora do alcance = seta na borda; a bússola usa losango na cor do slot (oco se caído). A
etiqueta de nome some no aliado seguido. Em rede, o jogador caído pode abrir a pausa (P no desktop) para sair;
no solo continua recusando.

Sair do lobby para o menu chama `Net.leave_room()`. Loja aberta a partir da sala volta para o `LOBBY`.
Na sala, dica fixa: "Quem cria a sala deve ter o melhor aparelho e conexão. Se o anfitrião sair do jogo, a
partida termina para todos."

Mensagens de `Net.room_error` (texto em `src/net`, PT-BR):

| `code` | Mensagem |
|---|---|
| `not_configured` | "O modo com amigos ainda não foi configurado." |
| `server_unreachable` | "O servidor de salas está indisponível agora. Ele é gratuito e tem um limite diário, que renova às 21h (horário de Brasília). Tente mais tarde. O modo solo funciona normalmente." |
| `room_not_found` | "Sala não encontrada. Confira o código." |
| `room_full` | "A sala já está cheia (4 caçadores)." |
| `in_progress` | "A caçada dessa sala já começou. Espere ela terminar." |
| `version_mismatch` | "Sua versão (X) é diferente da do anfitrião (Y). Recarregue a página para atualizar." |
| `host_left` | "O anfitrião saiu. A sala foi fechada." |
| `connection_lost` | "Conexão perdida." |

Conexão ao servidor tem prazo `net.connect_timeout_s` (8); nenhuma tela bloqueia esperando rede.

### 6.12 Pausa e save

- Pausa: §3.7. `player.gd:627–634` e `649–651` continuam abrindo o overlay ao perder foco; em rede ele não
  pausa a árvore e o caçador fica parado e vulnerável.
- Save: só `settings.player_name`. Nome vazio aparece como "Caçador N" (N = slot + 1). Nada de sala, código
  ou resultado pendente é gravado.

---

## 7. Deltas para `docs/arquitetura.md` (colar depois da aprovação)

| Seção | Mudança |
|---|---|
| Cabeçalho | Versão do contrato **1.1**; "cinco agentes" não muda; citar `docs/multiplayer.md` como detalhe do protocolo. |
| §1 | Parágrafo novo "**Cooperativo (beta):**" com as 6 primeiras linhas de §1 deste documento. Em Caçada: "Derrota: lavoura em 0% ou todos os caçadores mortos". |
| §2 | Tabela de dependência = §3.2 daqui (linha N; `Net` entre os autoloads; `ScenePaths.REMOTE_HUNTER` para B). Árvore: `server/`, `data/net.json`, `src/core/net_codec.gd`, `net_peer_info.gd`, `hunter_visual_base.gd`, `src/net/`, `src/ui/lobby/`, `assets/models/hunter/`, `tests/net/`, `tests/net_test.tscn`. |
| §3 | `[autoload]`: acrescentar `Net="*res://src/net/net.gd"` depois de `Router`. Nota de ordem: "→ `Net` (último; usa `Data`, `Profile`, `Router`; offline não processa)". §3.1: "Caçador remoto (`RemoteHunter`) não ocupa camada: sem corpo e sem forma." §3.2: nada (o `include_filter` já cobre `data/net.json`). |
| §5 | Cinco linhas de §3.5; nota sobre `player_died` e sinais de cão valerem para o jogador local. |
| §6.2 | `func get_net() -> Dictionary`. |
| §6.3 | Texto de `apply_hunt_result`: "se `VICTORY` **e `result.counts_for_progression`**: marca o contrato vencido…". Settings: `player_name`. |
| §6.7 | Linhas novas: `NetCodec` (RefCounted, constantes e quantização da rede), `NetPeerInfo` (RefCounted, um jogador da sala), `HunterVisualBase` (Node3D, visão do aliado + fallback). |
| §6.8 | `RemoteHunter` (`src/player/remote_hunter.gd`, cena `.tscn`, PlayerBase, API de `PlayerBase`), `SpectatorCamera` (interna). |
| §6.9 | `HuntHostSync`, `HuntReplica`, `BoarPuppet`, `DogPuppet` (internas); `BoarSpawner.scale_groups`, `notify_shot`; `Dog.setup(..., p_owner_slot)`, `command()`; `MapRoot.build_flora(density, sync_layout)`. |
| §6.10 | `LoadoutPanel` (`src/ui/common/loadout_panel.gd`, VBoxContainer). |
| §6.11 (nova) | Autoload `Net`: bloco de §3.4 daqui, com os valores de stub. Classes de N: `NetSession`, `NetSignaling`, `NetLink`, `NetRtc`, `NetLoopback` (internas). |
| §7.11 (nova) | Texto abaixo. |
| §7.8 | Jogador (A) passa a usar `play_3d` para tiros e passos de aliados; nenhum id novo. |
| §8.12 (nova) | "Caçada em rede": tabela de papéis de §6.1, regras de §6.3 (tiro e investida), §6.8, §6.9 e a frase "formatos de registro: `docs/multiplayer.md` §4". |
| §8.8 | Item 1: "todos os caçadores presentes mortos → `DEFEAT_DEATH`". Em rede só o anfitrião avalia; clientes terminam por `EV_HUNT_END` ou `DISCONNECTED`. |
| §9.1 | Bloco `coop` (abaixo). §9.9 (nova): `data/net.json` (abaixo). |
| §10 | `settings.player_name: ""`; versão do save continua 2. |
| §11 | Linha `LOBBY` com os nós de §6.11; `MAIN_MENU` ganha `%FriendsButton` → `LOBBY`; `RESULT` em sala: `%ContinueButton` → `LOBBY`. "O que persiste entre cenas": `Net` (sala e enlaces). |
| §12 | Suíte `tests/net_test.tscn` (watchdog 180 s) e `tests/web/coop_probe.py`; `check_scripts` confere `Net`, os sinais novos e a regra de camadas de N; `unit_tests` ganha `test_net.gd`. Servidor: `bun test server/`. |
| §13.1 | Linhas novas: "Aliados: ≤ 3 `RemoteHunter`, ≤ 600 tris e ≤ 10 `MeshInstance3D` cada, + 1 `Label3D`"; "Rede: download do cliente ≤ 5 kB/s; quadro de estado ≤ 1100 B; nenhuma alocação por tick além de um `PackedByteArray` por quadro"; raios de visão ≤ 130/s; draw calls: pior caso ≤ 230 com 3 aliados. |
| §13.2 | Riscos de §8 daqui (aba em segundo plano, NAT simétrico, cota diária do servidor de salas). |
| §14 | Pacote N e os critérios de aceite das fases de §9 daqui. |
| Apêndice A | Código de §3.6 daqui; `hunter_visual_base.gd` atual com `play_death(_instant: bool = false)`. |

**§7.11 Caçador aliado — `res://assets/models/hunter/hunter_visual.tscn`** (texto para colar)
- Raiz `Node3D` estendendo `HunterVisualBase` (`res://assets/models/hunter/hunter_visual.gd`). Origem no
  chão entre os pés, frente −Z, escala 1 = 1,78 m em pé. **O gameplay mantém a raiz em escala 1** (agachar é
  `set_crouching`) e é dono de posição e yaw da raiz.
- Filhos diretos obrigatórios: `Muzzle` e `NameAnchor` (`Marker3D`), reposicionados pelo asset a cada frame.
  O gameplay lê `global_position` deles no momento do uso (nunca guarda) e só pode pendurar filhos em
  `NameAnchor`.
- Orçamento: ≤ 600 triângulos, ≤ 10 `MeshInstance3D`, materiais compartilhados entre instâncias (cor por
  vértice; cor do slot sem material novo por jogador), sombra só no tronco, clarão do tiro sem luz.
- `setup(slot, weapon_id)` é chamado **exatamente uma vez, antes de `add_child`**. O slot não muda enquanto
  o caçador existe; não há `set_slot` e o gameplay não chama `setup` de novo.

| Método | Contrato |
|---|---|
| `setup(slot: int, weapon_id: StringName) -> void` | cor de identidade `SLOT_COLORS[slot]` e arma inicial |
| `set_weapon(weapon_id: StringName) -> void` | `&""` = desarmado (binóculo, item) |
| `set_locomotion(speed_mps: float) -> void` | 0 = parado; todo frame |
| `set_crouching(on: bool)`, `set_aiming(on: bool)`, `set_look_pitch(pitch_rad: float)` | pose; pitch positivo = olhando para cima |
| `play_fire()`, `play_reload(duration_s: float)`, `play_hit()` | momentos únicos (o som é do gameplay) |
| `play_death(instant: bool = false) -> void` | cai e congela; `instant = true` já nasce caído (entrada tardia/reconexão); ignora chamadas seguintes |
| `get_muzzle()`, `get_name_anchor()` | já na base |

Fallback: `HunterVisualBase.create_fallback()` (cápsula na cor do slot).

**§9.1 `data/game.json`, bloco novo `coop`**
```json
"coop": {
  "boar_count_mult_by_players": [1.0, 1.5, 2.0, 2.5],
  "extra_group_delay_s": 20.0,
  "spawn_spacing_m": 2.0,
  "spectate_delay_s": 2.0,
  "spectate_distance_m": 3.5,
  "spectate_height_m": 2.0,
  "name_tag_max_m": 120.0
}
```

**§9.9 `data/net.json`**
```json
{
  "version": 1,
  "server_url": "wss://javali-salas.acpw01.workers.dev/ws",
  "dev_server_url": "ws://localhost:8787/ws",
  "rtc_enabled": true,
  "ice_servers": ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"],
  "ice_timeout_s": 8.0,
  "rtc_stall_s": 3.0,
  "connect_timeout_s": 8.0,
  "ping_s": 15.0,
  "pong_timeout_s": 10.0,
  "max_players": 4,
  "snapshot_hz": 10,
  "hunter_state_hz": 10,
  "relay_hz": 10,
  "boar_interp_delay_ms": 200,
  "hunter_interp_delay_ms": 150,
  "max_frame_bytes": 1100,
  "reliable_window": 64,
  "load_timeout_s": 25.0,
  "host_stall_warn_s": 2.5,
  "host_timeout_s": 20.0,
  "peer_absent_s": 3.0,
  "peer_timeout_s": 30.0,
  "hit_claim_tolerance_m": 12.0,
  "name_max_chars": 12
}
```
`server_url` é a produção (`wss://javali-salas.acpw01.workers.dev/ws`, já no lugar do marcador `SUBDOMINIO`);
`dev_server_url` vale em nativo e em página servida de `localhost`. `relay_hz` é a taxa de envio de um enlace
enquanto está em relay (uma mensagem por tick por direção, §4.3). Só em página servida de
`localhost`/`127.0.0.1` valem as sobreposições por URL para teste: `?server=ws://127.0.0.1:PORT/ws`,
`?relay_only=1` (não tenta WebRTC), `?drop_ice=1` (não envia candidatos: força o estouro de
`ice_timeout_s`). Em nativo: `-- --server=…`.

---

## 8. Riscos

| # | Risco | Efeito | Mitigação |
|---|---|---|---|
| R1 | **Cota gratuita esgotada por pares em relay** (muitos jogadores em 4G com NAT simétrico) | sem salas novas e pares em relay caem até as 21h de Brasília | uma mensagem por tick por direção no relay (≈ 27 h de par por dia, §5.4); WebRTC como caminho normal; mensagem clara no lobby; `relay_hz` em dados; saída futura: TURN gratuito do Cloudflare |
| R2 | Primeiro deploy não fecha (wrangler com Bun, registro interativo do subdomínio `workers.dev`, diferença entre a entrada Bun e a entrada Worker) | F0 atrasa | F0 trata os três; `check.js` roda o mesmo roteiro contra Bun local, `wrangler dev` e produção; Node LTS só para o wrangler se preciso |
| R3 | Abuso do Worker (script ignorando `Origin` para queimar a cota ou chutar códigos) | multiplayer indisponível no dia; entrada indesejada numa sala | código de 5 caracteres, sala trancada em caçada, limites de tamanho e taxa, nenhuma rota além de `/ws`; não há teto global por IP no plano gratuito: risco aceito |
| R4 | **Aba do anfitrião em segundo plano** (ligação, troca de app, tela apagou) | simulação congela para todos; iOS derruba o socket em segundos | faixa de aviso + prazo de 20 s + fim com abates pagos; Wake Lock; dica no lobby para o anfitrião ser o melhor aparelho; migração de anfitrião fica fora |
| R5 | NAT simétrico em 4G | ICE não fecha | fallback automático por relay (o enlace já nasce nele); custo: latência pela borda do Cloudflare e consumo da cota diária (R1) |
| R6 | Perda e variação de atraso em rede móvel | réplicas aos trancos | 200 ms de buffer (tolera 1 snapshot perdido); eventos em canal confiável; no relay, descarte de estados velhos por `seq` |
| R7 | **Desempenho do celular anfitrião** | menos de 30 fps com 4 jogadores | teto de 26 javalis vivos continua; um raio de visão por javali por percepção; snapshot sem alocação por javali; medir na F4 em aparelho real; se faltar, baixar `coop.boar_count_mult_by_players` |
| R8 | +30 draw calls com 3 aliados (10 malhas cada) | estoura os 200 do pior caso | subir o teto para 230 ou pedir ao art-director `visibility_range_end` nos membros; medir na F2 |
| R9 | Dessincronização de mundo | tiro bloqueado por árvore que o outro não tem; réplica atravessando tronco | layout de flora sincronizado (§6.4); checagem de `v` + `proto`; teste que compara hash das posições de tronco entre qualidades |
| R10 | Divergência de estado | cliente perde um evento e fica com javali fantasma | pista de eventos numerada e em ordem estrita; `EV_BOAR_DEATH` leva `killed/total`; snapshot lista só vivos (réplica ausente por 1 s sem evento de morte é removida e registrada como erro) |
| R11 | WebRTC só é testável no Chrome | regressão no caminho RTC passa nas suítes nativas | `coop_probe.py` obrigatório antes de publicar mudança em `src/net`; teste manual em iPhone (Safari) por fase |
| R12 | Mudança no layout da flora ou nos campos de `src/core` quebra o solo | suítes atuais falham | `sync_layout = false` no solo; campos novos com default; `test_core.gd:23` e `contract_sigs.gd` atualizados na mesma fase |
| R13 | Bun instável como servidor local no Windows | testes de integração não sobem | `rooms.js` neutro; entrada Node de reserva (§5.1); produção não depende do Bun |
| R14 | WebRTC revela o IP dos jogadores entre si | privacidade | só salas privadas entre amigos; avisar no lobby se o dono quiser |
| R15 | Confiança no cliente (D3) | trapaça trivial | aceito: co-op entre amigos; validação leve evita só erro grosseiro |

---

## 9. Plano em fases

Modelo: Sonnet por padrão; Fable onde indicado. Toda fase termina com as 4 suítes atuais passando sem
mudança de resultado e é publicável (a entrada do menu é visível para todos desde a F6; antes só com `?mp=1`).

### F0 — Servidor de salas no ar
Status: concluída em 2026-11-13
- **Objetivo:** `wss://javali-salas.acpw01.workers.dev/ws` cria sala, deixa entrar, repassa sinalização
  e relay, respondendo de fora. Nenhum código de jogo.
- **Arquivos:** `server/*` (§3.3: `rooms.js`, `config.js`, `worker.js`, `wrangler.toml`, `server.js`,
  `check.js`, `rooms.test.js`, `README.md`), com o protocolo de §4.2–4.3 e os limites de §5.3 completos;
  `tools/wscheck.html` (abre o WebSocket com `t=create` e mostra "Sala criada: K7QF2" ou o erro; publicada
  no `gh-pages` para testar a partir da origem real); `data/net.json` com o `server_url` definitivo.
- **Dono:** coordenação (Sonnet; Fable se a hibernação ou o deploy derem trabalho). O dono do jogo já fez a
  parte dele (§10).
- **Verificações que só a F0 fecha:** `bun x wrangler deploy` sem Node (se falhar: Node LTS só para o
  wrangler); registro do subdomínio `workers.dev` no primeiro deploy (pode ser interativo); origem exata do
  GitHub Pages em `ALLOWED_ORIGINS`.
- **Aceite:** `bun test` verde cobrindo criar, entrar, lista de peers, sala cheia, versão diferente, sala
  trancada, código em uso, repasse de `signal`, repasse binário, regra da estrela, anfitrião saiu, cada
  limite, e **o mesmo roteiro com a lista de conexões recriada entre chamadas** (simula a hibernação);
  `bun check.js` verde contra o Bun local, contra `wrangler dev` e contra a URL de produção; origem errada
  recebe 403; `wscheck.html` aberta no celular mostra "Sala criada"; sala parada 30 s e retomada continua
  repassando (hibernou e voltou); painel do Cloudflare mostrando o consumo de requests do teste, anotado.
- **Fora:** tudo do jogo.

### F1 — Contrato e esqueleto
Status: concluída em 2026-11-13
- **Objetivo:** o projeto compila com os tipos novos e o `Net` offline; nada muda para o jogador.
- **Arquivos:** `src/core/*` (§3.6), `project.godot` (autoload), `src/net/net.gd` (stub offline),
  `data/net.json`, `data/game.json` (`coop`), `src/systems/data_registry.gd` (`get_net`),
  `save_service.gd` (`player_name`), `tests/lib/contract_sigs.gd`, `tests/check_scripts.gd`,
  `tests/unit/test_core.gd`, merge dos deltas de §7 em `docs/arquitetura.md`.
- **Dono:** coordenação (core, `project.godot`), game-systems (dados, save), qa-tester (testes),
  game-architect (merge do contrato).
- **Aceite:** 4 suítes verdes; `check_scripts` confere o autoload `Net`, os 5 sinais e a regra de camadas de
  N; teste de unidade: `Net.is_active() == false`, `Net.get_local_slot() == 0`, save antigo ganha
  `player_name = ""` sem mudar de versão.
- **Fora:** qualquer socket.

### F2 — Dois navegadores se vendo andar (caminho crítico)
Status: concluída em 2026-11-13
- **Objetivo jogável:** (então com `?mp=1`, removido na F6) um cria a sala, outro entra pelo código, o anfitrião inicia, os dois
  andam no mapa e se veem com o caçador do art-director, por WebRTC. Sem javalis para o cliente.
- **Arquivos:** `src/net/*` completo no nível de enlace (sinalização, relay, promoção a RTC, quadros com
  `seq`/`ack`, ticks, `L_*`, `C_STATE`, caçadores no `H_SNAPSHOT`); A: `remote_hunter.gd|.tscn`,
  `Player.net_write_state`, `window.huntProbe` estendido; B: papéis em `hunt_controller.gd` (N caçadores,
  cliente sem spawner, espera de `hunt_go`); systems: `src/ui/lobby/` mínimo (criar, entrar, lista, iniciar),
  `%FriendsButton` atrás de `?mp=1`; qa: `tests/unit/test_net.gd`, `tests/net_test.tscn` (cenários N1 sala,
  N2 movimento, pelo relay, com o servidor Bun local `server/server.js` em porta livre), `tests/web/coop_probe.py` (dois Chrome,
  caminho `rtc`).
- **Dono / modelo:** game-developer N (Fable), game-developer A e B (Sonnet, tarefas estreitas), game-systems
  (Sonnet), qa-tester (Sonnet).
- **Aceite:** `net_test` verde (dois processos headless: posição do caçador remoto a ≤ 0,5 m da real após
  1 s parado; versão diferente recusada; quinto peer recusado; processos filhos encerrados em todo caminho
  de saída); `coop_probe.py`: `huntProbe.path == "rtc"` nos dois e `allies[0]` de B segue A a ≤ 1 m; teste
  de unidade do enlace com loopback a 20% de perda e reordenação na pista de estado: eventos chegam todos e
  em ordem; medido e relatado o delta de `_process` depois de 5 s de aba congelada.
- **Fora:** javalis, lavoura, economia, morte, lobby final, rebaixamento de caminho.

### F3 — Fallback de relay robusto
Status: concluída em 2026-11-13
- **Objetivo:** par cujo ICE não fecha joga igual; RTC que morre no meio não derruba o jogador.
- **Arquivos:** `src/net/net_link.gd`, `net_rtc.gd` (prazo do ICE, rebaixamento, reenvio, `L_NEED_RELAY`);
  lobby mostra "direto"/"via servidor"; `coop_probe.py` com `?drop_ice=1` e `?relay_only=1`.
- **Dono / modelo:** game-developer N (Fable), qa-tester (Sonnet).
- **Aceite:** com `drop_ice=1`, `path == "relay"` depois de `ice_timeout_s` e o teste de andar passa; teste
  de unidade: troca de caminho com 5 eventos não confirmados entrega os 5 uma vez, em ordem; teste manual
  com um celular em 4G relatado; um enlace em relay envia no máximo `relay_hz` mensagens por segundo por
  direção (contado no teste, é o que protege a cota de §5.4).
- **Fora:** TURN, nova promoção depois do rebaixamento.

### F4 — Javalis replicados e tiro (caminho crítico)
Status: concluída em 2026-11-13
- **Objetivo jogável:** os dois veem os mesmos javalis, atiram, veem abates e são investidos.
- **Arquivos:** B: `hunt_host_sync.gd`, `hunt_replica.gd`, `boar_puppet.gd`, alvo múltiplo em `boar.gd`
  (§6.3), `boar_spawner.gd` (`notify_shot`), `map_root.gd` (`sync_layout`); A: `weapon.gd:121`, filtros de
  `shot_id` em `hud.gd`, mensagem de abate de aliado; qa: cenário N3, testes de réplica e de flora.
- **Dono / modelo:** game-developer B (Fable: IA dos javalis), game-developer A (Sonnet), qa-tester (Sonnet).
- **Aceite:** N3: anfitrião + cliente no contrato 0 com seed fixa, bot do cliente mata pelo menos 3 javalis
  atirando nas réplicas, `VICTORY` nos dois, soma dos abates = total, cada abate em um só resultado; teste
  de unidade: snapshot → réplica com erro de posição ≤ 1 cm; hash das posições de tronco igual em
  low/medium/high com `sync_layout`; `playthrough` sem mudança; banda medida ≤ 5 kB/s de download por
  cliente no contrato 5; fps do anfitrião em desktop ≥ 60 com 26 javalis e 3 remotos.
- **Fora:** lavoura replicada, fim de caçada em rede, economia, cães.

### F5 — Lavoura, itens, fim de caçada e economia
Status: concluída em 2026-11-13
- **Objetivo jogável:** uma caçada cooperativa completa, do lobby ao resultado, com dinheiro certo.
- **Arquivos:** B: lavoura (`crop_manager.gd`), ceva, térmica/drone na réplica, fim de caçada e quedas
  (§6.8, §6.9), `scale_groups`; A: `pause_overlay.gd`; N: prazos, `net_connection_lost`, tranca da sala;
  systems: `profile.gd:258`, `result.gd`, `shop.gd` (volta para a sala); qa: N4 (anfitrião cai), N5 (cliente
  cai), testes de economia e de escala.
- **Dono / modelo:** game-developer B (Fable: fluxo da caçada), game-developer A e N (Sonnet), game-systems
  (Sonnet), qa-tester (Sonnet).
- **Aceite:** N4: cliente termina `DISCONNECTED` em ≤ `host_timeout_s` + 2 s com os próprios abates
  creditados e sem progressão; N5: anfitrião segue e vence sozinho; teste de unidade: `apply_hunt_result`
  com `counts_for_progression = false` credita dinheiro e não desbloqueia; `scale_groups` dá 14 e 23 para o
  contrato 1 com 2 e 4 jogadores; canteiros comidos iguais nos dois peers (mesmo conjunto de índices).
- **Fora:** cães, espectador, lobby final.

### F6 — Lobby completo, aliados no HUD, espectador: lançamento beta
Status: concluída em 2026-11-14 (sessão manual com 3 aparelhos reais ainda pendente)
- **Objetivo jogável:** "Jogar com amigos (beta)" visível para todos.
- **Implementado:** ver §6.11 (lobby, convite, `LoadoutPanel`, `SpectatorCamera`, minimapa e bússola). Arte:
  `play_death(instant = true)` (nasce caído); `visibility_range_end` NÃO foi aplicado nos membros do caçador
  (silhueta humana a 100+ m é requisito de segurança; a economia seria ~500 triângulos e 18 draw calls com 3
  aliados). Ícones novos: `friends`, `host`, `ready`, `link`, `link_direct`, `link_relay`. Testes: `net_e2e_peer.gd`
  aperta `%ReadyButton` no cliente; suítes `tests/net_unit.tscn` e `tests/net_test.tscn`.
- **Arquivos:** systems: lobby final (nome, link `?sala=`, copiar, pronto, contratos, `LoadoutPanel`,
  mensagens de erro), `boot.gd`, `main_menu.gd`, `preparation.gd` (usa `LoadoutPanel`); A: minimapa, nomes,
  `spectator_camera.gd`, mensagens; art-director: ajustes do caçador (`play_death(instant)`, alcance de
  visibilidade dos membros) e ícone do botão; qa: `coop_probe.py` pelo fluxo real de menus, `flow_test`.
- **Dono / modelo:** game-systems, game-developer A, art-director, qa-tester (Sonnet).
- **Aceite:** `flow_test` sem mudança (nós da Preparação com os mesmos nomes); abrir `?sala=CODE` entra na
  sala sem digitar; servidor inacessível (URL de teste sem ninguém ouvindo) → mensagem `server_unreachable`
  em ≤ 9 s e "Voltar" funciona; morrer
  com aliado vivo mostra a câmera de espectador e "Assistindo: <Nome>"; sessão manual de 3 jogadores (PC,
  Android, iPhone) relatada; `mobile_probe.py` verde.
- **Fora:** cães, reconexão.

### F7 — Cães em rede
- **Objetivo jogável:** cada jogador leva o seu cão e manda "Pega!"/"Volta!".
- **Arquivos:** B: `dog.gd` (§6.5), `dog_puppet.gd`, registro `DOG`, `EV_DOG_*`, `EV_MESSAGE`; lobby libera
  o cão; qa: cenário N6.
- **Dono / modelo:** game-developer B (Sonnet), qa-tester (Sonnet).
- **Aceite:** N6: comando do cliente muda o estado só do cão dele; sinais de cão só no HUD do dono; marcação
  aparece para os dois; solo sem mudança.
- **Fora:** balanceamento de vários cães (dados, game-systems).

### F8 — Robustez móvel
- **Objetivo:** cair e voltar na mesma página sem perder a caçada; medir e ajustar em aparelhos reais.
- **Arquivos:** N e B: `want` + `token`, `EV_FULL_SYNC`, carência do slot; ajustes de taxa em `data/net.json`.
- **Dono / modelo:** game-developer N e B (Fable), qa-tester (Sonnet).
- **Aceite:** teste que derruba o WebSocket do cliente por 5 s: ele volta no mesmo slot com os mesmos
  javalis vivos e o mesmo resultado parcial; relatório de fps e banda em celular intermediário como
  anfitrião de 4.
- **Fora:** migração de anfitrião, TURN, reconexão depois de recarregar a página.

---

## 10. Checklist do dono do jogo

Só duas coisas dependem dele, e as duas já foram feitas.

| # | O que fazer | Situação |
|---|---|---|
| 1 | Criar uma conta gratuita no Cloudflare (e-mail e senha, sem cartão). | Feito. |
| 2 | Autorizar a publicação uma vez: a coordenação roda `wrangler login`, o navegador abre e ele clica em "Allow". | Feito: a autorização está salva na máquina. |

Todo o resto é dos agentes e da coordenação: escrever e testar o servidor, publicar o Worker, preencher
`data/net.json`. Se o primeiro deploy pedir para escolher o nome do subdomínio `workers.dev`, a coordenação
pergunta ao dono qual nome ele quer (é só um nome; aparece no endereço do servidor, não no jogo).

Depois de publicado, se um dia o lobby disser que o servidor de salas está indisponível, não há nada para
ele consertar: é o limite diário gratuito, que volta sozinho às 21h de Brasília.

---

## 11. Questões em aberto para o dono do jogo

Respondidas de forma provisória (padrão da coordenação até o dono dizer o contrário; todas baratas de mudar):

| Questão | Padrão adotado |
|---|---|
| Prêmio do abate | só para quem deu o tiro fatal (a regra mora num único ponto do anfitrião) |
| Bônus do contrato | cheio para cada jogador presente no fim |
| Multiplicadores de javalis | `[1.0, 1.5, 2.0, 2.5]` em `data/game.json` (o contrato 5 com 4 jogadores vira 63 javalis) |
| Anfitrião iniciar sozinho na sala | pode |
| Código da sala | 5 caracteres |

Restam para o dono:

1. **Nome do subdomínio `workers.dev`**, se o primeiro deploy pedir (só aparece no endereço do servidor).
2. **Se o limite gratuito começar a ser atingido**: aceitar "volta às 21h", ou passar ao plano pago do
   Cloudflare (valor a conferir na página de preços quando a questão surgir), ou priorizar o TURN gratuito.
   Só precisa ser decidido se acontecer; o painel do Cloudflare mostra o consumo.

Marcador para a coordenação (não é questão do dono): **origem exata do GitHub Pages** em `ALLOWED_ORIGINS`
(`server/wrangler.toml`), a conferir no repositório.

---

## 12. Objeções às decisões

Sigo todas como decididas; registro o que mudaria.

- **D14 (Cloudflare gratuito).** Sem objeção à escolha. Ressalva: o limite é duro (falha até as 21h de
  Brasília) e quem o gasta são os pares em fallback, justamente os jogadores de celular em 4G. Cabem ≈ 27
  horas de par em relay por dia (§5.4). Se o jogo crescer, a saída barata é o TURN gratuito do Cloudflare,
  que deveria entrar no plano logo depois do beta.
- **D4 (WebRTC como principal).** Sem objeção: com cota de mensagens, o WebRTC é o que mantém o jogo dentro
  do plano gratuito. Custo: metade da rede só é testável no Chrome (risco R11). O enlace nasce em relay e é
  promovido, então um problema no WebRTC degrada para relay em vez de quebrar.
- **D4b (sem TURN).** Sem objeção na v1. Custo aceito: cada par em NAT simétrico consome 3.600 requests por
  hora da cota diária de 100.000.
- **D6 (abate só para o tiro fatal).** Incentiva disputa de abate e deixa o novato sem renda. Padrão mantido
  pela coordenação; registrado.
- **D5 (sem reconexão na v1).** Em celular, cair por segundos é comum. Aceitável no beta porque os abates
  são pagos na queda, mas a F8 deveria vir logo depois do lançamento.
- **D1 (código de sala).** Objeção aceita pela coordenação: o código passou a 5 caracteres (33,5 milhões).
  A v1 continua sem expulsão de jogador.
- **D8 (um cão por jogador).** Quatro cães de agarre seguram quatro javalis ao mesmo tempo. É
  balanceamento, não arquitetura: fica para a fase dos cães, em dados.
- **D9 (visual do aliado).** Sem objeção à API. Faltavam orçamento e as quatro regras de §7.11; 10 malhas
  por aliado somam até 30 draw calls, por isso a linha nova no orçamento. `play_death(_instant: bool =
  false)` e o fallback na cor do slot foram aceitos; a coordenação aplica em `hunter_visual_base.gd`.
- **D2.** Sem objeção, com uma ressalva: "solo intocado" obriga a manter dois layouts de flora (o de hoje,
  que varia com a qualidade, e o sincronizado). Depois de validado, o sincronizado deveria virar o único.
