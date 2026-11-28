# Caçada ao Javali — Modo "Horda Javali" (contrato)

Versão do contrato: **1.0** (jogo **0.5.0**) · complementa `docs/arquitetura.md` (contrato 1.2) e
`docs/multiplayer.md`. Onde este documento contradiz os outros dois **no modo horda**, vale este. No modo
contrato (solo e cooperativo) nada muda: **nenhum código de horda executa com `mode == &"contract"`**.

**Horda 2.2 (jogo 0.9.11): Nível 2 com 10 ondas e o chefão "Cachaço rei".** Os números "8 ondas" deste documento valem para o
**Nível 1**; o Nível 2 tem o seu próprio array `waves` (§3.3). Chefão: tipo `boss` (§3.3, `arquitetura.md` §9.5), comportamento
(§6.1), barra (§8), rede (§9.4), mensagem e som (§11.2, §12). Plano e medição: `docs/plano_horda_boss.md`.

Regras de sempre: faça o mínimo, não invente API, relate o que estiver errado. Identificadores em inglês, texto
do jogador em PT-BR (exatamente como na §12).

---

## 1. O modo em uma página

- Só no multiplayer: o anfitrião escolhe na sala (`src/ui/lobby`) o modo **"Contrato"** (o de hoje) ou
  **"Horda Javali"**. Vale com 1 a 4 jogadores na sala. Não aparece no menu solo.
- O modo é propriedade do `HuntRequest` (`mode`: `&"contract"` padrão, `&"horde"`). A caçada em horda funciona
  **offline** com `HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE)` (testes, bot, sandboxes).
- Mapa: Mato Grosso. O objetivo é o **celeiro** (prop `barn`, hoje em (38, -88), yaw 0). O celeiro tem um
  **estoque de milho** 100% → 0%, que ocupa o lugar da saúde da lavoura em todo o caminho de dados
  (`CropManager`, `crop_health_changed`, `crop_under_attack`, `crop u16` do snapshot, `EV_HUNT_END`,
  `EV_FULL_SYNC`, `HuntResult.crop_health_pct`). As lavouras ficam no cenário, sem ser comidas.
- **Ondas** definidas em `data/horde.json` (8 no seed do Nível 1; 10 no Nível 2, §3.3), cada uma maior que a anterior; a
  última traz cachaço(s) alfa e, no Nível 2, o chefão. Intervalo antes da 1ª onda e entre ondas. Uma onda termina quando todos os javalis dela morrem.
- Javalis nascem nas `SpawnZones` e **correm direto para o celeiro**, comem o milho na borda dele e drenam o
  estoque. Ninguém foge. Fêmeas, machos e alfa investem pelas regras de agressão de hoje.
- **Vitória:** todas as ondas abatidas (`VICTORY`). **Derrota:** estoque em 0 (`DEFEAT_CROP`) ou todos os
  caçadores presentes mortos (`DEFEAT_DEATH`). Sem renascimento. Desistência e quedas como na §8.12.
- Todo jogador leva **todas as armas** de `data/weapons.json` (inclusive a de ouro), munição de reserva
  infinita. Equipamentos, consumíveis e cão: do inventário de cada um, como no contrato.
- Economia: abate paga `kill_reward` × `kill_reward_mult` (< 1); vitória paga `victory_bonus_money` × estoque
  preservado; nunca conta para a progressão de contratos; crédito único em `Profile.apply_hunt_result`.

---

## 2. Decisões deste contrato (além das da coordenação)

| # | Decisão | Motivo |
|---|---|---|
| D1 | O estoque do celeiro **é** a saúde do `CropManager`, posto em "modo estoque" (`set_store_mode(true)`): drena como hoje, nunca come canteiro. | Um único canal: HUD, snapshot, `EV_HUNT_END`, `EV_FULL_SYNC`, resultado e `DEFEAT_CROP` funcionam sem mudança. |
| D2 | `boar_counts_changed(killed, total)`, `killed u8/total u8` e `HuntResult.boars_total` continuam **da partida inteira** (todas as ondas). O progresso da onda vai num sinal próprio. | Não muda o significado de sinal/campo já testado. |
| D3 | Total da partida ≤ 255 (`NetCodec.MAX_BOARS_PER_HUNT`), garantido pela validação de dados e, em último caso, cortado em tempo de execução (§5.2). | Ids de javali são `u8`. Sem mudança de protocolo. |
| D4 | Escala por jogadores com `BoarSpawner.scale_groups` (sem mudança), alimentado por chaves **próprias** da horda (`player_count_mult`, `extra_group_delay_s`) em vez de `coop.*`. | `coop.extra_group_delay_s` (20 s) espalharia uma onda por minutos; a horda precisa de balanceamento independente. Desvio pequeno da decisão 3. |
| D5 | Estado de onda chega ao cliente por **evento** (`EV_HORDE_WAVE`, 7 B, 2 por onda), não por snapshot. | Raro, confiável e ordenado com `EV_BOAR_DEATH`; o snapshot do modo contrato não muda nenhum byte. |
| D6 | Modo no fio: **um byte no fim** de `L_LOBBY` e de `L_START`. `NetCodec.PROTOCOL_VERSION` **continua 1**. | O servidor não lê registros de jogo; `config/version` 0.5.0 já separa salas de versões diferentes. |
| D7 | Carcaças além de `max_carcasses` (12) ficam invisíveis (`visible = false`), não são liberadas. | Uma horda tem até ~190 abates: sem teto seriam ~1000 draw calls. Esconder evita referências a objeto liberado. |
| D8 | A ceva de milho funciona em horda como hoje (atrai até 4 javalis a 80 m, não drena nada). | "Consumíveis como no contrato"; vira tática legítima de defesa. Ver questão Q4. |
| D9 | Teclas `3`, `4`, `5` (ações novas `weapon_3`..`weapon_5`) escolhem as armas 3–5; `weapon_swap` (botão Trocar no toque) cicla todas. | No desktop `weapon_swap` não tem tecla; sem isso as armas 3–5 seriam inalcançáveis. No contrato as teclas novas não fazem nada (slot inexistente). |
| D10 | Vitória em horda conta em `stats.hunts_won` (apply_hunt_result não muda). | Menor mudança; ver Q3. |
| D11 | Mensagens de entrada de bando ("Uma vara saiu da mata!") são suprimidas em horda; fica só a do alfa. O anúncio de onda as substitui. | Uma onda de 30 javalis gera ~8 mensagens. |

---

## 3. Dados — `data/horde.json` (dono: game-systems)

### 3.1 Esquema

| Campo | Tipo | Unid. | Uso / regra |
|---|---|---|---|
| `version` | int | — | 1 |
| `name`, `description` | string | — | textos do lobby (PT-BR) |
| `map_id` | string | — | id de `maps.json`, `available: true`. Em rede o `Net` grava este mapa no `HuntRequest` (§9.3) |
| `objective_prop_id` | string | — | `prop_id` de um `PropSpawn` da cena do mapa (o celeiro) |
| `first_wave_delay_s` | float ≥ 0 | s | intervalo antes da onda 1 (contado a partir de `hunt_started`) |
| `intermission_s` | float ≥ 0 | s | intervalo entre uma onda vencida e a próxima |
| `barn_drain_mult` | float > 0 | — | substitui `contract.crop_drain_mult`: dreno de cada javali comendo = `crop_drain_pct_per_s × barn_drain_mult` (% do estoque por s) |
| `eat_ring_m` | float > 0 | m | raio, a partir da origem do celeiro, do anel onde os javalis comem |
| `to_barn_speed_frac` | float (0, 1,5] | — | velocidade da corrida ao celeiro = `run_speed_mps × to_barn_speed_frac` |
| `max_carcasses` | int ≥ 0 | — | carcaças visíveis ao mesmo tempo (D7) |
| `player_count_mult` | float[`net.max_players`] | — | multiplicador de javalis por onda, índice `player_count − 1`; cada ≥ 1,0, não decrescente |
| `extra_group_delay_s` | float ≥ 0 | s | atraso entre clones de grupo dentro da onda (`scale_groups`) |
| `kill_reward_mult` | float (0, 1) | — | multiplica o prêmio de abate |
| `victory_bonus_money` | int ≥ 0 | R$ | bônus de vitória × estoque%/100 |
| `waves` | array ≥ 1 | — | ordem = ordem de jogo. Cada onda: `{"groups": [...]}` com o **mesmo formato de grupo** de `maps.json` (`members` 1 ou 3–6 ids de tipo, líder primeiro; `spawn_zone` int ≥ 0, módulo das `SpawnZones`; `delay_s` ≥ 0 contado do início da onda) |

Regras de validação (`Data`, entram em `get_load_errors()`):
1. Todos os campos acima presentes com o tipo certo; `map_id` existe e está disponível; `player_count_mult` tem
   `net.max_players` entradas.
