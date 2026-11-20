# Caçada ao Javali — Horda: correções e Nível 2 (plano e contrato)

Versão do contrato: **horda 2.0** (jogo **0.9.0**) · complementa `docs/horda.md` (1.0), `docs/arquitetura.md` e
`docs/multiplayer.md`. Onde este documento contradiz `horda.md`, vale este. **Modo contrato: nenhum comportamento muda**
(todo código novo roda só com `is_horde()`). **Horda Nível 1** = regras de hoje (munição infinita, sem levantar, sem
limite de cercado) + correções C1–C3. **Nível 2** = C1–C3 + regras novas N1–N4.

Regras de sempre: mínimo necessário, nada de API inventada, relatar contrato errado. Identificadores em inglês, texto do
jogador em PT-BR exatamente como na §9.

---

## 1. Diagnóstico e solução das correções

### C1 — O tiro não atravessa a cerca

**Causa.** Cada `fence_segment` é um `PropSpawn` com `collision_size (4, 1,3, 0,15)`
(`src/world/maps/mato_grosso/mato_grosso_map.tscn:116–565`). `MapRoot.build_props_and_water` cria uma caixa cheia na
camada `Layers.STATIC` (`src/world/map_root.gd:198–210`), e `Layers.MASK_WEAPON_RAY = TERRAIN|STATIC|BOAR_HITZONE`
(`src/core/layers.gd:11`) é a máscara do raio (`src/weapons/hitscan.gd:9–13`). A cerca é uma parede de 1,3 m para a bala
(`weapon.gd:219` toca `impact_wood`) e também para a linha de visão do javali (`layers.gd:12`).

**Solução.** Camada nova `fence` (bit 5, valor 16). Em horda a caixa da cerca vai **só** para `FENCE`:
- `MASK_PLAYER_BODY` passa a incluir `FENCE` → a cerca continua barrando o jogador (sem pulo no jogo, 1,3 m não se passa).
- `MASK_WEAPON_RAY` e `MASK_LINE_OF_SIGHT` **não** incluem `FENCE` → bala e olhar passam pela cerca inteira.
- Mourões **não** param a bala: são ~0,1 m a cada 4 m (< 3% da área), e mourões com colisão própria custariam ~60 formas
  (orçamento de 400). Decisão: a cerca é transparente ao tiro.
- Javalis e cães não mudam: não têm corpo e a cerca tem `footprint_radius_m = 0` (já passam por ela hoje).
- Modo contrato: a cerca fica em `STATIC` como hoje (ver Q2).

### C2 — Os javalis entram no milho e o jogador não os vê

**Causa.** Em horda `Boar._enter_to_crop` mira direto o ponto de comer (`src/boars/boar.gd:703–708`, H2) e
`_tick_to_crop` faz `seek` em linha reta (`boar.gd:714–721`). O `ObstacleGrid` só conhece círculos
(`src/world/obstacle_grid.gd`) e a lavoura não é obstáculo. O milho (`mato_grosso_map.tscn:37–41`, centro (55, 20),
56 × 70 m, alto) fica entre `Spawn1` (20, 115) / `Spawn2` (105, 95) e o celeiro (38, −88): as duas retas cruzam o milharal.

**Solução escolhida: a rota contorna a lavoura.** Plano de rota com desvio por quinas de retângulos
(`HordeRoute.plan`, §4.4), calculado uma vez a cada `_enter_to_crop` (≤ 14 nós, custo desprezível). Retângulos evitados
= lavouras com `crop` em `route_avoid_crops` (seed `["corn"]`) crescidas `route_crop_margin_m` + o galpão do celeiro
(§1 C3). Com o seed, quem nasce em `Spawn1` desce pelo corredor da estrada entre soja e milho (x ≈ 21) e quem nasce em
`Spawn2` contorna pelo leste (x ≈ 89): duas linhas de chegada previsíveis e visíveis.
Rejeitados: milho baixo/transparente perto (mexe no MultiMesh da lavoura e no visual em todos os modos), silhueta através
do milho (shader/segundo passe por javali, caro em WebGL2), lavoura como obstáculo circular (círculos grandes prendem o
steering local). Javali que investe contra um caçador dentro do milho continua podendo entrar nele (R7).

### C3 — O jogador não entra no celeiro

**Causa.** O `PropSpawn` do celeiro tem `collision_size (16, 7, 10)` (`mato_grosso_map.tscn:88–93`): uma caixa cheia
(`map_root.gd:198–210`) sobre um galpão que o visual deixa aberto em −Z (`assets/models/props/barn_hd.gd:2–7`). O
obstáculo de steering é um círculo de raio 8 (`map_root.gd:211–213`) que cobre o interior todo.

**Solução (só em horda, via `MapRoot.set_horde_layout(true)`).**
- `PropSpawn` ganha `horde_collision_boxes: Array[AABB]` e `horde_obstacle_circles: PackedVector3Array` (referencial
  local do marcador). Em horda, se não vazios, substituem `collision_size` e `footprint_radius_m` **só** para colisão e
  steering; achatamento do terreno e exclusão de flora continuam usando `footprint_radius_m` (layout idêntico).
- Caixas do celeiro (local, `AABB(pos_min, size)`; frente aberta em −Z), 10 formas num único `StaticBody3D` `STATIC`:

| Peça | AABB |
|---|---|
| parede do fundo | `AABB(-8.0, 0.0, 4.76, 16.0, 5.1, 0.2)` |
| oitão oeste / leste | `AABB(-8.0, 0.0, -4.85, 0.2, 5.1, 9.76)` / `AABB(7.8, 0.0, -4.85, 0.2, 5.1, 9.76)` |
| telhado (bloco do beiral à cumeeira) | `AABB(-8.4, 4.9, -5.4, 16.8, 2.1, 10.8)` |
| esteios da frente x = −3,8 / 0 / 3,8 | `AABB(x-0.14, 0.0, -4.84, 0.28, 4.9, 0.28)` |
| tulha (caixa de grãos do estoque) | `AABB(-6.0, 0.0, 1.6, 12.0, 1.2, 3.1)` |
| fardos (frente-esquerda) | `AABB(-7.4, 0.0, -4.2, 1.2, 1.55, 1.45)` |
| cerca da baia (direita) | `AABB(6.2, 0.0, -4.1, 0.2, 1.7, 6.2)` |

- Círculos de steering do celeiro em horda (local `x, z, r`), 16 no total: fundo/tulha (−6, 3,2, 1,8), (−3, 3,2, 1,8),
  (0, 3,2, 1,8), (3, 3,2, 1,8), (6, 3,2, 1,8); quinas do fundo (−7,4, 4,0, 1,2), (7,4, 4,0, 1,2); oitões (±7,5, z, 0,9)
  com z ∈ {−4, −2, 0, 2}; fardos (−6,85, −3,5, 0,9). Javali que investe pode entrar no corredor da frente (z −4,7…1,6):
  o celeiro **não** é refúgio.
