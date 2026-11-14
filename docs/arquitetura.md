# Caçada ao Javali — Contrato de Arquitetura

Versão do contrato: **1.1** · Godot **4.7.2** · GDScript tipado · Renderer **Compatibility** · Web sem threads.

Este documento é a fonte da verdade. Quatro agentes implementam em paralelo sem conversar. Se algo aqui
estiver errado ou faltando, **faça o mínimo, não invente API, e relate** ao coordenador. Mudanças de
contrato passam pelo `game-architect`. O detalhe do protocolo de rede do modo cooperativo (formatos de
registro, sinalização, limites do servidor, fases) está em `docs/multiplayer.md`; este documento guarda só o
contrato que os pacotes precisam para se encaixar.

Convenções gerais:
- Identificadores, arquivos e comentários em inglês; todo texto visível ao jogador em PT-BR.
- Unidades: metros, segundos, kg, graus (em dados) / radianos (em código, converta com `deg_to_rad`), R$ como `int` (reais inteiros), ouro como `int`, porcentagem como `float` 0–100.
- Mundo: Y para cima, **frente = -Z** para tudo (jogador, javali, cão, armas, props). Norte do mapa = -Z.
- Scripts de autoload **não** declaram `class_name` (evita conflito com o nome do singleton).
- `class_name` são globais: todos os nomes deste documento são reservados; não crie outra classe com o mesmo nome.

---

## 1. Resumo do design (para quem chega frio)

FPS de caça 3D, arcade, para navegador (desktop, Android, iOS). O javali (*Sus scrofa*) é espécie invasora
no Brasil; o jogador é um controlador de fauna contratado por fazendeiros. Cada **mapa** (agora só
"Mato Grosso"; Pantanal, Campanha Gaúcha e Triângulo Mineiro aparecem trancados como "Em breve") tem
**5 contratos** de dificuldade crescente.

**Loop:** Boot ("Toque para começar") → Menu principal → Seleção de mapa → Preparação (contrato + loadout:
até 2 armas, até 3 equipamentos, 0–1 cão) → Caçada → Resultado → Loja → Preparação…

**Caçada:** todos os javalis do contrato entram no mapa (em grupos com atraso), saem da mata e vão comer a
lavoura, drenando a **saúde da lavoura** (100% → 0%). **Vitória:** todos abatidos. **Derrota:** lavoura em 0%
ou todos os caçadores mortos. Sem cronômetro. Desistir pelo menu de pausa = derrota (ABANDONED).

**Javalis:** Leitão (25–45 kg, sempre foge), Fêmea (60–110 kg, foge; em bando e acuada, defende), Macho
(90–160 kg, investe se o jogador chega perto ou se for ferido), Cachaço alfa (180–260 kg, sempre investe,
muita vida). Peso sorteado por indivíduo escala modelo (raiz cúbica), vida e recompensa. Bandos de 3–6 com
líder; alerta compartilhado; ao tiro o bando foge e machos/alfa contra-atacam. Investida telegrafada
(para e raspa o chão 0,8 s, corre em linha reta, pode ser esquivada). Zonas de acerto: cabeça, vitais,
corpo, traseiro.

**Economia:** R$ por abate = peso × R$/kg do tipo × multiplicadores (tiro limpo em cabeça/vitais; abate
com um tiro) × multiplicador do contrato; bônus de contrato na vitória proporcional à lavoura preservada.
Ouro (premium) só via doação Pix + código de resgate (validação offline, **insegura contra fraude**).

**Arsenal:** Carabina .22 (inicial), Espingarda 12 (bagos), Rifle .308 (luneta 4x), Rifle .30-06 semi,
[Ouro] Rifle .338 (luneta 8x). Hitscan com queda de dano por distância.
**Equipamentos:** binóculo, colete de couro, kit de primeiros socorros, ceva de milho, munição extra,
[Ouro] mira térmica, drone batedor. **Cães:** Vira-lata Caramelo (aponta), Foxhound (acua),
[Ouro] Dogo Argentino (agarra). Cão obedece "Pega!"/"Volta!", recua ferido, nunca morre.

**Tecnologia:** tudo procedural (malhas, texturas, sons). Javalis e cães **não usam física**: movimento
cinemático por steering sobre o heightmap. Só o jogador é `CharacterBody3D`. Tiro por raycast contra
`HitZone` (Area3D). Dados de balanceamento em JSON em `data/`. Save JSON em `user://`.

**Cooperativo (beta):** opção nova no menu, "Jogar com amigos (beta)". 2 a 4 caçadores no mesmo contrato,
sala privada por código de 5 caracteres ou link `?sala=CODIGO`. Sem PvP, sem fogo amigo, sem busca de partida
pública. Um jogador é o **anfitrião**: o jogo dele simula javalis, cães e lavoura exatamente como no solo; os
outros veem réplicas interpoladas e controlam só o próprio caçador. Quem atira decide o acerto na própria
tela; quem é investido decide o dano na própria tela. Dinheiro do abate para quem matou; bônus do contrato
inteiro para cada um; consumíveis de cada um. Caçador morto vira espectador. Anfitrião caiu: a caçada acaba e
cada um recebe os abates que já tinha feito. Conexão: WebRTC direto entre cada cliente e o anfitrião; se o
WebRTC não fechar (NAT de 4G), o par usa o servidor de salas (Cloudflare Workers + Durable Objects, plano
gratuito) como ponte. O solo não muda: sem sala ativa nenhum código de rede executa. Detalhe em
`docs/multiplayer.md`.

---

## 2. Árvore de pastas e donos

Regra de dependência (vale para compilação e para validação isolada):

| Quem | Pode referenciar por tipo/`class_name` | Pode carregar por caminho (com fallback) |
|---|---|---|
| Pacote A (`src/input`, `src/player`, `src/weapons`, `src/hud`) | `src/core/*`, autoloads (inclui `Net`) | `assets/*`, `ScenePaths.SETTINGS_PANEL` |
| Pacote B (`src/hunt`, `src/world`, `src/boars`, `src/dogs`) | `src/core/*`, autoloads (inclui `Net`) | `assets/*`, `ScenePaths.PLAYER`, `ScenePaths.REMOTE_HUNTER` |
| Pacote N (`src/net`) | `src/core/*`, autoloads | nada (troca de cena só via `Router`) |
| game-systems (`src/systems`, `src/ui`, `data`) | `src/core/*`, autoloads, suas classes | `ScenePaths.*` via Router |
| art-director (`assets`) | `src/core/*` (bases de visão), autoload `Profile` (só leitura de settings) | — |
| qa-tester (`tests`) | tudo | tudo |
| coordenação (`src/core`, `server/`, `project.godot`, `export_presets.cfg`) | — | — |

**Proibido:** A referenciar classes de B e vice-versa; A/B referenciarem classes de `src/systems`/`src/ui`
(use os autoloads); N referenciar classes de A, B ou systems; A, B, systems ou assets referenciarem classes de
N (usam o autoload `Net` e os tipos de `src/core`; `check_scripts` confere a regra); qualquer `.tscn` fora de `assets/` ter `ext_resource` apontando para `assets/` (assets
são carregados em código via `AssetLoader`, com fallback); assets conterem corpos físicos.

```
hunt-javali/
├── project.godot                 coordenador
├── export_presets.cfg            coordenador
├── CLAUDE.md                     coordenador
├── docs/                         game-architect
│   ├── arquitetura.md
│   └── multiplayer.md            detalhe do protocolo do modo cooperativo
├── server/                       coordenador (servidor de salas; JavaScript, fora do Godot)
├── tools/                        coordenador (godot.sh / godot.ps1)
├── data/                         game-systems  (seed inicial copiado da §9 pelo coordenador na Fase 0)
│   ├── game.json
│   ├── weapons.json
│   ├── equipment.json
│   ├── dogs.json
│   ├── boars.json
│   ├── maps.json
│   ├── gold_packages.json
│   ├── pix_config.json
│   └── net.json
├── src/
│   ├── core/                     coordenador (copiado VERBATIM do Apêndice A; ninguém mais edita)
│   │   ├── game_events.gd        autoload GameEvents
│   │   ├── layers.gd             class Layers
│   │   ├── ids.gd                class Ids
│   │   ├── scene_paths.gd        class ScenePaths
│   │   ├── asset_loader.gd       class AssetLoader
│   │   ├── hit_info.gd           class HitInfo
│   │   ├── hit_zone.gd           class HitZone
│   │   ├── kill_info.gd          class KillInfo
│   │   ├── hunt_request.gd       class HuntRequest
│   │   ├── hunt_result.gd        class HuntResult
│   │   ├── player_base.gd        class PlayerBase
│   │   ├── hunt_world.gd         class HuntWorld
│   │   ├── boar_visual_base.gd   class BoarVisualBase
│   │   ├── dog_visual_base.gd    class DogVisualBase
│   │   ├── hunter_visual_base.gd class HunterVisualBase
│   │   ├── net_codec.gd          class NetCodec
│   │   ├── net_peer_info.gd      class NetPeerInfo
│   │   ├── weapon_view_base.gd   class WeaponViewBase
│   │   └── map_environment_base.gd class MapEnvironmentBase
│   ├── input/                    game-developer Pacote A
│   ├── player/                   game-developer Pacote A
│   │   └── debug/                (sandbox do pacote A)
│   ├── weapons/                  game-developer Pacote A
│   ├── hud/                      game-developer Pacote A
│   │   └── touch/
│   ├── hunt/                     game-developer Pacote B
│   │   └── debug/
│   ├── world/                    game-developer Pacote B
│   │   └── maps/mato_grosso/
│   ├── boars/                    game-developer Pacote B
│   ├── dogs/                     game-developer Pacote B
│   ├── net/                      game-developer Pacote N (autoload Net e enlaces; ver §6.11)
│   ├── systems/                  game-systems
│   │   └── pix/
│   └── ui/                       game-systems
│       ├── boot/  main_menu/  map_select/  preparation/  shop/
│       ├── result/  donate/  settings/  common/  lobby/
├── assets/                       art-director
│   ├── audio/                    (autoload Sfx + sintetizadores)
│   ├── models/
│   │   ├── boar/  dog/  hunter/  weapons/  props/  flora/
│   ├── materials/
│   ├── shaders/
│   ├── env/
│   ├── vfx/
│   ├── ui/
│   │   └── icons/
│   └── preview/                  (cenas de screenshot do art-director; não usadas pelo jogo)
└── tests/                        qa-tester
    ├── lib/  unit/  bot/  net/  web/
    ├── check_scripts.tscn  unit_tests.tscn  flow_test.tscn  playthrough.tscn  net_test.tscn
```

Lista completa de arquivos por dono: §14.

---

## 3. `project.godot` (coordenador escreve exatamente isto)

```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; since the parameters that go here are not all obvious.
config_version=5

[application]

config/name="Caçada ao Javali"
config/description="Controle de javalis invasores em fazendas do Brasil."
run/main_scene="res://src/ui/boot/boot.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")

[autoload]

GameEvents="*res://src/core/game_events.gd"
Data="*res://src/systems/data_registry.gd"
Profile="*res://src/systems/profile.gd"
InputSetup="*res://src/input/input_setup.gd"
Sfx="*res://assets/audio/sfx_library.gd"
Router="*res://src/systems/router.gd"
Net="*res://src/net/net.gd"

[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=4

[input_devices]

pointing/emulate_touch_from_mouse=false
pointing/emulate_mouse_from_touch=true

[layer_names]

3d_physics/layer_1="terrain"
3d_physics/layer_2="static"
3d_physics/layer_3="player"
3d_physics/layer_4="boar_hitzone"

[physics]

common/physics_ticks_per_second=60
common/max_physics_steps_per_frame=4

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.55, 0.72, 0.86, 1)
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=0
anti_aliasing/quality/msaa_3d=0
```

Notas:
- **Ordem dos autoloads** importa: `GameEvents` (todos conectam nele) → `Data` (Profile precisa dos dados para
  defaults) → `Profile` (carrega save e settings) → `InputSetup` (lê settings de toque) → `Sfx` (lê volumes)
  → `Router` (usa todos os anteriores) → `Net` (último; usa `Data`, `Profile`, `Router`; offline não processa).
- `physics/3d/physics_engine`: **não escrever** (usar o padrão do 4.7). O contrato não depende do motor; o
  único ponto sensível (raycast contra `Area3D`) tem teste e plano B (§13, risco R2).
- `window/handheld/orientation=4` = sensor landscape (só vale em export nativo; na Web o `Router` mostra o
  aviso "Gire o aparelho", §11).
- `emulate_mouse_from_touch=true` é necessário para os `Control` dos menus responderem a toque. Consequência
  obrigatória: **botões do mouse não entram no InputMap** (§4).
- **Depois** que o art-director entregar `assets/ui/theme.tres` e `assets/ui/icons/app_icon.svg`, acrescentar:
  ```ini
  [application]
  config/icon="res://assets/ui/icons/app_icon.svg"
  [gui]
  theme/custom="res://assets/ui/theme.tres"
  ```
  O tema é global: nenhuma cena de UI/HUD atribui `theme` em código.
- **Não** existe seção `[input]`: as ações são registradas em código por `InputSetup`.

### 3.1 Camadas de colisão 3D

| Bit | Valor | Nome | Quem está nela | `collision_mask` do próprio objeto |
|---|---|---|---|---|
| 1 | 1 | terrain | `StaticBody3D` do terreno (HeightMapShape3D) e paredes de borda | 0 |
| 2 | 2 | static | corpos estáticos criados pelo Pacote B: props, troncos de árvore, cupinzeiros, cerca | 0 |
| 3 | 4 | player | `CharacterBody3D` do jogador | `terrain | static` (3) |
| 4 | 8 | boar_hitzone | `HitZone` (Area3D, `monitoring=false`, `monitorable=true`) | 0 |

Consultas (não são corpos):
| Consulta | Dono | Máscara | Áreas | Corpos |
|---|---|---|---|---|
| Raio de tiro | A | `Layers.MASK_WEAPON_RAY` = 1\|2\|8 = 11 | sim | sim (exclui RID do jogador) |
| Linha de visão do javali/cão | B | `Layers.MASK_LINE_OF_SIGHT` = 1\|2 = 3 | não | sim |
| Sonda de chão do bot/teleporte | A/tests | 1 | não | sim |

Javalis e cães **não** têm corpos: colidem com obstáculos por steering (§8.6) e não bloqueiam o jogador.
Bagos/balas atravessam o cão (sem fogo amigo). Caçador remoto (`RemoteHunter`) não ocupa camada: sem corpo e
sem forma.

### 3.2 `export_presets.cfg` (coordenador) — preset "Web"

Valores obrigatórios: `platform="Web"`, `export_filter="all_resources"`,
`include_filter="data/*.json"` (**JSON não é recurso; sem isso o jogo exportado não tem dados**),
`exclude_filter="tests/*, docs/*, tools/*, assets/preview/*"`, `variant/extensions_support=false`,
`variant/thread_support=false`, `vram_texture_compression/for_desktop=true`,
`vram_texture_compression/for_mobile=true`, `html/canvas_resize_policy=2`,
`html/focus_canvas_on_start=true`, `html/experimental_virtual_keyboard=true` (campo do código de resgate
no celular), `progressive_web_app/enabled=false`. Saída: `build/web/index.html`.

---

## 4. Ações de input

Registradas por **`InputSetup`** (`res://src/input/input_setup.gd`, Pacote A) em `_ready()` com
`InputMap.add_action(name, 0.2)` + `InputMap.action_add_event`. Idempotente (`if not InputMap.has_action`).

| Ação | Teclado | Mouse (injetado, ver abaixo) | Toque (Pacote A, `src/hud/touch/`) |
|---|---|---|---|
| `move_forward` | W, ↑ | — | joystick virtual (força analógica) |
| `move_back` | S, ↓ | — | joystick virtual |
| `move_left` | A, ← | — | joystick virtual |
| `move_right` | D, → | — | joystick virtual |
| `fire` | — | botão esquerdo | botão Tiro |
| `aim` | — | botão direito (segurar) | botão Mira (alterna) |
| `zoom_in` | = | roda para cima | slider de zoom |
| `zoom_out` | - | roda para baixo | slider de zoom |
| `reload` | R | — | botão Recarregar |
| `sprint` | Shift (esq.) | — | joystick empurrado > 90% por 0,3 s |
| `crouch` | Ctrl (esq.), C | — | botão Agachar (alterna) |
| `weapon_1` | 1 | — | — |
| `weapon_2` | 2 | — | — |
| `weapon_swap` | — | — | botão Trocar arma |
| `dog_command` | E | — | botão Cão |
| `use_item` | Q | — | botão Item |
| `item_next` | F | — | seta pequena ao lado do botão Item |
| `pause` | Esc, P | — | botão Pausa |

O olhar (mouse e arrasto na metade direita) **não é ação**: é tratado pelo `Player` diretamente.

**Mouse injetado.** Com `emulate_mouse_from_touch=true`, todo toque gera um clique de mouse falso
(`event.device == InputEvent.DEVICE_ID_EMULATION`); se o botão esquerdo estivesse no InputMap, tocar para
olhar dispararia a arma. Por isso `InputSetup._input(event)` converte **apenas** eventos
`InputEventMouseButton` com `device != InputEvent.DEVICE_ID_EMULATION` e só quando `is_touch_mode() == false`:
esquerdo → `Input.action_press/release("fire")`, direito → `"aim"`, roda → `Input.action_press("zoom_in")` +
release no frame seguinte (`call_deferred`). O `Player` também ignora `InputEventMouseMotion` com device de
emulação.

**Modo toque.** `InputSetup` mantém `_touch_mode: bool`. Inicial: setting `touch_controls` (`"on"` → true,
`"off"` → false, `"auto"` → `DisplayServer.is_touchscreen_available()`). Em `"auto"`, um
`InputEventScreenTouch` liga o modo toque; um `InputEventKey` ou `InputEventMouseMotion` real
(`device != DEVICE_ID_EMULATION`, `relative.length() > 2`) desliga. Ao mudar emite
`GameEvents.touch_mode_changed(is_touch)`. Teclado sempre funciona, mesmo em modo toque.

API de `InputSetup` (sem `class_name`):
```gdscript
const ACTIONS: PackedStringArray = ["move_forward","move_back","move_left","move_right","fire","aim",
	"zoom_in","zoom_out","reload","sprint","crouch","weapon_1","weapon_2","weapon_swap",
	"dog_command","use_item","item_next","pause"]
func register_actions() -> void          # chamado no _ready; idempotente
func is_touch_mode() -> bool
func set_touch_override(mode: String) -> void   # "auto" | "on" | "off"; reaplica e emite se mudou
func release_all_actions() -> void       # Input.action_release em todas (fim de caçada / pausa)
```

---

## 5. Barramento `GameEvents`

Arquivo `res://src/core/game_events.gd` (código verbatim no Apêndice A). Só declara sinais; nenhum estado.
Emite-se com `GameEvents.<sinal>.emit(...)`. Regra: quem é dono do fato emite; ninguém emite sinal de outro.

| Sinal | Emissor | Ouvintes | Quando |
|---|---|---|---|
| `hunt_started(request: HuntRequest)` | B `HuntController` | A `Hud`/`Player`, tests | mundo pronto, jogador posicionado, contagem inicial emitida |
| `hunt_ended(result: HuntResult)` | B `HuntController` | A (solta mouse, desliga input, some com controles de toque), tests | uma única vez, no frame em que a condição de fim é detectada |
| `hunt_paused_changed(paused: bool)` | A `PauseOverlay` | tests | ao pausar/despausar |
| `hunt_abandon_requested()` | A `PauseOverlay` ("Desistir") | B `HuntController` | B encerra com `ABANDONED` |
| `shot_fired(weapon_id: StringName, origin: Vector3, direction: Vector3, noise_radius_m: float)` | A `Weapon` | B (alerta javalis; conta tiros) | uma vez por puxada de gatilho (não por bago) |
| `player_damaged(amount: float, source_position: Vector3, health_after: float)` | A `Player.apply_damage` | A `Hud` (indicador direcional), tests | dano já reduzido pelo colete |
| `player_healed(amount: float, health_after: float)` | A `Player` | A `Hud` | kit usado |
| `player_died()` | A `Player` | B `HuntController` | vida chegou a 0 (uma vez) |
| `item_used(item_id: StringName, position: Vector3)` | A `ItemBelt` | B (ceva; conta consumíveis), tests | **só consumíveis** (`medkit`, `corn_bait`, `scout_drone`), após decrementar |
| `thermal_vision_changed(active: bool)` | A `Player` | B (`BoarVisualBase.set_highlight`) | mira térmica equipada e entrou/saiu da mira |
| `dog_command_requested()` | A (tecla E / botão Cão) | B `Dog` | B decide se é "Pega!" ou "Volta!" |
| `boar_spawned(boar_id: int, type_id: StringName, weight_kg: float)` | B | tests | javali entrou no mapa |
| `boar_hit(boar_id: int, zone: StringName, damage: float, hit_position: Vector3, shot_id: int)` | B `Boar` | A `Hud` (hitmarker, dedup por `shot_id`), tests | por bago/bala que acertou; `damage` já com multiplicador de zona |
| `boar_state_changed(boar_id: int, state: StringName)` | B `Boar` | tests | toda transição da FSM (`Ids.BS_*`) |
| `boar_killed(kill: KillInfo)` | B `HuntController` | A `Hud` (mensagem de abate), tests | morte, já com `reward_money` |
| `boar_counts_changed(killed: int, total: int)` | B | A `Hud` | no início e a cada morte |
| `crop_health_changed(pct: float)` | B `CropManager` | A `Hud` | quando variou ≥ `hunt.crop_health_signal_step_pct` desde o último envio, e ao chegar a 0 |
| `crop_under_attack(active: bool)` | B `CropManager` | A `Hud` ("Javalis na lavoura!" + `crop_alarm`) | nº de javalis comendo passa de 0→>0 (true) ou >0→0 (false) |
| `bait_placed(position: Vector3, duration_s: float)` | B | A `Hud` (minimapa), tests | ceva instanciada |
| `dog_state_changed(state: StringName)` | B `Dog` | A `Hud` | transição (`Ids.DS_*`) |
| `dog_health_changed(pct: float)` | B `Dog` | A `Hud` | vida do cão mudou (0–100) |
| `dog_marked_boar(position: Vector3, duration_s: float)` | B `Dog` | A `Hud` (bússola + minimapa) | cão apontou/acuou/agarrou |
| `dog_command_executed(command: StringName)` | B `Dog` | A `Hud` (balão "Pega!"/"Volta!") | `Ids.CMD_ATTACK` ou `Ids.CMD_RECALL` |
| `hud_message_requested(text: String, duration_s: float)` | B (e A) | A `Hud` | mensagens de contexto em PT-BR |
| `wallet_changed(money: int, gold: int)` | `Profile` | menus | qualquer alteração de saldo |
| `inventory_changed()` | `Profile` | menus | compra, consumo |
| `loadout_changed()` | `Profile` | `ui/preparation` | alteração de loadout |
| `progression_changed()` | `Profile` | menus | contrato vencido/desbloqueado |
| `settings_changed(key: String, value: Variant)` | `Profile` | `InputSetup`, `Sfx`, A `Player` (sensibilidade), B (qualidade só na próxima caçada) | `Profile.set_setting` |
| `touch_mode_changed(is_touch: bool)` | `InputSetup` | A `Hud`, menus | mudou o modo de input |
| `hunter_joined(slot: int, display_name: String)` | B `HuntController` | A `Hud` | caçador remoto criado na montagem |
| `hunter_left(slot: int)` | B `HuntController` | A `Hud` (mensagem), `SpectatorCamera` | peer saiu ou caiu durante a caçada |
| `hunter_died(slot: int)` | B `HuntController` | A `Hud`, `SpectatorCamera` | qualquer caçador (local ou remoto) morreu |
| `spectate_changed(slot: int)` | A `Player` | A `Hud` | começou/trocou de alvo como espectador (−1 = deixou) |
| `net_stall_changed(stalled: bool)` | `Net` | A `Hud` (faixa "Anfitrião sem resposta…") | cliente ficou `net.host_stall_warn_s` sem snapshot / voltou |

`player_died()` continua significando "o caçador **desta máquina** morreu". Sinais de cão
(`dog_state_changed`, `dog_health_changed`, `dog_command_executed`) passam a valer só para o cão do jogador
local, em qualquer máquina. `dog_marked_boar` e `bait_placed` valem para o time inteiro.

Ordem garantida na morte de um javali (B): `boar_hit` → `boar_state_changed(id, &"dead")` →
`boar_killed` → `boar_counts_changed`. A checagem de fim de caçada acontece no `_process` do
`HuntController` (mesmo frame ou o seguinte), nunca dentro do callback de dano.