2. Cada grupo: 1 ou 3–6 membros, todos ids de `boars.json`. Cada onda tem ≥ 1 grupo.
3. A **última** onda contém ao menos um `alpha`.
4. Teto de ids: `Σ_ondas ceil(total_base_da_onda × max(player_count_mult)) ≤ NetCodec.MAX_BOARS_PER_HUNT` (255).
   É um limite superior conservador do que `scale_groups` produz.

### 3.2 Seed (o game-systems copia; valores rebalanceáveis, nomes e estrutura não)

```json
{
  "version": 1,
  "name": "Horda Javali",
  "description": "Defendam o celeiro de milho contra ondas de javalis. Todas as armas liberadas, munição sem fim. Se a horda comer o milho ou derrubar todos os caçadores, acabou.",
  "map_id": "mato_grosso",
  "objective_prop_id": "barn",
  "first_wave_delay_s": 12.0,
  "intermission_s": 15.0,
  "barn_drain_mult": 1.0,
  "eat_ring_m": 10.0,
  "to_barn_speed_frac": 0.8,
  "max_carcasses": 12,
  "player_count_mult": [1.0, 1.4, 1.8, 2.2],
  "extra_group_delay_s": 4.0,
  "kill_reward_mult": 0.35,
  "victory_bonus_money": 3000,
  "waves": [
    {"groups": [
      {"members": ["sow", "piglet", "piglet", "piglet"], "spawn_zone": 1, "delay_s": 0.0}]},
    {"groups": [
      {"members": ["sow", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0},
      {"members": ["sow", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 5.0}]},
    {"groups": [
      {"members": ["sow", "sow", "piglet", "piglet"], "spawn_zone": 1, "delay_s": 0.0},
      {"members": ["boar"], "spawn_zone": 3, "delay_s": 6.0},
      {"members": ["sow", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 10.0}]},
    {"groups": [
      {"members": ["boar", "sow", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0},
      {"members": ["sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 6.0},
      {"members": ["boar"], "spawn_zone": 3, "delay_s": 12.0}]},
    {"groups": [
      {"members": ["boar", "sow", "sow", "piglet", "piglet"], "spawn_zone": 1, "delay_s": 0.0},
      {"members": ["sow", "piglet", "piglet", "piglet"], "spawn_zone": 3, "delay_s": 5.0},
      {"members": ["boar", "sow", "piglet"], "spawn_zone": 0, "delay_s": 10.0}]},
    {"groups": [
      {"members": ["boar", "sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0},
      {"members": ["boar", "sow", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 5.0},
      {"members": ["sow", "sow", "piglet", "piglet"], "spawn_zone": 3, "delay_s": 10.0}]},
    {"groups": [
      {"members": ["boar", "boar", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 1, "delay_s": 0.0},
      {"members": ["boar", "sow", "sow", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 5.0},
      {"members": ["sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 10.0}]},
    {"groups": [
      {"members": ["alpha", "boar", "boar"], "spawn_zone": 1, "delay_s": 0.0},
      {"members": ["boar", "sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 4.0},
      {"members": ["boar", "sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 8.0}]}
  ]
}
```
Totais base por onda: 4, 6, 8, 10, 12, 14, 16, 15 = **85** (solo). Com 4 jogadores (`scale_groups`, ×2,2):
9, 13, 18, 22, 26, 31, 35, 33 = **187** (limite da regra 4: 190 ≤ 255). Prêmio de exemplo (vetor de teste):
macho 132 kg, vitais, um tiro → `round(132 × 2,5 × 1,25 × 1,5 × 0,35)` = **R$ 217** (`value_per_kg` do macho em `data/boars.json` = 2,5). Bônus com 87% de estoque:
`round(3000 × 0,87)` = **R$ 2610**.

### 3.3 `waves` por nível e o tipo `boss` (0.9.11)

- `waves` é chave de `HORDE_OVERRIDE_KEYS` (`data_registry.gd`): o array do topo é o do **Nível 1** (**8 ondas**, 128
  javalis base) e `levels[1].overrides.waves` é o do **Nível 2** (**10 ondas**, 129 base: 6, 8, 10, 12, 13, 14, 15, 16, 17,
  18). Os dois níveis têm números de ondas diferentes — é contrato. Todo leitor usa o `waves` do nível **resolvido**
  (`Data.get_horde_level(level)`), e o lobby mostra "8 ondas" ou "10 ondas" conforme o nível.
- As regras de validação 2–4 de §3.1 rodam por nível resolvido (`_validate_horde_level` revalida o nível inteiro quando
  `overrides` não está vazio; o erro sai com o rótulo `horde level 2`). Orçamento de ids do Nível 2: Σ ceil(total × 1,9) =
  **250 de 255**; o do Nível 1 segue com 247. `player_count_mult` não muda entre níveis.
- A onda 10 (última) abre com `{"members": ["boss"], "spawn_zone": 1, "delay_s": 0.0}`, sozinho e primeiro, e traz também um
  grupo `["alpha", "boar", "boar"]`: a regra "a última onda contém `alpha`" (§3.1, 3) continua valendo.
- **Tipo `boss`** ("Cachaço rei", `data/boars.json`, `Ids.BOSS`): só existe no Nível 2, por isso não entra em
  `boar_overrides`. Campos, números e o novo `body_scale_mult`: `arquitetura.md` §9.5. Recompensa ≈ 1.280 (640 kg × 4,0 ×
  `kill_reward_mult` 0,5). `BoarSpawner` nunca clona grupo que contenha `alpha` **ou** `boss` (`UNIQUE_TYPES`): com 1–4
  jogadores o Nível 2 tem **exatamente 1 chefão e 2 alfas**.

---

## 4. Contrato em `src/core/` (já aplicado; ninguém mais edita)

Mudanças aditivas; nada existente mudou de assinatura. Código verbatim nos arquivos e no Apêndice A de
`docs/arquitetura.md` (seção "Acréscimos 0.5.0").

| Arquivo | Acréscimo |
|---|---|
| `game_events.gd` | `signal horde_wave_changed(wave: int, wave_count: int, phase: StringName, countdown_s: float)`; `signal horde_wave_progress(remaining: int, wave_total: int)` |
| `ids.gd` | `MODE_CONTRACT = &"contract"`, `MODE_HORDE = &"horde"`, `HP_INTERMISSION = &"intermission"`, `HP_WAVE = &"wave"` |
| `scene_paths.gd` | `BARN_CORN = "res://assets/models/props/barn_corn.tscn"` |
| `hunt_request.gd` | `var mode: StringName = &"contract"`; `make_debug(p_map_id = &"mato_grosso", p_contract_index = 0, p_mode = &"contract")` (3º parâmetro novo, opcional); `func is_horde() -> bool` |
| `hunt_result.gd` | `var mode: StringName = &"contract"`, `var horde_wave_count: int = 0`, `var horde_waves_cleared: int = 0`; `func is_horde() -> bool`; `to_dict()` ganha `"mode"`, `"horde_wave_count"`, `"horde_waves_cleared"` |
| `player_base.gd` | `func get_weapon_count() -> int` (0), `func has_infinite_reserve() -> bool` (false) |
| `hunt_world.gd` | `get_mode() -> StringName` (`&"contract"`), `is_horde() -> bool`, `get_objective_position() -> Vector3` (`INF`), `get_horde_wave() -> int` (0), `get_horde_wave_count() -> int` (0), `get_horde_phase() -> StringName` (`&""`), `get_horde_countdown_s() -> float` (0), `get_horde_wave_total() -> int` (0), `get_horde_wave_remaining() -> int` (0), `get_horde_waves_cleared() -> int` (0), `debug_horde_start_next_wave() -> void` |
| `net_codec.gd` | `EV_HORDE_WAVE = 0x2C`; `MODES: Array[StringName] = [&"contract", &"horde"]`; `HORDE_PHASES: Array[StringName] = [&"intermission", &"wave"]`; `MAX_BOARS_PER_HUNT = 255` |
| `corn_stock_visual_base.gd` (novo) | `class_name CornStockVisualBase extends Node3D` — §11.1 |

### 4.1 Sinais novos do `GameEvents`

| Sinal | Emissor | Ouvintes | Quando |
|---|---|---|---|
| `horde_wave_changed(wave, wave_count, phase, countdown_s)` | B `HuntController` (todas as máquinas) | A `Hud`, tests | mudança de fase: (a) início da caçada → `(1, N, HP_INTERMISSION, first_wave_delay_s)`; (b) onda começa → `(w, N, HP_WAVE, 0.0)`; (c) onda `w < N` vencida → `(w + 1, N, HP_INTERMISSION, intermission_s)`. A onda N vencida não emite (a caçada termina em `VICTORY`). No cliente também ao aplicar o `EV_HORDE_WAVE` da reentrada, com o `countdown_s` restante |
| `horde_boss_health_changed(pct)` (0.9.11) | B `HuntController` (offline e anfitrião; no cliente, `HuntReplica` ao ler `EV_BOSS_HP`, §9.4) | A `Hud` (`BossBar`), tests | só no Nível 2, com o chefão vivo: **100** quando ele nasce; depois a cada 0,25 s (máx. 4 Hz) só se o valor mudou; **um único 0** quando ele morre. O `pct` vem do host (`health / max_health × 100`): o dano do cão (`Boar.apply_dog_damage`) não passa por `boar_hit`, então a HUD não pode somar dano |
| `horde_wave_progress(remaining, wave_total)` | B `HuntController` | A `Hud`, tests | logo depois de (b), com `remaining = wave_total`; e a cada abate de javali da onda em curso, **depois** do `boar_counts_changed` desse abate |