- **Estoque de milho dentro:** vira uma **tulha** de madeira (caixa x ±6, z 1,6…4,7, parede 1,2 m) cheia de milho, no
  `barn_corn.tscn` (só existe em horda). Os estágios baixam o milho dentro da tulha sem mudar a pegada, então a colisão
  fixa da tulha bate com o visual em todo estágio. O corredor da frente fica livre para andar e para as caixas de cartucho.
- **Anel onde os javalis comem:** não muda (raio `eat_ring_m` 10 m, §5.6 de `horda.md`). Todo círculo novo termina a
  ≤ 9,6 m da origem e o retângulo do galpão (16 × 10) não contém ponto do anel.
- Rota (C2): o galpão é retângulo evitado com **saída** pela frente (local (0, −`collision_size.z`/2 − `route_corner_out_m`)):
  javali dentro dele sai pela abertura antes de seguir.

### Item 4 — Som de início de onda (registro, sem agente)

A coordenação gera `assets/audio/sfx/horde_wave_start.mp3` (sirene, ElevenLabs) e atualiza o prompt em
`assets/audio/sfx_prompts.json`. MP3 gravado é o padrão aceito (`arquitetura.md` §7.8); o `Sfx` já o prefere à síntese.
Nenhum código muda (o HUD já toca `horde_wave_start`). Nenhum agente mexe nesse id.

---

## 2. Regras do Nível 2

| # | Regra | Decisão |
|---|---|---|
| N1 | Munição contada | Cada arma começa com o pente cheio + `start_reserve_mags` pentes de reserva (× `reserve_mult` do equipamento `extra_ammo`), teto `reserve_cap_mags` pentes. Caixas de cartucho **genéricas** dentro do celeiro: cada uma dá `mags_per_crate` pentes a **todas** as armas carregadas, até o teto. Coleta **com botão** (Q4): um aperto de `interact` (F; no toque o botão "Pegar") ao lado de uma caixa, só se alguma arma estiver abaixo do teto e sem aliado caído ao alcance (aí `interact` levanta). A caixa some para todos e reaparece depois de `respawn_s`. Anfitrião é a autoridade. |
| N2 | Ninguém sai do cercado | Retângulo da cerca (`MapRoot.get_farm_rect()`, (−20, −110)–(55, −62)) encolhido `confine.inset_m`. O `Player` prende a própria posição XZ depois do `move_and_slide` (cobre a porteira, que não tem colisão, `mato_grosso_map.tscn:109–114`). Cada máquina prende o seu jogador. Nascimento dentro: `player_spawn` (30, −74, yaw 180°), espalhado por slot como hoje. |
| N3 | Javalis mais agressivos | Sobrescritas por tipo (`boar_overrides`) aplicadas sobre `data/boars.json`, lidas pelo anfitrião (`Boar`) **e** pelo cliente (`BoarPuppet`, dano da investida). Leitão continua nunca investindo. H1–H7 de `horda.md` §6 não mudam. |
| N4 | Caído / levantar | Com `revive.enabled` e ≥ 2 caçadores na caçada, vida 0 = **caído** (não morto). Caído: `is_alive() == false` (javalis, cão e fim de jogo o tratam como fora), `is_downed() == true`, câmera no chão, só olha e pausa. Um aliado vivo a ≤ `radius_m` segura `interact` (F / botão "Levantar") por `hold_s` → volta com `health` (50). Sem ajuda em `bleed_out_s` (60 s) → morte de vez (`player_died`, espectador como hoje). Todos fora de ação (caídos ou mortos) = `DEFEAT_DEATH` (regra de hoje, sem mudança de código). Sala de 1 jogador: não cai, morre (Q5). |

Agressividade do seed (sobre `boars.json`):

| Tipo | Campo: hoje → Nível 2 |
|---|---|
| `piglet` | nenhum (não investe) |
| `sow` | `aggression` defend_in_herd → **provoked**; `aggro_radius_m` 6 → 10; `max_charges` 1 → 2; `charge_damage` 15 → 18; `charge_telegraph_s` 0,8 → 0,6; `recover_s` 1,2 → 1,0 |
| `boar` | `aggro_radius_m` 12 → 18; `max_charges` 3 → 4; `charge_damage` 25 → 30; `charge_speed_mps` 10 → 11; `charge_telegraph_s` 0,8 → 0,6; `recover_s` 1,5 → 1,1 |
| `alpha` | `aggro_radius_m` 25 → 35; `charge_damage` 40 → 45; `charge_telegraph_s` 0,8 → 0,6; `recover_s` 1,8 → 1,4 |
| todos | `to_barn_speed_frac` 0,8 → 0,9 (via `overrides`) |

---

## 3. Dados — `data/horde.json` versão 2 (dono: game-systems)

Migração: o arquivo passa a `"version": 2`; `Data` aceita **só** a versão 2 (o arquivo é do repositório, nenhum save
depende dele). Todos os campos de topo da v1 (`horda.md` §3.1) continuam, com o mesmo significado, e valem para todos os
níveis. Campos de topo novos (correções, todos os níveis):

| Campo | Tipo | Seed | Uso |
|---|---|---|---|
| `route_avoid_crops` | string[] | `["corn"]` | `crop` de `CropField` que a rota contorna (C2) |
| `route_crop_margin_m` | float ≥ 0 | 4.0 | margem somada a cada lavoura evitada |
| `route_corner_out_m` | float > 0 | 2.0 | distância das quinas de desvio e da saída do galpão |
| `route_waypoint_arrive_m` | float > 0 | 3.0 | chegou ao ponto de desvio → próximo |
| `levels` | array ≥ 1 | 2 entradas | ordem = número do nível (`levels[i].level == i + 1`) |

Cada nível (todas as chaves obrigatórias, tipos exatos):

| Chave | Tipo / regra |
|---|---|
| `level` | int = índice + 1 |
| `name`, `description` | string PT-BR (lobby e resultado) |
| `overrides` | dict; chaves permitidas: `first_wave_delay_s`, `intermission_s`, `barn_drain_mult`, `to_barn_speed_frac`, `player_count_mult`, `extra_group_delay_s`, `kill_reward_mult`, `victory_bonus_money`, `waves` (mesmos tipos/regras do topo) |
| `ammo` | `{"infinite": bool, "start_reserve_mags": int ≥ 0, "reserve_cap_mags": int ≥ 0}`; `infinite == false` exige `reserve_cap_mags ≥ max(1, start_reserve_mags)` |
| `ammo_crates` | `{"positions": [[x, z], …] (local do celeiro, ≤ 8), "mags_per_crate": int ≥ 0, "respawn_s": float ≥ 0, "pickup_radius_m": float ≥ 0, "claim_tolerance_m": float ≥ 0, "claim_retry_s": float ≥ 0}`; `positions` não vazio exige `mags_per_crate ≥ 1`, `pickup_radius_m > 0`, `claim_retry_s > 0` |
| `confine` | `{"enabled": bool, "inset_m": float ≥ 0, "hint_s": float > 0, "hint_interval_s": float > 0}` |
| `player_spawn` | `[]` (usa `PlayerSpawn` do mapa) ou `[x, z, yaw_deg]` |
| `revive` | `{"enabled": bool, "health": float, "hold_s": float, "radius_m": float, "bleed_out_s": float ≥ 0 (0 = sem limite), "claim_tolerance_m": float ≥ 0, "retry_s": float ≥ 0}`; `enabled` exige `0 < health ≤ player.max_health`, `hold_s > 0`, `radius_m > 0`, `retry_s > 0` |
| `boar_overrides` | dict `type_id → {campo: valor}`; `type_id` de `boars.json`; campos permitidos: `aggression` (`never`/`defend_in_herd`/`provoked`/`always`), `aggro_radius_m`, `max_charges`, `charge_damage`, `charge_speed_mps`, `charge_telegraph_s`, `recover_s`, `run_speed_mps`, `vision_range_m`, `alert_time_s` (números ≥ 0) |