---

## 6. Autoloads e classes públicas

Assinaturas são contrato: **nome, tipos e ordem dos parâmetros exatos**. Stubs dos autoloads (Fase 0, pelo
coordenador) contêm **todas** as funções desta seção com corpo trivial que devolve o valor indicado como
"stub", para que A e B compilem e rodem isolados. O dono substitui os corpos sem mudar assinaturas.

### 6.1 Autoload `GameEvents` — `res://src/core/game_events.gd` — dono: coordenador
Só sinais (§5, Apêndice A).

### 6.2 Autoload `Data` — `res://src/systems/data_registry.gd` — dono: game-systems
Lê todos os JSON de `data/` no `_ready()`. Stub da Fase 0 **funcional** (Apêndice B), porque A e B
dependem dos dados para rodar isolados. game-systems acrescenta validação de esquema sem mudar a API.
```gdscript
func reload() -> void
func get_load_errors() -> PackedStringArray          # vazio = tudo ok
func get_game() -> Dictionary                         # data/game.json inteiro
func get_weapon(id: StringName) -> Dictionary         # {} + push_error se não existir
func get_weapon_ids() -> Array[StringName]            # na ordem do arquivo
func get_equipment(id: StringName) -> Dictionary
func get_equipment_ids() -> Array[StringName]
func get_dog(id: StringName) -> Dictionary
func get_dog_ids() -> Array[StringName]
func get_boar_type(id: StringName) -> Dictionary
func get_boar_type_ids() -> Array[StringName]
func get_boar_rules() -> Dictionary                   # boars.json sem a chave "types"
func get_map(id: StringName) -> Dictionary
func get_map_ids() -> Array[StringName]
func get_contract(map_id: StringName, index: int) -> Dictionary   # index 0-based
func get_contract_count(map_id: StringName) -> int
func get_gold_packages() -> Array[Dictionary]
func get_gold_package(id: StringName) -> Dictionary
func get_pix_config() -> Dictionary
func get_net() -> Dictionary                          # data/net.json inteiro (§9.9)
func get_item_def(id: StringName) -> Dictionary       # procura em weapons, equipment e dogs
func get_item_category(id: StringName) -> StringName  # &"weapon" | &"equipment" | &"dog" | &""
```
**Armadilhas obrigatórias para todo leitor de dados:**
1. `JSON.parse_string` devolve **todo número como `float`**. Converta: `int(def["price"])`.
2. Chaves dos dicionários vindos de JSON são `String`. Indexe sempre com literal `String`
   (`def["damage"]`), nunca com `StringName` (`def[&"damage"]`). Ids em listas também chegam como `String`;
   converta com `StringName(x)`.
3. Dicionários devolvidos são compartilhados: **não modifique**; use `.duplicate(true)` se precisar.

### 6.3 Autoload `Profile` — `res://src/systems/profile.gd` — dono: game-systems
Fachada do meta-jogo: carteira, inventário, loadout, progressão, settings, regras de economia, save.
```gdscript
const SAVE_VERSION: int = 2
const DEFAULT_SAVE_PATH: String = "user://save.json"

func set_save_path(path: String) -> void        # tests usam "user://test_save.json"; não carrega sozinho
func load_or_create() -> void                   # chamado no _ready; nunca falha (§10)
func save() -> bool
func reset_progress() -> void                   # novo perfil; mantém settings; salva
# carteira                                                 stub
func get_money() -> int                                   # 500
func get_gold() -> int                                    # 0
func add_money(amount: int) -> void                       # amount >= 0; emite wallet_changed
func add_gold(amount: int) -> void
# inventário / loja
func owns(item_id: StringName) -> bool                    # true só para &"carbine_22"
func get_item_count(item_id: StringName) -> int           # consumíveis: quantidade; demais: 0/1
func can_buy(item_id: StringName) -> StringName           # mesmos códigos de buy, sem efeito
func buy(item_id: StringName) -> StringName               # &"ok" | &"insufficient_funds" | &"already_owned" | &"max_reached" | &"unknown_item"; salva se ok
# loadout
func get_loadout_weapons() -> Array[StringName]           # sempre 2 entradas; &"" = vazio. stub [&"carbine_22", &""]
func set_loadout_weapon(slot: int, weapon_id: StringName) -> bool   # slot 0/1; &"" esvazia (slot 0 nunca vazio)
func get_loadout_dog() -> StringName                      # &"" = sem cão
func set_loadout_dog(dog_id: StringName) -> bool
func get_loadout_items() -> Array[StringName]             # até game.loadout.item_slots (3)
func set_loadout_items(item_ids: Array[StringName]) -> bool
# progressão
func get_unlocked_contract_count(map_id: StringName) -> int        # >= 1 para mapa disponível
func is_contract_unlocked(map_id: StringName, index: int) -> bool
func is_contract_completed(map_id: StringName, index: int) -> bool
func get_stats() -> Dictionary                            # cópia do bloco "stats" do save
# ponte com a caçada
func build_hunt_request(map_id: StringName, contract_index: int) -> HuntRequest   # stub: HuntRequest.make_debug(map_id, contract_index)
func kill_reward(type_id: StringName, weight_kg: float, killing_zone: StringName, one_shot: bool, map_id: StringName, contract_index: int) -> int   # stub 0
func contract_bonus(map_id: StringName, contract_index: int, crop_health_pct: float) -> int                                                       # stub 0
func apply_hunt_result(result: HuntResult) -> void        # ÚNICO ponto que credita a caçada; salva
# doações
func is_code_redeemed(code: String) -> bool
func mark_code_redeemed(code: String) -> void
# settings
func get_setting(key: String) -> Variant                  # stub: valor default da tabela §10
func set_setting(key: String, value: Variant) -> void     # valida, emite settings_changed, salva
```
`apply_hunt_result`: `money += result.total_money`; subtrai `result.consumables_used` do inventário;
se `VICTORY` **e `result.counts_for_progression`**: marca o contrato vencido e desbloqueia o próximo
(`index + 1`, se existir); atualiza stats; `save()`. Chamado só por `Router.finish_hunt`. Settings novo:
`player_name` (String, §10).

### 6.4 Autoload `InputSetup` — `res://src/input/input_setup.gd` — dono: Pacote A
API em §4. Stub: `register_actions()` vazio, `is_touch_mode()` → `false`.

### 6.5 Autoload `Sfx` — `res://assets/audio/sfx_library.gd` — dono: art-director
API e ids em §7.8. Stub: tudo no-op, `has_sound()` → `false`.