`wave` é 1-based em sinais, getters e fio. `phase` é sempre `Ids.HP_INTERMISSION` ou `Ids.HP_WAVE`. Nenhum dos
dois sinais é emitido com `is_horde() == false`.

### 4.2 Getters do `HuntWorld` (polling do HUD a 10 Hz e testes)

| Getter | Contrato | Contrato (modo) |
|---|---|---|
| `get_mode()` | `request.mode` | `&"contract"` |
| `get_objective_position()` | origem do `PropSpawn` do celeiro, Y = `get_height` | `Vector3.INF` |
| `get_horde_wave()` / `get_horde_wave_count()` | onda anunciada ou em curso (1..N) / N. Cliente antes do 1º `EV_HORDE_WAVE`: 0 / 0 | 0 / 0 |
| `get_horde_phase()` | `HP_INTERMISSION` ou `HP_WAVE` (cliente antes do 1º evento: `&""`) | `&""` |
| `get_horde_countdown_s()` | no intervalo, segundos restantes (decresce com `delta` em toda máquina); senão 0 | 0 |
| `get_horde_wave_total()` | javalis da onda `get_horde_wave()` já escalados | 0 |
| `get_horde_wave_remaining()` | fase onda: `wave_total − abates dessa onda`; intervalo: 0 | 0 |
| `get_horde_waves_cleared()` | ondas vencidas até agora; N na vitória | 0 |
| `debug_horde_start_next_wave()` | offline/anfitrião, fase intervalo: zera o contador (a onda começa no próximo frame). Cliente/fora do intervalo: nada | nada |

---

## 5. Montagem e fluxo da horda (Pacote B)

### 5.1 Montagem (deltas sobre a §8.1 de `arquitetura.md`, só com `_request.is_horde()`)

1. **Pedido.** `horde := Data.get_horde()`. Vazio → `push_error` e `_finish(ABANDONED)` (como mapa ausente).
   `_result.mode = Ids.MODE_HORDE`; `_result.counts_for_progression = false` (inclusive offline);
   `_result.contract_index = _request.contract_index` (sem uso).
2. **Plano** (offline e anfitrião): `plan := HordeDirector.plan_waves(horde, player_count)`
   (`player_count` = 1 offline; tamanho do roster no anfitrião). `_result.horde_wave_count = plan.size()`.
   O contrato passado ao spawner é `{"groups": <grupos de todas as ondas, achatados, cada um com "wave": índice 0-based>, "crop_drain_mult": horde.barn_drain_mult}`
   e `crop_drain_mult = horde.barn_drain_mult`. O cliente não planeja.
3. **Lavoura/estoque** (todos os papéis): logo depois de `crop.setup(...)`, `crop.set_store_mode(true)`.
4. **Celeiro** (todos os papéis), ao fim da etapa de props: `spawn := _map.find_prop_spawn(StringName(horde.objective_prop_id))`;
   nulo → `push_error` + `_finish(ABANDONED)`. Objetivo = `spawn.global_position` com Y = `get_height`. Visual:
   `AssetLoader.instantiate(ScenePaths.BARN_CORN) as CornStockVisualBase`, senão
   `CornStockVisualBase.create_fallback()` (instância de outra classe: `push_warning`, `free()`, fallback);
   `setup(horde.eat_ring_m)` **antes** de `add_child`; nome `BarnCorn`, filho do `HuntController`;
   `global_position` = objetivo, `rotation.y` = yaw do `PropSpawn`; `set_stock_pct(100.0)`. Ouve
   `GameEvents.crop_health_changed` → `set_stock_pct(pct)` e `crop_under_attack` → `set_under_attack(on)`.
5. **Spawner e diretor** (offline e anfitrião): `spawner.setup(...)` com o contrato do passo 2;
   `HordeDirector.new()` com nome `HordeDirector`, filho do controlador, `setup(self, spawner, horde, plan)`;
   `director.begin()` no mesmo ponto em que hoje se chama `spawner.begin()` (offline: fim da montagem;
   anfitrião: `_begin_net_hunt`). O diretor conecta `spawner.boar_died` **depois** do controlador.
6. `_result.boars_total = spawner.get_total()` (partida inteira); `boar_counts_changed(0, total)` como hoje.

### 5.2 `HordeDirector` (novo, `src/hunt/horde_director.gd`, `class_name HordeDirector extends Node`, interno de B)

```gdscript
signal wave_changed(wave: int, wave_count: int, phase: StringName, countdown_s: float)
signal wave_progress(remaining: int, wave_total: int)

static func plan_waves(horde: Dictionary, player_count: int) -> Array   # Array (uma entrada por onda) de Array[Dictionary] de grupos; cada grupo ganha "wave": int (0-based)
func setup(world: HuntController, spawner: BoarSpawner, horde: Dictionary, plan: Array) -> void
func begin() -> void
func skip_intermission() -> void
func get_wave() -> int                 # 1-based
func get_wave_count() -> int
func get_phase() -> StringName
func get_countdown_s() -> float
func get_wave_total() -> int
func get_wave_remaining() -> int
func get_waves_cleared() -> int
func get_killed_before() -> int        # abates da partida quando a fase atual começou (vai no EV_HORDE_WAVE)
```

`plan_waves` (função pura, testada pelo qa): para cada onda `i`, `scale_groups(wave.groups, player_count,
{"boar_count_mult_by_players": horde.player_count_mult, "extra_group_delay_s": horde.extra_group_delay_s})`, cada
grupo resultante com `"wave": i`. Se a soma passar de `NetCodec.MAX_BOARS_PER_HUNT`: `push_error` e remove
membros do fim do plano (último membro do último grupo da última onda, e assim por diante; grupo que fica
vazio sai; onda que fica vazia sai e o plano encolhe). Com dados válidos isso nunca acontece.

Máquina de fases (no `_process(delta)` do diretor; nada antes de `begin()` nem depois de `world.is_hunt_over()`):
- `begin()`: fase `HP_INTERMISSION`, onda 1, contador `first_wave_delay_s`; emite `wave_changed`.
- Intervalo: contador −= `delta`; ≤ 0 → fase `HP_WAVE`, `killed_before = world.get_boars_killed()`,
  `spawner.release_wave(onda − 1)`; emite `wave_changed(w, N, HP_WAVE, 0.0)` e `wave_progress(total, total)`.
- Onda: a cada `spawner.boar_died` de javali com `boar.wave == onda − 1` emite `wave_progress(spawner.get_wave_remaining(onda − 1), total)`.
  Quando `get_wave_remaining(onda − 1) == 0`: `waves_cleared = onda`; se `onda < N` → fase intervalo, onda + 1,
  contador `intermission_s`, emite `wave_changed`; se `onda == N` não faz nada (o controlador encerra).
- `skip_intermission()`: no intervalo, contador = 0.

O `HuntController` repassa `wave_changed`/`wave_progress` para o `GameEvents` (é o único emissor no
barramento) e, no anfitrião, a cada `wave_changed` chama `_host_sync.queue_horde_wave(...)` (§9.2). Getters de
§4.2 no offline/anfitrião leem do diretor; no cliente, do último `EV_HORDE_WAVE` (§9.2).

### 5.3 `BoarSpawner` (deltas internos de B)

- `setup(...)` não muda de assinatura. Grupo com chave `"wave"` ≥ 0 fica retido (`delay = INF`) até
  `release_wave(wave_index)`, que faz `delay = agora + delay_s`. Sem a chave: comportamento de hoje.
- `func release_wave(wave_index: int) -> void`, `func get_wave_total(wave_index: int) -> int`,
  `func get_wave_remaining(wave_index: int) -> int` (membros ainda não nascidos + vivos daquela onda).
- `_spawn_boar` grava `boar.wave = <índice da onda do grupo>` (−1 no contrato).
- Em horda, o bando nasce com `herd.wander_end_time = agora` (nunca vaga).
- `get_total()` = soma de todos os grupos, inclusive retidos.

### 5.4 `CropManager` em modo estoque