Validação (`get_load_errors()`): as regras 1–4 de `horda.md` §3.1 rodam **sobre cada nível resolvido** (topo + `overrides`),
inclusive o teto de 255 ids; mais as regras da tabela acima.

Seed (a parte nova; o topo v1 fica igual, só `version` muda):
```json
  "version": 2,
  "route_avoid_crops": ["corn"],
  "route_crop_margin_m": 4.0,
  "route_corner_out_m": 2.0,
  "route_waypoint_arrive_m": 3.0,
  "levels": [
    {"level": 1, "name": "Nível 1",
     "description": "Defendam o celeiro de milho contra ondas de javalis. Todas as armas liberadas, munição sem fim. Se a horda comer o milho ou derrubar todos os caçadores, acabou.",
     "overrides": {},
     "ammo": {"infinite": true, "start_reserve_mags": 0, "reserve_cap_mags": 0},
     "ammo_crates": {"positions": [], "mags_per_crate": 0, "respawn_s": 0.0, "pickup_radius_m": 0.0, "claim_tolerance_m": 0.0, "claim_retry_s": 0.0},
     "confine": {"enabled": false, "inset_m": 0.0, "hint_s": 2.5, "hint_interval_s": 5.0},
     "player_spawn": [],
     "revive": {"enabled": false, "health": 0.0, "hold_s": 0.0, "radius_m": 0.0, "bleed_out_s": 0.0, "claim_tolerance_m": 0.0, "retry_s": 0.0},
     "boar_overrides": {}},
    {"level": 2, "name": "Nível 2",
     "description": "Munição contada: os cartuchos estão no celeiro. Ninguém sai do cercado da fazenda, os javalis investem mais, e quem cair pode ser levantado por um companheiro.",
     "overrides": {"to_barn_speed_frac": 0.9, "kill_reward_mult": 0.5, "victory_bonus_money": 5000},
     "ammo": {"infinite": false, "start_reserve_mags": 2, "reserve_cap_mags": 6},
     "ammo_crates": {"positions": [[-3.0, -2.0], [0.0, -2.0], [3.0, -2.0]], "mags_per_crate": 2, "respawn_s": 60.0, "pickup_radius_m": 1.5, "claim_tolerance_m": 3.0, "claim_retry_s": 1.0},
     "confine": {"enabled": true, "inset_m": 0.6, "hint_s": 2.5, "hint_interval_s": 5.0},
     "player_spawn": [30.0, -74.0, 180.0],
     "revive": {"enabled": true, "health": 50.0, "hold_s": 4.0, "radius_m": 2.0, "bleed_out_s": 60.0, "claim_tolerance_m": 3.0, "retry_s": 1.0},
     "boar_overrides": {
       "sow": {"aggression": "provoked", "aggro_radius_m": 10.0, "max_charges": 2, "charge_damage": 18.0, "charge_telegraph_s": 0.6, "recover_s": 1.0},
       "boar": {"aggro_radius_m": 18.0, "max_charges": 4, "charge_damage": 30.0, "charge_speed_mps": 11.0, "charge_telegraph_s": 0.6, "recover_s": 1.1},
       "alpha": {"aggro_radius_m": 35.0, "charge_damage": 45.0, "charge_telegraph_s": 0.6, "recover_s": 1.4}}}
  ]
```
Vetores de teste: N1 com `extra_ammo` ausente → reserva inicial `.22` 20, demais 10; teto `.22` 60, demais 30. Nível 2:
macho 132 kg, vitais, um tiro → `round(132 × 2,5 × 1,25 × 1,5 × 0,5)` = **R$ 309**; bônus com 87% → `round(5000 × 0,87)`
= **R$ 4350**. Nível 1: R$ 217 / R$ 2610 (iguais a hoje).

### 3.1 API do `Data` e do `Profile` (game-systems)

```gdscript
# Data
func get_horde_level_count() -> int                      # levels.size(); 0 sem horda válida
func get_horde_level(level: int) -> Dictionary           # nível resolvido: cópia do topo (sem "levels") com "overrides" aplicados,
                                                         # mais as chaves do nível (level, name, description, ammo, ammo_crates,
                                                         # confine, player_spawn, revive, boar_overrides). {} fora de 1..count
func get_horde_boar_type(type_id: StringName, level: int) -> Dictionary   # get_boar_type(type_id) com boar_overrides do nível
                                                         # aplicados (cópia); level 0 ou fora do intervalo = get_boar_type(type_id)
# Profile (parâmetro novo no fim, opcional: chamadas de hoje não mudam)
func horde_kill_reward(type_id: StringName, weight_kg: float, killing_zone: StringName, one_shot: bool, level: int = 1) -> int
func horde_bonus(stock_pct: float, level: int = 1) -> int
```
`get_horde()` continua devolvendo o arquivo inteiro (uso do `Net._horde_available` e testes antigos).

---

## 4. Contrato de código

### 4.1 `src/core/` — acréscimos (coordenação aplica; ninguém mais edita)

| Arquivo | Acréscimo (verbatim) |
|---|---|
| `layers.gd` | `const FENCE: int = 16`; `MASK_PLAYER_BODY = TERRAIN \| STATIC \| FENCE` (19). `MASK_WEAPON_RAY` e `MASK_LINE_OF_SIGHT` não mudam |
| `game_events.gd` | `signal player_downed(bleed_out_s: float)` (A Player → A Hud; local); `signal player_revived(health: float)` (A Player → A Hud; local); `signal hunter_downed(slot: int)` (B HuntController → A Hud/Spectator); `signal hunter_revived(slot: int, by_slot: int)` (B HuntController → A Hud); `signal ammo_picked_up(rounds: int)` (A Player → A Hud; local) |
| `hunt_request.gd` | `var horde_level: int = 1` (só em horda); `make_debug(p_map_id = &"mato_grosso", p_contract_index = 0, p_mode = &"contract", p_horde_level: int = 1)` grava `horde_level` |
| `hunt_result.gd` | `var horde_level: int = 0` (0 no contrato); `to_dict()` ganha `"horde_level"` |
| `player_base.gd` | `func is_downed() -> bool` (false); `func revive(_health: float) -> void` (pass); `func get_bleed_out_left_s() -> float` (0.0); `func needs_ammo() -> bool` (false); `func add_ammo_mags(_mags: int) -> int` (0); `func get_revive_target_slot() -> int` (-1); `func get_revive_progress() -> float` (0.0); bot: `func bot_set_interact(_held: bool) -> void` (pass); Q4: `func get_ammo_crate_target() -> int` (-1) |
| `hunt_world.gd` | `func get_horde_level() -> int` (0); `func get_player_bounds() -> Rect2` (`Rect2()` = sem limite); `func request_revive(_target_slot: int) -> void` (pass); `func get_ammo_crate_positions() -> PackedVector3Array` (vazio); Q4: `func get_ammo_crate_in_reach(_at: Vector3) -> int` (-1); `func request_ammo_crate(_crate: int) -> void` (pass) |
| `net_codec.gd` | `const HF_DOWNED: int = 128`; `const EV_HUNTER_REVIVED: int = 0x2D`; `const EV_AMMO_CRATE: int = 0x2E`; `const C_REVIVE: int = 0x45`; `const C_AMMO_CRATE: int = 0x46` |
| `scene_paths.gd` | `const AMMO_CRATE: String = "res://assets/models/props/ammo_crate.tscn"` |