### 6.6 Autoload `Router` — `res://src/systems/router.gd` — dono: game-systems
```gdscript
var selected_map_id: StringName = &"mato_grosso"
var selected_contract_index: int = 0
var last_result: HuntResult = null

func goto(scene_path: String) -> void                 # despausa a árvore, release_all_actions, change_scene_to_file deferred
func get_current_scene_path() -> String
func set_pending_request(request: HuntRequest) -> void
func get_pending_request() -> HuntRequest             # null se não houver; NÃO consome
func start_hunt(request: HuntRequest) -> void         # set_pending_request + goto(ScenePaths.HUNT)
func finish_hunt(result: HuntResult) -> void          # last_result = result; Profile.apply_hunt_result(result); goto(ScenePaths.RESULT)
```
O Router também possui o aviso de orientação (CanvasLayer `layer = 100` com Label "Gire o aparelho para
jogar na horizontal", visível quando `get_viewport().get_visible_rect().size.y > size.x`).

### 6.7 Classes de `src/core/` (dono: coordenador, código no Apêndice A)

| class_name | Arquivo | Extends | Papel |
|---|---|---|---|
| `Layers` | `src/core/layers.gd` | RefCounted | constantes de bits de colisão |
| `Ids` | `src/core/ids.gd` | RefCounted | StringNames de zonas, tipos, estados, comandos, itens, moedas, qualidade |
| `ScenePaths` | `src/core/scene_paths.gd` | RefCounted | caminhos de cenas e convenções de assets |
| `AssetLoader` | `src/core/asset_loader.gd` | RefCounted | `instantiate(path) -> Node` / `load_resource(path) -> Resource`, null + aviso único se faltar |
| `HitInfo` | `src/core/hit_info.gd` | RefCounted | dados de um impacto de bala/bago |
| `HitZone` | `src/core/hit_zone.gd` | Area3D | zona de acerto; `receive_hit(hit)` → sinal `hit_received(hit)` |
| `KillInfo` | `src/core/kill_info.gd` | RefCounted | dados de um abate |
| `HuntRequest` | `src/core/hunt_request.gd` | RefCounted | o que a caçada recebe dos menus |
| `HuntResult` | `src/core/hunt_result.gd` | RefCounted | o que a caçada devolve |
| `PlayerBase` | `src/core/player_base.gd` | CharacterBody3D | contrato caçador ↔ caçada (A implementa `Player`) |
| `HuntWorld` | `src/core/hunt_world.gd` | Node3D | contrato caçada/mundo ↔ caçador/HUD/tests (B implementa `HuntController`) |
| `BoarVisualBase` | `src/core/boar_visual_base.gd` | Node3D | API da visão do javali + fallback |
| `DogVisualBase` | `src/core/dog_visual_base.gd` | Node3D | API da visão do cão + fallback |
| `HunterVisualBase` | `src/core/hunter_visual_base.gd` | Node3D | API da visão do caçador aliado (§7.11) + fallback |
| `NetCodec` | `src/core/net_codec.gd` | RefCounted | constantes e quantização da rede (compartilhadas por A, B e N) |
| `NetPeerInfo` | `src/core/net_peer_info.gd` | RefCounted | um jogador da sala |
| `WeaponViewBase` | `src/core/weapon_view_base.gd` | Node3D | API da arma em 1ª pessoa + fallback |
| `MapEnvironmentBase` | `src/core/map_environment_base.gd` | Node3D | API do ambiente (céu/sol) + fallback |

### 6.8 Pacote A — classes públicas (dono: game-developer A)

| class_name | Arquivo | Extends | API pública relevante para outros |
|---|---|---|---|
| `Player` | `src/player/player.gd` (cena `src/player/player.tscn`) | PlayerBase | toda a API de `PlayerBase` |
| `Weapon` | `src/weapons/weapon.gd` | Node | interna ao A |
| `WeaponHolder` | `src/weapons/weapon_holder.gd` | Node3D | interna |
| `Hitscan` | `src/weapons/hitscan.gd` | RefCounted (static) | `static func cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, max_range_m: float, exclude: Array[RID]) -> Dictionary` |
| `ItemBelt` | `src/player/item_belt.gd` | Node | interna |
| `Hud` | `src/hud/hud.gd` (cena `src/hud/hud.tscn`) | CanvasLayer | `func bind(player: PlayerBase, world: HuntWorld) -> void` |
| `PauseOverlay` | `src/hud/pause_overlay.gd` (cena `.tscn`) | CanvasLayer | interna |
| `TouchControls` | `src/hud/touch/touch_controls.gd` (cena `.tscn`) | CanvasLayer | interna |
| `VirtualJoystick` | `src/hud/touch/virtual_joystick.gd` | Control | interna |
| `RemoteHunter` | `src/player/remote_hunter.gd` (cena `src/player/remote_hunter.tscn`, `ScenePaths.REMOTE_HUNTER`) | PlayerBase | caçador de outro jogador; API de `PlayerBase` (`setup_remote(slot: int, display_name: String, weapon_id: StringName, world: HuntWorld)`, `net_apply_state`…); `net_write_state` devolve os últimos 14 bytes recebidos (`NetCodec.HUNTER_STATE_BYTES`), então o anfitrião reenvia todos os caçadores sem caso especial; sem corpo e sem forma de colisão |
| `SpectatorCamera` | `src/player/spectator_camera.gd` | Node3D | interna |

Estrutura obrigatória de `src/player/player.tscn` (B só usa a raiz):
```
Player (CharacterBody3D, player.gd)   origem = pés; collision_layer=4, collision_mask=3
├── CollisionShape3D (CapsuleShape3D r=0.35, h=1.8, centro y=0.9)
└── Head (Node3D, y = standing_eye_height_m)  ← yaw no Player, pitch no Head
    └── Camera3D (fov 75, near 0.05, far = view_distance_m da qualidade)
        └── WeaponHolder (Node3D)  ← recebe as WeaponViewBase
```
O `Player` instancia `ScenePaths.HUD` como filho em `setup()` e chama `hud.bind(self, world)`.

### 6.9 Pacote B — classes públicas (dono: game-developer B)

| class_name | Arquivo | Extends | Observação |
|---|---|---|---|
| `HuntController` | `src/hunt/hunt_controller.gd` (raiz de `src/hunt/hunt.tscn`) | HuntWorld | `var route_on_finish: bool = true` (tests põem false antes de `add_child`) |
| `BoarSpawner` | `src/hunt/boar_spawner.gd` | Node | interna; em rede: `static func scale_groups(groups: Array, player_count: int, coop: Dictionary) -> Array`, `func notify_shot(origin: Vector3, noise_radius_m: float) -> void` |
| `HuntHostSync` | `src/hunt/hunt_host_sync.gd` | Node | interna (anfitrião: enfileira `EV_*`, escreve o snapshot, aplica `C_*`) |
| `HuntReplica` | `src/hunt/hunt_replica.gd` | Node3D | interna (cliente: as réplicas de javalis e cães são filhas dela; `setup(world: HuntWorld, heightmap: Heightmap, map_rect: Rect2, crop: CropManager)`) |
| `BoarPuppet` | `src/boars/boar_puppet.gd` | Node3D | interna (réplica do javali, com 4 `HitZone`) |
| `DogPuppet` | `src/dogs/dog_puppet.gd` | Node3D | interna (réplica do cão) |
| `FallbackPlayer` | `src/hunt/debug/fallback_player.gd` | PlayerBase | cápsula simples usada se `player.tscn` não existir |
| `MapRoot` | `src/world/map_root.gd` | Node3D | raiz de toda cena de mapa (§8.5) |
| `Heightmap` | `src/world/heightmap.gd` | RefCounted | `get_height(x, z) -> float`, `get_normal(x, z) -> Vector3` |
| `Terrain` | `src/world/terrain.gd` | Node3D | malha + colisão |
| `CropField` | `src/world/crop_field.gd` | Marker3D | `@export var size_m: Vector2`, `@export var crop: StringName` (&"soy"/&"corn") |
| `CropManager` | `src/world/crop_manager.gd` | Node3D | saúde da lavoura, MultiMesh de plantas |
| `PropSpawn` | `src/world/prop_spawn.gd` | Marker3D | `@export var prop_id: StringName`, `@export var collision_size: Vector3`, `@export var footprint_radius_m: float` |
| `WaterBody` | `src/world/water_body.gd` | Marker3D | `@export var radius_m: float`, `@export var depth_m: float = 1.5` |
| `FloraZone` | `src/world/flora_zone.gd` | Marker3D | `@export var radius_m: float`, `@export var counts: Dictionary` (id String → int) |
| `FloraScatter` | `src/world/flora_scatter.gd` | Node3D | MultiMesh + troncos |
| `ObstacleGrid` | `src/world/obstacle_grid.gd` | RefCounted | consulta de obstáculos circulares para steering |
| `Bait` | `src/world/bait.gd` | Node3D | ceva ativa |
| `Steering` | `src/boars/steering.gd` | RefCounted (static) | seek/flee/separação/evitação |
| `Boar` | `src/boars/boar.gd` (cena `src/boars/boar.tscn`) | Node3D | FSM do javali |
| `BoarHerd` | `src/boars/boar_herd.gd` | RefCounted | líder, alerta compartilhado |
| `Dog` | `src/dogs/dog.gd` (cena `src/dogs/dog.tscn`) | Node3D | FSM do cão; `setup(p_breed_id: StringName, world: HuntWorld, spawn_position: Vector3, p_owner_slot: int = 0)`, `command()` público |

Alterações de assinatura existentes por causa da rede: `MapRoot.build_flora(density: float, sync_layout: bool
= false)`; `CropManager` ganha `apply_eaten(indices: PackedInt32Array)`, `set_replicated_health(pct: float)` e
o sinal `patch_eaten(index: int)`. O solo chama tudo com os defaults e o comportamento não muda.

Membros novos, internos de B (uso só dentro de `src/hunt`, `src/boars`, `src/world`):
- `BoarSpawner`: sinal `boar_added(boar: Boar)`.
- `MapRoot.get_flora_positions(id: StringName) -> PackedVector2Array`.
- `Boar`: sinais `hit_applied(boar, zone, damage, shot_id)` e `attacked(boar, victim_slot)`; `var killer_slot: int`;
  `get_hit_zone(zone: StringName) -> HitZone`, `get_yaw() -> float`, `net_state_byte() -> int`,
  `net_confirm_charge_hit(victim_slot: int) -> bool`; estáticos `make_hit_zones(parent: Node3D, p_boar_id: int,
  p_body_scale: float) -> Array[HitZone]`, `basis_for(yaw: float, up: Vector3) -> Basis`,
  `charge_hits(pos: Vector2, dir: Vector2, p_body_scale: float, boar_y: float, target: Vector3) -> bool`.
- `HuntController`: `place_bait(at: Vector3)` (ceva vinda da rede), `get_baits() -> Array[Bait]`.
- `CropManager`: `set_replicated_attack(on: bool)`, `is_under_attack() -> bool`, `get_eaten_indices() -> PackedInt32Array`.

### 6.10 game-systems — classes públicas (testadas pelo qa)

| class_name | Arquivo | Extends | API |
|---|---|---|---|
| `Wallet` | `src/systems/wallet.gd` | RefCounted | `var money: int`, `var gold: int`, `balance(currency: StringName) -> int`, `can_afford(price: int, currency: StringName) -> bool`, `spend(price: int, currency: StringName) -> bool`, `add(amount: int, currency: StringName) -> void` (negativo → push_error, ignora), `to_dict() -> Dictionary`, `static from_dict(d: Dictionary) -> Wallet` |
| `Inventory` | `src/systems/inventory.gd` | RefCounted | `var owned_weapons: Array[StringName]`, `var owned_dogs: Array[StringName]`, `var items: Dictionary` (StringName→int), `var loadout_weapons: Array[StringName]`, `var loadout_dog: StringName`, `var loadout_items: Array[StringName]`, `owns(id) -> bool`, `get_count(id) -> int`, `add_item(id: StringName, count: int) -> void`, `remove_item(id: StringName, count: int) -> bool`, `to_dict()`, `static from_dict(d) -> Inventory` |
| `Progression` | `src/systems/progression.gd` | RefCounted | `unlocked_count(map_id) -> int`, `is_unlocked(map_id, index) -> bool`, `is_completed(map_id, index) -> bool`, `mark_won(map_id: StringName, index: int, crop_pct: float) -> void`, `to_dict()`, `static from_dict(d) -> Progression` |
| `Shop` | `src/systems/shop.gd` | RefCounted (static) | `static func check(item_id: StringName, wallet: Wallet, inventory: Inventory) -> StringName`, `static func buy(item_id: StringName, wallet: Wallet, inventory: Inventory) -> StringName` |
| `RewardCalculator` | `src/systems/reward_calculator.gd` | RefCounted (static) | `static func kill_reward(type_def: Dictionary, rules: Dictionary, weight_kg: float, killing_zone: StringName, one_shot: bool, contract_def: Dictionary) -> int`, `static func contract_bonus(contract_def: Dictionary, crop_health_pct: float) -> int` |
| `SaveService` | `src/systems/save_service.gd` | RefCounted (static) | `static func write(path: String, data: Dictionary) -> bool`, `static func read(path: String) -> Dictionary` ({} se ausente/corrompido), `static func migrate(data: Dictionary) -> Dictionary`, `static func sanitize(data: Dictionary) -> Dictionary`, `static func new_save() -> Dictionary` |
| `PixBrCode` | `src/systems/pix/pix_br_code.gd` | RefCounted (static) | `static func crc16_ccitt(text: String) -> int`, `static func build(pix_key: String, amount_brl: float, merchant_name: String, merchant_city: String, txid: String = "***", description: String = "") -> String`, `static func sanitize(text: String, max_len: int) -> String` |
| `PixGateway` | `src/systems/pix/pix_gateway.gd` | RefCounted | `signal redeem_completed(ok: bool, gold: int, message: String)`, `func get_payment_payload(package: Dictionary) -> String`, `func request_redeem(code: String) -> void`, `func is_secure() -> bool`, `static func create_from_config(config: Dictionary) -> PixGateway` |
| `OfflineRedeemGateway` | `src/systems/pix/offline_redeem_gateway.gd` | PixGateway | `is_secure()` → false |
| `RedeemCode` | `src/systems/pix/redeem_code.gd` | RefCounted (static) | `static func normalize(code: String) -> String`, `static func generate(gold: int, nonce: String, secret: String) -> String`, `static func parse(code: String, secret: String) -> int` (ouro ou -1) |
| `DonationService` | `src/systems/pix/donation_service.gd` | RefCounted | `signal redeem_finished(ok: bool, gold: int, message: String)`, `func _init(gateway: PixGateway = null)`, `func get_packages() -> Array[Dictionary]`, `func get_pix_payload(package_id: StringName) -> String`, `func redeem(code: String) -> void` |

| `LoadoutPanel` | `src/ui/common/loadout_panel.gd` | VBoxContainer | painel de equipamento da Preparação, reaproveitado pelo lobby (`%WeaponSlot0`, `%WeaponSlot1`, `%DogOption`, `Item_<id>`) |

Detalhes de Pix em §9.8.

### 6.11 Autoload `Net` — `res://src/net/net.gd` — dono: Pacote N

Ordem dos autoloads: `Net` é o último (usa `Data`, `Profile`, `Router`). Offline (`Role.OFFLINE`) o autoload
fica com `set_process(false)`, não abre socket e todos os getters devolvem os valores "solo" abaixo (stub). O
stub da fase F1 é exatamente esse estado.

```gdscript
enum Role { OFFLINE, HOST, CLIENT }
enum RoomState { NONE, CONNECTING, LOBBY, LOADING, IN_HUNT }
enum Path { NONE, RELAY, RTC }

signal room_state_changed(state: int)                 # RoomState
signal room_error(code: StringName, message: String)  # message já em PT-BR
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
ficam em fila e são aplicados em ordem. Formatos de registro: `docs/multiplayer.md` §4. Ao entrar em
`LOADING`, `Net` completa o `Router.get_pending_request()` com `rng_seed` (= `get_hunt_seed()`),
`player_count`, `map_id` e `contract_index`.

Classes internas de N (ninguém fora de `src/net` as referencia): `NetSession` (sala, lobby, relógio de ticks,
despacho), `NetSignaling` (`WebSocketPeer`, JSON de sala/sinalização, quadros de relay), `NetLink` (um par:
caminho RELAY/RTC, `seq`/`ack`, reordenação, reenvio), `NetRtc` (`WebRTCPeerConnection` + 2 canais; só
instanciado no Web), `NetLoopback` (par em memória com perda/reordenação configuráveis, para testes).

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

---

## 7. Contrato de assets (art-director ↔ gameplay)

Regras gerais para **toda** cena em `assets/`:
- Só visual e som. **Nenhum** `PhysicsBody3D`, `Area3D`, `CollisionShape3D`, `AnimationPlayer` importado,
  `Skeleton3D`, luz `OmniLight3D`/`SpotLight3D` (a única luz do jogo é o `Sun` do ambiente).
- Origem no chão (Y=0) no centro da pegada; frente = -Z; escala 1 = tamanho de referência abaixo.
- Malhas construídas em código (`SurfaceTool`/`ArrayMesh`/primitivas) dentro do script do asset, em
  `_ready()` ou `_init()`. Animação procedural em `_process` do próprio asset.
- O script do asset **não** altera `scale`, `position` nem `rotation` do próprio nó raiz (o gameplay é
  dono do transform da raiz). Anima apenas filhos.
- Materiais compartilhados entre instâncias (cache estático no script); cores via vertex color.
- O asset deve funcionar com `process_mode` herdado (para pausar junto) e em `--headless`.

**Fallback (validação isolada).** Gameplay carrega assets só por `AssetLoader.instantiate(path)` /
`AssetLoader.load_resource(path)`. Se devolver `null` (arquivo ainda não existe) ou a raiz não for da
classe-base esperada, usa o fallback indicado em cada item. Fallbacks emitem **um** `push_warning` por
caminho. O teste de contrato de assets (§12) roda em modo estrito na integração e falha se algum fallback
foi usado.

### 7.1 Javali — `res://assets/models/boar/boar_visual.tscn`
- Raiz: `Node3D` com script que **estende `BoarVisualBase`** (`res://assets/models/boar/boar_visual.gd`).
- Filhos obrigatórios: `Head` (`Node3D`, acompanha a animação da cabeça; posição de repouso
  ≈ (0, 0.55, -0.62)).
- Referência (escala 1 = **100 kg**): comprimento 1,50 m (focinho z = -0.80, cauda z = +0.70), altura na
  cernelha 0,85 m, largura 0,50 m. O gameplay aplica `visual.scale = Vector3.ONE * BoarVisualBase.scale_for_weight(kg)`
  (raiz cúbica de kg/100). O modelo deve caber nas caixas de `BoarVisualBase.HIT_ZONES` (tolerância ±5 cm).
- Orçamento: ≤ 600 triângulos; ≤ 6 `MeshInstance3D`; pernas com `visibility_range_end = 40.0`;
  ≤ 1 material por tipo (4 no total, compartilhados). `cast_shadow` ligado só no corpo.
- Variação por tipo (em `setup`): leitão mais claro com listras tênues, fêmea marrom-acinzentada, macho
  escuro com presas visíveis, alfa quase preto, crina dorsal e presas grandes.
- API (todas virtuais em `BoarVisualBase`; o asset sobrescreve):

| Método | Contrato |
|---|---|
| `setup(type_id: StringName, weight_kg: float) -> void` | cosmético (cor, presas, crina); chamado uma vez antes de entrar no ar; não escala a raiz |
| `set_locomotion(speed_mps: float) -> void` | 0 = parado; ciclo de passo proporcional; >5 m/s galope. Chamado todo frame |
| `set_eating(on: bool) -> void` | cabeça baixa fuçando, loop |
| `set_wounded(on: bool) -> void` | manca |
| `set_highlight(on: bool) -> void` | mira térmica: material emissivo laranja-branco, visível através de vegetação não é exigido |
| `play_alert() -> void` | cabeça erguida, orelhas, ~1 s |
| `play_scrape() -> void` | telegrafa investida: raspa a pata dianteira e abaixa a cabeça; loop até outro `play_*`/`set_locomotion(>0)` |
| `play_attack() -> void` | golpe de presa ~0,4 s |
| `play_hit(zone: StringName) -> void` | tranco ~0,15 s |
| `play_death() -> void` | tomba de lado em ~0,7 s e congela; depois disso ignora as demais chamadas |

### 7.2 Cão — `res://assets/models/dog/dog_visual.tscn`
- Raiz: `Node3D` estendendo `DogVisualBase` (`res://assets/models/dog/dog_visual.gd`).
- Filhos obrigatórios: `Mouth` (`Marker3D`, ponta do focinho).
- Referências por raça (o asset aplica as proporções internamente; o gameplay **não** escala o cão):
  `caramelo` cernelha 0,52 m, comprimento 0,85 m, caramelo liso; `foxhound` 0,60 m / 0,95 m, tricolor;
  `dogo` 0,64 m / 1,00 m, branco musculoso.
- Orçamento: ≤ 500 triângulos, ≤ 6 `MeshInstance3D`, 1 material por raça.
- API:

| Método | Contrato |
|---|---|
| `setup(breed_id: StringName) -> void` | proporções e pelagem |
| `set_locomotion(speed_mps: float) -> void` | idem javali |
| `set_retreating(on: bool) -> void` | rabo baixo, orelhas para trás |
| `play_bark() -> void` | animação de latido ~0,3 s (o som é tocado pelo gameplay) |
| `play_bite(on: bool) -> void` | segurando/mordendo, loop enquanto `true` |
| `play_hurt() -> void` | ganido/tranco ~0,3 s |
| `play_point() -> void` | pose de amarração (aponta), loop até `set_locomotion(>0)` |

### 7.3 Armas em primeira pessoa — `res://assets/models/weapons/<weapon_id>_view.tscn`
Ids: `carbine_22`, `shotgun_12`, `rifle_308`, `rifle_3006`, `rifle_338` (caminho por
`ScenePaths.weapon_view(id)`).
- Raiz: `Node3D` estendendo `WeaponViewBase` (script compartilhado `res://assets/models/weapons/weapon_view.gd`
  é permitido; `setup(weapon_id)` escolhe o modelo).
- É filha do `Camera3D` (via `WeaponHolder`). Espaço da câmera: olho na origem, olhando -Z. Em
  `position = (0,0,0)` a arma aparece na **posição de quadril** (canto inferior direito, coronha ≈
  (0.20, -0.22, -0.30)).
- Filhos obrigatórios:
  - `Muzzle` (`Marker3D`) na boca do cano, -Z para fora. Origem dos efeitos visuais; **o raio do tiro sai da câmera**, não do Muzzle.
  - `AdsAnchor` (`Marker3D`) no ponto da linha de mira (alça/massa ou centro da ocular). Na mira, o A move a
    raiz para `Vector3(-AdsAnchor.position.x, -AdsAnchor.position.y, 0.0)`.
- Inclui braços (manga cáqui, mãos de pele). Comprimento: .22 ≈ 0,95 m; 12 ≈ 1,0 m; rifles ≈ 1,1 m; luneta
  visível no .308/.30-06/.338.
- Orçamento: ≤ 1500 triângulos com braços; ≤ 4 `MeshInstance3D`; `cast_shadow = OFF`; sem luz no flash.
- API:

| Método | Contrato |
|---|---|
| `setup(weapon_id: StringName) -> void` | monta o modelo |
| `play_fire() -> void` | coice (anima filhos) + clarão emissivo no Muzzle por 0,06 s |
| `play_cycle(duration_s: float) -> void` | ferrolho/bomba/no-op (.22 e .30-06), cabe em `duration_s` |
| `play_reload(duration_s: float) -> void` | recarga completa em `duration_s` |
| `play_draw(duration_s: float) -> void` | sacar a arma |
| `get_muzzle() -> Node3D` / `get_ads_anchor() -> Node3D` | já implementados na base |

Quando a arma tem `scoped = true` e a mira está ≥ 95% ativa, o A **esconde** a visão e o HUD mostra a
sobreposição de luneta (§7.9).

### 7.4 Props — `res://assets/models/props/<prop_id>.tscn`
Raiz `Node3D`, sem script obrigatório, sem física. O Pacote B cria a colisão a partir do `PropSpawn`
(`collision_size`), então as dimensões abaixo são contrato (±10%):

| prop_id | Dimensões (X × Y × Z m) | Descrição | Tris máx |
|---|---|---|---|
| `farmhouse` | 12 × 6 × 8 | sede: alvenaria branca, telhado de telha, varanda (frente -Z) | 900 |
| `barn` | 16 × 7 × 10 | galpão de madeira/zinco aberto na frente | 700 |
| `water_tank` | 3 × 8 × 3 | caixa d'água em torre de madeira | 300 |
| `fence_segment` | 4 × 1,3 × 0,15 | cerca de arame com 2 mourões, ao longo de X | 80 |
| `gate` | 4 × 1,4 × 0,2 | porteira de madeira | 120 |
| `corn_bait` | 1,0 × 0,3 × 1,0 | monte de milho em espiga (ceva) | 150 |
| `feed_trough` | 3 × 0,6 × 0,8 | cocho | 80 |

Fallback (B): `BoxMesh` do tamanho `collision_size` com cor neutra.

### 7.5 Flora e lavoura — `res://assets/models/flora/flora_library.gd`
Script **sem `class_name`**, `extends RefCounted`, com:
```gdscript
static func build_mesh(id: StringName) -> Mesh   # null se id desconhecido; Mesh com material em cada superfície
```
O B chama `var lib: Script = AssetLoader.load_resource(ScenePaths.FLORA_LIBRARY) as Script` e
`lib.call(&"build_mesh", id)`, uma vez por id (cache). Origem na base, Y para cima; o B aplica yaw
aleatório e escala ±20%. Sem `cast_shadow` em grama, arbusto e lavoura (o B força OFF).

| id | Referência | Tris máx | Colisão criada pelo B |
|---|---|---|---|
| `grass_tuft` | tufo de capim dourado 0,4 m alt. | 8 | — |
| `shrub` | arbusto do cerrado 1,0 alt. × 1,2 larg. | 60 | — |
| `cerrado_tree` | árvore retorcida 4,5 m, tronco r 0,2, copa 3 m | 200 | cilindro r 0,2 × 3 m |
| `ipe` | ipê-amarelo 7 m, tronco r 0,3, copa amarela 5 m | 250 | cilindro r 0,3 × 4 m |
| `buriti` | palmeira 12 m, tronco r 0,25, leque 6 m | 250 | cilindro r 0,25 × 6 m |
| `termite_mound` | cupinzeiro 1,2 alt. × 1,2 base, terra vermelha | 60 | cilindro r 0,6 × 1,2 m |
| `soy_patch` | moita de soja cobrindo 2×2 m, 0,6 m alt. | 24 | — |
| `soy_eaten` | soja revirada 2×2 m, 0,15 m alt. | 16 | — |
| `corn_patch` | milho cobrindo 2×2 m, 2,0 m alt. | 36 | — |
| `corn_eaten` | milho quebrado 2×2 m, 0,5 m alt. | 20 | — |

Shader de vento (vértice) permitido em grama, arbusto, lavoura e copas. Fallback (B): `CylinderMesh`/
`BoxMesh`/`QuadMesh` coloridos nas dimensões da tabela.

### 7.6 Materiais de terreno e água
- `res://assets/materials/terrain.tres` — `ShaderMaterial` (shader em `assets/shaders/terrain.gdshader`).
  Entrada definida pelo B: **vertex color** `COLOR.r` = máscara de lavoura (terra arada/verde),
  `COLOR.g` = terra vermelha exposta (estradas, carreiros), `COLOR.b` = margem úmida; resto = capim do
  cerrado; `COLOR.a` = 1. `UV` = posição mundo XZ / 4,0 (repete a cada 4 m). Normais fornecidas.
- `res://assets/materials/water.tres` — `ShaderMaterial` para o açude; o B cria um `PlaneMesh` circular
  (`radius_m` do `WaterBody`) 0,3 m abaixo da borda.
- Fallback (B): `StandardMaterial3D` com `vertex_color_use_as_albedo = true` / azul translúcido.

### 7.7 Ambiente — `res://assets/env/<map_id>_env.tscn` (`ScenePaths.environment(map_id)`)
- Raiz `Node3D` estendendo `MapEnvironmentBase`; filhos obrigatórios `WorldEnvironment`
  (com `Environment`, céu `ProceduralSkyMaterial` ou shader de céu, névoa de profundidade se suportada no
  Compatibility) e `Sun` (`DirectionalLight3D`, ~45° de elevação, tarde dourada).
- API: `apply_quality(quality: StringName) -> void` com `Ids.Q_LOW`/`Q_MEDIUM`/`Q_HIGH`: liga/desliga
  `Sun.shadow_enabled` e ajusta `directional_shadow_max_distance` conforme `game.json.quality_presets`.
  (O B passa a qualidade; a base lê os números de `Data`.)
- Fallback: `MapEnvironmentBase.create_fallback()`.

### 7.8 Biblioteca de sons — autoload `Sfx` (`res://assets/audio/sfx_library.gd`)
Sintetiza `AudioStreamWAV` (22050 Hz, mono, 16 bits) em `_ready()`; orçamento total ≤ 400 ms de CPU em
desktop e ≤ 4 MB de amostras. Cria em código os barramentos `SFX`, `Ambience`, `UI` (filhos de `Master`).
**Sem efeitos de barramento** (na Web o modo "sample" os ignora). Pool: 12 `AudioStreamPlayer3D`
(`unit_size = 8`, `max_distance = 250`) + 6 `AudioStreamPlayer`; ao esgotar, rouba o mais antigo.
```gdscript
func has_sound(id: StringName) -> bool
func play(id: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void               # 2D
func play_3d(id: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void
func play_loop(id: StringName, volume_db: float = 0.0) -> void    # ambiente; um por id
func stop_loop(id: StringName) -> void
func stop_all_loops() -> void
func unlock_audio() -> void            # chamado pelo boot no 1º gesto; toca amostra silenciosa
func set_bus_volume(bus: StringName, linear: float) -> void       # &"Master" | &"SFX" | &"Ambience" | &"UI"
```
Id desconhecido: um `push_warning` por id, sem som. Volumes iniciais e mudanças: lê `Profile.get_setting`
e escuta `GameEvents.settings_changed` (`volume_master`, `volume_sfx`, `volume_ambience`; UI usa SFX).

Ids (quem toca entre parênteses):

| Grupo | Ids |
|---|---|
| Armas (A) | `shot_22`, `shot_12`, `shot_308`, `shot_3006`, `shot_338`, `dry_fire`, `reload_start`, `reload_end`, `bolt_cycle`, `pump_cycle`, `weapon_swap`, `scope_in`, `scope_out` |
| Impactos (A) | `impact_dirt`, `impact_wood`, `impact_flesh` |
| Jogador (A) | `step_grass`, `step_dirt`, `player_hurt`, `player_heal`, `player_death`, `heartbeat`, `binocular_in` |
| HUD (A) | `hit_marker`, `kill_confirm`, `crop_alarm`, `drone_buzz` |
| Javali (B) | `boar_grunt`, `boar_squeal`, `boar_snort_alert`, `boar_scrape`, `boar_charge_roar`, `boar_eat`, `boar_death` |
| Cão (B) | `dog_bark`, `dog_growl`, `dog_yelp`, `dog_whine` |
| Mundo (B) | `bait_drop`, `amb_cerrado_loop`, `amb_wind_loop`, `victory_sting`, `defeat_sting` |
| UI (systems) | `ui_click`, `ui_buy`, `ui_error`, `ui_coin` |

Cooperativo: o Pacote A (`RemoteHunter`) passa a usar `play_3d` para os tiros e passos de aliados, com os
ids de arma e de passo já listados. Nenhum id novo.

### 7.9 UI: tema, ícones, sobreposição de luneta
- **Tema** `res://assets/ui/theme.tres` (aplicado globalmente via `gui/theme/custom`). Fonte padrão do Godot
  (suporta acentos), tamanho base 20 px; alvo de toque mínimo 64 px a 720p. Variações de tipo obrigatórias
  (`theme_type_variation`), usadas por systems e A:

| Variação | Base | Uso |
|---|---|---|
| `TitleLabel` | Label | títulos de tela, 44 px |
| `HeaderLabel` | Label | cabeçalhos, 28 px |
| `MoneyLabel` | Label | R$ (verde) |
| `GoldLabel` | Label | ouro (dourado) |
| `PrimaryButton` | Button | ação principal, 26 px, altura mín. 72 |
| `SecondaryButton` | Button | ações secundárias |
| `DangerButton` | Button | desistir/apagar |
| `CardPanel` | PanelContainer | cartões de item/mapa/contrato |
| `HudPanel` | PanelContainer | fundos translúcidos do HUD |
| `HudLabel` | Label | texto do HUD com contorno |
| `HudBigLabel` | Label | mensagens de abate/aviso, 34 px |
| `CropBar` | ProgressBar | barra da lavoura (verde→vermelho é feito pelo A via `modulate`) |
| `HealthBar` | ProgressBar | vida |

  Paleta de referência: terra vermelha `#A4442A`, capim `#C2A95A`, mata `#2F5D3A`, céu `#8EC3E6`, ipê
  `#F2C12E`, dinheiro `#3FAF5A`, ouro `#E8B923`, perigo `#D9452B`, texto `#F4EFE6`, painel `#1E1A16` (85%).
  Fallback: tema padrão do Godot (variações inexistentes são ignoradas pelo engine).
- **Ícones** `res://assets/ui/icons/<id>.svg` (`ScenePaths.icon(id)`), 128×128, SVG escrito à mão. Ids:
  todos os ids de arma, equipamento e cão; `money`, `gold`, `boar`, `crop`, `health`, `ammo`, `lock`,
  `dog_paw`, `app_icon`; mapas `map_mato_grosso`, `map_pantanal`, `map_campanha_gaucha`,
  `map_triangulo_mineiro`; toque `btn_fire`, `btn_aim`, `btn_reload`, `btn_swap`, `btn_dog`, `btn_item`,
  `btn_crouch`, `btn_pause`, `joystick_base`, `joystick_knob`. Fallback: sem ícone (texto) / círculos
  desenhados com `draw_circle`.
- **Luneta** `res://assets/ui/scope_overlay.gdshader` (`shader_type canvas_item`), aplicado pelo A num
  `ColorRect` de tela cheia. Uniforms: `float reticle_kind` (0 = duplex fino, 1 = mil-dot), `float
  vignette_radius` (0–1, default 0.42), `vec4 reticle_color`. Fallback: o A desenha círculo preto com
  `draw_arc` e cruz.

### 7.10 Efeitos — `res://assets/vfx/<id>.tscn`
`impact_dust`, `impact_blood`, `impact_wood`: raiz `CPUParticles3D` com `one_shot = true`,
`emitting = false`, ≤ 24 partículas, `lifetime` ≤ 0,8 s. O A instancia, posiciona, faz `emitting = true` e
libera após `lifetime * 2`. Máximo 6 simultâneos (o A descarta excedentes). Fallback: nada.

### 7.11 Caçador aliado — `res://assets/models/hunter/hunter_visual.tscn`
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

---

## 8. Costuras entre pacotes

### 8.1 Montagem da caçada (B ↔ A)
`HuntController._ready()` (B), em etapas separadas por `await get_tree().process_frame`, com um
`CanvasLayer` `LoadingOverlay` (layer 30, "Preparando a caçada…") visível:
1. `request = Router.get_pending_request()`; se `null`, `HuntRequest.make_debug()`.
2. Carrega o mapa: `load(ScenePaths.map_scene(request.map_id)) as PackedScene` (cena do próprio B; sem
   fallback: se faltar, `push_error` e encerra com `ABANDONED`), instancia e `add_child` com nome `Map`. Gera terreno, água, props, flora, lavoura.
3. Ambiente: `AssetLoader.instantiate(ScenePaths.environment(map_id))` ou `MapEnvironmentBase.create_fallback()`;
   `apply_quality(qualidade)`. Qualidade = `Profile.get_setting("quality")`; `"auto"` → `Ids.Q_LOW` se
   `InputSetup.is_touch_mode()`, senão `Ids.Q_MEDIUM`. Aplica também `get_viewport().scaling_3d_scale =
   render_scale` e densidade de flora.
4. Jogador: `AssetLoader.instantiate(ScenePaths.PLAYER)`; se `null` ou não `PlayerBase`, `FallbackPlayer.new()`.
   `add_child(player)`; `player.global_position` = `PlayerSpawn` com Y = `get_height`; `player.rotation.y` =
   yaw do `PlayerSpawn`; **depois** `player.setup(request, self)`.
5. Cão (se `request.dog_id != &""`), ao lado do jogador.
6. Agenda os grupos do contrato (`delay_s`). Emite `boar_counts_changed(0, total)`,
   `crop_health_changed(100.0)`, marca `is_world_ready() = true`, emite `world_ready` e
   `GameEvents.hunt_started(request)`. Esconde o `LoadingOverlay`.

Orçamento: a soma das etapas ≤ 3 s em celular intermediário; nenhuma etapa > 700 ms.

`Player.setup(request, world)` (A): lê armas (`request.weapon_ids`), itens (`request.item_ids`,
`request.item_counts`), aplica passivos (colete, munição extra, térmica), cria o `Hud`, ativa a câmera,
captura o mouse no 1º clique (desktop).

### 8.2 Dano: jogador → javali
1. A, ao puxar o gatilho: `shot_id` = contador global incrementado por puxada (começa em 1). Para cada bago
   (`pellets`): direção = olhar + espalhamento; `Hitscan.cast(...)` com máscara `Layers.MASK_WEAPON_RAY`,
   `collide_with_areas = true`, `collide_with_bodies = true`, alcance `max_range_m`, excluindo o RID do
   jogador.
2. Se o colisor é `HitZone`: monta `HitInfo` (`damage` = `weapon.damage × falloff(distância)`, **sem**
   multiplicador de zona) e chama `hit_zone.receive_hit(hit)`. Efeito `impact_blood` + `impact_flesh`.
   Senão: `impact_dust` (terreno) ou `impact_wood` (static) + som.
3. `HitZone.receive_hit` preenche `hit.zone` e `hit.target_id` e emite `hit_received(hit)`.
4. B (`Boar`, conectado às suas 4 `HitZone`): `final = hit.damage × zone_multipliers[zone]`; reduz vida;
   emite `GameEvents.boar_hit(id, zone, final, hit.position, hit.shot_id)`; reage (FSM); se vida ≤ 0 → morte.
5. Morte (B, `HuntController`): `one_shot` = todos os acertos recebidos por esse javali têm o mesmo
   `shot_id` (bagos do mesmo disparo contam como um tiro); `killing_zone` = zona do golpe final (`Ids.ZONE_DOG`
   se foi o cão); `reward = Profile.kill_reward(type, kg, killing_zone, one_shot, map_id, contract_index)`;
   cria `KillInfo`, adiciona ao resultado, emite `boar_killed` e `boar_counts_changed`.
6. Um javali morto ignora novos `hit_received` (as `HitZone` são desligadas com `set_deferred("monitorable", false)`
   e `collision_layer = 0`). Carcaça permanece.

Queda de dano: `d ≤ falloff_start_m` → 1; `d ≥ falloff_end_m` → `min_damage_mult`; entre → `lerp`.

`HitZone` de cada javali (criadas pelo B como filhas da raiz do `Boar`, **não** da visão):
`BoxShape3D` com centro/tamanho de `BoarVisualBase.HIT_ZONES[zone]` multiplicados por
`scale_for_weight(kg)`. Nomes dos nós: `HitHead`, `HitVital`, `HitBody`, `HitRear`. O `Boar` gira a raiz
(yaw) e a posiciona; não escala nós físicos (os tamanhos já vêm multiplicados).

### 8.3 Dano: javali → jogador e → cão
- B, na investida (`charge`): a cada frame, se a distância XZ entre focinho e jogador
  `< 0.5 + 0.6 × scale` e o jogador está no semicírculo frontal, chama **uma vez por investida**
  `player.apply_damage(charge_damage, boar.global_position, knockback_mps)` e `visual.play_attack()`.
- A (`Player.apply_damage`): `amount × (1 − damage_reduction do colete)`; empurrão horizontal na direção
  oposta à fonte; emite `player_damaged`; vida ≤ 0 → `player_died` (uma vez), input desligado, câmera cai.
- Cão: dano interno ao B (`Dog.take_damage`), nunca abaixo de 1 de vida.

### 8.4 HUD recebe estado
- Do próprio pacote A (leitura direta, todo frame): vida, munição, arma, mira/zoom, item selecionado.
- Do mundo via `HuntWorld` (polling a 10 Hz, sem alocar por frame além de um `PackedVector3Array`):
  minimapa (`get_map_rect`, `get_crop_rects`, `get_dog_position`, `get_alive_boar_ids` +
  `get_boar_position` **só** durante revelação do drone), bússola (`get_nearest_boar_position` quando o cão
  é `caramelo`, marcações do cão).
- Por eventos (§5): contagem, lavoura, aviso de lavoura, abates, hitmarker, estado/vida do cão, mensagens.
- Ao `bind`, o HUD lê o estado inicial de `world` (`get_crop_health_pct`, `get_boars_killed`,
  `get_boars_total`, `has_dog`) para não depender da ordem dos sinais.

Layout do HUD (referência 1280×720, âncoras; respeita margem de 24 px nas laterais):
topo-esquerda vida + ícone do colete + botão pausa (toque); topo-centro bússola (480 px, N/L/S/O, marcador
do cão e do javali marcado) com barra "Lavoura 87%" abaixo e aviso "Javalis na lavoura!" piscando; topo-direita
minimapa 180×180 e "Javalis 3/8"; centro mira; centro-baixo mensagem de abate ("Macho abatido — 132 kg ·
R$ 990 · Tiro limpo! · Um tiro só!", 3 s); baixo-direita munição "5 | 30" e nome da arma; anel de dano
direcional em torno do centro (1,2 s); estado do cão abaixo do minimapa.
Toque (CanvasLayer 11, visível só em modo toque): joystick à esquerda (raio 90 px, flutuante no 40%
esquerdo da tela), arrastar na metade direita para olhar (por índice de toque), botões
`TouchScreenButton` com `action` = nome da ação: Tiro (110 px, baixo-direita), Mira, Recarregar, Trocar,
Cão, Item (+ `item_next`), Agachar, Pausa. Slider vertical de zoom à direita quando mirando com
`ads_zoom_max > ads_zoom_min`. Pausa (CanvasLayer 20, `process_mode = ALWAYS`): "Retomar", "Configurações"
(instancia `ScenePaths.SETTINGS_PANEL` se existir; sinal `closed`), "Desistir da caçada".

### 8.5 Mundo exposto: estrutura obrigatória de uma cena de mapa
Caminho: `ScenePaths.map_scene(map_id)` = `res://src/world/maps/<map_id>/<map_id>_map.tscn` (B).
```
<MapId>Map (Node3D, script res://src/world/map_root.gd → MapRoot)
│   @export map_size_m: float = 256.0            mapa quadrado centrado na origem
│   @export grid_resolution: int = 129           amostras por lado (espaçamento 2 m)
│   @export terrain_seed: int = 1                ruído determinístico
│   @export height_amplitude_m: float = 6.0
│   @export base_flora: Dictionary = {}          id → instâncias espalhadas no mapa todo (antes da densidade)
├── PlayerSpawn (Marker3D)                       yaw = direção inicial do olhar
├── CropFields (Node3D) → N × CropField         retângulos XZ (size_m), crop &"soy" | &"corn"; terreno achatado
├── SpawnZones (Node3D) → Marker3D …             índice = ordem dos filhos; javalis surgem num raio de 8 m
├── RetreatZones (Node3D) → Marker3D …           refúgios na mata para onde os javalis fogem
├── Water (Node3D) → WaterBody …                 açudes: terreno rebaixado depth_m, obstáculo para steering
├── PropSpawns (Node3D) → PropSpawn …            props + colisão + obstáculo (footprint_radius_m; 0 = javali passa)
└── FloraZones (Node3D) → FloraZone …            concentrações (mata de galeria, buritizal)
```
Para adicionar um mapa: entrada em `data/maps.json` (`available: true`, contratos), esta cena e
(opcional) `assets/env/<map_id>_env.tscn`. Nenhum código novo.

**Layout de Mato Grosso** (`src/world/maps/mato_grosso/mato_grosso_map.tscn`; mapa 256 m, -128…128):
- `PlayerSpawn` (10, 0, -50), olhando para +Z (sul, para a lavoura).
- Soja: `CropField` centro (-35, 0, 15), `size_m` (90, 70). Milho: centro (55, 0, 20), `size_m` (56, 70).
- Sede: `farmhouse` (10, -85) yaw 0; `barn` (38, -88); `water_tank` (-8, -92); `feed_trough` (25, -70);
  cerca (`fence_segment`, footprint 0) em retângulo de (-20,-110) a (55,-62) com `gate` em (10, -62).
- Açude: `WaterBody` (-70, -55), raio 18, buritis ao redor (`FloraZone` raio 30: buriti 12, shrub 20).
- Mata de galeria ao sul (z 85…124) com buritis e árvores (`FloraZone`s em (-90,105), (-30,110), (30,108),
  (95,100), raio 30, cerrado_tree 25, buriti 6, ipe 3, shrub 30) e a leste (`FloraZone` (112,-40) raio 22).
- `SpawnZones`: (-95, 110), (20, 115), (105, 95), (115, -50).
- `RetreatZones`: (-80, 108), (0, 112), (90, 102), (112, -38).
- `base_flora`: grass_tuft 2500, shrub 250, cerrado_tree 90, ipe 18, termite_mound 30 (nunca dentro de
  lavoura, água ou cerca da sede).
- Estrada de terra (COLOR.g) da porteira até a lavoura.

API do mundo para todos: a de `HuntWorld` (Apêndice A). Altura: `get_height(x, z)` = interpolação
bilinear da grade 129×129 (a mesma que gera a malha). Colisão: `HeightMapShape3D` 257×257 (1 m),
reamostrada bilinearmente da grade de 2 m (sem escalar o shape), + 4 paredes de borda (layer terrain).

### 8.6 Movimento de javalis e cães (decisão)
Sem NavMesh e sem física. Justificativa: até 19 agentes em celular, terreno aberto, obstáculos poucos e
convexos; `CharacterBody3D` custaria ~19 `move_and_slide` por frame e NavMesh exigiria bake (custo de
carregamento e memória na Web) sem ganho em mapa aberto.
- Posição XZ integrada por steering (seek, flee, arrive, separação no bando 1,5 m, evitação de obstáculos
  circulares do `ObstacleGrid` com antecipação de 4 m, limite do mapa com margem 4 m); Y =
  `get_height(x, z)`; inclinação visual opcional pela normal.
- Rotação: yaw com velocidade máxima `turn_speed_deg_s`; investida trava a direção.
- Percepção escalonada: cada javali avalia visão/audição a cada `hunt.boar_perception_interval_s` (0,2 s),
  defasado pelo id; raio de linha de visão só se estiver no cone e no alcance.
- Processamento em `_process(delta)` (não física). Jogador em `_physics_process`.

### 8.7 Loadout entra, resultado sai (systems ↔ caçada)
```
Preparation (ui) → Profile.build_hunt_request(map, idx) → Router.start_hunt(request)
  → hunt.tscn: HuntController lê Router.get_pending_request()
  → … caçada … → GameEvents.hunt_ended(result) → espera hunt.end_delay_s (tempo real, tree não pausada)
  → se route_on_finish: Router.finish_hunt(result) → Profile.apply_hunt_result(result) → result.tscn
```
`build_hunt_request` só inclui itens que o jogador possui; `item_counts[id]` = `min(posse, max_per_hunt)`
para consumíveis e 1 para os demais. O B soma `consumables_used` a partir de `GameEvents.item_used`.
Prêmios de abate são exibidos na hora (HUD) e **creditados uma única vez** em `apply_hunt_result` —
inclusive em derrota/desistência (o bônus de contrato só na vitória).

### 8.8 Fim da caçada (B)
Avaliado no `_process` do `HuntController`, nesta ordem, só se `not is_hunt_over()`:
1. todos os caçadores presentes mortos (no solo: `player_died` recebido) → `DEFEAT_DEATH`. Em rede só o
   anfitrião avalia; clientes terminam por `EV_HUNT_END` ou `DISCONNECTED`;
2. `crop_health_pct <= 0` → `DEFEAT_CROP`;
3. `hunt_abandon_requested` recebido → `ABANDONED`;
4. `killed == total` → `VICTORY` (`contract_bonus = Profile.contract_bonus(...)`).
Monta `HuntResult` (`total_money = money_from_kills + contract_bonus`), emite `hunt_ended` uma vez, toca
`victory_sting`/`defeat_sting`, para a drenagem da lavoura e o input do jogador (`set_input_enabled(false)`).
`duration_s` desconta tempo pausado.

### 8.9 Comportamento dos javalis (B — regras de jogo verificáveis)
Estados (`Ids`): `wander`, `to_crop`, `eat`, `to_bait`, `alert`, `flee`, `scrape`, `charge`, `recover`,
`bayed`, `held`, `dead`. "Ferido" é um modificador (`wounded`: vida < `wounded_health_frac`), não estado.
- `wander` na mata ao nascer por 5–15 s → `to_crop` (alvo: ponto aleatório numa `CropField`, ou `to_bait` se
  houver ceva ativa a ≤ `attract_radius_m` com vaga) → `eat` (drena `crop_drain_pct_per_s ×
  contract.crop_drain_mult` por segundo; a ceva não drena lavoura e segura o javali até expirar).
- Percepção: vê o jogador se dentro de `vision_range_m` (× 0,6 agachado, × 1,3 correndo) e do cone
  `vision_fov_deg` com linha de visão; ouve passos se distância < `player.get_noise_radius()`; ouve tiro se
  distância < `noise_radius_m × hearing_mult`. Ver/ouvir passos → `alert` (`alert_time_s`, `play_alert`); se
  continuar detectando ao fim → reação. Tiro ouvido ou ser atingido → reação imediata. Alerta e reação são
  compartilhados pelo bando (líder decide o ponto de fuga).
- Reação por `aggression`: `never` → `flee`; `defend_in_herd` → `charge` uma vez se o bando tem ≥ 2 vivos e
  o jogador está a ≤ `aggro_radius_m`, senão `flee`; `provoked` → `charge` se jogador a ≤ `aggro_radius_m`
  ou se foi atingido, até `max_charges` por encontro, depois `flee`; `always` → sempre `charge`.
  Num bando atingido, membros `provoked`/`always` investem e o resto foge.
- `flee`: corre a `run_speed_mps` até a `RetreatZone` mais distante do jogador entre as 2 mais próximas;
  descansa `flee_rest_min_s`–`flee_rest_max_s`; volta a `to_crop`.
- Investida: `scrape` por `charge_telegraph_s` (0,8 s) com `play_scrape` + `boar_scrape`; trava a direção no
  jogador; `charge` em linha reta a `charge_speed_mps` até acertar, passar 4 m do ponto travado ou
  `charge_max_distance_m`; `recover` por `recover_s` (lento, vulnerável); reavalia.
- Ferido (`wounded`): velocidades × `wounded_speed_mult`, `set_wounded(true)`; leitão/fêmea feridos fogem.
- Cão: `bayed` (foxhound): para e encara o cão por `bay_duration_s`; `held` (dogo): imóvel por
  `hold_duration_s`, sofrendo `bite_dps`; alfa se solta após `alpha_break_free_s`. Javalis `provoked`/`always`
  a ≤ 2,5 m do cão causam `dog_damage_per_s`.

### 8.10 Cão (B)
Estados (`Ids`): `follow` (a `follow_distance_m` atrás do jogador), `seek` (indo ao javali vivo mais próximo
num raio `search_radius_m`), `point` (caramelo: para a 15 m do alvo, `play_point`, late, marca por
`mark_duration_s`), `bay` (foxhound), `hold` (dogo), `retreat` (vida < `retreat_health_frac`: volta ao
jogador, regenera `regen_per_s`, não obedece "Pega!" até `return_health_frac`), `return` (voltando).
`dog_command_requested`: se `follow` → `seek` + `dog_command_executed(Ids.CMD_ATTACK)` + HUD "Pega!";
caso contrário → `return` + `CMD_RECALL` + "Volta!". Caramelo também alimenta a bússola continuamente
(`get_nearest_boar_position`). O cão nunca morre.

### 8.11 Itens (A, com efeito no mundo pelo B)
| Item | Tipo | Efeito | Dono do efeito |
|---|---|---|---|
| `binoculars` | ativo | alterna visão 6x sem arma (Q); bloqueia tiro | A |
| `leather_vest` | passivo | reduz dano recebido | A |
| `medkit` | consumível | cura `heal` em `use_time_s` (sem atirar) | A; emite `item_used` |
| `corn_bait` | consumível | coloca ceva no chão à frente (2 m) | A emite `item_used`; B cria `Bait` + `bait_placed` |
| `extra_ammo` | passivo | reserva × `reserve_mult` | A |
| `thermal_scope` | passivo | ao mirar, javalis a ≤ `highlight_range_m` destacados | A emite `thermal_vision_changed`; B chama `set_highlight` |
| `scout_drone` | consumível | revela todos os javalis no minimapa por `reveal_s` | A (HUD), emite `item_used` |
`use_item` usa o item selecionado entre ativos/consumíveis equipados; `item_next` cicla.

### 8.12 Caçada em rede (B, com A e N)
Formatos de registro: `docs/multiplayer.md` §4. Offline (`Net.get_role() == Role.OFFLINE`) tudo acima vale
sem mudança. `get_player()` continua sendo "o caçador desta máquina"; a IA usa `get_hunters()`.

**Papéis na montagem.** `HuntController` continua raiz única de `hunt.tscn`; lê `Net.get_role()` uma vez
na montagem.

| Trecho | HOST | CLIENT |
|---|---|---|
| RNG | `rng_seed` de `L_START` (nunca 0) | o mesmo seed (lavoura com o mesmo jitter visual) |
| Flora | `build_flora(density, true)` | idem |
| Caçadores | `Player` local em `PlayerSpawn` deslocado `(slot − (n−1)/2) × coop.spawn_spacing_m` no eixo direito; `RemoteHunter` para cada outro slot (`AssetLoader.instantiate(ScenePaths.REMOTE_HUNTER)` + `setup_remote`) | idem |
| Cães | um `Dog` por slot com cão (`NetPeerInfo.dog_id`), `owner_slot` | `DogPuppet` criado pela réplica ao ver o cão no snapshot |
| Javalis | `spawner.setup` com contrato escalado (`BoarSpawner.scale_groups`); cria `HuntHostSync` | não chama `spawner.setup`; cria `HuntReplica` |
| Início | `Net.bind_world(self)`; espera `Net.hunt_go` com o overlay "Aguardando os outros caçadores…"; depois `spawner.begin()` e `hunt_started` | `Net.bind_world(self)` (Net envia `L_LOADED`); espera `Net.hunt_go`; `hunt_started` |
| Getters de javali (`HuntWorld`) | `spawner` | `HuntReplica` (mesmas respostas, a partir das réplicas) |
| `debug_*` | como hoje | sem efeito |

**Alvo múltiplo (anfitrião).** O javali percorre `get_hunters()` vivos e presentes (`is_alive()` e
`is_present()`), do mais próximo ao mais distante, e guarda `_target_hunter`, nunca sem validar. No máximo um
raio de visão por javali por percepção. `HitInfo.shooter_slot` define a ameaça e o `killer_slot`; abate por cão
vai para o dono do cão.

**Tiro ("favor the shooter").** A `HitZone` da réplica recebe `receive_hit` da arma como hoje. A
`HuntReplica` junta os acertos do mesmo `shot_id` e, no `shot_fired`, fecha um `C_SHOT`; o acerto já emite
`boar_hit` local (hitmarker imediato). O anfitrião valida: javali vivo; `damage ≤ weapon.damage`; `n ≤
weapon.pellets`; `dist ≤ weapon.max_range_m`; `|distância(javali no anfitrião, origem) − dist| ≤
net.hit_claim_tolerance_m`. Passou: monta `HitInfo` (`shooter_slot`, `shot_id`, `zone`, `damage`) e chama o
mesmo caminho de dano do solo. Todo `C_SHOT` chama `spawner.notify_shot`. `shot_id` carrega o slot nos 8 bits
altos (`NetCodec.make_shot_id`); quem conta "meu tiro" filtra por `NetCodec.shot_slot(shot_id) ==
world.get_local_slot()`. O `C_SHOT` de tiro que errou vai com `shot_id = NetCodec.make_shot_id(slot, 0)`. O
cliente ignora o campo `killed` do snapshot: os abates da equipe vêm de `EV_BOAR_DEATH`.

**Investida ("favor the victim").** Em `charge`, a réplica roda a geometria de acerto
(`Boar.charge_hits`) contra o `Player` local; acertou (uma vez por investida): `player.apply_damage` local,
`play_attack` e `C_CHARGE_HIT`. O anfitrião testa só caçadores `is_local()`; para os remotos espera
`C_CHARGE_HIT` e então `_enter_recover()` + `EV_BOAR_ATTACK`.

**Morte, espectador e fim.** `Player._die` não muda. Em rede, passados `coop.spectate_delay_s` e havendo
aliado vivo, o `Player` ativa `SpectatorCamera` (terceira pessoa a `coop.spectate_distance_m` atrás e
`coop.spectate_height_m` acima do aliado; `fire` troca de alvo). O controlador acompanha `is_alive()` de cada
caçador e emite `hunter_died(slot)`. Só o anfitrião decide o fim (§8.8); `_finish` enfileira `EV_HUNT_END` e
chama `Net.flush()`; o cliente, ao receber, roda o mesmo `_finish(outcome)` com a lavoura do evento. Pausa >
"Desistir": anfitrião ("Encerrar a caçada para todos") → `ABANDONED` para todos; cliente ("Sair da caçada") →
`Net.leave_room()` e resultado local `ABANDONED` com os próprios abates. Depois de `hunt.end_delay_s`, cada peer
chama `Router.finish_hunt(result)`; a sala volta a LOBBY e a tela de resultado oferece "Voltar para a sala".

**Quedas, ausências e prazos.**

| Situação | Detecção | Efeito |
|---|---|---|
| Anfitrião saiu ou caiu | `host_left` do servidor, ou `net.host_timeout_s` sem snapshot | cliente: `net_connection_lost()` → `Outcome.DISCONNECTED`; abates pagos, consumíveis descontados, sem bônus, sem progressão |
| Anfitrião congelado (aba em segundo plano) | `net.host_stall_warn_s` sem snapshot | faixa no HUD (`net_stall_changed`); réplicas param; o caçador do cliente segue jogável. Voltou antes de `host_timeout_s`: segue. Medido: após 5 s de aba congelada o delta de `_process` é ~0,07 s (não carrega o tempo perdido), então prazos usam relógio de parede; ao acordar de um congelamento da própria máquina, os relógios de silêncio são zerados |
| Cliente saiu ou caiu | `peer_left`, ou `net.peer_timeout_s` sem estado | `net_peer_left(slot)`: caçador e cão dele somem; a caçada segue; se não sobrar vivo, derrota |
| Cliente em silêncio curto | `net.peer_absent_s` | `is_present() = false`: javalis o ignoram |
| Anfitrião perdeu a rede | WebSocket e todos os enlaces caídos | `net_connection_lost()` no anfitrião: remotos saem, ele termina a caçada sozinho ("Conexão perdida: você continua sozinho.") |
| Servidor de salas indisponível durante a caçada | WebSocket fechado ou envio falhando | enlaces em RTC continuam; enlaces em relay caem (linhas acima) |
| Reconexão pelo mesmo código | — | fora da v1; sala trancada recusa `join` |
| Cliente em `LOADING` sem `L_GO` | `net.load_timeout_s` + `net.host_timeout_s` | cliente desiste (`DISCONNECTED`) |

`net_connection_lost()` vem antes de `room_error`. No cliente encerra `DISCONNECTED`; no ANFITRIÃO não encerra:
ele segue sozinho ("Conexão perdida: você continua sozinho."). Cliente removido por silêncio não é avisado:
encerra pelo próprio `host_timeout_s`. A sala destranca quando o anfitrião chama `Net.unbind_world`.
`DISCONNECTED` paga os abates, sem bônus e sem progresso; conta em `hunts_played`, não em `hunts_won`.
`hunter_died(slot)` é emitido também no solo, para o caçador local (o HUD ignora o slot local). "Todos os
caçadores presentes mortos" conta quem ainda está na caçada; quem está só em silêncio curto vale pelo último
estado. Anfitrião que desiste ("Encerrar a caçada para todos"): anfitrião `ABANDONED`, `EV_HUNT_END` +
`Net.flush()`; clientes `ABANDONED` com `counts_for_progression = false` e abates pagos. Cliente que sai:
`Net.leave_room()` + `ABANDONED` local.

**Economia.** O anfitrião calcula `Profile.kill_reward` e envia o valor em `EV_BOAR_DEATH`; cada máquina só
acrescenta a `result.kills`/`money_from_kills` os abates com `killer_slot` local. `boar_killed` é emitido para
todos os abates. Cada peer calcula `Profile.contract_bonus` com a lavoura de `EV_HUNT_END` (cheio para cada um
que estava na sala no fim). Ao montar a caçada em rede, `result.counts_for_progression =
Profile.is_contract_unlocked(map, index)`. Cada peer monta o próprio `HuntRequest` com
`Profile.build_hunt_request`; `Net` preenche `rng_seed`, `player_count`, `map_id` e `contract_index`.
`HuntResult.scoreboard`: uma entrada por slot que começou a caçada (inclusive quem saiu): `{slot, name, kills,
money, weight_kg}`; `money` = só dinheiro de abate; vazio no solo. Mensagem de abate de aliado: "<Nome> abateu um
javali: <tipo>, <kg> kg". Loadout, munição e itens nunca saem
da máquina do dono. `Router.finish_hunt` e `apply_hunt_result` continuam sendo o único ponto de crédito, uma
vez por máquina.

**Escala de javalis** (`BoarSpawner.scale_groups`, função pura): `alvo = round(total_base ×
coop.boar_count_mult_by_players[n − 1])`. Clona grupos inteiros em ordem (pulando os que têm `alpha`), cada
clone com `spawn_zone + 1 + volta` e `delay_s = maior delay do contrato + coop.extra_group_delay_s × (ordem do
clone)`; o último clone perde membros do fim (nunca o líder) para fechar no alvo. O teto
`hunt.max_alive_boars` continua valendo: grupos esperam vaga. Exemplo: primeiro contrato (índice 0, 9 javalis)
→ 14 e 23 com 2 e 4 jogadores; o maior caso atual é 63 javalis (cabem em ids de 1 byte).
Medido nas fases F4/F5: snapshot de 254 B com 26 javalis; download do cliente ~3,5–4,6 kB/s (meta 5);
anfitrião > 100 fps no desktop.

**Mundo.** Heightmap, props, água e índices dos canteiros são determinísticos entre peers. A flora não é entre
qualidades gráficas: com `sync_layout = true` o laço sorteia sempre a quantidade cheia e só guarda as primeiras
`round(count × density)` de capim/arbusto; o solo chama com `false` (layout de hoje). Lavoura no cliente: o
`CropManager` é o mesmo, sem comedores; `EV_CROP_EATEN` → `apply_eaten(indices)`; `set_replicated_health(pct)`
a cada snapshot atualiza a saúde e passa pelo mesmo `crop_health_changed` do solo.

---

## 9. Dados (`data/`)

**Formato: JSON** — escrito à mão por agente, lido por testes e por código sem depender de classes de
`Resource` nem de UIDs/`ext_resource`, diff legível; o custo (sem tipagem do editor) é coberto pela validação
do `Data` e por `unit_tests`. Todo arquivo tem `"version": 1` na raiz. Listas de definições são arrays de
objetos com `"id"` único (a ordem do arquivo é a ordem na UI). Lembre: números chegam como `float` (§6.2).

Os blocos abaixo são o **seed completo**: o coordenador os copia verbatim na Fase 0; depois o game-systems é
dono e pode rebalancear **valores** (não nomes de campos nem ids).

### 9.1 `data/game.json`
| Campo | Tipo | Unid. | Uso |
|---|---|---|---|
| `player.*` | número | m, m/s, s, graus | controlador A |
| `hunt.*` | número | s, % | B |
| `economy.start_*` | número/lista/obj | R$, ouro | perfil novo |
| `loadout.weapon_slots/item_slots` | int | — | preparação |
| `shop.max_consumable_owned` | int | — | loja |
| `coop.*` | número/lista | m, s | modo cooperativo (B, A) |
| `quality_presets.<low|medium|high>` | obj | — | B, ambiente |
```json
{
  "version": 1,
  "player": {
    "max_health": 100,
    "walk_speed_mps": 4.0,
    "sprint_speed_mps": 6.5,
    "crouch_speed_mps": 2.0,
    "aim_speed_mult": 0.6,
    "acceleration_mps2": 30.0,
    "standing_eye_height_m": 1.65,
    "crouch_eye_height_m": 1.05,
    "capsule_radius_m": 0.35,
    "capsule_height_m": 1.8,
    "crouch_capsule_height_m": 1.2,
    "crouch_transition_s": 0.2,
    "noise_radius_walk_m": 8.0,
    "noise_radius_sprint_m": 22.0,
    "noise_radius_crouch_m": 0.0,
    "knockback_mps": 6.0,
    "base_fov_deg": 75.0,
    "max_pitch_deg": 85.0,
    "mouse_deg_per_px": 0.12,
    "touch_deg_per_px": 0.25,
    "damage_indicator_s": 1.2,
    "low_health_frac": 0.3
  },
  "hunt": {
    "end_delay_s": 2.5,
    "crop_health_signal_step_pct": 0.5,
    "max_alive_boars": 26,
    "kill_message_s": 3.0,
    "boar_perception_interval_s": 0.2,
    "spawn_radius_m": 8.0,
    "wander_before_crop_min_s": 5.0,
    "wander_before_crop_max_s": 15.0
  },
  "economy": {
    "start_money": 500,
    "start_gold": 0,
    "start_weapons": ["carbine_22"],
    "start_items": {"medkit": 1, "scout_drone": 3}
  },
  "loadout": {"weapon_slots": 2, "item_slots": 3},
  "shop": {"max_consumable_owned": 9},
  "coop": {
    "boar_count_mult_by_players": [1.0, 1.5, 2.0, 2.5],
    "extra_group_delay_s": 20.0,
    "spawn_spacing_m": 2.0,
    "spectate_delay_s": 2.0,
    "spectate_distance_m": 3.5,
    "spectate_height_m": 2.0,
    "name_tag_max_m": 120.0
  },
  "quality_presets": {
    "low":    {"shadows": false, "shadow_distance_m": 0,  "flora_density": 0.5,  "render_scale": 0.75, "view_distance_m": 160},
    "medium": {"shadows": true,  "shadow_distance_m": 30, "flora_density": 0.75, "render_scale": 0.9,  "view_distance_m": 220},
    "high":   {"shadows": true,  "shadow_distance_m": 45, "flora_density": 1.0,  "render_scale": 1.0,  "view_distance_m": 300}
  }
}
```
`coop.*` (B, A, `Net`): `boar_count_mult_by_players` é indexado por `player_count − 1`; os demais campos estão
em §8.12.

### 9.2 `data/weapons.json`
| Campo | Tipo | Unid. | Significado |
|---|---|---|---|
| `id`, `name`, `description` | string | — | id = nome do asset `<id>_view.tscn` |
| `price` / `currency` | int / `"money"`\|`"gold"` | R$ ou ouro | 0 = inicial |
| `damage` | float | pontos | por bala/bago antes de zona |
| `pellets` | int | — | bagos por disparo |
| `falloff_start_m`, `falloff_end_m`, `min_damage_mult` | float | m, fração | queda de dano |
| `max_range_m` | float | m | comprimento do raio |
| `fire_interval_s` | float | s | intervalo mínimo entre disparos (inclui ciclo) |
| `cycle_s` | float | s | animação de ferrolho/bomba (0 = semi) |
| `cycle_sfx` | string | — | id Sfx do ciclo ou `""` |
| `mag_size`, `reserve_ammo` | int | — | munição por caçada |
| `reload_s` | float | s | recarga completa |
| `hip_spread_deg`, `ads_spread_deg`, `move_spread_add_deg` | float | graus | cone de dispersão (meio-ângulo) |
| `ads_time_s` | float | s | entrar na mira |
| `ads_zoom_min`, `ads_zoom_max` | float | x | zoom ajustável pela roda/slider; FOV = 2·atan(tan(base/2)/zoom) |
| `scoped` | bool | — | luneta (esconde arma e mostra overlay) |
| `reticle_kind` | int | — | uniform do overlay |
| `recoil_pitch_deg`, `recoil_recover_s` | float | graus, s | coice da câmera |
| `noise_radius_m` | float | m | raio em que javalis ouvem o tiro |
| `shot_sfx` | string | — | id Sfx |
```json
{
  "version": 1,
  "weapons": [
    {"id": "carbine_22", "name": "Carabina .22", "description": "Leve e silenciosa. Boa para leitões e fêmeas de perto.",
     "price": 0, "currency": "money", "damage": 38.0, "pellets": 1,
     "falloff_start_m": 40.0, "falloff_end_m": 120.0, "min_damage_mult": 0.4, "max_range_m": 160.0,
     "fire_interval_s": 0.35, "cycle_s": 0.0, "cycle_sfx": "", "mag_size": 10, "reserve_ammo": 50, "reload_s": 1.8,
     "hip_spread_deg": 2.0, "ads_spread_deg": 0.3, "move_spread_add_deg": 1.5, "ads_time_s": 0.18,
     "ads_zoom_min": 1.5, "ads_zoom_max": 1.5, "scoped": false, "reticle_kind": 0,
     "recoil_pitch_deg": 1.0, "recoil_recover_s": 0.15, "noise_radius_m": 60.0, "shot_sfx": "shot_22"},
    {"id": "shotgun_12", "name": "Espingarda calibre 12", "description": "Nove bagos por tiro. Devastadora de perto, inútil de longe.",
     "price": 1800, "currency": "money", "damage": 16.0, "pellets": 9,
     "falloff_start_m": 8.0, "falloff_end_m": 35.0, "min_damage_mult": 0.1, "max_range_m": 60.0,
     "fire_interval_s": 0.9, "cycle_s": 0.55, "cycle_sfx": "pump_cycle", "mag_size": 5, "reserve_ammo": 30, "reload_s": 3.0,
     "hip_spread_deg": 6.0, "ads_spread_deg": 4.5, "move_spread_add_deg": 1.0, "ads_time_s": 0.2,
     "ads_zoom_min": 1.2, "ads_zoom_max": 1.2, "scoped": false, "reticle_kind": 0,
     "recoil_pitch_deg": 5.0, "recoil_recover_s": 0.3, "noise_radius_m": 110.0, "shot_sfx": "shot_12"},
    {"id": "rifle_308", "name": "Rifle .308 com luneta 4x", "description": "Ferrolho preciso. Derruba fêmeas e machos a distância.",
     "price": 4500, "currency": "money", "damage": 110.0, "pellets": 1,
     "falloff_start_m": 120.0, "falloff_end_m": 300.0, "min_damage_mult": 0.6, "max_range_m": 360.0,
     "fire_interval_s": 1.2, "cycle_s": 0.8, "cycle_sfx": "bolt_cycle", "mag_size": 5, "reserve_ammo": 30, "reload_s": 2.5,
     "hip_spread_deg": 3.0, "ads_spread_deg": 0.1, "move_spread_add_deg": 2.5, "ads_time_s": 0.3,
     "ads_zoom_min": 2.0, "ads_zoom_max": 4.0, "scoped": true, "reticle_kind": 0,
     "recoil_pitch_deg": 4.0, "recoil_recover_s": 0.35, "noise_radius_m": 140.0, "shot_sfx": "shot_308"},
    {"id": "rifle_3006", "name": "Rifle .30-06 semiautomático", "description": "Tiros rápidos para segurar o bando inteiro.",
     "price": 9500, "currency": "money", "damage": 115.0, "pellets": 1,
     "falloff_start_m": 120.0, "falloff_end_m": 300.0, "min_damage_mult": 0.6, "max_range_m": 360.0,
     "fire_interval_s": 0.45, "cycle_s": 0.0, "cycle_sfx": "", "mag_size": 5, "reserve_ammo": 40, "reload_s": 2.6,
     "hip_spread_deg": 3.0, "ads_spread_deg": 0.2, "move_spread_add_deg": 2.5, "ads_time_s": 0.3,
     "ads_zoom_min": 2.0, "ads_zoom_max": 4.0, "scoped": true, "reticle_kind": 0,
     "recoil_pitch_deg": 3.5, "recoil_recover_s": 0.25, "noise_radius_m": 150.0, "shot_sfx": "shot_3006"},
    {"id": "rifle_338", "name": "Rifle .338 com luneta 8x", "description": "Arma de elite para o cachaço. Item de ouro.",
     "price": 300, "currency": "gold", "damage": 180.0, "pellets": 1,
     "falloff_start_m": 200.0, "falloff_end_m": 400.0, "min_damage_mult": 0.7, "max_range_m": 400.0,
     "fire_interval_s": 1.4, "cycle_s": 0.9, "cycle_sfx": "bolt_cycle", "mag_size": 5, "reserve_ammo": 25, "reload_s": 2.8,
     "hip_spread_deg": 3.5, "ads_spread_deg": 0.05, "move_spread_add_deg": 3.0, "ads_time_s": 0.35,
     "ads_zoom_min": 3.0, "ads_zoom_max": 8.0, "scoped": true, "reticle_kind": 1,
     "recoil_pitch_deg": 5.5, "recoil_recover_s": 0.4, "noise_radius_m": 160.0, "shot_sfx": "shot_338"}
  ]
}
```

### 9.3 `data/equipment.json`
| Campo | Tipo | Significado |
|---|---|---|
| `id`, `name`, `description` | string | |
| `kind` | `"passive"` \| `"active"` \| `"consumable"` | passivo/ativo: compra única; consumível: acumula |
| `price`, `currency` | int, string | preço unitário |
| `max_per_hunt` | int | consumíveis levados por caçada |
| `effect` | objeto | parâmetros específicos (unidades no nome do campo) |
```json
{
  "version": 1,
  "items": [
    {"id": "binoculars", "name": "Binóculo", "description": "Zoom de 6x para achar o bando sem espantá-lo.",
     "kind": "active", "price": 600, "currency": "money", "max_per_hunt": 1, "effect": {"zoom": 6.0}},
    {"id": "leather_vest", "name": "Colete de couro", "description": "Reduz o dano das presas em 35%.",
     "kind": "passive", "price": 2500, "currency": "money", "max_per_hunt": 1, "effect": {"damage_reduction": 0.35}},
    {"id": "medkit", "name": "Kit de primeiros socorros", "description": "Recupera 50 de vida. Consumível.",
     "kind": "consumable", "price": 300, "currency": "money", "max_per_hunt": 3, "effect": {"heal": 50.0, "use_time_s": 1.5}},
    {"id": "corn_bait", "name": "Ceva de milho", "description": "Atrai javalis próximos por 45 s, longe da lavoura. Consumível.",
     "kind": "consumable", "price": 400, "currency": "money", "max_per_hunt": 2,
     "effect": {"duration_s": 45.0, "attract_radius_m": 80.0, "max_boars": 4}},
    {"id": "extra_ammo", "name": "Munição extra", "description": "Dobra a munição de reserva de todas as armas.",
     "kind": "passive", "price": 800, "currency": "money", "max_per_hunt": 1, "effect": {"reserve_mult": 2.0}},
    {"id": "thermal_scope", "name": "Mira térmica", "description": "Ao mirar, destaca javalis até 150 m.",
     "kind": "passive", "price": 150, "currency": "gold", "max_per_hunt": 1, "effect": {"highlight_range_m": 150.0}},
    {"id": "scout_drone", "name": "Drone batedor", "description": "Revela todos os javalis no minimapa por 10 s. Consumível.",
     "kind": "consumable", "price": 400, "currency": "money", "max_per_hunt": 3, "effect": {"reveal_s": 10.0}}
  ]
}
```

### 9.4 `data/dogs.json`
| Campo | Tipo | Unid. | Significado |
|---|---|---|---|
| `ability` | `"point"`\|`"bay"`\|`"hold"` | — | caramelo / foxhound / dogo |
| `max_health`, `regen_per_s` | float | pontos | |
| `follow_speed_mps`, `run_speed_mps`, `follow_distance_m`, `search_radius_m` | float | m, m/s | |
| `mark_duration_s`, `bay_duration_s`, `hold_duration_s`, `alpha_break_free_s` | float | s | 0 = não se aplica |
| `bite_dps` | float | dano/s | só `hold` |
| `retreat_health_frac`, `return_health_frac` | float | fração | |
```json
{
  "version": 1,
  "dogs": [
    {"id": "caramelo", "name": "Vira-lata Caramelo", "description": "Fareja e aponta o javali mais próximo. Late para marcar.",
     "price": 1500, "currency": "money", "ability": "point", "max_health": 100.0, "regen_per_s": 5.0,
     "follow_speed_mps": 5.5, "run_speed_mps": 8.5, "follow_distance_m": 3.0, "search_radius_m": 120.0,
     "mark_duration_s": 6.0, "bay_duration_s": 0.0, "hold_duration_s": 0.0, "alpha_break_free_s": 0.0, "bite_dps": 0.0,
     "retreat_health_frac": 0.3, "return_health_frac": 0.7},
    {"id": "foxhound", "name": "Foxhound Americano", "description": "Rastreador veloz: persegue e acua o javali, latindo.",
     "price": 6000, "currency": "money", "ability": "bay", "max_health": 120.0, "regen_per_s": 5.0,
     "follow_speed_mps": 6.0, "run_speed_mps": 10.5, "follow_distance_m": 3.0, "search_radius_m": 150.0,
     "mark_duration_s": 8.0, "bay_duration_s": 8.0, "hold_duration_s": 0.0, "alpha_break_free_s": 4.0, "bite_dps": 0.0,
     "retreat_health_frac": 0.3, "return_health_frac": 0.7},
    {"id": "dogo", "name": "Dogo Argentino", "description": "Cão de agarre: segura o javali no lugar e morde. Item de ouro.",
     "price": 400, "currency": "gold", "ability": "hold", "max_health": 180.0, "regen_per_s": 6.0,
     "follow_speed_mps": 5.5, "run_speed_mps": 9.0, "follow_distance_m": 3.0, "search_radius_m": 100.0,
     "mark_duration_s": 6.0, "bay_duration_s": 0.0, "hold_duration_s": 6.0, "alpha_break_free_s": 2.5, "bite_dps": 10.0,
     "retreat_health_frac": 0.3, "return_health_frac": 0.7}
  ]
}
```

### 9.5 `data/boars.json`
Regras globais + tipos. Vida = `weight_kg × health_per_kg`. Escala visual = `BoarVisualBase.scale_for_weight`.
Peso sorteado: `lerp(min, max, (randf() + randf()) / 2)` (tende ao meio).
| Campo do tipo | Tipo | Unid. |
|---|---|---|
| `weight_min_kg`, `weight_max_kg`, `health_per_kg`, `value_per_kg` | float | kg, pontos/kg, R$/kg |
| `walk_speed_mps`, `run_speed_mps`, `charge_speed_mps`, `turn_speed_deg_s` | float | |
| `aggression` | `"never"`\|`"defend_in_herd"`\|`"provoked"`\|`"always"` | |
| `aggro_radius_m`, `max_charges`, `charge_damage`, `charge_telegraph_s`, `charge_max_distance_m`, `recover_s` | float/int | |
| `vision_range_m`, `vision_fov_deg`, `hearing_mult`, `alert_time_s` | float | |
| `crop_drain_pct_per_s` | float | % da lavoura por segundo comendo |
| `wounded_health_frac`, `wounded_speed_mult`, `flee_rest_min_s`, `flee_rest_max_s`, `dog_damage_per_s` | float | |
```json
{
  "version": 1,
  "zone_multipliers": {"head": 2.5, "vital": 2.0, "body": 1.0, "rear": 0.6},
  "reward": {"clean_zones": ["head", "vital"], "clean_kill_mult": 1.25, "one_shot_mult": 1.5},
  "types": [
    {"id": "piglet", "name": "Leitão", "weight_min_kg": 25.0, "weight_max_kg": 45.0, "health_per_kg": 1.2, "value_per_kg": 5.0,
     "walk_speed_mps": 1.4, "run_speed_mps": 7.0, "charge_speed_mps": 0.0, "turn_speed_deg_s": 260.0,
     "aggression": "never", "aggro_radius_m": 0.0, "max_charges": 0, "charge_damage": 0.0, "charge_telegraph_s": 0.8,
     "charge_max_distance_m": 0.0, "recover_s": 0.0,
     "vision_range_m": 35.0, "vision_fov_deg": 120.0, "hearing_mult": 1.0, "alert_time_s": 1.0,
     "crop_drain_pct_per_s": 0.10, "wounded_health_frac": 0.35, "wounded_speed_mult": 0.6,
     "flee_rest_min_s": 20.0, "flee_rest_max_s": 35.0, "dog_damage_per_s": 0.0},
    {"id": "sow", "name": "Fêmea", "weight_min_kg": 60.0, "weight_max_kg": 110.0, "health_per_kg": 1.2, "value_per_kg": 5.0,
     "walk_speed_mps": 1.4, "run_speed_mps": 7.5, "charge_speed_mps": 9.0, "turn_speed_deg_s": 220.0,
     "aggression": "defend_in_herd", "aggro_radius_m": 6.0, "max_charges": 1, "charge_damage": 15.0, "charge_telegraph_s": 0.8,
     "charge_max_distance_m": 20.0, "recover_s": 1.2,
     "vision_range_m": 40.0, "vision_fov_deg": 120.0, "hearing_mult": 1.0, "alert_time_s": 1.2,
     "crop_drain_pct_per_s": 0.15, "wounded_health_frac": 0.35, "wounded_speed_mult": 0.6,
     "flee_rest_min_s": 20.0, "flee_rest_max_s": 35.0, "dog_damage_per_s": 8.0},
    {"id": "boar", "name": "Macho", "weight_min_kg": 90.0, "weight_max_kg": 160.0, "health_per_kg": 1.4, "value_per_kg": 6.0,
     "walk_speed_mps": 1.5, "run_speed_mps": 8.0, "charge_speed_mps": 10.0, "turn_speed_deg_s": 200.0,
     "aggression": "provoked", "aggro_radius_m": 12.0, "max_charges": 3, "charge_damage": 25.0, "charge_telegraph_s": 0.8,
     "charge_max_distance_m": 25.0, "recover_s": 1.5,
     "vision_range_m": 40.0, "vision_fov_deg": 120.0, "hearing_mult": 1.0, "alert_time_s": 1.2,
     "crop_drain_pct_per_s": 0.18, "wounded_health_frac": 0.35, "wounded_speed_mult": 0.75,
     "flee_rest_min_s": 20.0, "flee_rest_max_s": 30.0, "dog_damage_per_s": 15.0},
    {"id": "alpha", "name": "Cachaço alfa", "weight_min_kg": 180.0, "weight_max_kg": 260.0, "health_per_kg": 2.2, "value_per_kg": 8.0,
     "walk_speed_mps": 1.5, "run_speed_mps": 7.5, "charge_speed_mps": 11.0, "turn_speed_deg_s": 180.0,
     "aggression": "always", "aggro_radius_m": 25.0, "max_charges": 99, "charge_damage": 40.0, "charge_telegraph_s": 0.8,
     "charge_max_distance_m": 30.0, "recover_s": 1.8,
     "vision_range_m": 45.0, "vision_fov_deg": 140.0, "hearing_mult": 1.2, "alert_time_s": 0.8,
     "crop_drain_pct_per_s": 0.25, "wounded_health_frac": 0.25, "wounded_speed_mult": 0.85,
     "flee_rest_min_s": 15.0, "flee_rest_max_s": 25.0, "dog_damage_per_s": 25.0}
  ]
}
```

### 9.6 `data/maps.json` — mapas e contratos
Contrato: `name`, `description`, `reward_mult` (multiplica prêmio de abate), `bonus_money` (R$ na vitória ×
lavoura%/100), `crop_drain_mult`, `groups`. Grupo: `members` (ids de tipo; o **primeiro é o líder**; 1 membro =
solitário; bando = 3–6), `spawn_zone` (índice em `SpawnZones`, módulo da contagem), `delay_s`. Soma de
membros ≤ `hunt.max_alive_boars`.
```json
{
  "version": 1,
  "maps": [
    {"id": "mato_grosso", "name": "Mato Grosso", "region": "MT", "available": true,
     "description": "Fazenda de soja e milho na borda do cerrado. Terra vermelha, buritis e ipês.",
     "contracts": [
       {"name": "Primeira ronda", "description": "Uma vara pequena anda fuçando a soja.",
        "reward_mult": 1.0, "bonus_money": 800, "crop_drain_mult": 1.0,
        "groups": [
          {"members": ["sow", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0},
          {"members": ["sow"], "spawn_zone": 2, "delay_s": 20.0}]},
       {"name": "Vara na soja", "description": "Duas varas e um macho solitário.",
        "reward_mult": 1.1, "bonus_money": 1500, "crop_drain_mult": 1.1,
        "groups": [
          {"members": ["sow", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0},
          {"members": ["sow", "sow", "piglet", "piglet"], "spawn_zone": 1, "delay_s": 15.0},
          {"members": ["boar"], "spawn_zone": 2, "delay_s": 40.0}]},
       {"name": "O macho do milharal", "description": "Um macho lidera a vara. Cuidado com a investida.",
        "reward_mult": 1.2, "bonus_money": 2500, "crop_drain_mult": 1.2,
        "groups": [
          {"members": ["boar", "sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0},
          {"members": ["sow", "piglet", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 20.0},
          {"members": ["boar"], "spawn_zone": 3, "delay_s": 45.0}]},
       {"name": "Lavoura cercada", "description": "Varas chegando por todos os lados.",
        "reward_mult": 1.35, "bonus_money": 4000, "crop_drain_mult": 1.3,
        "groups": [
          {"members": ["boar", "sow", "sow", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0},
          {"members": ["sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 1, "delay_s": 10.0},
          {"members": ["boar", "sow", "piglet", "piglet"], "spawn_zone": 3, "delay_s": 30.0},
          {"members": ["boar"], "spawn_zone": 2, "delay_s": 50.0}]},
       {"name": "O Cachaço", "description": "O cachaço alfa comanda a maior vara da região.",
        "reward_mult": 1.5, "bonus_money": 7000, "crop_drain_mult": 1.4,
        "groups": [
          {"members": ["alpha", "boar", "sow", "sow", "piglet", "piglet"], "spawn_zone": 1, "delay_s": 0.0},
          {"members": ["sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 10.0},
          {"members": ["boar", "sow", "sow", "piglet", "piglet"], "spawn_zone": 3, "delay_s": 25.0},
          {"members": ["boar"], "spawn_zone": 2, "delay_s": 45.0}]}
     ]},
    {"id": "pantanal", "name": "Pantanal", "region": "MS", "available": false,
     "description": "Em breve: campos alagados e cordilheiras de mata.", "contracts": []},
    {"id": "campanha_gaucha", "name": "Campanha Gaúcha", "region": "RS", "available": false,
     "description": "Em breve: coxilhas, arroz e lavouras de inverno.", "contracts": []},
    {"id": "triangulo_mineiro", "name": "Triângulo Mineiro", "region": "MG", "available": false,
     "description": "Em breve: cana, café e veredas.", "contracts": []}
  ]
}
```
Totais: 5, 8, 11, 15, 17 javalis.

**Fórmulas (RewardCalculator):**
```
clean    = killing_zone in rules.reward.clean_zones
kill     = round(weight_kg × type.value_per_kg × (clean ? clean_kill_mult : 1) × (one_shot ? one_shot_mult : 1) × contract.reward_mult)
bonus    = round(contract.bonus_money × clamp(crop_health_pct, 0, 100) / 100)      # só na vitória
```
Exemplo: macho de 132 kg, tiro limpo nos vitais, um tiro só, contrato 3 →
`round(132 × 6 × 1.25 × 1.5 × 1.2)` = **R$ 1782**.
Economia esperada: contrato 1 rende ≈ R$ 1.500–2.300 (compra a espingarda); contratos 2–3 levam ao .308;
4–5 ao .30-06.

### 9.7 `data/gold_packages.json`
```json
{
  "version": 1,
  "packages": [
    {"id": "gold_50",  "name": "Punhado de ouro", "price_brl": 5.0,  "gold": 50},
    {"id": "gold_110", "name": "Bolsa de ouro",   "price_brl": 10.0, "gold": 110},
    {"id": "gold_300", "name": "Saco de ouro",    "price_brl": 25.0, "gold": 300},
    {"id": "gold_650", "name": "Baú de ouro",     "price_brl": 50.0, "gold": 650}
  ]
}
```

### 9.8 `data/pix_config.json` e fluxo Pix
```json
{
  "version": 1,
  "gateway": "offline",
  "pix_key": "SUA-CHAVE-PIX-AQUI",
  "merchant_name": "CACADA AO JAVALI",
  "merchant_city": "CUIABA",
  "description": "Apoio Cacada ao Javali",
  "txid": "***",
  "redeem_secret": "TROQUE-ESTE-SEGREDO-ANTES-DE-PUBLICAR",
  "support_text": "Depois de doar, envie o comprovante para receber seu código de resgate."
}
```
**BR Code estático (EMV) — `PixBrCode.build`.** Campos `ID + LEN(2 dígitos decimais) + VALOR`, só ASCII:
```
00 02 01                                   Payload Format Indicator
26 LL  00 14 br.gov.bcb.pix                Merchant Account Info (GUI)
       01 LL <pix_key>
       02 LL <description>                 (omitir se vazio; total do campo 26 ≤ 99)
52 04 0000                                 Merchant Category Code
53 03 986                                  BRL
54 LL <valor com ponto e 2 casas, ex. 5.00>
58 02 BR
59 LL <merchant_name sanitizado, ≤ 25>     sem acentos, MAIÚSCULAS
60 LL <merchant_city sanitizado, ≤ 15>
62 LL  05 LL <txid>                        "***" para estático
63 04 <CRC>                                CRC16/CCITT-FALSE (poly 0x1021, init 0xFFFF, sem reflexão, sem xorout)
                                           calculado sobre a string inteira incluindo "6304"; 4 hex MAIÚSCULOS
```
Vetor de teste obrigatório: `crc16_ccitt("123456789") == 0x29B1`.

**Interface trocável.** A UI (`src/ui/donate/`) só conhece `DonationService`. `DonationService` usa um
`PixGateway` criado por `PixGateway.create_from_config(Data.get_pix_config())`: `"offline"` →
`OfflineRedeemGateway`. Um backend real (ex.: `HttpPspGateway`, que consulta um servidor alimentado por
webhook do PSP) é outra subclasse com o mesmo sinal `redeem_completed`, selecionada por `"gateway"` — a UI
não muda. `request_redeem` é assíncrono por contrato (a versão offline emite com `call_deferred`).

**Código de resgate offline — `RedeemCode`.** Formato `JV-<OURO 4 dígitos>-<NONCE 6 [A-Z0-9]>-<CHK 4 hex>`,
ex. `JV-0050-K7Q2MZ-1F3A`. `CHK` = 4 primeiros caracteres em maiúsculas de
`(secret + "|" + ouro_4_dígitos + "|" + nonce).sha256_text()`. `normalize` remove espaços e põe em
maiúsculas. `parse` devolve o ouro se o formato e o CHK conferem e o ouro é o de algum pacote; senão -1.
`DonationService.redeem`: normaliza → já usado (`Profile.is_code_redeemed`) → "Este código já foi usado."
→ gateway → ok: `Profile.add_gold`, `Profile.mark_code_redeemed`, `Profile.save()`, mensagem
"Obrigado! +N de ouro." / falha: "Código inválido. Confira e tente de novo."
O desenvolvedor gera códigos com `RedeemCode.generate` (ex.: uma cena de ferramenta fora do export).

> **AVISO — a validação offline NÃO é segura contra fraude.** O segredo está no pacote do jogo (qualquer um
> pode extraí-lo do `.pck`/JS e gerar códigos), o controle de "código já usado" vive só no save local (que o
> jogador pode apagar ou editar), e o próprio saldo de ouro é um número em JSON no navegador. Isso serve para
> agradecer doações de boa-fé, não para proteger receita. A tela de doação deve dizer que é uma **doação**
> (sem garantia de entrega automática) e não pode afirmar que o pagamento foi verificado.
> Segurança real exige um backend (webhook do PSP + códigos emitidos e invalidados no servidor), plugado
> como nova subclasse de `PixGateway`.

### 9.9 `data/net.json`
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
enquanto está em relay (uma mensagem por tick por direção). Só em página servida de `localhost`/`127.0.0.1`
valem as sobreposições por URL para teste: `?server=ws://127.0.0.1:PORT/ws`, `?relay_only=1` (não tenta
WebRTC), `?drop_ice=1` (não envia candidatos: força o estouro de `ice_timeout_s`). Em nativo: `-- --server=…`.
Dono: game-systems; leitor: `Net` (e `HuntHostSync`/`HuntReplica` para `hit_claim_tolerance_m` e as demoras
de interpolação). Protocolo e limites do servidor: `docs/multiplayer.md` §4 e §5.

---

## 10. Save

- Caminho `user://save.json` (Web: IndexedDB). Backup `user://save.bak.json`.
- Escrita (`SaveService.write`): serializa com `JSON.stringify(data, "\t")`; se `save.json` existe e é JSON
  válido, copia para `save.bak.json`; grava `save.json`; relê e confere o parse. Retorna `false` em qualquer
  falha (sem crash).
- Leitura (`Profile.load_or_create`): `save.json` → se ausente/inválido, `save.bak.json` → se inválido,
  `SaveService.new_save()`. Depois `migrate` (cadeia `version n → n+1`; versão maior que a suportada: usa
  como está, ignorando campos desconhecidos) e `sanitize` (todo campo com tipo errado/ausente recebe o default;
  números negativos viram 0; ids desconhecidos em listas são descartados; loadout inválido é corrigido para
  `carbine_22`). Se usou backup ou novo por corrupção, `push_warning` e salva imediatamente.
- Quando salvar: compra, alteração de loadout, `apply_hunt_result`, resgate de ouro, `set_setting`,
  `reset_progress`. Não salvar por frame.

Migração 1 → 2: o drone batedor virou item básico; todo save v1 recebe uma vez `economy.start_items.scout_drone`
unidades somadas ao que já tinha (se `inventory.items` for um objeto) e o drone entra no loadout se houver slot
livre. Sem `inventory.items` válido a migração não cria nada e o `sanitize` aplica `start_items`. A versão
gravada passa a 2, então a concessão não se repete; `Profile.load_or_create` grava o save migrado na hora.

Esquema (versão 2):
```json
{
  "format": "cacada-ao-javali-save",
  "version": 2,
  "saved_at_unix": 1762790000,
  "wallet": {"money": 500, "gold": 0},
  "inventory": {
    "weapons": ["carbine_22"],
    "dogs": [],
    "items": {"medkit": 1, "scout_drone": 3}
  },
  "loadout": {"weapons": ["carbine_22", ""], "dog": "", "items": ["medkit", "scout_drone"]},
  "progression": {
    "mato_grosso": {"unlocked": 1, "best_crop_pct": [-1.0, -1.0, -1.0, -1.0, -1.0]}
  },
  "stats": {"hunts_played": 0, "hunts_won": 0, "boars_killed": 0, "heaviest_kg": 0.0, "money_earned_total": 0},
  "redeemed_codes": [],
  "settings": {
    "mouse_sensitivity": 1.0,
    "touch_sensitivity": 1.0,
    "invert_y": false,
    "volume_master": 1.0,
    "volume_sfx": 1.0,
    "volume_ambience": 0.7,
    "quality": "auto",
    "touch_controls": "auto",
    "show_fps": false,
    "player_name": ""
  }
}
```
`best_crop_pct[i] = -1` = nunca vencido; `is_contract_completed` = `>= 0`. `items` guarda quantidade de
consumíveis e `1` para passivos/ativos possuídos. Settings: `mouse_sensitivity`/`touch_sensitivity` 0,1–3,0
(multiplicam `player.mouse_deg_per_px`/`touch_deg_per_px`); volumes 0–1; `quality` ∈ `auto|low|medium|high`;
`touch_controls` ∈ `auto|on|off`; `player_name` String (até `net.name_max_chars`, sem caracteres de controle;
vazio aparece como "Caçador N", N = slot + 1). A versão do save continua 2: save antigo ganha
`player_name = ""` pelo `sanitize`. Nada de sala, código ou resultado pendente é gravado.

---

## 11. Fluxo de cenas

Cena principal: `res://src/ui/boot/boot.tscn`. Troca **sempre** por `Router.goto(path)` (usa
`change_scene_to_file` deferred, despausa a árvore, chama `InputSetup.release_all_actions()`). Ninguém chama
`change_scene_to_*` diretamente.

| Cena (`ScenePaths`) | Arquivo | Dono | Botões (nós com nome único `%`) → destino |
|---|---|---|---|
| `BOOT` | `src/ui/boot/boot.tscn` | systems | `%StartButton` (tela cheia, "Toque para começar"): `Sfx.unlock_audio()`, tela cheia em toque, → `MAIN_MENU` |
| `MAIN_MENU` | `src/ui/main_menu/main_menu.tscn` | systems | `%PlayButton` → `MAP_SELECT`; `%FriendsButton` ("Jogar com amigos (beta)"; sempre visível desde a F6) → `LOBBY`; `%ShopButton` → `SHOP`; `%DonateButton` → `DONATE`; `%SettingsButton` → `SETTINGS`; mostra `%MoneyLabel`, `%GoldLabel` |
| `MAP_SELECT` | `src/ui/map_select/map_select.tscn` | systems | botões gerados `Map_<map_id>` (indisponível: desabilitado, "Em breve") → seta `Router.selected_map_id` → `PREPARATION`; `%BackButton` |
| `PREPARATION` | `src/ui/preparation/preparation.tscn` | systems | `Contract_<index>` (0-based; trancado = desabilitado), `%WeaponSlot0`, `%WeaponSlot1`, `%DogOption` (OptionButton), `Item_<id>` (CheckButton), `%StartHuntButton` → `Router.start_hunt(Profile.build_hunt_request(...))`; `%ShopButton`; `%BackButton` → `MAP_SELECT` |
| `HUNT` | `src/hunt/hunt.tscn` | B | — |
| `RESULT` | `src/ui/result/result.tscn` | systems | lê `Router.last_result`: resultado, lista de abates (tipo, kg, R$), bônus, total, lavoura %. `%ContinueButton` → `SHOP` (em sala: `LOBBY`); `%RetryButton` → `PREPARATION`; `%MenuButton` → `MAIN_MENU` |
| `SHOP` | `src/ui/shop/shop.tscn` | systems | abas Armas/Equipamentos/Cães; `Buy_<id>`; `%NextHuntButton` → `PREPARATION`; `%BackButton` → `MAIN_MENU` |
| `DONATE` | `src/ui/donate/donate.tscn` | systems | `Package_<id>`, `%PixCodeText` (LineEdit só leitura), `%CopyButton` (`DisplayServer.clipboard_set`), `%RedeemCodeEdit`, `%RedeemButton`, `%RedeemStatusLabel`, `%BackButton` → `MAIN_MENU` |
| `SETTINGS` | `src/ui/settings/settings.tscn` | systems | contém `settings_panel.tscn`; `%BackButton` → `MAIN_MENU` |
| `SETTINGS_PANEL` | `src/ui/settings/settings_panel.tscn` | systems | raiz `Control` com `signal closed`; `%CloseButton` emite `closed`; reutilizado na pausa |
| `LOBBY` | `src/ui/lobby/lobby.tscn` | systems | estados Entrada / Conectando / Sala (abaixo); sai por `%BackButton` → `MAIN_MENU` e `%LeaveButton` (ambos chamam `Net.leave_room()`) |

`LOBBY` (nós; `%` = nome único):

| Estado do lobby | Nós |
|---|---|
| Entrada | `%NameEdit` (grava `player_name`), `%CreateRoomButton`, `%CodeEdit` (5 caracteres, maiúsculas), `%JoinButton`, `%BackButton` → `MAIN_MENU`; `%StatusLabel` mostra o erro |
| Conectando | `%StatusLabel`, `%CancelButton` (sempre habilitado) |
| Sala | `%MessageLabel`, `%RoomCodeLabel`, `%RoomLinkLabel`, `%CopyLinkButton` (Web: copia `Net.get_room_link()` e mostra "Link copiado!" por `Lobby.COPIED_FEEDBACK_S`; fora do Web copia o código), `Slot_N/{Swatch, Info/Name, Info/Detail, Role}` (Detail = arma e "direto"/"via servidor"), `%MapOption` e `Contract_<index>` (só anfitrião; só contratos desbloqueados dele), `%ContractLabel`, `%HintLabel`, `LoadoutPanel` (`%WeaponSlot0`, `%WeaponSlot1`, `%DogOption`, `Item_<id>`), `%ReadyButton` (cliente), `%StartButton` (anfitrião; habilita só com todos os clientes prontos), `%ShopButton`, `%LeaveButton` |

`%BackButton` só na tela de entrada. `Lobby` tem `class_name`. O `Net` escolhe o contrato padrão; o lobby só
chama `Net.host_select_contract` quando o anfitrião escolhe, e `_begin_hunt` usa `Net.get_hunt_seed()`. O
cliente aperta `%ReadyButton` (o pronto automático da F2 acabou). Cão desabilitado com "Cães em rede: em
breve." até a F7. `LoadoutPanel` (`src/ui/common/loadout_panel.gd`, `class_name LoadoutPanel`,
`VBoxContainer`): `setup(root: Control, dog_locked_text: String = "")`, sinal `changed`; usado pela Preparação
(mesmos nós `%`) e pelo lobby.

Cada peer troca para `HUNT` ao receber `Net.room_state_changed(LOADING)`. Na tela de resultado em sala,
"Voltar à sala" → `LOBBY` e `%MenuButton` chama `Net.leave_room()`.

Link com `?sala=CODIGO`: o Boot (`boot.gd`), depois do toque inicial, lê `Net.take_url_room_code()`; se não
vazio, vai ao `LOBBY` com o código como meta do `Router` (`Lobby.INVITE_META`; a API do `Router` não muda), e o
lobby entra na sala sozinho com o nome salvo.

Espectador (F6): `SpectatorCamera` (`src/player/spectator_camera.gd`, extends `Camera3D`; `begin`,
`get_target_slot`, `get_candidates`, `switch_target`, `is_active`), criada pelo `Player` ao morrer se houver
aliado vivo; ela emite `spectate_changed`. `Player.get_spectator()`, `Player.is_spectating()`. Troca de alvo
por `fire`, `item_next` ou `weapon_swap`; respeita só o terreno. Minimapa: `ally_yaws`, `ally_down`,
`center_color`, `is_in_view()` (arrays paralelos a `allies`/`ally_colors`); aliado vivo = seta na cor do slot,
caído = X, fora do alcance = seta na borda. Bússola: losango na cor do slot (oco se caído). Jogador caído em
rede pode abrir a pausa (P) para sair; no solo continua recusando. Loja aberta a partir da sala volta para o
`LOBBY`. Na sala, dica fixa: "Quem cria a sala deve ter o melhor aparelho e conexão. Se o anfitrião sair do
jogo, a partida termina para todos." Conexão ao servidor tem prazo `net.connect_timeout_s`; nenhuma tela
bloqueia esperando rede. Até a fase dos cães, o lobby mostra "Cães ainda não entram no modo com amigos" e
`dog` vai 255. Textos de erro: `Net.room_error` (§6.11). Resultado em rede: "Seus abates: 7 · Equipe: 21 de
25", placar por jogador (`HuntResult.scoreboard`) e, para `DISCONNECTED`, "Conexão perdida: a caçada foi
encerrada"; com `counts_for_progression == false`: "Este contrato ainda não estava liberado para você: os
prêmios foram pagos, mas o progresso não avança."

O que persiste entre cenas: apenas autoloads (`Profile` com save, `Router` com `selected_map_id`,
`selected_contract_index`, `pending_request`, `last_result`; `InputSetup`; `Sfx` com loops — o B chama
`Sfx.stop_all_loops()` ao sair da caçada, em `_exit_tree`; `Net` com a sala e os enlaces). Nada de nós órfãos
entre cenas.

Camadas de `CanvasLayer`: HUD 10, toque 11, pausa 20, carregamento 30, aviso de orientação 100.

Web: pausa automática (A) quando o mouse capturado é perdido (o Esc do navegador sai do pointer lock e
pode não chegar ao jogo) e em `NOTIFICATION_APPLICATION_FOCUS_OUT`. "Retomar" recaptura (é um clique, gesto
válido).

---

## 12. Estratégia de testes (qa-tester, `tests/`)

Execução e ordem em `CLAUDE.md`. Cada cena de teste é uma cena raiz com script que imprime
`PASS <nome>` / `FAIL <nome>: <motivo>` / `SKIP <nome>: <motivo>`, termina com
`RESULT: <p> passed, <f> failed, <s> skipped` e chama `get_tree().quit(0 if f == 0 else 1)`. Timeout interno
(watchdog) para nunca travar: check 60 s, unit 60 s, flow 120 s, playthrough 300 s (tempo de jogo).
Modo estrito: `OS.get_cmdline_user_args()` contém `--strict` → assets ausentes/fallbacks contam como FAIL
(usado na integração: `tools/godot.sh --headless --path . res://tests/unit_tests.tscn -- --strict`).
Todo teste que mexe em perfil chama primeiro `Profile.set_save_path("user://test_save.json")` e
`Profile.reset_progress()`.

| Cena | Cobre |
|---|---|
| `tests/check_scripts.tscn` | carrega todo `.gd` em `res://src`, `res://assets`, `res://tests` (`ResourceLoader.load` + `GDScript.can_instantiate()`), carrega todo `.tscn` como `PackedScene` (sem instanciar `hunt.tscn`), instancia e libera cada cena de `assets/`; confere que os 7 autoloads (incluindo `Net`) existem e têm todos os métodos da §6 (`has_method`) e todos os sinais de `GameEvents` da §5, inclusive os 5 do cooperativo (`has_signal`); confere a regra de camadas de N (§2). |
| `tests/unit_tests.tscn` | `Data` (sem erros; ids referenciados existem; bandos 3–6 ou 1; soma ≤ `max_alive_boars`; todo contrato de mapa disponível tem ≥ 1 grupo), `Wallet`, `Inventory`, `Shop` (sem saldo, já possui, máximo, ouro), `RewardCalculator` (exemplo da §9.6 = 1782), `Progression`, `SaveService` (arquivo corrompido, vazio, versão antiga, tipos errados, backup), `PixBrCode` (CRC "123456789" = 0x29B1; estrutura dos campos; CRC final confere), `RedeemCode` (gera/valida/rejeita alterado/rejeita reuso via `DonationService`), `HuntResult`/`HitInfo`, `BoarVisualBase.scale_for_weight`, **contrato de assets** (cada caminho da §7: carrega, raiz estende a base, filhos obrigatórios, chama cada método da API sem erro, contagem de triângulos ≤ orçamento; flora: `build_mesh` de cada id ≠ null), `Heightmap` (determinismo por seed; bilinear em pontos da grade), `test_net.gd` (`NetCodec`, enlace com `NetLoopback` com perda/reordenação, réplica, `scale_groups`, economia em rede). |
| `tests/flow_test.tscn` | Boot → `%StartButton` → menu → `%PlayButton` → `Map_mato_grosso` → `Contract_0` + `%StartHuntButton` → espera `GameEvents.hunt_started` → `world.debug_force_end(HuntResult.Outcome.VICTORY)` → espera cena `RESULT` → confere `Profile.get_money()` aumentou e contrato 1 desbloqueado → `%ContinueButton` → `SHOP` → `Buy_shotgun_12` com saldo forçado → `%NextHuntButton` → `PREPARATION`. Cliques via `button.pressed.emit()`; cenas encontradas com `get_tree().current_scene.get_node("%Nome")` ou `find_child("Map_mato_grosso", true, false)`. |
| `tests/playthrough.tscn` | Instancia `ScenePaths.HUNT` como filho (com `route_on_finish = false` e `Router.set_pending_request(...)` com `rng_seed = 12345`), `Engine.time_scale = 4.0`. Cenário 1 (bot vence o contrato 0): para cada javali vivo, `bot_teleport` a 20 m dele (lado oposto à mata, Y via `world.get_height`), `bot_look_at(world.get_boar_zone_position(id, &"vital"))`, `bot_set_aim(true)`, `bot_fire()` respeitando cadência, `bot_reload()` com pente vazio; espera `VICTORY` com ≥ 1 abate por tiro real. Cenário 2 (bot parado, contrato 0): `DEFEAT_CROP` dentro do tempo (acelere com `debug_set_crop_health(5.0)` após 30 s). Cenário 3: `player.apply_damage(9999, ...)` → `DEFEAT_DEATH`. Cenário 4: dois javalis mortos no mesmo frame (`debug_kill_boar` duas vezes) não duplicam contagem nem `hunt_ended`. Checa: `hunt_ended` emitido exatamente 1 vez, `HuntResult` coerente (`total_money = money_from_kills + contract_bonus`, `kills.size() == killed`). |

| `tests/net_test.tscn` | integração do cooperativo: servidor Bun local (`server/server.js`, porta livre) e processos Godot headless pelo relay, cada cenário em processo filho; todo filho encerra em qualquer caminho de saída. 9 cenários: `relay_normal`, `relay_host_drops`, `deadlines` (enlace e sala, `src/net/debug/net_e2e`; o par cliente `net_e2e_peer.gd` aperta `%ReadyButton`), `victory`, `crop`, `death`, `host_drop`, `host_freeze`, `client_drop` (caçada, `src/hunt/debug/net_hunt_e2e`). Sem Bun, cada cenário sai como SKIP explícito. Cães (N6) ficam para a F7. |
| `tests/net_unit.tscn` | sandboxes de processo único (sem socket nem Bun), cada uma em processo filho com `--fixed-fps 60`: `net_roles`, `net_boars`, `net_flow`, `hud_net`, `link_selftest`; filho sem a linha-resumo é FAIL. `-- --only=a,b` seleciona. |
| `tests/web/coop_probe.py` | dois Chrome exercitando WebRTC de verdade e o fallback (`?relay_only=1`, `?drop_ice=1`); obrigatório antes de publicar mudança em `src/net`. Na mesma máquina precisa de `--disable-features=WebRtcHideLocalIpsWithMdns` (senão o ICE não fecha). |

Servidor de salas: `bun test` em `server/` (lógica neutra em `server/rooms.js`) e `server/check.js` contra Bun
local e produção (`wrangler dev` não funciona em Bun: o Worker é verificado publicando e rodando
`bun check.js <url de produção>`). Detalhe em `docs/multiplayer.md` §2.2 (A7).

Ganchos de produção para o bot (já no contrato): `PlayerBase.bot_*`, `get_ammo_*`, `is_reloading`;
`HuntWorld.get_alive_boar_ids`, `get_boar_position`, `get_boar_zone_position`, `get_boar_type`,
`is_world_ready`/`world_ready`, `is_hunt_over`, `get_result`, `debug_kill_boar`, `debug_set_crop_health`,
`debug_force_end`; `HuntController.route_on_finish`; `HuntRequest.rng_seed`; `Profile.set_save_path`;
`Router.set_pending_request`. Com `bot_set_enabled(true)` o `Player` ignora input real e não captura o mouse.
`--headless` não renderiza: nenhum código de gameplay pode depender de `Viewport.get_texture()` ou de
resultado de renderização.

---

## 13. Desempenho e riscos da Web/iOS

### 13.1 Orçamento (celular intermediário, WebGL2, 30+ fps; medir em "low"/"medium")
| Item | Orçamento |
|---|---|
| Draw calls por frame (visão típica) | ≤ 150 (pior caso ≤ 200) |
| Triângulos visíveis | ≤ 150 k |
| Terreno | 256 × 256 m; grade 129×129 (2 m); malha em 2×2 blocos de 64×64 quads = 32 768 tris, 4 draw calls; colisão HeightMapShape3D 257×257 |
| Flora | só `MultiMeshInstance3D`, blocos de 128 m (2×2) por id; grama `visibility_range_end` 60 m, arbusto 90 m, árvores = view distance; densidade × `flora_density` |
| Lavoura | patches 2×2 m em `MultiMesh` por blocos de 32×32 m, 2 multimeshes por bloco (saudável/comida; trocar = escalar instância a 0); `visibility_range_end` 110 m; ≈ 30 draw calls |
| Javalis simultâneos | ≤ 26 vivos (+ carcaças); ≤ 6 MeshInstance por javali, pernas somem a 40 m |
| Física | 1 `CharacterBody3D`; ≤ 200 shapes estáticas; 72 `HitZone`; ≤ 100 raios de visão/s; 0 corpos de IA |
| Sombras | 1 `DirectionalLight3D`; desligada em "low"; 30/45 m em medium/high; mapa 2048, filtro hard; flora/lavoura/arma sem sombra |
| Luzes extras | nenhuma |
| Partículas | `CPUParticles3D`, ≤ 24 cada, ≤ 6 ativas |
| Materiais únicos | ≤ 24 no total |
| Texturas | ≤ 512² cada; preferir ruído no shader; `NoiseTexture2D` ≤ 256² |
| Áudio | ≤ 18 vozes; ≤ 4 MB de amostras |
| Carregar a caçada | ≤ 3 s; nenhuma etapa > 700 ms |
| Memória | alvo ≤ 300 MB no total da aba |
| Alocação | nada de `Array`/`Dictionary` novos por frame em laços de IA; HUD/minimapa a 10 Hz |
| Aliados (cooperativo) | ≤ 3 `RemoteHunter`, ≤ 600 tris e ≤ 10 `MeshInstance3D` cada, + 1 `Label3D`; draw calls: pior caso ≤ 230 com 3 aliados |
| Rede (cooperativo) | download do cliente ≤ 5 kB/s; quadro de estado ≤ 1100 B (`net.max_frame_bytes`); nenhuma alocação por tick além de um `PackedByteArray` por quadro; raios de visão ≤ 130/s |

### 13.2 Riscos conhecidos da Web/iOS e mitigação
- **Áudio só após gesto:** o Boot exige toque/clique; `Sfx.unlock_audio()` dentro do handler. iOS no modo
  silencioso pode emudecer Web Audio — aceitar.
- **Pointer lock:** só pode ser pedido em gesto; Esc do navegador solta o mouse sem garantir o evento → pausa
  automática ao perder a captura. Safari desktop tem pointer lock; iOS não (modo toque).
- **Tela cheia:** iPhone Safari não suporta Fullscreen API para canvas (iPad sim). Pedir no gesto do Boot só
  em modo toque; falha silenciosa. Barras do navegador ficam — layout com âncoras e `expand`.
- **Orientação:** não dá para travar na Web → aviso "Gire o aparelho" (Router).
- **Sem threads:** tudo no thread principal; geração do mundo fatiada em frames; síntese de áudio limitada.
- **Modo "sample" do áudio Web:** sem efeitos de barramento; use só volume/pitch.
- **Memória iOS:** abas pesadas são recarregadas pelo Safari; manter texturas pequenas e malhas compartilhadas.
- **IndexedDB:** o `user://` é sincronizado de forma assíncrona; salvar logo após cada evento importante
  (nunca só ao fechar a aba). Navegação privada pode não persistir — o jogo continua sem erro.
- **Área de transferência:** `clipboard_set` pode falhar no iOS; o `%PixCodeText` permanece selecionável.
- **Teclado virtual:** necessário para `%RedeemCodeEdit` (preset `html/experimental_virtual_keyboard=true`).
- **Toque + mouse emulado:** ver §4 (botões do mouse fora do InputMap).
- **JSON no export:** `include_filter="data/*.json"` obrigatório (§3.2).
- **Resolução 3D:** `scaling_3d_scale` no Compatibility usa bilinear; se não surtir efeito numa versão, a
  qualidade "low" ainda reduz sombras e flora.
- **Cooperativo — aba do anfitrião em segundo plano** (ligação, troca de app, tela apagada): a simulação
  congela para todos e o iOS derruba o socket em segundos. Mitigação: faixa de aviso (`host_stall_warn_s`) +
  prazo de `host_timeout_s` + fim com abates pagos; Wake Lock (`navigator.wakeLock.request("screen")`, falha
  silenciosa) durante a caçada em rede; dica no lobby para o anfitrião ser o melhor aparelho; migração de
  anfitrião fica fora da v1.
- **Cooperativo — NAT simétrico em 4G:** o ICE não fecha. Mitigação: o enlace nasce em relay pelo servidor de
  salas e é promovido a WebRTC; sem TURN na v1.
- **Cooperativo — cota diária do servidor de salas (plano gratuito):** esgotada, não se criam salas novas e
  pares em relay caem até as 21h de Brasília; o solo nunca depende do servidor. Mitigação: uma mensagem por
  tick por direção no relay (`relay_hz`), WebRTC como caminho normal, mensagem clara no lobby
  (`server_unreachable`); saída futura: TURN gratuito do Cloudflare. Demais riscos (desempenho do anfitrião,
  draw calls dos aliados, dessincronização de mundo, WebRTC só testável no Chrome): `docs/multiplayer.md` §8.

### 13.3 Riscos de integração (do contrato)
- **R1 — Costura visual × gameplay do javali.** Escala por peso, orientação -Z, caixas de `HIT_ZONES` e
  posição de `Head` precisam bater; fallback esconde a falta. Mitigação: constantes únicas em
  `BoarVisualBase`, teste de contrato estrito, screenshot de integração com as `HitZone` visíveis
  (`get_tree().debug_collisions_hint`).
- **R2 — Raycast contra `Area3D`.** Depende do motor de física padrão do 4.7 (`collide_with_areas`). Teste no
  sandbox do A e no `unit_tests`. Plano B, contido em `src/core/hit_zone.gd`: trocar `extends Area3D` por
  `extends AnimatableBody3D` (`sync_to_physics = false`) mantendo a API — o A não muda.
- **R3 — Deriva de assinaturas e dados.** Stubs dos autoloads precisam ter **todas** as assinaturas da §6, e
  donos não podem renomear nada; `float` vs `int` e `String` vs `StringName` vindos de JSON. Mitigação:
  `check_scripts` confere métodos/sinais; regras da §6.2; seed de dados na Fase 0.

---

## 14. Pacotes de trabalho

### Fase 0 — coordenador (antes de disparar os agentes)
1. `project.godot` (§3) e `export_presets.cfg` (§3.2).
2. `src/core/*.gd` copiados **verbatim** do Apêndice A.
3. Stubs dos autoloads com todas as assinaturas da §6 (Apêndice B: `Data` funcional; demais com os valores
   "stub" indicados): `src/systems/data_registry.gd`, `src/systems/profile.gd`, `src/systems/router.gd`,
   `src/input/input_setup.gd`, `assets/audio/sfx_library.gd`; no cooperativo (F1), `src/net/net.gd` com o
   stub offline de §6.11.
4. `data/*.json` copiados verbatim da §9 (seed). A partir daí são do game-systems.
5. Rodar `--import` e `check_scripts` (este último ainda não existe: basta abrir o projeto headless com
   `--quit` sem erros de parser).

### Pacote A — game-developer (jogador, armas, input, HUD)
Arquivos: `src/input/input_setup.gd`; `src/player/player.tscn`, `player.gd`, `item_belt.gd`,
`src/player/debug/player_sandbox.tscn`, `sandbox_world.gd` (estende `HuntWorld`: chão plano 200×200 com
`StaticBody3D` layer 1, 3 alvos com `HitZone` e contador), `src/weapons/weapon.gd`, `weapon_holder.gd`,
`hitscan.gd`; `src/hud/hud.tscn`, `hud.gd`, `minimap.gd`, `compass.gd`, `damage_indicator.gd`,
`kill_message.gd`, `scope_overlay.gd`, `pause_overlay.tscn`, `pause_overlay.gd`,
`src/hud/touch/touch_controls.tscn`, `touch_controls.gd`, `virtual_joystick.gd`, `look_pad.gd`.
Critérios de aceite:
- `check_scripts` sem erros; nenhum arquivo fora das pastas do A; nenhuma referência a classes de B/systems.
- `player_sandbox.tscn` roda headless com `--quit-after 300` sem erros; com janela: anda (WASD), corre, agacha
  (altura do olho muda), olha (mouse capturado ao clicar), mira com zoom (roda), atira, recarrega, troca 1/2.
- Acertar a `HitZone` de um alvo a 30 m com a .22 dispara `hit_received` com `damage` = 38 × falloff (=38).
  Bagos da 12 compartilham `shot_id`. `shot_fired` 1× por disparo.
- `apply_damage(20, pos)` com colete reduz para 13; `player_damaged` e indicador direcional; vida 0 →
  `player_died` uma vez.
- Em modo toque (`set_touch_override("on")`): joystick move, arrastar à direita olha, Tiro atira, e um toque
  na área de olhar **não** dispara a arma.
- Sem `weapon_view` existente, fallback aparece e o tiro funciona; com térmica equipada, mirar emite
  `thermal_vision_changed(true)`.
- Todos os ganchos `bot_*` funcionam no sandbox (teste manual descrito no relatório).

### Pacote B — game-developer (javalis, cães, mundo, fluxo da caçada)
Arquivos: `src/hunt/hunt.tscn`, `hunt_controller.gd`, `boar_spawner.gd`, `src/hunt/debug/fallback_player.gd`;
`src/world/map_root.gd`, `heightmap.gd`, `terrain.gd`, `crop_field.gd`, `crop_manager.gd`, `prop_spawn.gd`,
`water_body.gd`, `flora_zone.gd`, `flora_scatter.gd`, `obstacle_grid.gd`, `bait.gd`,
`src/world/maps/mato_grosso/mato_grosso_map.tscn`; `src/boars/boar.tscn`, `boar.gd`, `boar_herd.gd`,
`steering.gd`; `src/dogs/dog.tscn`, `dog.gd`.
Critérios de aceite:
- `check_scripts` sem erros; nenhuma referência a classes de A/systems; nenhum `ext_resource` para `assets/`.
- `hunt.tscn` roda direto (sem Router) com `HuntRequest.make_debug()`: carrega em ≤ 3 s em desktop,
  emite `hunt_started`, `boar_counts_changed(0, 5)`, sem erros mesmo sem nenhum asset (fallbacks) e com
  `FallbackPlayer` se `player.tscn` não existir.
- Javalis andam sobre o terreno (|y − get_height| < 0,05), não atravessam props com footprint, vão à lavoura e
  a drenam (`crop_health_changed` decrescente), fogem ao ouvir `shot_fired` próximo e voltam depois.
- Macho a < 12 m do jogador: `scrape` ≥ 0,8 s antes de `charge` (verificável por `boar_state_changed`);
  a investida causa dano uma vez e passa direto se o jogador sai da linha.
- `debug_kill_boar` em todos → `VICTORY` 1×; `debug_set_crop_health(0)` → `DEFEAT_CROP`; `player_died`
  → `DEFEAT_DEATH`; `hunt_abandon_requested` → `ABANDONED`. `route_on_finish=false` não troca de cena.
- Cão: segue, "Pega!"/"Volta!" via `dog_command_requested`, recua com vida baixa e nunca morre.
- Ceva: `item_used(&"corn_bait", pos)` atrai até 4 javalis a 80 m por 45 s, sem drenar a lavoura.
- Mapa Mato Grosso conforme §8.5. Fps ≥ 60 em desktop no contrato 5 (17 javalis), medido e relatado.

### game-systems (dados, sistemas, menus)
Arquivos: `data/*.json` (manter/ajustar o seed); `src/systems/data_registry.gd` (completar validação),
`profile.gd`, `router.gd`, `wallet.gd`, `inventory.gd`, `progression.gd`, `shop.gd`, `reward_calculator.gd`,
`save_service.gd`, `src/systems/pix/pix_br_code.gd`, `pix_gateway.gd`, `offline_redeem_gateway.gd`,
`redeem_code.gd`, `donation_service.gd`; `src/ui/boot/boot.tscn|.gd`, `main_menu/`, `map_select/`,
`preparation/`, `shop/`, `result/`, `donate/`, `settings/settings.tscn|.gd`, `settings_panel.tscn|.gd`,
`src/ui/common/` (componentes de cartão/preço reutilizáveis).
Critérios de aceite:
- `check_scripts` sem erros; regras de economia testáveis sem abrir telas (classes estáticas/RefCounted).
- `Data.get_load_errors()` vazio; contratos conforme §9.6.
- Save: apagar, corromper (`{`), truncar ou trocar tipos → o jogo abre com perfil válido e sem crash.
- Compra sem saldo devolve `&"insufficient_funds"` sem alterar nada; arma comprada aparece na preparação.
- `crc16_ccitt("123456789") == 0x29B1`; payload Pix montado conforme §9.8 com a chave placeholder.
- Fluxo completo pelos botões da §11 (nomes exatos); mapas indisponíveis aparecem "Em breve" e desabilitados.
- Tela de doação mostra o aviso de doação/sem garantia e nunca diz "pagamento confirmado".
- Todas as telas utilizáveis a 1280×720 e a 2340×1080 (celular), alvos de toque ≥ 64 px.

### art-director (assets)
Arquivos: `assets/audio/sfx_library.gd` (+ `assets/audio/synth/*.gd`), `assets/models/boar/boar_visual.tscn|.gd`,
`assets/models/dog/dog_visual.tscn|.gd`, `assets/models/weapons/{carbine_22,shotgun_12,rifle_308,rifle_3006,rifle_338}_view.tscn`
+ `weapon_view.gd`, `assets/models/props/{farmhouse,barn,water_tank,fence_segment,gate,corn_bait,feed_trough}.tscn`,
`assets/models/flora/flora_library.gd`, `assets/materials/terrain.tres`, `water.tres`,
`assets/shaders/*.gdshader`, `assets/env/mato_grosso_env.tscn` (+ script), `assets/vfx/{impact_dust,impact_blood,impact_wood}.tscn`,
`assets/ui/theme.tres`, `assets/ui/scope_overlay.gdshader`, `assets/ui/icons/*.svg` (lista da §7.9),
`assets/preview/*` (cenas de screenshot).
Critérios de aceite:
- Cada asset no caminho exato, raiz estendendo a base correta, filhos obrigatórios presentes, toda a API
  chamável sem erro em headless, orçamento de triângulos/instâncias respeitado (teste de contrato estrito).
- Javalis de 25, 100 e 260 kg com `scale_for_weight` cabem nas `HIT_ZONES` (screenshot lado a lado).
- Todos os ids de som da §7.8 existem (`has_sound`); síntese ≤ 400 ms em desktop (medido e relatado).
- Screenshots de: mapa com ambiente, cada arma em quadril e mira, javalis dos 4 tipos, 3 cães, ícones.
- Nenhum corpo físico, `AnimationPlayer` importado, esqueleto, luz extra ou arquivo binário baixado.

### qa-tester
Arquivos: `tests/check_scripts.tscn|.gd`, `tests/unit_tests.tscn|.gd`, `tests/unit/test_*.gd`,
`tests/flow_test.tscn|.gd`, `tests/playthrough.tscn|.gd`, `tests/bot/hunt_bot.gd`, `tests/lib/test_case.gd`.
Critérios de aceite: as 4 cenas existem, terminam sozinhas com código de saída correto, cobrem a §12, e
cada teste que falha imprime arquivo/condição. Testes que dependem de pacote ainda não entregue imprimem
`SKIP` (exceto em `--strict`).

### Pacote N — game-developer (rede do cooperativo)
Arquivos: `src/net/net.gd` (autoload `Net`, §6.11), `net_session.gd`, `net_signaling.gd`, `net_link.gd`,
`net_rtc.gd`, `net_loopback.gd`. Só referencia `src/core/*` e autoloads; troca de cena só via `Router`.
Os pacotes A, B, systems e art-director também recebem tarefas do cooperativo (arquivos novos listados em
§2, §6.8–§6.11 e §7.11; `src/ui/lobby/` e `loadout_panel.gd` são do game-systems; `server/` e `src/core/*` da
coordenação; `tests/net/`, `tests/net_test.tscn`, `tests/unit/test_net.gd`, `tests/web/coop_probe.py` do
qa-tester).

### Fases do cooperativo e critérios de aceite
Modelo: Sonnet por padrão; Fable onde indicado. Toda fase termina com as 4 suítes atuais passando sem mudança
de resultado e é publicável (a entrada do menu é visível para todos desde a F6; antes só com `?mp=1`). Detalhe de arquivos por fase:
`docs/multiplayer.md` §9.

| Fase | Objetivo | Dono / modelo | Aceite |
|---|---|---|---|
| F0 — servidor de salas no ar | `wss://javali-salas.SUBDOMINIO.workers.dev/ws` cria sala, deixa entrar, repassa sinalização e relay. Nenhum código de jogo | coordenação (Sonnet; Fable se hibernação ou deploy derem trabalho) | `bun test` verde (criar, entrar, lista de peers, sala cheia, versão diferente, sala trancada, código em uso, `signal`, repasse binário, regra da estrela, anfitrião saiu, cada limite, e o mesmo roteiro com a lista de conexões recriada entre chamadas); `bun check.js` verde contra Bun local, `wrangler dev` e produção; origem errada recebe 403; `tools/wscheck.html` mostra "Sala criada" no celular; sala parada 30 s e retomada continua repassando |
| F1 — contrato e esqueleto | o projeto compila com os tipos novos e o `Net` offline; nada muda para o jogador | coordenação (core, `project.godot`), game-systems (dados, save), qa-tester (testes), game-architect (contrato) | 4 suítes verdes; `check_scripts` confere o autoload `Net`, os 5 sinais e a regra de camadas de N; unidade: `Net.is_active() == false`, `Net.get_local_slot() == 0`, save antigo ganha `player_name = ""` sem mudar de versão |
| F2 — dois navegadores se vendo andar (caminho crítico) | com `?mp=1`, um cria a sala, outro entra pelo código, o anfitrião inicia, os dois andam e se veem, por WebRTC; sem javalis para o cliente | N (Fable); A, B, systems, qa (Sonnet) | `net_test` verde (posição do caçador remoto a ≤ 0,5 m da real após 1 s parado; versão diferente recusada; quinto peer recusado; processos filhos encerrados em todo caminho de saída); `coop_probe.py`: `huntProbe.path == "rtc"` nos dois e `allies[0]` de B segue A a ≤ 1 m; unidade do enlace com loopback a 20% de perda e reordenação: eventos chegam todos e em ordem; medido o delta de `_process` depois de 5 s de aba congelada |
| F3 — fallback de relay robusto | par cujo ICE não fecha joga igual; RTC que morre no meio não derruba o jogador | N (Fable), qa (Sonnet) | com `drop_ice=1`, `path == "relay"` depois de `ice_timeout_s` e o teste de andar passa; unidade: troca de caminho com 5 eventos não confirmados entrega os 5 uma vez, em ordem; um enlace em relay envia no máximo `relay_hz` mensagens por segundo por direção |
| F4 — javalis replicados e tiro (caminho crítico) | os dois veem os mesmos javalis, atiram, veem abates e são investidos | B (Fable: IA dos javalis), A e qa (Sonnet) | N3: anfitrião + cliente no contrato 0 com seed fixa, bot do cliente mata ≥ 3 javalis atirando nas réplicas, `VICTORY` nos dois, soma dos abates = total, cada abate em um só resultado; snapshot → réplica com erro ≤ 1 cm; hash das posições de tronco igual em low/medium/high com `sync_layout`; `playthrough` sem mudança; banda ≤ 5 kB/s de download por cliente no contrato 5; fps do anfitrião em desktop ≥ 60 com 26 javalis e 3 remotos |
| F5 — lavoura, itens, fim de caçada e economia | uma caçada cooperativa completa, do lobby ao resultado, com dinheiro certo | B (Fable: fluxo da caçada), A, N, systems, qa (Sonnet) | N4: cliente termina `DISCONNECTED` em ≤ `host_timeout_s` + 2 s com os próprios abates creditados e sem progressão; N5: anfitrião segue e vence sozinho; `apply_hunt_result` com `counts_for_progression = false` credita dinheiro e não desbloqueia; `scale_groups` dá 14 e 23 para o contrato 1 com 2 e 4 jogadores; canteiros comidos iguais nos dois peers |
| F6 — lobby completo, aliados no HUD, espectador: beta (concluída em 2026-11-14 (sessão manual com 3 aparelhos reais ainda pendente)) | "Jogar com amigos (beta)" visível para todos | systems, A, art-director, qa (Sonnet) | `flow_test` sem mudança; abrir `?sala=CODE` entra na sala sem digitar; servidor inacessível → `server_unreachable` em ≤ 9 s e "Voltar" funciona; morrer com aliado vivo mostra a câmera de espectador e "Assistindo: <Nome>"; sessão manual de 3 jogadores (PC, Android, iPhone) relatada; `mobile_probe.py` verde |
| F7 — cães em rede | cada jogador leva o seu cão e manda "Pega!"/"Volta!" | B, qa (Sonnet) | N6: comando do cliente muda o estado só do cão dele; sinais de cão só no HUD do dono; marcação aparece para os dois; solo sem mudança |
| F8 — robustez móvel | cair e voltar na mesma página sem perder a caçada | N e B (Fable), qa (Sonnet) | derrubar o WebSocket do cliente por 5 s: ele volta no mesmo slot com os mesmos javalis vivos e o mesmo resultado parcial; relatório de fps e banda em celular intermediário como anfitrião de 4 |

---

## Apêndice A — `src/core/` (verbatim; coordenador copia, ninguém edita)

### `src/core/game_events.gd`
```gdscript
extends Node
## Autoload "GameEvents": global signal bus. Declares signals only. See docs/arquitetura.md §5.

@warning_ignore_start("unused_signal")

# Hunt lifecycle
signal hunt_started(request: HuntRequest)
signal hunt_ended(result: HuntResult)
signal hunt_paused_changed(paused: bool)
signal hunt_abandon_requested()

# Player / weapons / items
signal shot_fired(weapon_id: StringName, origin: Vector3, direction: Vector3, noise_radius_m: float)
signal player_damaged(amount: float, source_position: Vector3, health_after: float)
signal player_healed(amount: float, health_after: float)
signal player_died()
signal item_used(item_id: StringName, position: Vector3)
signal thermal_vision_changed(active: bool)
signal dog_command_requested()

# Boars / world
signal boar_spawned(boar_id: int, type_id: StringName, weight_kg: float)
signal boar_hit(boar_id: int, zone: StringName, damage: float, hit_position: Vector3, shot_id: int)
signal boar_state_changed(boar_id: int, state: StringName)
signal boar_killed(kill: KillInfo)
signal boar_counts_changed(killed: int, total: int)
signal crop_health_changed(pct: float)
signal crop_under_attack(active: bool)
signal bait_placed(position: Vector3, duration_s: float)

# Dog
signal dog_state_changed(state: StringName)
signal dog_health_changed(pct: float)
signal dog_marked_boar(position: Vector3, duration_s: float)
signal dog_command_executed(command: StringName)

# HUD
signal hud_message_requested(text: String, duration_s: float)

# Meta-game
signal wallet_changed(money: int, gold: int)
signal inventory_changed()
signal loadout_changed()
signal progression_changed()
signal settings_changed(key: String, value: Variant)
signal touch_mode_changed(is_touch: bool)

# Co-op (see docs/multiplayer.md)
signal hunter_joined(slot: int, display_name: String)
signal hunter_left(slot: int)
signal hunter_died(slot: int)
signal spectate_changed(slot: int)
signal net_stall_changed(stalled: bool)

@warning_ignore_restore("unused_signal")
```

### `src/core/layers.gd`
```gdscript
class_name Layers
extends RefCounted
## 3D collision bits. Names match project.godot [layer_names].

const TERRAIN: int = 1
const STATIC: int = 2
const PLAYER: int = 4
const BOAR_HITZONE: int = 8

const MASK_PLAYER_BODY: int = TERRAIN | STATIC
const MASK_WEAPON_RAY: int = TERRAIN | STATIC | BOAR_HITZONE
const MASK_LINE_OF_SIGHT: int = TERRAIN | STATIC
const MASK_GROUND: int = TERRAIN
```

### `src/core/ids.gd`
```gdscript
class_name Ids
extends RefCounted
## Shared StringName ids. Data ids must match data/*.json.

# Hit zones
const ZONE_HEAD: StringName = &"head"
const ZONE_VITAL: StringName = &"vital"
const ZONE_BODY: StringName = &"body"
const ZONE_REAR: StringName = &"rear"
const ZONE_DOG: StringName = &"dog"

# Currencies
const MONEY: StringName = &"money"
const GOLD: StringName = &"gold"

# Boar types
const PIGLET: StringName = &"piglet"
const SOW: StringName = &"sow"
const BOAR: StringName = &"boar"
const ALPHA: StringName = &"alpha"

# Boar states
const BS_WANDER: StringName = &"wander"
const BS_TO_CROP: StringName = &"to_crop"
const BS_EAT: StringName = &"eat"
const BS_TO_BAIT: StringName = &"to_bait"
const BS_ALERT: StringName = &"alert"
const BS_FLEE: StringName = &"flee"
const BS_SCRAPE: StringName = &"scrape"
const BS_CHARGE: StringName = &"charge"
const BS_RECOVER: StringName = &"recover"
const BS_BAYED: StringName = &"bayed"
const BS_HELD: StringName = &"held"
const BS_DEAD: StringName = &"dead"

# Dog states and commands
const DS_FOLLOW: StringName = &"follow"
const DS_SEEK: StringName = &"seek"
const DS_POINT: StringName = &"point"
const DS_BAY: StringName = &"bay"
const DS_HOLD: StringName = &"hold"
const DS_RETREAT: StringName = &"retreat"
const DS_RETURN: StringName = &"return"
const CMD_ATTACK: StringName = &"attack"
const CMD_RECALL: StringName = &"recall"

# Weapons
const W_CARBINE_22: StringName = &"carbine_22"
const W_SHOTGUN_12: StringName = &"shotgun_12"
const W_RIFLE_308: StringName = &"rifle_308"
const W_RIFLE_3006: StringName = &"rifle_3006"
const W_RIFLE_338: StringName = &"rifle_338"

# Equipment
const I_BINOCULARS: StringName = &"binoculars"
const I_LEATHER_VEST: StringName = &"leather_vest"
const I_MEDKIT: StringName = &"medkit"
const I_CORN_BAIT: StringName = &"corn_bait"
const I_EXTRA_AMMO: StringName = &"extra_ammo"
const I_THERMAL_SCOPE: StringName = &"thermal_scope"
const I_SCOUT_DRONE: StringName = &"scout_drone"

# Dogs
const D_CARAMELO: StringName = &"caramelo"
const D_FOXHOUND: StringName = &"foxhound"
const D_DOGO: StringName = &"dogo"

# Quality
const Q_LOW: StringName = &"low"
const Q_MEDIUM: StringName = &"medium"
const Q_HIGH: StringName = &"high"
```

### `src/core/scene_paths.gd`
```gdscript
class_name ScenePaths
extends RefCounted
## Scene paths and asset path conventions. Single source for every load().

const BOOT: String = "res://src/ui/boot/boot.tscn"
const MAIN_MENU: String = "res://src/ui/main_menu/main_menu.tscn"
const MAP_SELECT: String = "res://src/ui/map_select/map_select.tscn"
const PREPARATION: String = "res://src/ui/preparation/preparation.tscn"
const SHOP: String = "res://src/ui/shop/shop.tscn"
const RESULT: String = "res://src/ui/result/result.tscn"
const DONATE: String = "res://src/ui/donate/donate.tscn"
const SETTINGS: String = "res://src/ui/settings/settings.tscn"
const SETTINGS_PANEL: String = "res://src/ui/settings/settings_panel.tscn"
const LOBBY: String = "res://src/ui/lobby/lobby.tscn"
const HUNT: String = "res://src/hunt/hunt.tscn"
const PLAYER: String = "res://src/player/player.tscn"
const REMOTE_HUNTER: String = "res://src/player/remote_hunter.tscn"
const HUD: String = "res://src/hud/hud.tscn"
const BOAR: String = "res://src/boars/boar.tscn"
const DOG: String = "res://src/dogs/dog.tscn"

const BOAR_VISUAL: String = "res://assets/models/boar/boar_visual.tscn"
const DOG_VISUAL: String = "res://assets/models/dog/dog_visual.tscn"
const HUNTER_VISUAL: String = "res://assets/models/hunter/hunter_visual.tscn"
const FLORA_LIBRARY: String = "res://assets/models/flora/flora_library.gd"
const TERRAIN_MATERIAL: String = "res://assets/materials/terrain.tres"
const WATER_MATERIAL: String = "res://assets/materials/water.tres"
const UI_THEME: String = "res://assets/ui/theme.tres"
const SCOPE_SHADER: String = "res://assets/ui/scope_overlay.gdshader"


static func map_scene(map_id: StringName) -> String:
	return "res://src/world/maps/%s/%s_map.tscn" % [map_id, map_id]


static func weapon_view(weapon_id: StringName) -> String:
	return "res://assets/models/weapons/%s_view.tscn" % weapon_id


static func prop(prop_id: StringName) -> String:
	return "res://assets/models/props/%s.tscn" % prop_id


static func environment(map_id: StringName) -> String:
	return "res://assets/env/%s_env.tscn" % map_id


static func vfx(vfx_id: StringName) -> String:
	return "res://assets/vfx/%s.tscn" % vfx_id


static func icon(icon_id: StringName) -> String:
	return "res://assets/ui/icons/%s.svg" % icon_id
```

### `src/core/asset_loader.gd`
```gdscript
class_name AssetLoader
extends RefCounted
## Loads assets that may not exist yet. Returns null (and warns once) so callers use a fallback.

static var _missing: Dictionary = {}


static func exists(path: String) -> bool:
	return ResourceLoader.exists(path)


static func load_resource(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		_report(path)
		return null
	var res: Resource = load(path)
	if res == null:
		_report(path)
	return res


static func instantiate(path: String) -> Node:
	var packed: PackedScene = load_resource(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate()


static func get_missing() -> PackedStringArray:
	return PackedStringArray(_missing.keys())


static func clear_missing() -> void:
	_missing.clear()


static func _report(path: String) -> void:
	if _missing.has(path):
		return
	_missing[path] = true
	push_warning("AssetLoader: missing asset '%s', using fallback." % path)
```
Quem recebe uma instância cuja raiz não é da classe-base esperada faz `push_warning`, libera a instância
(`free()`) e usa o fallback. O teste estrito usa `AssetLoader.get_missing()` para detectar fallbacks.

### `src/core/hit_info.gd`
```gdscript
class_name HitInfo
extends RefCounted
## One bullet/pellet impact. Filled by the weapon (A); zone/target_id filled by HitZone.

var shot_id: int = 0
var weapon_id: StringName = &""
var damage: float = 0.0              # after distance falloff, before zone multiplier
var origin: Vector3 = Vector3.ZERO
var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var direction: Vector3 = Vector3.FORWARD
var distance_m: float = 0.0
var zone: StringName = &""
var target_id: int = -1
var shooter_slot: int = 0            # co-op: slot of the hunter who fired (0 in solo)
```

### `src/core/hit_zone.gd`
```gdscript
class_name HitZone
extends Area3D
## Shootable zone of a target. The weapon calls receive_hit(); the owner listens to hit_received.

signal hit_received(hit: HitInfo)

@export var zone: StringName = &"body"
var target_id: int = -1


func _ready() -> void:
	collision_layer = Layers.BOAR_HITZONE
	collision_mask = 0
	monitoring = false
	monitorable = true


func receive_hit(hit: HitInfo) -> void:
	hit.zone = zone
	hit.target_id = target_id
	hit_received.emit(hit)


func disable() -> void:
	collision_layer = 0
	set_deferred("monitorable", false)
```

### `src/core/kill_info.gd`
```gdscript
class_name KillInfo
extends RefCounted

var boar_id: int = -1
var type_id: StringName = &""
var weight_kg: float = 0.0
var killing_zone: StringName = &""
var one_shot: bool = false
var clean_kill: bool = false
var reward_money: int = 0
var position: Vector3 = Vector3.ZERO
var time_s: float = 0.0
var killer_slot: int = 0             # co-op: slot of the hunter credited with the kill (0 in solo)


func to_dict() -> Dictionary:
	return {
		"boar_id": boar_id, "type_id": String(type_id), "weight_kg": weight_kg,
		"killing_zone": String(killing_zone), "one_shot": one_shot, "clean_kill": clean_kill,
		"reward_money": reward_money, "time_s": time_s,
	}
```

### `src/core/hunt_request.gd`
```gdscript
class_name HuntRequest
extends RefCounted
## What the hunt receives from the menus (built by Profile.build_hunt_request).

var map_id: StringName = &"mato_grosso"
var contract_index: int = 0
var weapon_ids: Array[StringName] = [&"carbine_22"]   # 1..2 entries, slot order, no empty ids
var dog_id: StringName = &""                          # &"" = no dog
var item_ids: Array[StringName] = []                  # equipped equipment ids (max 3)
var item_counts: Dictionary = {}                      # StringName -> int (consumables: carried; others: 1)
var quality: StringName = &""                         # &"" = resolve from settings
var rng_seed: int = 0                                 # 0 = randomize
var player_count: int = 1                             # co-op: hunters in the hunt (1 = solo)


static func make_debug(p_map_id: StringName = &"mato_grosso", p_contract_index: int = 0) -> HuntRequest:
	var r: HuntRequest = HuntRequest.new()
	r.map_id = p_map_id
	r.contract_index = p_contract_index
	return r


func has_item(item_id: StringName) -> bool:
	return item_ids.has(item_id)


func get_item_count(item_id: StringName) -> int:
	return int(item_counts.get(item_id, 0))
```

### `src/core/hunt_result.gd`
```gdscript
class_name HuntResult
extends RefCounted
## What the hunt returns. Applied once by Profile.apply_hunt_result.

enum Outcome { VICTORY, DEFEAT_CROP, DEFEAT_DEATH, ABANDONED, DISCONNECTED }

var outcome: Outcome = Outcome.ABANDONED
var map_id: StringName = &""
var contract_index: int = 0
var kills: Array[KillInfo] = []
var boars_total: int = 0
var money_from_kills: int = 0
var contract_bonus: int = 0
var total_money: int = 0
var crop_health_pct: float = 100.0
var duration_s: float = 0.0
var shots_fired: int = 0
var shots_hit: int = 0
var consumables_used: Dictionary = {}   # StringName -> int
# Co-op. kills/money_from_kills = only the local player's; boars_total = the team's.
var counts_for_progression: bool = true # false: rewards are paid but the contract is not marked won/unlocked
var player_count: int = 1
var team_kills: int = 0
var scoreboard: Array[Dictionary] = []  # {slot, name, kills, money}; empty in solo


func is_victory() -> bool:
	return outcome == Outcome.VICTORY


func to_dict() -> Dictionary:
	var kill_dicts: Array = []
	for k: KillInfo in kills:
		kill_dicts.append(k.to_dict())
	return {
		"outcome": Outcome.keys()[outcome], "map_id": String(map_id), "contract_index": contract_index,
		"kills": kill_dicts, "boars_total": boars_total, "money_from_kills": money_from_kills,
		"contract_bonus": contract_bonus, "total_money": total_money,
		"crop_health_pct": crop_health_pct, "duration_s": duration_s,
		"shots_fired": shots_fired, "shots_hit": shots_hit,
	}
```

### `src/core/player_base.gd`
```gdscript
class_name PlayerBase
extends CharacterBody3D
## Contract hunter <-> hunt. Package A implements Player (extends this). Package B uses only this API.
## Origin = feet. Forward = -Z (yaw on this node).

var slot: int = 0


func setup(_request: HuntRequest, _world: HuntWorld) -> void:
	pass


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


func apply_damage(_amount: float, _source_position: Vector3, _knockback_mps: float = 0.0) -> void:
	pass


func heal(_amount: float) -> void:
	pass


func is_alive() -> bool:
	return true


func get_health() -> float:
	return 100.0


func get_max_health() -> float:
	return 100.0


func get_eye_position() -> Vector3:
	return global_position + Vector3(0.0, 1.65, 0.0)


func get_look_direction() -> Vector3:
	return -global_transform.basis.z


func is_crouching() -> bool:
	return false


func get_noise_radius() -> float:
	return 0.0


func set_input_enabled(_enabled: bool) -> void:
	pass


func get_current_weapon_id() -> StringName:
	return &""


func get_ammo_in_mag() -> int:
	return 0


func get_ammo_reserve() -> int:
	return 0


func is_reloading() -> bool:
	return false


# --- Bot hooks (tests) ---
func bot_set_enabled(_enabled: bool) -> void:
	pass


func bot_set_move(_direction: Vector2, _sprint: bool) -> void:   # x = right, y = forward, length <= 1
	pass


func bot_look_at(_point: Vector3) -> void:
	pass


func bot_set_aim(_aiming: bool) -> void:
	pass


func bot_fire() -> bool:   # true if a shot was fired
	return false


func bot_reload() -> void:
	pass


func bot_select_weapon(_slot: int) -> void:
	pass


func bot_use_item(_item_id: StringName) -> bool:
	return false


func bot_dog_command() -> void:
	pass


func bot_teleport(target_position: Vector3) -> void:
	global_position = target_position
	velocity = Vector3.ZERO
```

### `src/core/hunt_world.gd`
```gdscript
class_name HuntWorld
extends Node3D
## Contract hunt/world <-> player, HUD and tests. Package B implements HuntController (extends this).
## Map rect is in XZ: position = (min_x, min_z), size = (size_x, size_z).

signal world_ready()


func is_world_ready() -> bool:
	return false


func get_map_id() -> StringName:
	return &""


func get_contract_index() -> int:
	return 0


func get_map_rect() -> Rect2:
	return Rect2(-128.0, -128.0, 256.0, 256.0)


func get_height(_x: float, _z: float) -> float:
	return 0.0


func get_normal(_x: float, _z: float) -> Vector3:
	return Vector3.UP


func get_crop_rects() -> Array[Rect2]:
	return []


func get_crop_health_pct() -> float:
	return 100.0


func get_boars_total() -> int:
	return 0


func get_boars_killed() -> int:
	return 0


func get_alive_boar_ids() -> PackedInt32Array:
	return PackedInt32Array()


func get_boar_position(_boar_id: int) -> Vector3:
	return Vector3.INF


func get_boar_type(_boar_id: int) -> StringName:
	return &""


func get_boar_zone_position(_boar_id: int, _zone: StringName) -> Vector3:
	return Vector3.INF


func get_nearest_boar_position(_from: Vector3) -> Vector3:
	return Vector3.INF


func get_marked_boar_positions() -> PackedVector3Array:
	return PackedVector3Array()


func has_dog() -> bool:
	return false


func get_dog_position() -> Vector3:
	return Vector3.INF


func get_dog_state() -> StringName:
	return &""


func get_dog_health_pct() -> float:
	return 0.0


func get_player() -> PlayerBase:   # the hunter of THIS machine
	return null


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


func get_elapsed_s() -> float:
	return 0.0


func is_hunt_over() -> bool:
	return false


func get_result() -> HuntResult:
	return null


# --- Debug hooks (tests) ---
func debug_kill_boar(_boar_id: int) -> void:
	pass


func debug_set_crop_health(_pct: float) -> void:
	pass


func debug_force_end(_outcome: HuntResult.Outcome) -> void:
	pass


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

### `src/core/boar_visual_base.gd`
```gdscript
class_name BoarVisualBase
extends Node3D
## Visual-only boar. Origin on the ground, forward -Z. Scale 1 = 100 kg reference animal.
## Gameplay owns the root transform (sets uniform scale with scale_for_weight).

const REFERENCE_WEIGHT_KG: float = 100.0
## zone -> [center, size] in meters at scale 1 (gameplay multiplies both by scale_for_weight).
const HIT_ZONES: Dictionary = {
	&"head": [Vector3(0.0, 0.55, -0.62), Vector3(0.30, 0.35, 0.40)],
	&"vital": [Vector3(0.0, 0.50, -0.25), Vector3(0.42, 0.40, 0.35)],
	&"body": [Vector3(0.0, 0.52, 0.15), Vector3(0.46, 0.46, 0.50)],
	&"rear": [Vector3(0.0, 0.50, 0.52), Vector3(0.42, 0.44, 0.30)],
}


static func scale_for_weight(weight_kg: float) -> float:
	return pow(maxf(weight_kg, 1.0) / REFERENCE_WEIGHT_KG, 1.0 / 3.0)


func setup(_type_id: StringName, _weight_kg: float) -> void:
	pass


func set_locomotion(_speed_mps: float) -> void:
	pass


func set_eating(_on: bool) -> void:
	pass


func set_wounded(_on: bool) -> void:
	pass


func set_highlight(_on: bool) -> void:
	pass


func play_alert() -> void:
	pass


func play_scrape() -> void:
	pass


func play_attack() -> void:
	pass


func play_hit(_zone: StringName) -> void:
	pass


func play_death() -> void:
	pass


static func create_fallback() -> BoarVisualBase:
	var v: BoarVisualBase = BoarVisualBase.new()
	v.name = "BoarVisualFallback"
	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.48, 0.55, 1.4)
	body.mesh = box
	body.position = Vector3(0.0, 0.5, 0.05)
	v.add_child(body)
	var head: Node3D = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.55, -0.62)
	v.add_child(head)
	return v