`func set_store_mode(on: bool) -> void` e `func is_store_mode() -> bool`. Chamado antes de qualquer comedor.
Com `on`: o `_process` drena `_health_pct` exatamente como hoje, mas **não** chama `_eat_near`; `set_health`
não come canteiros; `patch_eaten` nunca é emitido (logo nenhum `EV_CROP_EATEN` em horda). `get_rects()`,
`register_eater`, `unregister_eater`, `set_replicated_health`, `set_replicated_attack` e os sinais do
barramento não mudam. Sem `set_store_mode`, nada muda.

### 5.5 Fim, economia e resultado

- Ordem de fim de `_process` **não muda** (§8.8): mortos → estoque ≤ 0 → desistência → `killed == total`. Como
  `total` é o da partida, a vitória só chega depois da última onda.
- Abate (offline/anfitrião): `kill.reward_money = Profile.horde_kill_reward(type_id, weight_kg, killing_zone, one_shot)`
  no lugar de `Profile.kill_reward(...)`. O resto de `_on_boar_died` não muda (o valor viaja no `EV_BOAR_DEATH`).
- `_finish`: `VICTORY` → `contract_bonus = Profile.horde_bonus(crop_health_pct)` e
  `horde_waves_cleared = horde_wave_count`; outros desfechos → `contract_bonus = 0` e
  `horde_waves_cleared = get_horde_waves_cleared()`. `total_money = money_from_kills + contract_bonus` (igual).
  O cliente faz o mesmo com o estoque do `EV_HUNT_END` e as ondas do seu último `EV_HORDE_WAVE` (§9.2).
- `counts_for_progression = false` sempre. Conta em `hunts_played` (e em `hunts_won` na vitória, D10).
- Grupo entrando (`_on_group_entered`): em horda só a mensagem do alfa (`MSG_ALPHA`, e `EV_MESSAGE` msg 2) e, desde a 0.9.11,
  a do chefão (`MSG_BOSS`, `EV_MESSAGE` msg **6**, §9.4). A checagem do chefão vem antes da de `count == 1`.
- **Carcaças (D7):** em horda o anfitrião/offline guarda os javalis mortos numa fila; passou de
  `max_carcasses`, o mais antigo recebe `visible = false`. O cliente faz o mesmo com as `BoarPuppet` mortas
  (inclusive as mortas pela repetição do `EV_FULL_SYNC`). Nada é liberado; ids continuam registrados.

### 5.6 Ponto de comer

`HuntController.get_horde_eat_point(boar_id: int) -> Vector2` (interno de B): objetivo XZ +
`Vector2(sin(a), -cos(a)) × eat_ring_m`, com `a = boar_id × 2.3999632` (ângulo áureo), preso ao retângulo do
mapa com margem `Boar.MAP_MARGIN_M`. Com o seed (anel 10 m, celeiro 16 × 10 m com obstáculo r 8 m) o anel
inteiro fica fora do galpão.

---

## 6. Javalis na horda (Pacote B, `src/boars/boar.gd`)

Uma única IA: a FSM da §8.9 com estes desvios, todos condicionados a `_world.is_horde()` (lido uma vez em
`setup`). Números vêm de `data/horde.json`.

| # | Onde | Desvio |
|---|---|---|
| H1 | `start()` | entra direto em `_enter_to_crop()` (o estado `wander` nunca é emitido) |
| H2 | `_enter_to_crop()` | `_target = _world.get_horde_eat_point(boar_id)`; não chama `herd.ensure_crop_target` |
| H3 | `_tick_to_crop()` | velocidade `_speed_for(_run_speed × to_barn_speed_frac)` × `arrive_scale` (corre, mancando se ferido) |
| H4 | `_tick_eat()` sem ceva | chegou ao alvo → come parado: sem troca de lugar (`EAT_SHIFT_*` desligado) |
| H5 | `_enter_flee()` | vira `_horde_regroup()`: `_approaching = false`; `_end_encounter()`; se (estado é `to_crop` ou `eat`) **e** não está na ceva → nada; senão `_release_bait()` e `_enter_to_crop()`. O estado `flee` nunca é emitido. Cobre toda chamada de hoje (`_decide`, `_reevaluate`, `_tick_approach`) |
| H6 | `_after_perception()` | detecção em estado calmo só levanta o alerta do bando se `_wants_charge(distância até o alvo, false)` for verdadeiro; senão a detecção é ignorada (segue para o celeiro). A busca de ceva não muda |
| H7 | `BoarSpawner` | bando nasce com `wander_end_time = agora` (`_resume` nunca volta a vagar) |

Consequências verificáveis: em horda nenhum `boar_state_changed(_, &"wander")` nem `(_, &"flee")`; leitão
nunca investe; fêmea investe só a ≤ `aggro_radius_m` com bando ≥ 2 vivos e sem ferimento (regra de hoje);
macho investe a ≤ `aggro_radius_m`, ou se foi atingido, até `max_charges` por encontro; alfa investe sempre que
detecta; quem não investe volta ao celeiro. Ferido não foge (H5). Tiro ouvido e ser atingido usam o caminho de
hoje (`react` → `_decide`), que termina em investida ou em H5. Cão (`bayed`/`held`) não muda. Réplicas, estado
de rede (`net_state_byte`) e a percepção escalonada não mudam.

### 6.1 O chefão (0.9.11)

Mesma FSM e mesmos desvios H1–H7; o que muda é dado e três pontos de código:
- Escala: `body_scale = scale_for_weight(peso) × body_scale_mult` (1,15 no `boss`) em `Boar.setup` e `BoarPuppet.setup` ≈ 2,125,
  raio ≈ 0,744 m. Zonas de acerto, raio de corpo, focinho da investida e altura dos olhos derivam de `body_scale`;
  `BoarSpawner._spawn_boar` usa `boar.body_scale` (não o peso) para o raio de posicionamento.
- Cão: `Boar._dog_time` trata `Ids.BOSS` como `Ids.ALPHA` (solta-se no `alpha_break_free_s`).
- Rugido: `Sfx.play_3d(&"boar_boss_roar", ...)` uma vez em `Boar.start()` e em `BoarPuppet._ready()` quando o tipo é `Ids.BOSS`;
  **não** no `setup` (o nó ainda está fora da árvore e `global_position` é inválido). Limitação conhecida: o replay do
  `EV_FULL_SYNC` faz o rugido tocar de novo no cliente que volta.
- Barra de vida: `HuntController` acompanha o `Boar` com `type_id == Ids.BOSS` (`spawner.boar_added`, só em horda) e emite
  `horde_boss_health_changed` (§4.1); `_boss_gone()` na morte.

---

## 7. Armas e munição (Pacote A)

Verificação do que existe, para mais de 2 armas:

| Peça | Situação | Mudança |
|---|---|---|
| `WeaponHolder.add_view/select` | lista sem limite | nenhuma |
| `Player.setup` | itera `request.weapon_ids` sem limite | em horda itera `Data.get_weapon_ids()` (ordem do arquivo; slot 0 = `carbine_22` selecionada no início) e ignora `request.weapon_ids` |
| `weapon_swap` / botão Trocar (toque) | `(_slot + 1) % _weapons.size()` | nenhuma (já cicla todas) |
| `weapon_1`/`weapon_2` | slots 0/1 | ações novas `weapon_3`, `weapon_4`, `weapon_5` (teclas `3`, `4`, `5`) em `InputSetup.ACTIONS`, slots 2–4; slot inexistente = nada (contrato inalterado) |
| `HUNTER_STATE.weapon u8` | índice em `Data.get_weapon_ids()` | nenhuma (cobre as 5) |
| `L_READY weapon0/weapon1`, `NetPeerInfo.weapon_id` | resumo para o lobby / 1º visual do aliado | nenhuma (o `HUNTER_STATE` corrige a arma em mãos) |
| `bot_select_weapon(slot)` | qualquer slot | nenhuma |

Munição: `Weapon.setup(id: StringName, reserve_mult: float = 1.0, infinite_reserve: bool = false) -> bool`
(3º parâmetro novo, interno de A). Com `infinite_reserve`: `ammo_reserve = maxi(round(reserve_ammo ×
reserve_mult), mag_size)` e **nunca diminui** (`_finish_reload` não subtrai); recarga, cadência e recarga
automática continuam iguais. `Player.has_infinite_reserve()` = `_request.is_horde()`; `get_ammo_reserve()`
devolve o valor constante (> 0, o bot continua funcionando); `get_weapon_count()` = armas carregadas.
`extra_ammo` pode estar equipado e não tem efeito visível.

---

## 8. HUD (Pacote A, `src/hud/`)

Em `bind`, se `world.is_horde()`: liga o layout de horda e lê o estado inicial pelos getters de §4.2. No modo
contrato o HUD não muda nada (mesmos textos e nós).