Coordenação também: `project.godot` `layer_names/3d_physics/layer_5="fence"`; `docs/arquitetura.md` §3.1 (linha da camada
5) e Apêndice A; `config/version = "0.9.0"` antes de publicar.

### 4.2 Getters e semântica (B implementa no `HuntController`)

| Getter | Horda | Contrato |
|---|---|---|
| `get_horde_level()` | `clampi(request.horde_level, 1, Data.get_horde_level_count())` (fora do intervalo: `push_warning`) | 0 |
| `get_player_bounds()` | `confine.enabled`: `_map.get_farm_rect().grow(-confine.inset_m)`; senão `Rect2()` | `Rect2()` |
| `request_revive(slot)` | offline: nada; anfitrião: `_host_revive(slot, local_slot)`; cliente: enfileira `C_REVIVE` | nada |
| `get_ammo_crate_positions()` | posições (Y = chão) das caixas disponíveis | vazio |
| `get_ammo_crate_in_reach(at)` | caixa disponível mais próxima a ≤ `pickup_radius_m` (XZ) de `at`; -1 = nenhuma | -1 |
| `request_ammo_crate(crate)` | aperto de `interact` do jogador local: offline/anfitrião pega, cliente enfileira `C_AMMO_CRATE` | nada |

`HuntResult.horde_level = get_horde_level()` em horda. Economia: `Profile.horde_kill_reward(..., get_horde_level())` e
`Profile.horde_bonus(pct, get_horde_level())`. Toda leitura de config de horda no B passa de `Data.get_horde()` para
`Data.get_horde_level(get_horde_level())` (`eat_ring_m`, `max_carcasses`, `barn_drain_mult`, plano de ondas, etc.).

### 4.3 `MapRoot` / `PropSpawn` (B, `src/world/`)

```gdscript
# PropSpawn
@export var horde_collision_boxes: Array[AABB] = []          # local; horde layout: replace collision_size
@export var horde_obstacle_circles: PackedVector3Array = PackedVector3Array()   # local (x, z, r); horde: replace footprint
# MapRoot
func set_horde_layout(on: bool) -> void       # antes de build_props_and_water; false = comportamento de hoje
func get_farm_rect() -> Rect2                 # XZ da cerca (centros dos fence_segment/gate); Rect2() sem cerca; válido após build_props_and_water
func get_horde_route_obstacles(avoid_crops: Array, crop_margin_m: float, corner_out_m: float) -> Array[Dictionary]
	# [{"rect": Rect2, "exit": Vector2}] — lavouras com crop em avoid_crops (rect crescido crop_margin_m, exit Vector2.INF)
	# + cada PropSpawn com horde_collision_boxes (rect = XZ das caixas transformadas; exit = marcador +
	#   basis × (0, 0, -(collision_size.z / 2 + corner_out_m)))
```
Com `set_horde_layout(true)`: (1) caixas de `horde_collision_boxes` num `StaticBody3D` `Body` (`STATIC`), uma forma por
caixa, contadas no orçamento; (2) círculos de `horde_obstacle_circles` no `ObstacleGrid` no lugar de `footprint_radius_m`;
(3) corpos de `FENCE_IDS` com `collision_layer = Layers.FENCE`. Exclusão de flora e achatamento: inalterados.
O `HuntController` chama `set_horde_layout(is_horde())` antes de `build_props_and_water()` e guarda
`horde_route_obstacles: Array[Dictionary]` (membro interno de B) logo depois.

### 4.4 Rota (B, `src/boars/horde_route.gd`, `class_name HordeRoute extends RefCounted`)

```gdscript
static func plan(from: Vector2, to: Vector2, obstacles: Array[Dictionary], corner_out_m: float) -> PackedVector2Array
	# pontos a seguir, sem `from`, terminando em `to`
```
Regras: segmento bloqueado = cruza o **interior aberto** de algum `rect` (tocar a borda não bloqueia; ε 1e-4). Nós: `from`,
as 4 quinas de `rect.grow(corner_out_m)` de cada obstáculo na ordem (min.x,min.y), (max.x,min.y), (max.x,max.y),
(min.x,max.y), depois `to`; quina dentro de outro `rect` sai. Menor caminho (Dijkstra, empate = menor índice de nó).
`from` dentro de um obstáculo com `exit` ≠ INF → o 1º ponto é `exit` e o planejamento segue a partir dele; sem `exit` →
esse obstáculo é ignorado. `to` dentro de um obstáculo → esse obstáculo é ignorado. Sem caminho → `[to]`.
Vetores (só o milho, `Rect2(23, -19, 64, 78)`, `corner_out_m` 2): de (105, 95) para (38, −88) → `[(89, -21), (38, -88)]`;
de (20, 115) → `[(21, -21), (38, -88)]`; sem obstáculo → `[to]`.

`Boar` em horda: `_enter_to_crop` faz `_route = HordeRoute.plan(get_xz(), eat_point, _world.horde_route_obstacles,
route_corner_out_m)`; `_tick_to_crop` segue `_route[_route_i]`, avança quando a distância < `route_waypoint_arrive_m`
(exceto o último, que usa `ARRIVE_M` como hoje). Fora de horda: nada muda.

### 4.5 Agressividade (B)

`Boar.setup` lê o tipo com `Data.get_horde_boar_type(type_id, _world.get_horde_level())` (contrato: nível 0 = tipo puro;
mover a leitura de `_horde` para antes de `_read_type`). `BoarPuppet` (cliente) lê `charge_damage` do mesmo jeito.
`_to_barn_frac` = `get_horde_level(nível).to_barn_speed_frac`. Nenhuma regra nova de FSM.

### 4.6 Munição (A, `Player`; B, caixas)

`Player.setup` em horda com `ammo.infinite == false`: `Weapon.setup(id, reserve_mult, false)` e depois
`ammo_reserve = roundi(mag_size × start_reserve_mags × reserve_mult)`. `has_infinite_reserve()` = horda **e**
`ammo.infinite`. `needs_ammo()` = alguma arma com `ammo_reserve < mag_size × reserve_cap_mags` (infinita: false).
`add_ammo_mags(mags)`: por arma, soma `mini(mags × mag_size, cap − ammo_reserve)` se > 0; emite `ammo_changed` das
armas mudadas, `GameEvents.ammo_picked_up(total)` e `Sfx.play(&"ammo_pickup")` se total > 0; devolve o total.