```

### `src/core/dog_visual_base.gd`
```gdscript
class_name DogVisualBase
extends Node3D
## Visual-only dog. Origin on the ground, forward -Z. Breed proportions are applied by the asset.


func setup(_breed_id: StringName) -> void:
	pass


func set_locomotion(_speed_mps: float) -> void:
	pass


func set_retreating(_on: bool) -> void:
	pass


func play_bark() -> void:
	pass


func play_bite(_on: bool) -> void:
	pass


func play_hurt() -> void:
	pass


func play_point() -> void:
	pass


static func create_fallback() -> DogVisualBase:
	var v: DogVisualBase = DogVisualBase.new()
	v.name = "DogVisualFallback"
	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.25, 0.3, 0.8)
	body.mesh = box
	body.position = Vector3(0.0, 0.45, 0.0)
	v.add_child(body)
	var mouth: Marker3D = Marker3D.new()
	mouth.name = "Mouth"
	mouth.position = Vector3(0.0, 0.5, -0.45)
	v.add_child(mouth)
	return v
```

### `src/core/hunter_visual_base.gd`
```gdscript
class_name HunterVisualBase
extends Node3D
## Visual-only third-person hunter: how a player is seen by the other players in multiplayer.
## Origin on the ground between the feet, forward -Z. Scale 1 = 1.78 m tall standing.
## Gameplay owns the root transform (position + yaw). The asset animates children only.
## Required children: Muzzle (Marker3D, follows the weapon tip), NameAnchor (Marker3D above the head).