| Elemento | Horda |
|---|---|
| Barra do topo (`CropBar`) | rótulo `"Celeiro %d%%"`; mesma barra e cores; mesma fonte (`crop_health_changed`) |
| Aviso piscante | `"Javalis no celeiro!"` + `crop_alarm` (mesma regra de `crop_under_attack`) |
| Contador do topo-direita | o `"Javalis k/t"` some; no lugar, Label `WaveLabel` (HudLabel, 24 px): fase onda `"Onda %d/%d · faltam %d"` (onda, N, restantes); intervalo `"Onda %d/%d em %d s"` (próxima onda, N, `ceili(contador)`, atualizado a 10 Hz); antes do 1º estado (cliente) `"Onda –"` |
| Anúncio | Label `WaveBanner` (HudBigLabel, centro-alto abaixo da barra), 3 s, em `horde_wave_changed`: intervalo da onda 1 → `"Defenda o celeiro! A horda chega em %d s"`; onda começa → `"Onda %d de %d"` (última: `"Última onda! Onda %d de %d"`); intervalo da onda w ≥ 2 → `"Onda %d vencida!"` (w − 1) |
| Sons | onda começa → `Sfx.play(&"horde_wave_start")`; intervalo da onda w ≥ 2 → `Sfx.play(&"horde_wave_clear")` |
| Minimapa | não desenha lavouras (`crop_rects = []`); desenha o celeiro em `get_objective_position()` com o ícone `barn` (24 px) ou, sem ícone, quadrado cheio 12 px cor `#F2C12E` |
| Bússola | marcador do celeiro (mesmo ícone/quadrado, 20 px), sempre visível |
| Munição | `"%d | ∞"` quando `has_infinite_reserve()`; alerta de pouca munição considera só o pente |
| Barra do chefão (0.9.11) | `BossBar` (`src/hud/boss_bar.gd`; `set_health_pct(pct)`, `hide_bar()`), topo centralizado logo abaixo do espaço da `WaveBanner`; nome `"CACHAÇO REI"`. Aparece com `horde_boss_health_changed > 0`, esvazia e some 1 s depois do `0`, some na hora em `hunt_ended`. Enquanto visível, a `Hud` desce com um offset único os blocos centrados `ContextMessage`, `DownBanner`, `SpectateBanner`, `SpectateHint`, `DownedLabel`, `DownedHint` e `HintBanner` (`arquitetura.md` §8.4) |
| Fim | `VICTORY` → `"Celeiro defendido!"`; `DEFEAT_CROP` → `"O celeiro foi devorado!"`; demais como hoje |

O HUD guarda `wave_total` e `remaining` dos sinais; não calcula nada de rede. `WaveLabel` e `WaveBanner` são
nomes de nó (os testes os acham com `find_child(name, true, false)`).

---

## 9. Rede (Pacote N e Pacote B)

### 9.1 Modo na sala (N)

API nova do autoload `Net` (§6.11 de `arquitetura.md`):
```gdscript
func host_select_mode(mode: StringName) -> bool   # só anfitrião, só em LOBBY; mode em NetCodec.MODES;
                                                  # &"horde" exige Data.get_horde() não vazio e o mapa dele disponível.
                                                  # Mudou: L_LOBBY para todos + roster_changed. Não mexe em mapa/contrato escolhidos.
func get_selected_mode() -> StringName            # (&"contract") o modo da sala; volta a &"contract" em create_room/join_room/leave_room
```

Registros (layout completo em `docs/multiplayer.md` §4.5):

| Registro | Antes | Depois |
|---|---|---|
| `L_LOBBY` | `state u8, map u8, contract u8, n u8, n×{slot, flags, weapon0, dog}` (4+4n) | **+ `mode u8` no fim** (5+4n). Ausente = contrato |
| `L_START` | `map u8, contract u8, rng_seed u32, player_count u8, slots_mask u8, dog[net.max_players] u8` (12) | **+ `mode u8` no fim**, na posição `8 + net.max_players` (13). Ausente = contrato |

`mode u8` = índice em `NetCodec.MODES`; desconhecido = contrato. O cliente grava o modo do `L_LOBBY` (em `LOBBY`)
e do `L_START`. Em `_enter_loading`, depois do que já preenche hoje, o `Net` grava `request.mode = <modo da
sala>`; se horda, também `request.map_id = StringName(Data.get_horde()["map_id"])` e `request.contract_index = 0`
(em todos os peers; o `L_START` continua levando o mapa/contrato do lobby, sem uso na horda).
`host_start_hunt` não muda (o contrato selecionado continua válido).

### 9.2 `EV_HORDE_WAVE` (B: `HuntHostSync` escreve, `HuntReplica` lê)

`EV_HORDE_WAVE` (`0x2C`), H→C, pista E, **7 bytes**:
```
wave u8          1..wave_count (onda anunciada no intervalo / em curso)
wave_count u8
phase u8         índice em NetCodec.HORDE_PHASES (0 intervalo, 1 onda)
countdown u16    ×0,1 s, arredondado para cima; 0 na fase onda
wave_total u8    javalis da onda `wave`, já escalados
killed_before u8 abates da partida (o killed do EV_BOAR_DEATH) quando a fase começou
```
Enviado uma vez por `wave_changed` no anfitrião (2 por onda). O `Net` já despacha qualquer tipo
`0x21..0x3F` do anfitrião para `world.net_apply_event`; nada muda no `Net`.

- `HuntHostSync`: `func queue_horde_wave(wave: int, wave_count: int, phase: StringName, countdown_s: float, wave_total: int, killed_before: int) -> void`
  e `func write_horde_wave_replay(out: StreamPeerBuffer, wave: int, wave_count: int, phase: StringName, countdown_s: float, wave_total: int, killed_before: int) -> void` (1 registro).
- `HuntReplica`: `signal horde_wave_received(wave: int, wave_count: int, phase: StringName, countdown_s: float, wave_total: int, killed_before: int)`;
  ignora corpo < 7 bytes.
- `HuntController` (cliente): guarda o estado, recomeça o contador local, emite `horde_wave_changed`; se fase
  onda, emite `horde_wave_progress(remaining, wave_total)` com `remaining = clampi(wave_total − (_net_killed −
  killed_before), 0, wave_total)`, e o reemite a cada `kill_confirmed` (depois do `boar_counts_changed`).
  Ondas vencidas do cliente: fase intervalo da onda w → `w − 1`; vitória → `wave_count`.

### 9.3 Snapshot, fim e reconexão

- `H_SNAPSHOT`: **nenhum byte muda.** `crop u16` = estoque; `flags b0` = "javalis no celeiro". Até 26 vivos: o
  orçamento de banda do §4.6 de `multiplayer.md` vale igual.
- `EV_HUNT_END`, `EV_BOAR_*`: sem mudança (`killed/total` da partida, ≤ 255 por D3).
- `EV_FULL_SYNC` (F8): cabeçalho sem mudança (`crop` = estoque). A repetição ganha, **só em horda**, um
  `EV_HORDE_WAVE` com o estado atual (`countdown` = restante), depois das `EV_DOG_MARK` e antes do
  `EV_HUNT_END`, contado em `n_records`. Em horda não há `EV_CROP_EATEN` na repetição. Diário: até 255
  nascimentos + 255 abates = ~7,7 kB (contra 1,9 kB no pior contrato), ~8 quadros de ≤ 1100 B, dentro de
  `reliable_window` (64) e do balde do servidor.
- `PROTOCOL_VERSION` continua **1**; `config/version` sobe para **0.5.0** (coordenação), e salas já exigem
  versão igual. Servidor (`server/`) não muda.

### 9.4 `EV_BOSS_HP` e a mensagem do chefão (0.9.11; B)

`EV_BOSS_HP` (`0x2F`), H→C, pista E, corpo **1 byte**: `pct u8` (0..100). Registro de 4 bytes (3 de cabeçalho + 1).
O anfitrião envia 100 quando o chefão nasce, depois **a cada 0,25 s (4 Hz) enquanto ele vive, mesmo sem mudança de vida**
(~16 B/s por cliente), e um registro `0` quando ele morre. `HuntHostSync.queue_boss_health(pct: float) -> void` escreve;
`HuntReplica` lê (ignora corpo vazio) e emite direto `GameEvents.horde_boss_health_changed(float(pct))`. O `Net` já despacha
`0x21..0x3F` para `world.net_apply_event`; nada muda nele.

- **`EV_FULL_SYNC` não carrega `EV_BOSS_HP`** (limitação conhecida): a barra do cliente que volta de um rejoin com o chefão vivo
  depende da repetição (≤ 0,25 s de atraso). Plausível, não exercitado por teste.
- **`EV_MESSAGE` msg 6 = chefão** (`HuntController.NET_MSG_BOSS = 6`, `MSG_BOSS`, texto na §12). Por que 6 e não 3: os códigos
  3..5 são do cão (`Dog.NET_MSG_NO_BOAR`, `NET_MSG_RETREAT`, `NET_MSG_RECOVERED`; texto em `Dog.MESSAGES`), então
  `HuntController.NET_MESSAGES` tem buracos `""` em 3..5 (caem no `Dog.MESSAGES`) e o chefão ficou no primeiro código livre.