Caixas — `HordeAmmoCrates` (`src/hunt/horde_ammo_crates.gd`, `extends Node3D`, interno de B, nome `AmmoCrates`, filho do
`HuntController`, só se `positions` não vazio). Posição = transform do `PropSpawn` do celeiro × (x, 0, z), Y =
`get_height`. Visual por caixa: `AssetLoader.instantiate(ScenePaths.AMMO_CRATE)` ou `FallbackMeshes.box(Vector3(0.6,
0.35, 0.4), Color("#4F5B2E"))`; `visible` = disponível. Sem colisão. **Pega com botão (Q4)**, nunca por proximidade:
o `Player` calcula a cada quadro `get_ammo_crate_target()` = `world.get_ammo_crate_in_reach(posição)` se vivo, com
`needs_ammo()` e sem alvo de levantar (senão -1). Um **aperto** de `interact` (borda: estava solto e foi apertado; segurar
não repete; o bot conta `bot_set_interact(true)` mesmo que dure um quadro) com alvo ≥ 0 chama
`world.request_ammo_crate(alvo)`, que revalida (vivo, `needs_ammo()`, disponível, ≤ `pickup_radius_m`):
- offline/anfitrião: caixa indisponível, `respawn_at = agora + respawn_s`, `add_ammo_mags(mags_per_crate)`; anfitrião
  enfileira `EV_AMMO_CRATE(crate, 0, slot local)`;
- cliente: enfileira `C_AMMO_CRATE(crate)` no máximo a cada `claim_retry_s` por caixa (nada muda localmente até o evento).
O reaparecimento (anfitrião/offline) segue num tique de 10 Hz.
Anfitrião em `C_AMMO_CRATE` de `s`: caixa disponível, caçador `s` vivo e a ≤ `pickup_radius_m + claim_tolerance_m` →
indisponível, `EV_AMMO_CRATE(crate, 0, s)`; senão ignora. Reaparecer (anfitrião/offline): `EV_AMMO_CRATE(crate, 1, 255)`.
Cliente em `EV_AMMO_CRATE`: aplica disponibilidade; se `available == 0` e `taker == slot local` → `add_ammo_mags`.

### 4.7 Caído e levantar (A: `Player`/`RemoteHunter`; B: validação e rede)

Estados do `Player` (dono = máquina do jogador): **vivo** → (vida 0, `revive.enabled`, `world.get_hunters().size() ≥ 2`)
→ **caído** → (`revive`) → vivo; caído → (`bleed_out_s > 0` esgotado) → **morto**. Sem as condições: vivo → morto (hoje).

| | `is_alive()` | `is_downed()` | Flags `HUNTER_STATE` | Sinais locais |
|---|---|---|---|---|
| vivo | true | false | `HF_ALIVE` | — |
| caído | false | true | `HF_DOWNED` (sem `HF_ALIVE`) | ao cair: `player_downed(bleed_out_s)` + `Sfx player_death` |
| morto | false | false | nenhum dos dois | `player_died` (como hoje; espectador, faixa de morte) |

Caído: câmera desce a 0,45 m e rola 20° (constantes de A), pode olhar (`_can_look` aceita caído) e pausar; mover, atirar,
mirar, recarregar, trocar arma, itens e cão ficam fechados; arma escondida; `apply_damage` ignora. `revive(health)` só age
caído: vida = `health`, volta tudo, `player_revived(health)` + `Sfx revive_done`.
Quem levanta (vivo): alvo = caçador `is_downed()` mais próximo a ≤ `radius_m` (XZ). Segurando `interact` com alvo:
progresso += `delta / hold_s`; movimento zerado; tiro/mira/recarga/troca bloqueados. Soltou, alvo saiu do raio ou deixou de
estar caído → 0. Chegou a 1 → `world.request_revive(alvo)`, progresso 0, mesmo alvo ignorado por `retry_s`.
`get_revive_target_slot()` / `get_revive_progress()` expõem isso ao HUD.

B — `_host_revive(target, by)`: horda com `revive.enabled`; `get_hunter(target).is_downed()`; `get_hunter(by).is_alive()`;
distância XZ ≤ `radius_m + claim_tolerance_m` → se `target` é o jogador local, `_player.revive(revive.health)`; enfileira
`EV_HUNTER_REVIVED(target, by)`; emite `hunter_revived(target, by)`. Cliente em `EV_HUNTER_REVIVED`: se `target` = slot
local → `_player.revive(revive.health)`; emite `hunter_revived(target, by)`. `revive` fora do estado caído é no-op (corrida
com o sangramento: fica morto).
`_track_deaths` (todas as máquinas, por polling): vivo → apaga o slot de `_downed_slots` em silêncio; `is_downed()` e não
marcado → marca e emite `hunter_downed(slot)`; não vivo e não caído e não em `_dead_slots` → `hunter_died(slot)` (hoje).
`_all_hunters_dead()` **não muda** (caído não é vivo). `_on_player_died` (offline) **não muda** (só morte de vez).

`RemoteHunter`: `is_downed()` = `HF_DOWNED` do último estado; `HF_ALIVE` caiu → `play_death()` (hoje); `HF_ALIVE` voltou
depois de cair → troca o filho `Visual` por instância nova (`setup`, `set_weapon`), sem mudar `HunterVisualBase`. Rótulo
do nome: `"%s (caído)"` enquanto caído.

### 4.8 Rede (B escreve/lê; nada muda no `Net` para os registros de jogo)

| Registro | Dir. | Pista | Quando | Corpo | Bytes |
|---|---|---|---|---|---|
| `EV_HUNTER_REVIVED` `0x2D` | H→C | E | por levantada aceita | `target_slot u8, by_slot u8` | 2 |
| `EV_AMMO_CRATE` `0x2E` | H→C | E | caixa pega / reaparece; repetição F8 | `crate u8, available u8 (0/1), taker_slot u8 (255 = ninguém)` | 3 |
| `C_REVIVE` `0x45` | C→H | E | por levantada completa | `target_slot u8` | 1 |
| `C_AMMO_CRATE` `0x46` | C→H | E | por pedido de caixa | `crate u8` | 1 |
| `HUNTER_STATE.flags` b7 | — | — | — | `HF_DOWNED` (128); 14 bytes, nenhum byte novo | — |

Corpo menor que o esperado → ignora. `Net` já despacha `0x21..0x3F` ao cliente e `> 0x40` ao anfitrião
(`net_session.gd:1475,1489`). `HuntHostSync`: `queue_hunter_revived(target_slot: int, by_slot: int)`,
`queue_ammo_crate(crate: int, available: bool, taker_slot: int)`, `write_ammo_crate_replay(out: StreamPeerBuffer, crate:
int, available: bool)`. `HuntReplica`: `signal hunter_revived_received(target_slot: int, by_slot: int)`,
`signal ammo_crate_received(crate: int, available: bool, taker_slot: int)`, `func queue_revive_claim(target_slot: int)`,
`func queue_ammo_crate_claim(crate: int)` (mesma fila e descarte em reconexão dos outros `C_*`).
`EV_FULL_SYNC` em horda com caixas: depois do `EV_HORDE_WAVE`, um `EV_AMMO_CRATE(crate, estado, 255)` por caixa, antes do
`EV_HUNT_END`, contados em `n_records` (≤ 8 × 6 B). Caído/vivo chega pelo snapshot. `H_SNAPSHOT` sem byte novo.