const SLOT_COUNT: int = 4

## Identity color of each player slot. Single source for the model, name tag, minimap and lobby.
## Chosen to stand out against cerrado greens/browns and to stay apart from damage red.
const SLOT_COLORS: Array[Color] = [
	Color(0.93, 0.47, 0.13),   # 0 orange
	Color(0.20, 0.56, 0.90),   # 1 blue
	Color(0.96, 0.80, 0.18),   # 2 yellow
	Color(0.74, 0.36, 0.84),   # 3 purple
]


static func slot_color(slot: int) -> Color:
	return SLOT_COLORS[posmod(slot, SLOT_COUNT)]


var _fallback_body: MeshInstance3D = null   # set only by create_fallback()


func setup(slot: int, _weapon_id: StringName) -> void:   # cosmetic; called once before entering the tree
	if _fallback_body != null:   # fallback capsule: paint with the slot color
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = slot_color(slot)
		_fallback_body.material_override = mat


func set_weapon(_weapon_id: StringName) -> void:   # &"" = unarmed
	pass


func set_locomotion(_speed_mps: float) -> void:   # 0 = idle; called every frame
	pass


func set_crouching(_on: bool) -> void:
	pass


func set_aiming(_on: bool) -> void:   # weapon shouldered vs. carried low
	pass