---

## 10. Meta-jogo, lobby e resultado (game-systems)

### 10.1 `Data` e `Profile`

```gdscript
# Data (§6.2)
func get_horde() -> Dictionary        # data/horde.json inteiro; {} se ausente (e erro em get_load_errors)
# Profile (§6.3)                                                                                   stub
func horde_kill_reward(type_id: StringName, weight_kg: float, killing_zone: StringName, one_shot: bool) -> int   # 0
func horde_bonus(stock_pct: float) -> int                                                                         # 0
```
`horde_kill_reward` = `RewardCalculator.kill_reward(type_def, rules, weight_kg, killing_zone, one_shot,
{"reward_mult": horde.kill_reward_mult})` (0 para tipo desconhecido). `horde_bonus` =
`RewardCalculator.contract_bonus({"bonus_money": horde.victory_bonus_money}, stock_pct)`. `apply_hunt_result`,
`build_hunt_request` e `RewardCalculator` não mudam.

### 10.2 Lobby (`src/ui/lobby/lobby.gd`) — nós novos (`%` = nome único)

No painel esquerdo, acima de "Mapa e contrato": cabeçalho `"Modo de jogo"`, `%ModeLabel` (todos),
`%ModeContractButton` e `%ModeHordeButton` (só anfitrião; `toggle_mode`, `SecondaryButton`, ≥ 64 px; o do modo
atual pressionado; ao apertar → `Net.host_select_mode(...)`, falhou → `ui_error` e reflete o estado do `Net`),
`%HordeInfoLabel` (muted, quebra linha, visível só em horda, texto = `horde.description`).

| Modo da sala (`Net.get_selected_mode()`) | Contrato | Horda |
|---|---|---|
| `%ModeLabel` | `"Modo: Contrato"` | `"Modo: Horda Javali"` |
| cabeçalho "Mapa e contrato", `%MapOption`, `Contract_<i>` | como hoje | escondidos |
| `%ContractLabel` | como hoje | `"%s: Horda Javali, %d ondas"` (nome do mapa de `horde.map_id`, `waves.size()`) |
| Detalhe de cada jogador (`Info/Detail`) | arma do loadout | `"Todas as armas"` no lugar da arma |
| `LoadoutPanel` | como hoje | `set_weapons_locked("Na Horda Javali todos levam todas as armas, com munição infinita.")` |
| `%StartButton` | `"Iniciar caçada"` | `"Iniciar horda"` |

`LoadoutPanel` ganha `func set_weapons_locked(text: String) -> void` (`""` destrava): desabilita
`%WeaponSlot0`/`%WeaponSlot1` e mostra `text` em `%WeaponsLockedLabel`. A Preparação não chama. `_begin_hunt`
não muda (o `Net` grava o modo, §9.1).

### 10.3 Resultado (`src/ui/result/result.gd`), com `result.is_horde()`

| Item | Horda |
|---|---|
| Título | `VICTORY` `"Celeiro defendido!"`; `DEFEAT_CROP` `"O celeiro foi devorado"`; `DEFEAT_DEATH` `"Derrota: os caçadores caíram"`; `ABANDONED` `"Horda abandonada"`; `DISCONNECTED` como hoje |
| Dica | `DEFEAT_CROP` `"Os abates feitos foram pagos. Fiquem perto do celeiro e derrubem primeiro quem já está comendo o milho. A ceva de milho afasta parte da horda."`; `DEFEAT_DEATH` `"Os abates feitos foram pagos. Machos e cachaços raspam o chão antes de investir: saia da linha da corrida. O colete de couro reduz o dano."`; `ABANDONED` `"Os abates feitos foram pagos. O bônus de defesa só sai na vitória."`; `DISCONNECTED` como hoje |
| Cabeçalho | `"Horda Javali  \|  %s"` (nome do mapa) no lugar de `"Contrato %d: …"` |
| Abates | em rede `"Seus abates: %d · Equipe: %d"`; offline `"Abates: %d"` (sem "de N") |
| Linha nova | `_value_row("Ondas vencidas", "%d de %d")` (`horde_waves_cleared`, `horde_wave_count`) |
| Estoque | `"Celeiro preservado"` no lugar de `"Lavoura preservada"` |
| Bônus | rótulo `"Bônus de defesa"`; vitória: `"Celeiro em %d%% de %s"` (máximo = `horde.victory_bonus_money`); derrota: `"Só na vitória (até %s)"` |
| Escondidos | `%RetryButton`, a meta de "Próximo contrato liberado" e o `NO_PROGRESS_TEXT` |
| `%ContinueButton` | como hoje (em sala: "Voltar à sala") |

---

## 11. Arte e som (art-director, 100% procedural)

### 11.1 Estoque de milho — `res://assets/models/props/barn_corn.tscn` (`ScenePaths.BARN_CORN`)

- Raiz `Node3D` com script `res://assets/models/props/barn_corn.gd` que **estende `CornStockVisualBase`**.
  Regras gerais da §7 de `arquitetura.md` (sem física, sem luz, malha em código, não mexe na raiz).
- Referencial = o do prop `barn` (16 × 7 × 10 m, aberto em −Z): origem no chão no centro do galpão, frente −Z.
  O gameplay põe a raiz na posição/yaw do `PropSpawn` do celeiro; o galpão continua sendo o prop `barn`.
- Conteúdo: um monte grande de espigas dentro do galpão (cabe em 14 × 8 m, ≤ 3 m de altura, visível pela
  frente aberta) e montes/sacos/balaios em volta do galpão **sobre o anel de raio `ring_radius_m`** recebido em
  `setup` (pelo menos 6 montes, o primeiro em −Z), que é onde os javalis comem.
- Estágios (`CornStockVisualBase.stage_for(pct)`): 4 cheio; 3, 2, 1 progressivamente menores (montes de fora
  diminuem e somem, o de dentro baixa); 0 = vazio (palha e espigas roídas no chão). Troca de estágio
  instantânea ou em ≤ 0,5 s.
- Orçamento: ≤ 900 triângulos, ≤ 8 `MeshInstance3D`, 1–2 materiais compartilhados, cor por vértice (milho
  `#E8B923`, palha `#C2A95A`, saco `#B9A27A`), `cast_shadow` só no monte de dentro.

| Método | Contrato |
|---|---|
| `setup(ring_radius_m: float) -> void` | exatamente uma vez, antes de `add_child`; posiciona os montes de fora no anel |
| `set_stock_pct(pct: float) -> void` | 0–100; mostra `stage_for(pct)`; chamado a cada mudança (idempotente) |
| `set_under_attack(on: bool) -> void` | cosmético opcional (espigas tremendo, grãos voando); no-op é aceito |
| `static stage_for(pct: float) -> int` | já na base |

Fallback (B): `CornStockVisualBase.create_fallback()` (6 cones amarelos que encolhem por estágio).

### 11.2 Sons novos (autoload `Sfx`, §7.8)

| Id | Quem toca | Descrição |
|---|---|---|
| `horde_wave_start` | A (HUD) | berrante/corneta grave e curta, ~1,5 s, anuncia a onda |
| `horde_wave_clear` | A (HUD) | vinheta curta de alívio, ~1 s, mais leve que `victory_sting` |
| `boar_boss_roar` (0.9.11) | B (`Boar.start()`, `BoarPuppet._ready()`) | rugido grave do chefão, ~2,4 s, uma vez ao entrar; som lazy de `assets/audio/synth/synth_world.gd`, via `Sfx.play_3d` |

Síntese procedural obrigatória (fallback); MP3 opcional pela regra de `sfx_prompts.json`. `has_sound()` passa a
ser verdadeiro para os dois.

### 11.3 Ícone

`res://assets/ui/icons/barn.svg` (`ScenePaths.icon(&"barn")`), 128 × 128, silhueta de galpão com espiga, para
minimapa, bússola e o botão de modo do lobby. Fallback: quadrado/texto.

---

## 12. Textos PT-BR (exatos)

| Onde | Texto |
|---|---|
| Lobby | `"Modo de jogo"`, `"Contrato"`, `"Horda Javali"`, `"Modo: Contrato"`, `"Modo: Horda Javali"`, `"%s: Horda Javali, %d ondas"`, `"Todas as armas"`, `"Iniciar horda"`, `"Na Horda Javali todos levam todas as armas, com munição infinita."`; descrição = `horde.description` |
| HUD | `"Celeiro %d%%"`, `"Javalis no celeiro!"`, `"Onda %d/%d · faltam %d"`, `"Onda %d/%d em %d s"`, `"Onda –"`, `"Defenda o celeiro! A horda chega em %d s"`, `"Onda %d de %d"`, `"Última onda! Onda %d de %d"`, `"Onda %d vencida!"`, `"%d | ∞"`, `"Celeiro defendido!"`, `"O celeiro foi devorado!"` |
| Resultado | §10.3 |
| Mensagem do alfa | `"O cachaço alfa entrou na área!"` (a de hoje) |
| Chefão (0.9.11) | `boss.name` `"Cachaço rei"`; `HuntController.MSG_BOSS` `"O cachaço rei entrou na área!"`; nome na `BossBar` `"CACHAÇO REI"` |