**Sala (Pacote N):** `L_LOBBY` ganha `horde_level u8` depois de `mode` (6+4n); `L_START` ganha `horde_level u8` na posição
`9 + net.max_players` (14). Ausente, 0 ou > `Data.get_horde_level_count()` → 1.
```gdscript
func host_select_horde_level(level: int) -> bool   # anfitrião, LOBBY, 1..Data.get_horde_level_count(); mudou: L_LOBBY + roster_changed
func get_selected_horde_level() -> int             # (1) volta a 1 em create_room/join_room/leave_room
```
`_fill_request`: `request.horde_level = <nível da sala>` (sempre; só tem efeito em horda). `PROTOCOL_VERSION` continua 1;
`config/version` 0.9.0 separa as salas.

### 4.9 Entrada (A)

Ação nova `interact`, tecla **F**, em `InputSetup.ACTIONS` (depois de `help`). F já é `spectate_next`, mas nunca ao mesmo
tempo: `interact` só é lida com o jogador vivo, `spectate_next` só com espectador ativo. Toque: `InteractButton` em
`TouchControls`, visível com `get_revive_target_slot() >= 0` (rótulo "Levantar") ou, sem alvo de levantar, com
`get_ammo_crate_target() >= 0` (rótulo "Pegar"; Q4), ≥ 96 px, segura `interact` enquanto pressionado, sem sobrepor botão
existente em 1280×720 e 2340×1080. Caído no toque: só o arrasto de olhar e a Pausa ficam.

---

## 5. HUD (A2, `src/hud/`) e textos PT-BR exatos

Tudo só com `world.is_horde()`; nomes de nó achados por `find_child(name, true, false)`.

| Elemento | Regra | Texto |
|---|---|---|
| Munição | `has_infinite_reserve()` false → formato do contrato | `"%d \| %d"` |
| Aviso de munição (nível sem infinita) | arma atual `mag + reserva == 0` | `"Sem munição: pegue cartuchos no celeiro."` |
| | reserva 0 e pente > 0 (uma vez por arma até pegar caixa) | `"Última carga: pegue cartuchos no celeiro."` |
| Coleta | `ammo_picked_up(r)` | `"+%d cartuchos"` |
| Minimapa | caixas disponíveis (`get_ammo_crate_positions`): ponto 6 px `#8FB339`; aliado caído: ponto `#E04A3A` | — |
| Bússola | aliado caído: marcador `#E04A3A` sempre visível | — |
| `RevivePrompt` (HudLabel) | alvo ≥ 0, teclado | `"Segure %s para levantar %s"` (tecla `get_key_label(&"interact")`, nome) |
| | alvo ≥ 0, toque | `"Segure Levantar para ajudar %s"` |
| `ReviveBar` (ProgressBar 0..1) | progresso > 0 | rótulo `"Levantando %s…"` |
| `AmmoPrompt` (HudLabel, mesmo lugar do `RevivePrompt`, nunca junto) | `get_ammo_crate_target() ≥ 0` (já exclui alvo de levantar e reserva no teto), teclado | `"Aperte %s para pegar munição"` (tecla `get_key_label(&"interact")`) |
| | idem, toque | `"Toque em Pegar para pegar munição"` (rótulo do botão) |
| `DownedOverlay` (ColorRect `#7A0000`, alfa 0,35) + `DownedLabel` (HudBigLabel) + `DownedHint` | `player_downed` até `player_revived`/`player_died` | `"Você caiu!"`; `"Um companheiro pode te levantar."`; com `bleed_out_s > 0` 2ª linha `"Sangrando: %d s"` (`ceili(get_bleed_out_left_s())`, 10 Hz) |
| Feed | `hunter_downed(s)`, s ≠ local | `"%s caiu! Vá até lá e segure %s."` (teclado) / `"%s caiu! Vá até lá e segure Levantar."` (toque) |
| | `hunter_revived(s, by)`: s = local / by = local / outros | `"%s te levantou!"` / `"Você levantou %s."` / `"%s levantou %s."` |
| Cercado | `Player` preso na borda; no máximo a cada `confine.hint_interval_s`, via `hud_message_requested(texto, confine.hint_s)` | `"Fique dentro do cercado da fazenda."` |
| Botão de toque | `InteractButton` (ação `interact`) | `"Levantar"` (alvo de levantar) / `"Pegar"` (caixa ao alcance) |

Lobby/resultado (systems): `"Nível"`, `"Nível escolhido: %s"`, `"%s: Horda Javali, %s, %d ondas"` (mapa, nome do nível,
ondas do nível), trava de armas `"Na Horda Javali todos levam todas as armas, com munição infinita."` (nível com
`ammo.infinite`) ou `"Na Horda Javali todos levam todas as armas. Munição contada: pegue cartuchos no celeiro."`;
cabeçalho do resultado `"Horda Javali · %s  |  %s"` (nome do nível, mapa).

---

## 6. Lobby e resultado (S2)

- Lobby, só em horda: `%HordeLevelRow` (HBoxContainer) com um botão por nível, nomes `HordeLevel_1`, `HordeLevel_2`
  (criados de `Data.get_horde_level_count()`, texto = `name`, `toggle_mode`, `SecondaryButton`, ≥ 64 px; o do nível da sala
  pressionado; só o anfitrião aperta → `Net.host_select_horde_level(n)`, falhou → `ui_error`). `%HordeLevelLabel` (todos)
  `"Nível escolhido: %s"`. `%HordeInfoLabel` = `description` do nível. **Nível 2 não exige vencer o 1** (Q1).
- Resultado: cabeçalho com o nível; o resto de `horda.md` §10.3 igual. `apply_hunt_result` não muda.

---

## 7. Arte e som (art-director)

| Entrega | Contrato |
|---|---|
| `barn_corn.tscn`/`.gd` | tulha de madeira fixa em x [−6, 6], z [1,6, 4,7], parede 1,2 m, no referencial do celeiro; milho dentro; estágios 4…1 só baixam a altura do milho (pegada fixa), 0 = tulha vazia com palha; montes do anel como hoje. Orçamento novo: ≤ 1000 triângulos, ≤ 9 `MeshInstance3D` |
| `ammo_crate.tscn` (`ScenePaths.AMMO_CRATE`) | raiz `Node3D`, sem física e sem luz, origem no chão no centro, ~0,6 × 0,35 × 0,4 m, caixote de madeira com faixa verde-oliva e cartuchos à vista; ≤ 300 triângulos, 1 material, `cast_shadow` off |
| Sons `ammo_pickup` (~0,4 s, cartuchos/caixa) e `revive_done` (~0,8 s, alívio curto) | síntese procedural obrigatória; entradas em `sfx_prompts.json` (MP3 opcional depois); `has_sound` verdadeiro |
| `assets/preview/barn_corn_preview.tscn` | tulha nos 5 estágios dentro do galpão + caixas nas posições do seed |
| Fora | `barn_hd.gd`, cerca (já é de arame), `horde_wave_start` (MP3 da coordenação) |