func set_look_pitch(_pitch_rad: float) -> void:   # positive = looking up; bends torso/weapon
	pass


func play_fire() -> void:   # recoil kick + muzzle flash
	pass


func play_reload(_duration_s: float) -> void:
	pass


func play_hit() -> void:   # flinch when damaged
	pass


func play_death(_instant: bool = false) -> void:   # falls and freezes; instant = born fallen; ignores later calls
	pass


func get_muzzle() -> Node3D:
	return get_node_or_null(^"Muzzle") as Node3D


func get_name_anchor() -> Node3D:
	return get_node_or_null(^"NameAnchor") as Node3D


static func create_fallback() -> HunterVisualBase:
	var v: HunterVisualBase = HunterVisualBase.new()
	v.name = "HunterVisualFallback"
	var body: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.78
	body.mesh = capsule
	body.position = Vector3(0.0, 0.89, 0.0)
	v.add_child(body)
	v._fallback_body = body
	var muzzle: Marker3D = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.2, 1.35, -0.9)
	v.add_child(muzzle)
	var name_anchor: Marker3D = Marker3D.new()
	name_anchor.name = "NameAnchor"
	name_anchor.position = Vector3(0.0, 2.05, 0.0)
	v.add_child(name_anchor)
	return v
```

### `src/core/net_codec.gd`
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

### `src/core/net_peer_info.gd`
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

### `src/core/weapon_view_base.gd`
```gdscript
class_name WeaponViewBase
extends Node3D
## First-person weapon + arms. Child of the camera; camera space, looking -Z.
## Required children: Muzzle (Marker3D), AdsAnchor (Marker3D).