---

## 13. Desempenho, limites e riscos

- **Orçamento:** igual ao do contrato 5 com 4 jogadores: ≤ 26 vivos (`hunt.max_alive_boars`), ≤ 12 carcaças
  visíveis, + `BarnCorn` (≤ 900 tris, ≤ 8 instâncias). Cada `Player` instancia as 5 vistas de arma (≤ 1500 tris
  cada, só uma visível): + ~3 `WeaponViewBase` ocultas na memória, sem draw call.
- **Ids:** ≤ 255 por partida (D3). `HuntHostSync` já avisa id > 255; com dados válidos não ocorre.
- **R1 — Onda travada:** um javali que nunca chega nem morre (preso em quina de obstáculo) segura a onda para
  sempre. Mitigação: H3/H5 sempre o mandam ao anel; aceite de B mede que todos chegam a `eat` (§14). Se
  aparecer em jogo, a saída é um prazo de onda em dados — fora desta versão.
- **R2 — Arma de ouro grátis na horda:** o `.338` (300 de ouro) fica disponível a todos na horda. Pode reduzir o
  incentivo de compra/doação. Decisão da coordenação; registrada em Q2.
- **R3 — Economia:** com o seed, uma horda solo vencida rende ~R$ 6–8 mil em ~10 min (estimativa refeita com `value_per_kg` real; a primeira, R$ 12–15 mil, usava 6 R$/kg para o macho).
  Números são do game-systems (`kill_reward_mult`, `victory_bonus_money`).
- **R4 — Repetição do F8 maior:** até ~7,7 kB numa reentrada (4 mensagens de relay). Dentro dos limites
  medidos; o `coop_probe.py` deve exercitar uma reentrada em horda adiantada (onda ≥ 5).
- **R5 — Alfa não escala com jogadores:** `scale_groups` não clona grupos com alfa (regra de hoje) nem, desde a 0.9.11, com
  `boss` (`UNIQUE_TYPES`). Com 4 jogadores a última onda continua com 1 alfa (2 no Nível 2) e 1 chefão. Ajuste é em dados.
- **R6 — Ceva desvia a horda (D8):** pode deixar a defesa fácil demais; se for o caso, é dado
  (`corn_bait.effect`) ou uma regra futura "ceva sem efeito em horda" (Q4).

---

## 14. Pacotes de trabalho

Regra de dependência da §2 de `arquitetura.md` vale igual: A não referencia classes de B e vice-versa; ninguém
referencia classes de N; systems/ui não referenciam A/B. Comandos a partir da raiz, todos encerram sozinhos.
Toda entrega roda `check_scripts` e as suítes que a mudança afeta **sem mudança de resultado no modo contrato**.

### Ordem

| Etapa | Quem | Pode rodar em paralelo com | Espera |
|---|---|---|---|
| 0 | coordenação: `src/core` (feito), `--import`, `check_scripts` | — | — |
| 1 | game-systems **S1** (dados + `Data` + `Profile`) | N, A, art | etapa 0 |
| 1 | Pacote N | S1, A, art | etapa 0 |
| 1 | Pacote A | S1, N, art | etapa 0 |
| 1 | art-director | todos | etapa 0 |
| 2 | Pacote B (Fable: IA e fluxo) | S2 | S1 (chama `Profile.horde_*` e `Data.get_horde`, dependência de compilação) |
| 2 | game-systems **S2** (lobby, `LoadoutPanel`, resultado) | B | S1 e N (`Net.host_select_mode`/`get_selected_mode`, dependência de compilação) |
| 3 | qa-tester (pode escrever testes de unidade de core/dados desde a etapa 1) | — | todos para a rodada final |
| 4 | coordenação: `config/version = "0.5.0"`, export, `mobile_probe.py`, `coop_probe.py`, publicação | — | qa verde |

### Pacote B — game-developer (Fable)

Escopo: modo estoque do `CropManager`; plano de ondas e `HordeDirector`; ondas retidas/liberadas no
`BoarSpawner`; desvios H1–H7 do `Boar`; montagem de horda no `HuntController` (celeiro, visual do estoque,
getters, economia, fim, mensagens, teto de carcaças); `EV_HORDE_WAVE` no anfitrião e no cliente; repetição
no `EV_FULL_SYNC`; sandboxes.
Arquivos: `src/hunt/hunt_controller.gd`, `src/hunt/horde_director.gd` (novo), `src/hunt/boar_spawner.gd`,
`src/hunt/hunt_host_sync.gd`, `src/hunt/hunt_replica.gd`, `src/boars/boar.gd`, `src/world/crop_manager.gd`,
`src/world/map_root.gd` (`func find_prop_spawn(prop_id: StringName) -> PropSpawn`, interno), `src/hunt/debug/horde_selftest.gd|.tscn` (novo),
`src/hunt/debug/net_horde_test.gd|.tscn` (novo), `src/hunt/debug/net_hunt_e2e.gd` (cenário `horde`).
Fora: cena do mapa (o celeiro fica onde está), `dog.gd`, HUD, lobby, dados.
Aceite:
- `tools/godot.sh --headless --path . res://tests/check_scripts.tscn` verde.
- `tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/horde_selftest.tscn` imprime só
  `PASS` e `RESULT`, cobrindo: (a) `make_debug(&"mato_grosso", 0, Ids.MODE_HORDE)` monta, `get_mode() ==
  &"horde"`, `get_objective_position()` a ≤ 0,1 m de (38, y, −88), `horde_wave_changed(1, 8,
  &"intermission", 12.0)` antes do 1º javali; (b) com o jogador teleportado para (−110, y, −110) e agachado,
  para cada onda: `debug_horde_start_next_wave()`, espera todos os javalis da onda nascerem e chegarem a `eat`
  (cada um em ≤ 90 s de jogo depois de nascer), confere que o estoque caiu e que `crop.get_patch_eaten() == 0`,
  mata todos com `debug_kill_boar`, `debug_set_crop_health(100.0)`; nenhum `wander`/`flee` em
  `boar_state_changed` durante tudo; (c) ao fim de (b) → `VICTORY` 1×,
  `horde_waves_cleared == horde_wave_count == 8`, `counts_for_progression == false`, `contract_bonus ==
  Profile.horde_bonus(crop_health_pct)`, cada `kill.reward_money == Profile.horde_kill_reward(...)`, ids ≤ 255,
  nunca mais de `max_carcasses` carcaças visíveis; `horde_wave_progress` depois de `boar_counts_changed`;
  (d) `debug_set_crop_health(0)` → `DEFEAT_CROP`; `apply_damage(9999)` → `DEFEAT_DEATH`; (e) macho a 8 m do
  jogador: `scrape` ≥ 0,8 s antes de `charge`; leitão nunca entra em `scrape`.
- `tools/godot.sh --headless --path . res://tests/net_unit.tscn -- --only=net_horde` (cena registrada pelo
  qa): anfitrião e cliente no mesmo processo (ganchos `test_net_role`): cliente com mesmos
  `get_horde_wave/phase/wave_total/remaining` que o anfitrião depois de cada fase; `net_write_full_sync` em
  horda contém 1 `EV_HORDE_WAVE` e nenhum `EV_CROP_EATEN`; cliente que perdeu eventos e aplica o sync chega ao
  mesmo estado de onda; resultado do cliente `mode == &"horde"` e mesmas ondas vencidas.
- `net_test` cenário `horde` (dois processos, relay, seed fixa, `Net.host_select_mode(&"horde")`): `VICTORY` nos
  dois, `result.mode == &"horde"` nos dois, soma dos abates = total.
- Sem regressão: `hunt_selftest`, `net_unit` inteiro, `playthrough`, `flow_test` iguais a antes.

### Pacote A — game-developer (Sonnet)