---

## 8. Pacotes de trabalho

Regras de `horda.md` §14 valem (A não referencia B; ninguém referencia N; systems/ui não referenciam A/B). Toda entrega:
`check_scripts` verde e as suítes afetadas **sem mudança no modo contrato e na horda Nível 1** (exceto C1–C3).

| Etapa | Pacote | Agente / modelo | Paralelo com | Espera |
|---|---|---|---|---|
| 0 | Núcleo (§4.1), `layer_5`, MP3 da sirene | coordenação | — | — |
| 1 | **S1** dados v2 + `Data` + `Profile` | game-systems / Sonnet | N, ART | 0 |
| 1 | **N** nível na sala | game-developer / Sonnet | S1, ART | 0 |
| 1 | **ART** tulha, caixa, 2 sons | art-director / Sonnet | todos | 0 |
| 2 | **B** mundo, IA, fluxo, caixas, levantar em rede | game-developer / **Opus** (caminho crítico) | A1, A2, S2 | S1 (`Data.get_horde_level*`) |
| 2 | **A1** jogador: munição, cercado, caído/levantar, `RemoteHunter`, `interact` | game-developer / **Opus** (caminho crítico) | B, A2, S2 | S1 |
| 2 | **A2** HUD e toque | game-developer / Sonnet | B, A1, S2 | 0 (só API de `PlayerBase`/`GameEvents`) |
| 2 | **S2** lobby e resultado | game-systems / Sonnet | B, A1, A2 | S1, N |
| 3 | **QA** testes e rodada final | qa-tester / Sonnet | — | todos |
| 4 | versão 0.9.0, export, `mobile_probe.py`, `coop_probe.py`, publicação | coordenação | — | QA verde |

### B — game-developer (Opus)
Arquivos: `src/world/map_root.gd`, `src/world/prop_spawn.gd`, `src/world/maps/mato_grosso/mato_grosso_map.tscn` (só o
`PropSpawn` `Barn`: `horde_collision_boxes`/`horde_obstacle_circles` de §1 C3), `src/boars/boar.gd`, `src/boars/boar_puppet.gd`,
`src/boars/horde_route.gd` (novo), `src/hunt/hunt_controller.gd`, `src/hunt/horde_ammo_crates.gd` (novo),
`src/hunt/hunt_host_sync.gd`, `src/hunt/hunt_replica.gd`, `src/hunt/debug/horde_selftest.gd`,
`src/hunt/debug/horde2_selftest.gd|.tscn` (novo), `src/hunt/debug/net_horde2_test.gd|.tscn` (novo).
Ordem interna: C1–C3 → N2/N3/spawn → caixas → levantar em rede.
Fora: `Player`, HUD, `Net`, dados, assets, `HordeDirector` (não muda).
Aceite:
- `horde_selftest` (Nível 1) passa como hoje, mais: um raio de (14, 1,2, −58) para −Z (segmento `FenceS8`; x = 10 é a porteira, sem colisão) não acerta corpo de cerca em horda e
  acerta no contrato (`hunt_selftest`); jogador (bot) andando de (40, y, −100) para (40, y, −89) entra no galpão (passa entre os
  esteios) e, seguindo para (40, y, −78), para na tulha sem atravessar o fundo; formas estáticas ≤ 400; nenhum javali em `to_crop` com XZ dentro de `Rect2(27, −15, 56, 70)`;
  todos chegam a `eat` em ≤ 90 s por onda.
- `horde2_selftest` (`make_debug(&"mato_grosso", 0, Ids.MODE_HORDE, 2)`): `get_horde_level() == 2`; jogador nasce a ≤ 4 m
  de (30, −74); `get_player_bounds()` = `Rect2(-19.4, -109.4, 73.8, 46.8)`; 3 caixas em (35|38|41, y, −90); fêmea com
  jogador a 9 m investe (`scrape` antes de `charge`, ≥ 0,6 s − tolerância); leitão nunca `scrape`; caixa pega some e volta
  depois de 60 s (parado em cima não pega; um aperto de `interact` pega uma vez); com `debug_set_crop_health(0)` → `DEFEAT_CROP`; resultado com `horde_level == 2` e prêmios = `Profile.*(…, 2)`.
- `net_horde2_test` (anfitrião + cliente no mesmo processo, `test_net_role`): cliente caído → `hunter_downed` nas duas
  máquinas; anfitrião segura 4 s ao lado → `EV_HUNTER_REVIVED`, cliente vivo com 50; anfitrião caído e cliente levanta via
  `C_REVIVE`; pedido fora do raio + tolerância é ignorado; os dois caídos → `DEFEAT_DEATH`; caixa pedida pelo cliente (só no aperto de `interact`; parado em cima não pede) →
  `EV_AMMO_CRATE` com `taker` = cliente, reserva do cliente subiu, caixa invisível nas duas; dois pedidos simultâneos → só um
  ganha; `net_write_full_sync` contém um `EV_AMMO_CRATE` por caixa; cliente com sangramento esgotado → `hunter_died`.
- Sem regressão: `hunt_selftest`, `net_unit` inteiro, `playthrough`, `flow_test`.

### A1 — game-developer (Opus)
Arquivos: `src/player/player.gd`, `src/player/player.tscn` (nada além do que precisar; a máscara vem de
`Layers.MASK_PLAYER_BODY` no `_ready`), `src/player/remote_hunter.gd`, `src/weapons/weapon.gd` (se precisar),
`src/input/input_setup.gd`, `src/player/debug/sandbox_world.gd`, `src/player/debug/player_horde2_test.gd|.tscn` (novo),
`src/player/debug/remote_sandbox.gd`.
Fora: HUD, `TouchControls`, classes de B.
Aceite (`player_horde2_test`, mundo falso com `get_horde_level() == 2`, 2 caçadores, bounds definidos):
reservas iniciais 20/10/10/10/10; recarga gasta reserva; `needs_ammo()`; `add_ammo_mags(2)` devolve a soma certa e respeita
o teto; empurrar para fora do bounds para na borda e pede a dica no máximo a cada 5 s; `apply_damage(9999)` → caído
(`is_alive()` false, `is_downed()` true, `HF_DOWNED` no estado, sem `player_died`); `revive(50)` → vivo com 50; sangramento
60 s → `player_died` 1×; bot segurando `interact` ao lado de um caído por 4 s chama `request_revive` 1×; com 1 caçador ou
nível 1, vida 0 = morte de hoje; `remote_sandbox`: `HF_DOWNED` → `is_downed()`, volta de `HF_ALIVE` troca o visual.
`player_horde_test` (Nível 1) e `test_input` (com `interact`) sem regressão.