func setup(_weapon_id: StringName) -> void:
	pass


func play_fire() -> void:
	pass


func play_cycle(_duration_s: float) -> void:
	pass


func play_reload(_duration_s: float) -> void:
	pass


func play_draw(_duration_s: float) -> void:
	pass


func get_muzzle() -> Node3D:
	return get_node_or_null(^"Muzzle") as Node3D


func get_ads_anchor() -> Node3D:
	return get_node_or_null(^"AdsAnchor") as Node3D


static func create_fallback() -> WeaponViewBase:
	var v: WeaponViewBase = WeaponViewBase.new()
	v.name = "WeaponViewFallback"
	var barrel: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.05, 0.08, 0.9)
	barrel.mesh = box
	barrel.position = Vector3(0.2, -0.2, -0.6)
	barrel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(barrel)
	var muzzle: Marker3D = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.2, -0.2, -1.05)
	v.add_child(muzzle)
	var ads: Marker3D = Marker3D.new()
	ads.name = "AdsAnchor"
	ads.position = Vector3(0.2, -0.14, -0.4)
	v.add_child(ads)
	return v
```

### `src/core/map_environment_base.gd`
```gdscript
class_name MapEnvironmentBase
extends Node3D
## Sky, fog and sun of a map. Required children: WorldEnvironment, Sun (DirectionalLight3D).