Escopo: todas as armas e reserva infinita em horda; teclas 3–5; HUD de horda (§8).
Arquivos: `src/player/player.gd`, `src/weapons/weapon.gd`, `src/input/input_setup.gd`, `src/hud/hud.gd`,
`src/hud/minimap.gd`, `src/hud/compass.gd`, `src/player/debug/sandbox_world.gd` (opção de horda),
`src/player/debug/player_horde_test.gd|.tscn` (novo), `src/hud/debug/hud_horde_test.gd|.tscn` (novo).
Fora: `RemoteHunter`, `TouchControls` (sem botão novo), `PauseOverlay`, qualquer classe de B.
Aceite:
- `check_scripts` verde; nenhuma referência a classes de B/systems/N.
- `tools/godot.sh --headless --fixed-fps 60 --path . res://src/player/debug/player_horde_test.tscn`: com
  `HuntRequest.make_debug(&"mato_grosso", 0, Ids.MODE_HORDE)`, `get_weapon_count() == Data.get_weapon_ids().size()`
  e as armas na ordem do arquivo; `weapon_swap` 5× volta ao slot 0 passando por todos; `weapon_3` seleciona
  `rifle_308`; esvaziar o pente e recarregar 3× mantém `get_ammo_reserve()` igual; `has_infinite_reserve()`;
  com `make_debug()` (contrato) o comportamento e a reserva são os de hoje e `weapon_3` não troca nada.
- `tools/godot.sh --headless --path . res://src/hud/debug/hud_horde_test.tscn`: mundo falso com `is_horde()`
  e sinais emitidos à mão → textos exatos de §8/§12 em `WaveLabel`, `WaveBanner`, barra e aviso; com mundo de
  contrato, `"Lavoura 100%"`, `"Javalis 0/0"` e nenhum `WaveLabel` visível.
- `hud_net` e `tests/unit/test_input.gd` sem regressão (este último ajustado pelo qa para as 3 ações novas).

### Pacote N — game-developer (Sonnet)

Escopo: modo da sala no `Net`, bytes de modo no `L_LOBBY`/`L_START`, `request.mode`/mapa/contrato em
`_enter_loading`.
Arquivos: `src/net/net.gd`, `src/net/net_session.gd`, `src/net/debug/net_mode_selftest.gd|.tscn` (novo, processo
único, corpos de registro montados à mão), `src/net/debug/net_e2e.gd` (verificação de modo no roteiro de sala).
Fora: `EV_HORDE_WAVE` (é de B), servidor, `PROTOCOL_VERSION`.
Aceite:
- `check_scripts` verde (regra de camadas de N).
- `tools/godot.sh --headless --path . res://src/net/debug/net_mode_selftest.tscn`: `L_LOBBY` com e sem o byte
  final → `get_selected_mode()` `&"horde"`/`&"contract"`; `L_START` de 12 e de 13 bytes → idem; `host_select_mode`
  falha para cliente, fora de `LOBBY`, para id desconhecido e para `&"horde"` com `Data.get_horde()` vazio;
  `create_room` volta o modo a contrato; layout escrito pelo anfitrião = §9.1 byte a byte.
- `net_e2e` (com Bun): o cliente vê o modo escolhido pelo anfitrião antes do `L_START` e os dois `HuntRequest`
  saem com `mode == &"horde"`, `map_id == &"mato_grosso"`, `contract_index == 0`; sem Bun, `SKIP`.
- `link_selftest` e `net_e2e` do modo contrato sem regressão.

### game-systems — S1 (Sonnet), depois S2 (Sonnet)

S1 — Escopo: `data/horde.json` (seed §3.2), validação (§3.1), `Data.get_horde()`, `Profile.horde_kill_reward`,
`Profile.horde_bonus`. Arquivos: `data/horde.json`, `src/systems/data_registry.gd`, `src/systems/profile.gd`.
S2 — Escopo: seletor de modo e estado de horda no lobby, `LoadoutPanel.set_weapons_locked`, tela de resultado
de horda. Arquivos: `src/ui/lobby/lobby.gd`, `src/ui/common/loadout_panel.gd`, `src/ui/result/result.gd`,
`src/ui/result/debug/result_horde_sandbox.gd|.tscn` (novo).
Fora: menu solo, Preparação, `apply_hunt_result`, `RewardCalculator`, `data/maps.json`.
Aceite:
- `check_scripts` verde; `Data.get_load_errors()` vazio com o seed; cada regra de §3.1 quebrada à mão gera erro.
- `Profile.horde_kill_reward(&"boar", 132.0, &"vital", true) == 217`; `Profile.horde_bonus(87.0) == 2610`;
  `apply_hunt_result` de um `HuntResult` de horda vencido credita `total_money` e não muda
  `get_unlocked_contract_count`.
- `tools/godot.sh --headless --path . res://src/ui/result/debug/result_horde_sandbox.tscn`: títulos, "Ondas
  vencidas: 5 de 8", "Celeiro preservado", "Bônus de defesa" e `%RetryButton` invisível, para cada desfecho.
- Lobby a 1280×720 e 2340×1080: `%ModeContractButton`/`%ModeHordeButton` só para o anfitrião, ≥ 64 px;
  `%ModeLabel` para todos; em horda contratos escondidos e `%WeaponSlot0/1` desabilitados.
- `flow_test` do contrato sem mudança.

### art-director (Sonnet)

Escopo: §11. Arquivos: `assets/models/props/barn_corn.tscn` + `barn_corn.gd`, `assets/audio/sfx_library.gd`
(+ `assets/audio/synth/*`), `assets/audio/sfx_prompts.json` (2 entradas), `assets/ui/icons/barn.svg`,
`assets/preview/barn_corn_preview.tscn` (5 estágios lado a lado, ao lado do prop `barn`).
Fora: o prop `barn` (não muda), qualquer código fora de `assets/`.
Aceite: teste de contrato de assets em modo estrito (`unit_tests -- --strict`) com o asset novo (carrega, raiz
`CornStockVisualBase`, chama `setup`, `set_stock_pct` 0/10/30/60/90/100 e `set_under_attack` sem erro,
≤ 900 tris, ≤ 8 instâncias); `Sfx.has_sound(&"horde_wave_start")` e `(&"horde_wave_clear")`; screenshot dos 5
estágios com o galpão.

### qa-tester (Sonnet)

Arquivos: `tests/lib/contract_sigs.gd` (sinais, getters, `Profile.horde_*`, `Data.get_horde`,
`Net.host_select_mode`/`get_selected_mode`, `CornStockVisualBase`, `PlayerBase.get_weapon_count`/
`has_infinite_reserve`), `tests/check_scripts.gd` (2 sinais novos), `tests/unit/test_core.gd`
(padrões de `HuntRequest.mode`/`HuntResult.mode`, `make_debug` com 3º parâmetro, `stage_for` em 0/0,1/25/25,1/100),
`tests/unit/test_data.gd` (`horde.json`), `tests/unit/test_economy.gd` (vetores de §3.2), `tests/unit/test_horde.gd`
(novo: `HordeDirector.plan_waves` com 1, 2, 3, 4 jogadores = 85, 119, 153, 187 javalis, todos os grupos marcados com `"wave"`,
soma ≤ 255, corte com dados inflados), `tests/unit/test_assets.gd` (`barn_corn`), `tests/unit/test_input.gd`
(`weapon_3..5`), `tests/net_unit.gd` (registrar `net_horde`), `tests/net_test.gd` (cenário `horde`),
`tests/playthrough.gd` e `tests/bot/hunt_bot.gd` (cenários de horda), `tests/flow_test.gd` (rota de horda).
Aceite:
- `playthrough`: cenário H1 (horda solo, `debug_kill_boar` + `debug_horde_start_next_wave`, ao menos 1 abate por
  tiro real do bot) → `VICTORY` com as checagens de B (c); H2 (bot parado, `debug_set_crop_health(5)` após 30 s)
  → `DEFEAT_CROP`; H3 nenhum `wander`/`flee` durante H1; H4 reserva constante depois de 3 recargas. Os 4
  cenários do contrato inalterados.
- `flow_test`: rota nova a partir do menu: `Router.start_hunt(HuntRequest.make_debug(&"mato_grosso", 0,
  Ids.MODE_HORDE))` → `hunt_started` → `debug_force_end(VICTORY)` → `RESULT` com `Profile.get_money()` +=
  `Profile.horde_bonus(100.0)`, contratos desbloqueados iguais, `%RetryButton` invisível → `%ContinueButton` →
  `SHOP`. A rota do contrato não muda.
- As 4 suítes, `net_unit` e `net_test` terminam sozinhas com o código de saída certo.

---

## 15. Questões em aberto para o dono do jogo

- **Q1 — Tamanho da horda:** 8 ondas, 85 javalis solo / 187 com 4, ~10 min. Mais curto ou mais longo?
- **Q2 — Rifle .338 de graça na horda:** é item de ouro na loja. Fica liberado (decisão atual) ou a horda usa
  só armas de dinheiro?
- **Q3 — Estatística:** vitória em horda conta em "caçadas vencidas" (hoje sim) ou ganha estatística própria
  (melhor onda alcançada)?
- **Q4 — Ceva na horda:** a ceva de milho tira até 4 javalis do celeiro por 45 s. Mantém ou desliga em horda?
- **Q5 — Renascimento:** sem renascer, uma sala de 1 jogador perde na primeira morte. Aceita para a 0.5.0?
- **Q6 — Horda no menu solo** fica para depois (o código já roda offline; seria só a entrada de menu).