### A2 — game-developer (Sonnet)
Arquivos: `src/hud/hud.gd`, `src/hud/hud.tscn`, `src/hud/minimap.gd`, `src/hud/compass.gd`, `src/hud/map_markers.gd`,
`src/hud/touch/touch_controls.gd|.tscn`, `src/hud/debug/hud_horde2_test.gd|.tscn` (novo).
Fora: `Player`, classes de B. Aceite: `hud_horde2_test` (jogador e mundo falsos, sinais à mão) → textos exatos da §5 em
cada nó; `"%d | %d"` sem `∞`; `InteractButton` só com alvo; `hud_horde_test` (Nível 1) e `hud_net_test` sem regressão;
`mobile_probe.py` sem sobreposição (coordenação roda).

### N — game-developer (Sonnet)
Arquivos: `src/net/net.gd`, `src/net/net_session.gd`, `src/net/debug/net_mode_selftest.gd`.
Aceite: `L_LOBBY` com/sem o byte de nível e `L_START` de 13 e 14 bytes → `get_selected_horde_level()` 2/1; nível 0 ou 3 → 1;
`host_select_horde_level` falha para cliente, fora de `LOBBY`, 0 e > count; `create_room` volta a 1; layout byte a byte;
`net_e2e` com nível 2 → os dois `HuntRequest` com `horde_level == 2`. Modo contrato e nível 1 sem regressão.

### S1 / S2 — game-systems (Sonnet)
S1 arquivos: `data/horde.json`, `src/systems/data_registry.gd`, `src/systems/profile.gd`. Aceite: seed sem erro; cada regra
de §3 quebrada gera erro; `get_horde_level(2).kill_reward_mult == 0.5`; `get_horde_boar_type(&"sow", 2).aggression ==
"provoked"`, `get_horde_boar_type(&"sow", 1) == get_boar_type(&"sow")`; vetores R$ 309 / 4350 / 217 / 2610.
S2 arquivos: `src/ui/lobby/lobby.gd`, `src/ui/common/loadout_panel.gd`, `src/ui/result/result.gd`,
`src/ui/result/debug/result_horde_sandbox.gd`. Aceite: botões de nível só para o anfitrião e só em horda, ≥ 64 px, a
1280×720 e 2340×1080; textos da §5; `flow_test` do contrato igual.

### ART — art-director (Sonnet)
Arquivos: `assets/models/props/barn_corn.gd|.tscn`, `assets/models/props/ammo_crate.tscn` (+ script de malha em
`assets/models/props/`), `assets/audio/sfx_library.gd`, `assets/audio/synth/*`, `assets/audio/sfx_prompts.json` (2
entradas), `assets/preview/barn_corn_preview.tscn`. Aceite: `unit_tests -- --strict` com os limites de §7;
`Sfx.has_sound(&"ammo_pickup")` e `(&"revive_done")`; screenshot do preview.

### QA — qa-tester (Sonnet)
Arquivos: `tests/lib/contract_sigs.gd` (tudo de §4.1, `Data.get_horde_level*`, `Net.*horde_level`, `HordeRoute.plan`),
`tests/check_scripts.gd` (5 sinais), `tests/unit/test_core.gd` (padrões e `make_debug` 4º parâmetro, `to_dict`),
`tests/unit/test_data.gd` (v2), `tests/unit/test_economy.gd` (vetores), `tests/unit/test_horde.gd` (`HordeRoute.plan`:
vetores da §4.4, saída de obstáculo, quina dentro de outro rect; `plan_waves` por nível ≤ 255), `tests/unit/test_input.gd`
(`interact`), `tests/unit/test_assets.gd` (tulha e caixa), `tests/net_unit.gd` (registrar `net_horde2`),
`tests/net_test.gd` (cenário `horde2`: dois processos, um cai, outro levanta, `VICTORY` ou `DEFEAT_*` iguais nos dois),
`tests/playthrough.gd` + `tests/bot/hunt_bot.gd` (H5: horda Nível 2 solo com bot pegando caixa com `bot_set_interact`
e vencendo com `debug_kill_boar`; H6: reserva cai e sobe na caixa; parado em cima ou com reserva no teto não pega), `tests/flow_test.gd` (rota de horda Nível 2 até `RESULT`).
Aceite: as 4 suítes + `net_unit` + `net_test` terminam sozinhas com o código certo.

Suítes por mudança: `check_scripts` sempre; `unit_tests` (S1, ART, QA); `flow_test` (S2, B); `playthrough` (B, A1);
cenas próprias de cada pacote; `net_unit`/`net_test` (B, N, A1).

---

## 9. Riscos

- **R1 — Rede do levantar:** validado pelo anfitrião com a última posição conhecida (tolerância 3 m). Corrida com o
  sangramento: quem morreu antes do evento continua morto e todos veem a mensagem de levantada seguida de `hunter_died`.
- **R2 — Caixa com atraso:** no cliente a munição chega 100–300 ms depois; o anfitrião garante uma caixa para um só.
- **R3 — Javali preso no celeiro:** círculos em U podem segurar javali que investiu para dentro; a rota sai pela frente e o
  aceite de B mede chegada a `eat`. Se aparecer, mais círculos ou raio maior (dados da cena).
- **R4 — Teto invisível:** o bloco do telhado começa a 4,9 m; tiro para cima dentro do galpão para abaixo da cumeeira.
- **R5 — Modos divergentes:** cerca e celeiro mudam só na horda; no contrato a bala ainda para na cerca (Q2).
- **R6 — `HF_DOWNED` usa o último bit livre** de `flags`; a próxima flag exigirá byte novo (mudança de protocolo).
- **R7 — Milho ainda esconde** javali que investe atrás de caçador que entrou na lavoura.
- **R8 — Balanceamento do Nível 2** (munição, caixas, agressividade, prêmios) sem teste com gente; tudo em dados.
- **R9 — F compartilhado** com `spectate_next`: seguro pelos estados, mas a legenda de teclas mostra F duas vezes.
- **R10 — Desempenho:** +9 formas estáticas, ≤ 3 caixas (3 draw calls), rota calculada só ao entrar em `to_crop`,
  tulha +1 instância; dentro do orçamento de `arquitetura.md` §13.1.

## 10. Questões para o dono do jogo (respondidas)

- **Q1** Nível 2 fica liberado direto (decisão atual) ou só depois de vencer o Nível 1? → **Liberado direto.**
- **Q2** A bala passar pela cerca e o celeiro aberto valem também no modo contrato? (hoje: só na horda) → **Só na horda.**
- **Q3** Quem cai sangra 60 s até morrer de vez. Prefere sem limite? → **60 s.**
- **Q4** Caixa de cartucho é pega só de chegar perto (decisão atual) ou com botão? → **Com botão** (aperto de `interact`:
  F / "Pegar" no toque; §4.6, §4.9, §5).
- **Q5** Sala de 1 jogador no Nível 2: cair = derrota (ninguém para levantar). Ok? → **Sim.**
- **Q6** Javalis continuam passando pela cerca de arame. Querem que só entrem pela porteira? → **Continuam passando pela cerca.**
- **Q7** Prêmios do Nível 2: abate × 0,5 e bônus de vitória R$ 5000. Ok? → **Ok.**