func apply_quality(quality: StringName) -> void:
	var sun: DirectionalLight3D = get_node_or_null(^"Sun") as DirectionalLight3D
	if sun == null:
		return
	var presets: Dictionary = Data.get_game().get("quality_presets", {})
	var preset: Dictionary = presets.get(String(quality), {})
	sun.shadow_enabled = bool(preset.get("shadows", false))
	sun.directional_shadow_max_distance = float(preset.get("shadow_distance_m", 30.0))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL


static func create_fallback() -> MapEnvironmentBase:
	var root: MapEnvironmentBase = MapEnvironmentBase.new()
	root.name = "MapEnvironmentFallback"
	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env: Environment = Environment.new()
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	we.environment = env
	root.add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	root.add_child(sun)
	return root
```
O art-director sobrescreve `apply_quality` se quiser, mas deve chamar `super(quality)` ou reproduzir o efeito.

---

## Apêndice B — stub funcional de `Data` (Fase 0)

`src/systems/data_registry.gd` — o coordenador escreve isto; o game-systems estende (validação) sem mudar a API.
```gdscript
extends Node
## Autoload "Data": read-only access to data/*.json. See docs/arquitetura.md §6.2 and §9.

const FILES: Dictionary = {
	"game": "res://data/game.json",
	"weapons": "res://data/weapons.json",
	"equipment": "res://data/equipment.json",
	"dogs": "res://data/dogs.json",
	"boars": "res://data/boars.json",
	"maps": "res://data/maps.json",
	"gold": "res://data/gold_packages.json",
	"pix": "res://data/pix_config.json",
}
# file key -> list key inside the file
const LISTS: Dictionary = {
	"weapons": "weapons", "equipment": "items", "dogs": "dogs",
	"boars": "types", "maps": "maps", "gold": "packages",
}

var _raw: Dictionary = {}
var _index: Dictionary = {}   # file key -> { id String -> Dictionary }
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	reload()


func reload() -> void:
	_raw.clear()
	_index.clear()
	_errors.clear()
	for key: String in FILES:
		var path: String = FILES[key]
		var text: String = FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		if parsed is Dictionary:
			_raw[key] = parsed
		else:
			_raw[key] = {}
			_errors.append("Data: cannot read %s" % path)
	for key: String in LISTS:
		var by_id: Dictionary = {}
		for entry: Variant in _raw[key].get(LISTS[key], []):
			if entry is Dictionary and entry.has("id"):
				by_id[String(entry["id"])] = entry
		_index[key] = by_id
	for e: String in _errors:
		push_error(e)


func get_load_errors() -> PackedStringArray:
	return _errors


func get_game() -> Dictionary:
	return _raw.get("game", {})


func get_weapon(id: StringName) -> Dictionary:
	return _lookup("weapons", id)


func get_weapon_ids() -> Array[StringName]:
	return _ids("weapons")


func get_equipment(id: StringName) -> Dictionary:
	return _lookup("equipment", id)


func get_equipment_ids() -> Array[StringName]:
	return _ids("equipment")


func get_dog(id: StringName) -> Dictionary:
	return _lookup("dogs", id)


func get_dog_ids() -> Array[StringName]:
	return _ids("dogs")


func get_boar_type(id: StringName) -> Dictionary:
	return _lookup("boars", id)


func get_boar_type_ids() -> Array[StringName]:
	return _ids("boars")


func get_boar_rules() -> Dictionary:
	var rules: Dictionary = _raw.get("boars", {}).duplicate()
	rules.erase("types")
	return rules


func get_map(id: StringName) -> Dictionary:
	return _lookup("maps", id)


func get_map_ids() -> Array[StringName]:
	return _ids("maps")


func get_contract(map_id: StringName, index: int) -> Dictionary:
	var contracts: Array = get_map(map_id).get("contracts", [])
	if index < 0 or index >= contracts.size():
		push_error("Data: no contract %d in map %s" % [index, map_id])
		return {}
	return contracts[index]


func get_contract_count(map_id: StringName) -> int:
	return (get_map(map_id).get("contracts", []) as Array).size()


func get_gold_packages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in _raw.get("gold", {}).get("packages", []):
		if entry is Dictionary:
			out.append(entry)
	return out


func get_gold_package(id: StringName) -> Dictionary:
	return _lookup("gold", id)


func get_pix_config() -> Dictionary:
	return _raw.get("pix", {})


func get_item_def(id: StringName) -> Dictionary:
	for key: String in ["weapons", "equipment", "dogs"]:
		if _index.get(key, {}).has(String(id)):
			return _index[key][String(id)]
	return {}


func get_item_category(id: StringName) -> StringName:
	if _index.get("weapons", {}).has(String(id)):
		return &"weapon"
	if _index.get("equipment", {}).has(String(id)):
		return &"equipment"
	if _index.get("dogs", {}).has(String(id)):
		return &"dog"
	return &""


func _lookup(key: String, id: StringName) -> Dictionary:
	var by_id: Dictionary = _index.get(key, {})
	if not by_id.has(String(id)):
		push_error("Data: unknown id '%s' in %s" % [id, key])
		return {}
	return by_id[String(id)]


func _ids(key: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: Variant in _raw.get(key, {}).get(LISTS[key], []):
		if entry is Dictionary and entry.has("id"):
			out.append(StringName(entry["id"]))
	return out
```

Stubs dos demais autoloads: um `extends Node` (sem `class_name`) com cada função da §6.3, §4, §7.8 e §6.6,
corpo devolvendo o valor "stub" indicado (ou o default do tipo: `0`, `false`, `""`, `&""`, `[]`, `{}`,
`null`), e `Router.goto` já funcional (`get_tree().paused = false` +
`get_tree().call_deferred("change_scene_to_file", scene_path)`).
