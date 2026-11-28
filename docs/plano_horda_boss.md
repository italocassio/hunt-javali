# Caçada ao Javali — Horda Nível 2: 10 ondas e o chefão (plano e contrato)

Versão do contrato: **horda 2.2** (jogo alvo **0.9.11**) · complementa `docs/horda.md`,
`docs/plano_horda_nivel2.md` e `docs/arquitetura.md`. Onde este documento contradiz os anteriores, vale este.

**Pedido do dono (2026-11-28):** no modo horda **Nível 2**, (1) 8 → **10 ondas**; (2) na última onda entra um
**javali chefão** — barra de vida própria e maior, agressivo, e visivelmente grande.
**Dificuldade definida pelo dono:** o cachaço rei morre em **~20 tiros na média** e em **no mínimo 10 tiros de
cabeça**. Nome confirmado: **Cachaço rei**. Nível 1 fica com 8 ondas.

**Escopo.** Só o Nível 2. O Nível 1 continua com as 8 ondas de hoje (o array `waves` do topo de `data/horde.json`
não muda; o Nível 2 passa a ter o seu próprio `waves` em `overrides`). Modo contrato: nada muda.

Regras de sempre: mínimo necessário, nada de API inventada, relatar contrato errado. Identificadores e comentários
em inglês, texto do jogador em PT-BR exatamente como na §7.

---

## 1. Restrições duras (não negociáveis)

| # | Restrição | Onde |
|---|---|---|
| R1 | `Σ_ondas ceil(total_base × max(player_count_mult)) ≤ 255` | `NetCodec.MAX_BOARS_PER_HUNT`, validado em `data_registry._validate_horde_config` |
| R2 | Peso na rede é `u16 × 0,01 kg` → **nenhum javali pode passar de 655 kg** | `hunt_host_sync.gd:355`, `hunt_replica.gd:445` |
| R3 | Grupo de onda tem **1 ou 3–6** membros | `data_registry._validate_horde_config` |
| R4 | A última onda precisa conter um `alpha` | idem — por isso a onda 10 tem chefão **e** alfa |
| R5 | `BoarSpawner.scale_groups` nunca clona grupo que contenha `alpha` — **tem de valer para `boss` também**, senão 4 jogadores enfrentam vários chefões | `src/hunt/boar_spawner.gd:94` |
| R6 | Tipo de javali vai na rede como índice `u8` em `Data.get_boar_type_ids()` — um 5º tipo não muda protocolo | `hunt_host_sync.gd:354` |

O orçamento de ids de hoje (8 ondas, 128 javalis base, `max_mult` 1,9) já consome **247 de 255**. Por isso as 10
ondas do Nível 2 redistribuem o total em vez de somar: **129 base → 250 de orçamento** (5 de folga). O
`player_count_mult` **não muda** (sem regressão no balanceamento de 2–4 jogadores).

---

## 2. Dados — `data/boars.json`: tipo novo `boss`

Entrada nova no fim de `types` (todos os campos obrigatórios do tipo, mesma ordem dos outros):

```json
{"id": "boss", "name": "Cachaço rei", "weight_min_kg": 620.0, "weight_max_kg": 640.0, "health_per_kg": 7.0, "value_per_kg": 4.0,
 "walk_speed_mps": 2.4, "run_speed_mps": 8.0, "charge_speed_mps": 12.0, "turn_speed_deg_s": 140.0,
 "aggression": "always", "aggro_radius_m": 60.0, "max_charges": 99, "charge_damage": 40.0, "charge_telegraph_s": 0.6,
 "charge_max_distance_m": 40.0, "recover_s": 1.8,
 "vision_range_m": 60.0, "vision_fov_deg": 160.0, "hearing_mult": 1.5, "alert_time_s": 0.5,
 "crop_drain_pct_per_s": 0.35, "wounded_health_frac": 0.20, "wounded_speed_mult": 0.95,
 "flee_rest_min_s": 10.0, "flee_rest_max_s": 15.0, "dog_damage_per_s": 30.0,
 "body_scale_mult": 1.15}
```

Por que estes números:
- **Vida 4340–4480** (`620–640 kg × health_per_kg 7.0`). É o número que entrega o pedido do dono: **exatamente 10
  tiros de cabeça** com a arma mais forte do jogo e ~20 na média (tabela abaixo). A faixa de peso é estreita de
  propósito, para a contagem de tiros não variar de partida para partida. Nenhuma melhoria da loja aumenta dano de
  arma (`data/upgrades.json` só tem mochila e faca), então a tabela é estável.
- **Peso ≤ 640 kg** fica abaixo do teto da rede (R2) e dá escala `(kg/100)^(1/3)` ≈ **1,85**.
- **`body_scale_mult` 1.15** (campo novo, ver §3.2) leva a escala final a ≈ **2,1× o javali de referência** e
  ≈ **1,55× o cachaço alfa**: impressão de chefão sem inflar vida nem recompensa. O raio de corpo vira ~0,75 m.
- **Agressivo:** `always`, enxerga a 60 m, investe sem limite (`max_charges` 99) a 12 m/s. A contrapartida do
  jogador é o giro lento (`turn_speed_deg_s` 140) e o telegrafo de 0,6 s: a luta é de contorno.
- **Dano de investida 40 e `recover_s` 1,8** (em vez de 50 e 1,2 do rascunho anterior). Motivo: com 4.400 de vida o
  chefão fica ~50 s em campo, tempo para muitas investidas. A 50 de dano dois toques derrubam quem está com vida
  cheia e a sala de um jogador perde a partida; a 40, com 1,8 s entre investidas, dá para curar e para o
  companheiro levantar. **Estes dois são os botões de ajuste da luta** — se o playthrough do F5 mostrar que está
  fácil, sobe o dano antes de mexer na vida.
- **`crop_drain_pct_per_s` 0,35** (não 0,50): vivendo 10× mais que o alfa, perto do milho ele sozinho levaria
  ~17% do celeiro na luta inteira. 0,35 mantém a ameaça sem decidir a partida pelo relógio.
- **Recompensa** 640 kg × 4,0 × `kill_reward_mult` 0,5 ≈ **1.280** (o alfa fica em ~450): paga os ~20 tiros.
- Não entra em `boar_overrides` do Nível 2: o tipo só existe no Nível 2, então os números base já são os dele.

### 2.1 Tiros para matar (vida 4.480, multiplicadores de `boars.json`: cabeça ×2,5, vital ×2,0, corpo ×1,0)

| Arma | Dano | Cabeça | Vital | Corpo |
|---|---|---|---|---|
| Rifle .338 (luneta 8x) | 180 | **10** | 13 | 25 |
| Rifle .30-06 | 115 | 16 | 20 | 39 |
| Rifle .308 (luneta 4x) | 110 | 17 | 21 | 41 |
| Espingarda 12 (9 bagos, < 14 m) | 144 | — | — | 32 |
| Carabina .22 | 38 | 48 | 60 | 118 |

Média esperada de uma partida de Nível 2 (rifle bom, mistura de cabeça/vital/corpo): **~20 tiros**. ✔ pedido do dono.

### 2.2 Munição do Nível 2 — **a compensação foi revertida pela medição (2026-11-28)**

O plano previa 25 tiros de corpo no chefão contra um teto de carga de 35, e por isso subia
`ammo.reserve_cap_mags` para 8 e `ammo_crates.mags_per_crate` para 3. A medição da F5b derrubou a premissa: a luta
real custa **11 tiros com o .338 e 19 com o .30-06** (§2.3), e o caçador terminou a onda 10 usando **29–32
cartuchos de 45, sem ficar sem munição uma única vez**, com a terceira caixa nem sendo consumida.

**Decisão: o bloco `ammo`/`ammo_crates` do Nível 2 fica exatamente como já estava publicado** —
`start_reserve_mags` 2, `reserve_cap_mags` **6**, `mags_per_crate` **2**, 3 caixas, `respawn_s` 60 s. Com 35
cartuchos de carga contra os 29–32 medidos, a onda 10 fecha com pouca sobra e obriga a ida ao celeiro, que é a
tensão que o Nível 2 foi feito para ter. Nada de dados mudou na munição; as únicas mudanças de dados desta frente
são o tipo `boss`, as 10 ondas e o `victory_bonus_money`.

Nota de projeto: teto 6 + caixa 2 é a combinação em que **três caixas enchem a reserva**, premissa do cenário H6 do
`playthrough` ("no teto o jogador não consome caixa"). Teto 8 com caixa 2 quebra essa premissa — se alguém for
mexer no teto, mexa nos dois números juntos.

### 2.3 A luta medida (F5b, `tests/boss_fight.tscn`, 3 sementes)

| Arma | Tiros | Acertos por zona | Tempo |
|---|---|---|---|
| Rifle .338 | **11** | 9 cabeça + 2 vital | 41–44 s |
| Rifle .30-06 | **19** | 12 cabeça + 4 vital + 1 corpo | 39–43 s |

**Por que menos que a tabela da §2.1:** na escala 2,13 a caixa da cabeça fica na frente do peito, então tiro mirado
no vital registra `head` (9 de 11). A tabela da §2.1 continua certa por zona; o que ela descreve de forma otimista
é a mistura de zonas que um jogador consegue de fato. O piso de 10 tiros de cabeça do dono continua valendo e está
travado por `test_data::test_boss_needs_many_shots_with_the_strongest_weapon`.

Investidas: o chefão sozinho encaixa 1 a 3 no duelo de ~40 s (40–120 de dano). Com a onda 10 inteira o caçador leva
80–250 — o aperto vem da escolta, não do chefão. Celeiro perdido na onda 10: 16–42 pontos (nos duelos, 0: o chefão
persegue o caçador em vez de ir ao milho). Ressalva de método: o bot fica parado a ~16 m, então as investidas
encaixadas são **limite superior**.

---

## 3. Dados — `data/horde.json`: 10 ondas do Nível 2

### 3.1 `levels[1].overrides`

Acrescenta `"waves"` (chave já permitida em `HORDE_OVERRIDE_KEYS`) e sobe o bônus de vitória, que agora cobre duas
ondas a mais:

```json
"overrides": {"to_barn_speed_frac": 0.9, "kill_reward_mult": 0.5, "victory_bonus_money": 6000, "waves": [
  {"groups": [
    {"members": ["sow", "piglet", "piglet"], "spawn_zone": 1, "delay_s": 0.0},
    {"members": ["piglet", "piglet", "piglet"], "spawn_zone": 3, "delay_s": 6.0}]},
  {"groups": [
    {"members": ["sow", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0},
    {"members": ["sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 5.0}]},
  {"groups": [
    {"members": ["sow", "sow", "piglet", "piglet"], "spawn_zone": 1, "delay_s": 0.0},
    {"members": ["boar"], "spawn_zone": 3, "delay_s": 6.0},
    {"members": ["sow", "piglet", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 10.0}]},
  {"groups": [
    {"members": ["boar", "sow", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0},
    {"members": ["sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 6.0},
    {"members": ["boar", "sow", "piglet"], "spawn_zone": 3, "delay_s": 12.0}]},
  {"groups": [
    {"members": ["boar", "sow", "sow", "piglet", "piglet"], "spawn_zone": 1, "delay_s": 0.0},
    {"members": ["sow", "piglet", "piglet", "piglet"], "spawn_zone": 3, "delay_s": 5.0},
    {"members": ["boar", "sow", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 10.0}]},
  {"groups": [
    {"members": ["boar", "sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 0.0},
    {"members": ["boar", "sow", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 5.0},
    {"members": ["sow", "sow", "piglet", "piglet"], "spawn_zone": 3, "delay_s": 10.0}]},
  {"groups": [
    {"members": ["boar", "boar", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 1, "delay_s": 0.0},
    {"members": ["boar", "sow", "sow", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 5.0},
    {"members": ["sow", "piglet", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 10.0}]},
  {"groups": [
    {"members": ["boar", "boar", "sow", "sow", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 0.0},
    {"members": ["boar", "sow", "sow", "piglet", "piglet"], "spawn_zone": 1, "delay_s": 5.0},
    {"members": ["boar", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 3, "delay_s": 10.0}]},
  {"groups": [
    {"members": ["alpha"], "spawn_zone": 1, "delay_s": 0.0},
    {"members": ["boar", "boar", "sow", "sow", "piglet", "piglet"], "spawn_zone": 0, "delay_s": 4.0},
    {"members": ["boar", "sow", "sow", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 9.0},
    {"members": ["boar", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 3, "delay_s": 14.0}]},
  {"groups": [
    {"members": ["boss"], "spawn_zone": 1, "delay_s": 0.0},
    {"members": ["alpha", "boar", "boar"], "spawn_zone": 0, "delay_s": 5.0},
    {"members": ["boar", "sow", "sow", "piglet", "piglet", "piglet"], "spawn_zone": 2, "delay_s": 9.0},
    {"members": ["boar", "sow", "sow", "piglet", "piglet"], "spawn_zone": 3, "delay_s": 13.0},
    {"members": ["boar", "sow", "piglet"], "spawn_zone": 1, "delay_s": 17.0}]}
]}
```

Totais base por onda: **6, 8, 10, 12, 13, 14, 15, 16, 17, 18 = 129**.
Orçamento de ids (×1,9, arredondado para cima por onda): 12+16+19+23+25+27+29+31+33+35 = **250 ≤ 255** (R1).
O chefão entra **sozinho e primeiro** na onda 10; o resto da onda chega atrás dele.

### 3.2 Campo novo `body_scale_mult` (`data/boars.json`)

Multiplicador opcional da escala do corpo, **default 1.0**, por tipo. Validação em `data_registry`: se presente,
número em `(0,5 … 3,0]`. Os tipos de hoje não declaram o campo e não mudam.

### 3.3 Validação que precisa continuar valendo

`_validate_horde_level` já revalida o nível inteiro quando `overrides` não está vazio, então as 10 ondas do Nível 2
passam por R1, R3 e R4 automaticamente. **Nada a relaxar.** Confira que a mensagem de erro aparece com o rótulo
`horde level 2`.

---

## 4. Contrato de código

### 4.1 `src/core/` — acréscimos (a coordenação aplica; nenhum agente edita)

```gdscript
# src/core/ids.gd
const BOSS: StringName = &"boss"

# src/core/game_events.gd  (bloco "Horde mode")
## Vida do chefão da última onda, 0..100; 100 ao aparecer, 0 quando morre. B HuntController -> A Hud
signal horde_boss_health_changed(pct: float)

# src/core/net_codec.gd
const EV_BOSS_HP: int = 0x2F           ## Horde: vida do chefão, pct u8 (0..100)
```

### 4.2 Pacote B — comportamento do chefão (`src/boars`, `src/hunt`)

1. **Escala.** `Boar.setup` e `BoarPuppet.setup` passam a multiplicar a escala pelo `body_scale_mult` do tipo:
   `body_scale = BoarVisualBase.scale_for_weight(weight_kg) * mult`. Em `Boar.setup` o tipo é lido **depois** da
   escala hoje (`boar.gd:185` antes de `boar.gd:189`): leia o def antes. No puppet use
   `Data.get_horde_boar_type(type_id, horde_level)`, que já é o que o nível passa.
2. **Cão.** `Boar._dog_time` (`boar.gd:1023`) trata `Ids.BOSS` como `Ids.ALPHA`: o chefão se solta do cão no
   `alpha_break_free_s`.
3. **Clonagem (R5).** `BoarSpawner.scale_groups` (`boar_spawner.gd:94`) exclui dos `sources` todo grupo que contenha
   `alpha` **ou** `boss`.
4. **Vida na HUD.** O `HuntController` acompanha o javali vivo cujo `type_id == Ids.BOSS` e emite
   `GameEvents.horde_boss_health_changed(pct)`: 100 ao nascer, a cada mudança de vida com limite de **4 Hz**, e 0 na
   morte. Só em `is_horde()`. Dano do cão (`Boar.apply_dog_damage`) **não** passa por `boar_hit`, então a HUD não
   pode somar dano: é o host/offline que manda o pct.
5. **Rede.** `HuntHostSync` envia `EV_BOSS_HP` (1 byte, pct) na mesma cadência de 4 Hz enquanto o chefão vive — a
   repetição também resolve o rejoin, sem mexer em `EV_FULL_SYNC`. `HuntReplica` lê e emite
   `GameEvents.horde_boss_health_changed`.
6. **Aviso de entrada.** `HuntController._on_group_entered` (`hunt_controller.gd:958`): com `leader_type == Ids.BOSS`
   mostra `MSG_BOSS` (§7) e manda **`NET_MSG_BOSS = 6`**. *(Correção de 2026-11-28: este plano pedia 3, que está
   errado — 3 é `Dog.NET_MSG_NO_BOAR` (`src/dogs/dog.gd:43`, códigos 3..5 são do cão). Um 4º item em
   `NET_MESSAGES` faria o cliente mostrar o aviso do chefão no lugar de "O cão não farejou nenhum javali por
   perto.". O chefão fica no primeiro código livre, 6, com 3..5 como buracos vazios que caem no `Dog.MESSAGES`.)*
   O teste do `leader_type` que
   hoje filtra tudo que não é alfa em horda precisa deixar o chefão passar, e a checagem do chefão vem **antes** da
   de `count == 1` (o grupo dele tem um membro só).

### 4.3 Pacote A — barra do chefão (`src/hud`)

Componente novo `src/hud/boss_bar.gd` (`class_name BossBar extends Control`), criado e posicionado pela `Hud`:

- Ancorado no **topo, centralizado**, logo abaixo do espaço da faixa de onda (`HORDE_BANNER_GAP_PX +
  HORDE_BANNER_HEIGHT_PX` sob a base real do painel do celeiro) — nunca por cima da bússola, do painel do celeiro,
  da faixa de onda nem da faixa de contexto.
- Largura 44% da tela (mínimo 320 px, máximo 720 px), altura 22 px, mais o nome **`CACHAÇO REI`** acima em caixa
  alta. Trilho escuro, preenchimento vermelho-sangue, borda fina clara, 4 marcas divisórias. Use os tokens do tema
  da UI; nada de cor inventada fora do `UiKit`/tema.
- API: `set_health_pct(pct: float)`, `hide_bar()`. A `Hud` liga em `GameEvents.horde_boss_health_changed`: `> 0`
  aparece (com um fade curto de entrada), `0` esvazia e esconde depois de ~1 s, `hunt_ended` esconde na hora.
- Interpolação: o preenchimento persegue o valor alvo (~8 unidades por frame a 60 fps) para o pct de 4 Hz não
  aparecer aos saltos.
- Toque: a barra é só leitura, não recebe entrada, e no layout de toque continua abaixo do bloco do topo.

### 4.4 Arte (`assets/`)

- `assets/models/boar/boar_hd_model.gd`: entrada de `palette()` para `Ids.BOSS` (mais escuro e grisalho que o alfa,
  presas bem maiores: `tusk` ~1,8, `tusk_w` ~1,6, `mane` ~0,13 com `mane_long`), entrada em `tusk_bucket()`
  (`inverse_lerp(520, 640, kg)`) e corcova de ombro maior que a do alfa nas duas chamadas de `hump`.
- `assets/models/boar/boar_visual.gd:153`: `Ids.BOSS` entra na lista de tipos aceitos.
- `assets/preview/preview_boars.gd` e `preview_boar_hd.gd`: incluir o chefão (peso 600) para render de conferência.
- Som: rugido do chefão em `assets/audio/synth/synth_world.gd` com id `boar_boss_roar`, tocado pela entrada do
  chefão (a HUD/B dispara o som já existente de onda; o rugido entra junto do `MSG_BOSS`).
- Custo: um 5º tipo acrescenta um conjunto de malhas no cache (`_key` inclui o `type_id`). Confira o aquecimento
  (`src/hunt/shader_warmup.gd`) e o orçamento de triângulos do preview HD.

---

## 5. Tarefas

Ordem: **F0 → F1 → (F2 ‖ F4) → F3 → F5 → F6**. F2 e F4 podem rodar em paralelo depois de F1; F3 depende do sinal de
F0 e pode começar junto de F2 (a HUD só precisa do sinal, não da emissão).

### F0 — Coordenação (sessão principal, sem agente) — **feita em 2026-11-28**
Os três acréscimos da §4.1 em `src/core/ids.gd`, `src/core/game_events.gd`, `src/core/net_codec.gd`, mais o
registro do sinal novo na lista de contrato `tests/lib/contract_sigs.gd` (`check_scripts` reprova sinal do
`GameEvents` fora dessa lista). `check_scripts` 19/19. **Nenhum agente edita estes quatro arquivos.**

### F1 — `game-systems` (modelo: sonnet)
**Arquivos:** `data/boars.json`, `data/horde.json`, `src/systems/data_registry.gd`.
**Fazer:** o tipo `boss` da §2; os dois ajustes de munição da §2.2 (`reserve_cap_mags` 8, `mags_per_crate` 3); o
`overrides` do Nível 2 da §3.1 (inclusive `victory_bonus_money` 6000); validação do campo `body_scale_mult` da §3.2.
**Fora do escopo:** `player_count_mult`, as 8 ondas do topo (Nível 1), `positions`/`respawn_s` das caixas, qualquer
arquivo em `src/hud`, `src/boars`, `src/hunt`, `assets/`. Não editar `project.godot`.
**Aceite:** `tools/godot.sh --headless --path . res://tests/check_scripts.tscn` e `res://tests/unit_tests.tscn`
passam; o registro de dados não acusa erro (orçamento de ids = 250); o lobby mostra "10 ondas" no Nível 2 e
"8 ondas" no Nível 1 (`src/ui/lobby/lobby.gd:464` já lê `waves.size()` do nível resolvido — só conferir, não mudar).
**Relatar:** orçamento de ids calculado pelo seu lado; a tabela de tiros para matar da §2.1 recalculada a partir dos
dados que você gravou (vida mínima e máxima, por arma e por zona), confirmando **≥ 10 tiros de cabeça** com a arma
mais forte; e se o peso do chefão quebra algum recorde/formatação de peso no `Profile` ou na mensagem de abate.

### F2 — `game-developer` Pacote B (modelo: **opus** — caminho crítico: IA do javali e rede)
**Arquivos:** `src/boars/boar.gd`, `src/boars/boar_puppet.gd`, `src/hunt/boar_spawner.gd`,
`src/hunt/hunt_controller.gd`, `src/hunt/hunt_host_sync.gd`, `src/hunt/hunt_replica.gd`.
**Fazer:** os 6 itens da §4.2.
**Fora do escopo:** `src/core/*` (já aplicado em F0), `src/hud/*`, `data/*`, `assets/*`, `export_presets.cfg`,
`project.godot`. Não mexer na rota (`horde_route.gd`) nem no `HordeDirector`.
**Aceite:** `check_scripts`, `unit_tests`, `flow_test` e `playthrough` passam;
`res://src/hunt/debug/horde2_selftest.tscn` e `res://src/hunt/debug/net_horde2_test.tscn` passam; com 4 jogadores o
plano do Nível 2 tem **exatamente um** `boss` e **exatamente dois** `alpha`.
**Relatar:** quantos bytes/s o `EV_BOSS_HP` acrescenta e se o chefão (raio ~0,75 m) atravessa o portão da cerca e a
porta do celeiro sem travar.

### F3 — `game-developer` Pacote A (modelo: sonnet)
**Arquivos:** `src/hud/boss_bar.gd` (novo), `src/hud/hud.gd`, `src/hud/debug/hud_horde2_test.gd`.
**Fazer:** a §4.3 e um caso no teste de HUD que emite `horde_boss_health_changed` em 100 → 40 → 0 e confere
visibilidade, largura e que a barra não encosta nos outros blocos do topo.
**Fora do escopo:** `src/core/*`, `src/hunt/*`, `src/boars/*`, `data/*`, `assets/*`. Não mexer no restante do layout
da HUD nem nos controles de toque.
**Aceite:** `check_scripts`, `unit_tests` e `res://src/hud/debug/hud_horde2_test.tscn` passam; screenshot com janela
em 1280×720 e em 390×844 (retrato de celular) mostrando a barra cheia e pela metade.
**Relatar:** posição final em pixels e o que ficou acima/abaixo dela.

### F4 — `art-director` (modelo: sonnet)
**Arquivos:** `assets/models/boar/boar_hd_model.gd`, `assets/models/boar/boar_visual.gd`,
`assets/preview/preview_boars.gd`, `assets/preview/preview_boar_hd.gd`, `assets/audio/synth/synth_world.gd`.
**Fazer:** a §4.4. Depende de F1 (o tipo `boss` precisa existir nos dados).
**Fora do escopo:** `src/*`, `data/*`, qualquer imagem raster nova (arte 100% procedural), o visual da barra de vida
(é do F3).
**Aceite:** `check_scripts` e `unit_tests` passam; render de conferência com os 5 tipos lado a lado mostrando o
chefão nitidamente maior que o alfa; orçamento de triângulos e tempo de aquecimento relatados.
**Relatar:** triângulos por LOD do chefão e o custo do conjunto de malhas a mais.

### F5 — `qa-tester` (modelo: sonnet)
**Arquivos:** `tests/unit/test_data.gd`, `tests/unit/test_coop.gd`, `tests/unit/test_assets.gd`,
`src/hunt/debug/horde_selftest.gd`, `src/hunt/debug/net_flow_test.gd`.
**Fazer:** estender os testes que têm lista fixa de tipos de javali (`[piglet, sow, boar, alpha]` em `test_data.gd:23`,
`test_assets.gd:14`, `preview_boar_hd.gd:14`) e os que contam `alpha` em grupos clonados (`test_coop.gd:32,132`,
`net_flow_test.gd:118,131`) para cobrir `boss`. Dois casos novos:
- `horde_selftest`: o plano do Nível 2 tem 10 ondas, total base 129, orçamento ≤ 255 e um único chefão em 1–4
  jogadores.
- `tests/unit/test_data.gd`: **trava o pedido do dono** — para a arma de maior dano de `weapons.json`,
  `vida_mínima_do_boss / (dano × multiplicador de cabeça) ≥ 10`, e o mesmo cálculo no corpo entre 20 e 30. Esse
  teste é o que impede um ajuste futuro de deixar a luta fácil sem alguém perceber.
**Rodar, nesta ordem:** `--import` (se houver arquivo novo), `check_scripts`, `unit_tests`, `flow_test`,
`playthrough`, `horde2_selftest`, `horde_barn_selftest`, `net_horde2_test`, `hud_horde2_test`, e a exportação Web.
`mobile_probe` **não** é necessário (nenhum controle de toque mudou).
**Fora do escopo:** corrigir o que achar nos pacotes dos outros — abra relato reproduzível.
**Aceite:** relatório com cada comando, resultado e os bugs reproduzíveis que sobraram. Além disso, **medir a luta**
no `playthrough` ou numa cena de teste: quantos tiros e quantos segundos o chefão levou, quantas investidas ele
acertou, quanto do celeiro foi perdido na onda 10 e se a munição fechou em sala de um jogador. Esse número é o que
decide se mexemos em `charge_damage`/`recover_s` (§2) ou em `respawn_s` (§2.2) — **não ajuste você mesmo**, relate.

### F6 — `game-architect` (modelo: sonnet)
**Arquivos:** `docs/arquitetura.md`, `docs/horda.md`.
**Fazer:** registrar no contrato o tipo `boss`, o campo `body_scale_mult`, o sinal
`horde_boss_health_changed`, o evento `EV_BOSS_HP`, o `BossBar` e o `waves` por nível. Só isto.
**Fora do escopo:** qualquer arquivo em `src/`, `data/` ou `assets/`; a dívida de documentação antiga (0.9.3) fica
onde está.

---

## 6. Validação final (coordenação)

```bash
tools/godot.sh --headless --path . --import
tools/godot.sh --headless --path . res://tests/check_scripts.tscn
tools/godot.sh --headless --path . res://tests/unit_tests.tscn
tools/godot.sh --headless --fixed-fps 60 --path . res://tests/flow_test.tscn
tools/godot.sh --headless --fixed-fps 60 --path . res://tests/playthrough.tscn
tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/horde2_selftest.tscn
tools/godot.sh --headless --fixed-fps 60 --path . res://src/hunt/debug/net_horde2_test.tscn
tools/godot.sh --headless --path . --export-release "Web" build/web/index.html
```

Cena de **medição**, fora da cadeia de todo commit (leva ~4 min por semente e só falha se a onda 10 não for
alcançada ou o chefão não morrer). Rode quando mexer em vida do chefão, `charge_damage`, `recover_s`, dano de arma,
multiplicadores de zona ou munição do Nível 2:

```bash
tools/godot.sh --headless --fixed-fps 60 --path . res://tests/boss_fight.tscn -- --only=duel_338,duel_3006,wave10 --seed=404
```

Depois: `config/version` → **0.9.11** em `project.godot` (só a sessão principal), commit na `main`, `build/web` na
`gh-pages` a partir de worktree limpo.

---

## 7. Texto do jogador (PT-BR, exatamente assim)

| Chave | Texto |
|---|---|
| `boars.json` `boss.name` | `Cachaço rei` |
| `HuntController.MSG_BOSS` | `O cachaço rei entrou na área!` |
| `BossBar` nome | `CACHAÇO REI` |
| `horde.json` `levels[1].description` | `Munição contada: os cartuchos estão no celeiro. Ninguém sai do cercado da fazenda, os javalis investem mais, e quem cair pode ser levantado por um companheiro. Dez ondas — na última vem o cachaço rei.` |

---

## 8. Decidido pelo dono e o que sobra em aberto

Decidido em 2026-11-28: nome **Cachaço rei**; **Nível 1 fica com 8 ondas**; luta de **~20 tiros, no mínimo 10 de
cabeça** (§2.1).

Resolvido depois da medição (§2.2, §2.3): a munição do Nível 2 **não mudou** — a compensação do plano foi revertida
porque a luta custa 11–19 tiros, não 25. `charge_damage` 40 e `recover_s` 1,8 ficam como estão: o chefão sozinho
encaixa 1 a 3 investidas em ~40 s, e o aperto da onda 10 vem da escolta.

Em aberto para o dono:
1. **A arma de elite mata em 11 tiros** (§2.3), contra os ~20 pedidos. O piso de 10 na cabeça está cumprido e
   travado por teste, e o .30-06 fica em 19. Se quiser que o .338 também custe ~20, o botão é `health_per_kg` do
   `boss` (7,0 → ~14,0 dobraria), mas aí o .308 e a espingarda passam de 40 e 60 tiros. Recomendação: deixar como
   está e tratar o .338 como o prêmio de quem comprou a arma de ouro.
2. **Partida mais longa:** duas ondas a mais somam ~30 s de intervalo + os javalis extras, mais ~40 s de chefão. Se
   ficar comprido, o ajuste é `intermission_s` do nível (hoje 15 s).
3. **Ouvir o rugido** (`boar_boss_roar`) no build Web: nenhum agente tem áudio e `--headless` não toca som. Está
   provado que o id resolve, sintetiza um WAV de 2,4 s, não é silêncio nem loop e dispara no nascimento do chefão —
   se o som não agradar, é refazer só ele.

Dívidas conhecidas (não bloqueiam a publicação):
- **Rejoin com o chefão vivo não está testado.** O `EV_FULL_SYNC` não carrega `EV_BOSS_HP`; a barra do cliente que
  volta depende da repetição a 4 Hz (≤ 0,25 s de atraso). Plausível, não exercitado.
- **Rugido repetido no replay do rejoin:** o `BoarPuppet._ready()` ruge de novo quando o diário é reproduzido,
  inclusive para um chefão já morto. É o mesmo defeito antigo do replay, que já reproduz os ganidos de morte;
  silenciar só o rugido exigiria API nova no `BoarPuppet`.
- Nenhum teste junta um chefão vivo a uma `BossBar` real (as cenas de caçada headless não instanciam a `Hud`).
- `start_bayed`/`start_held` com o chefão não foram exercitados (a medição usou `apply_dog_damage` direto).
- Comentário de `_boss_gone()` em `src/hunt/hunt_controller.gd` diz "(or the hunt ended with it alive)", mas
  `_finish()` não o chama — o comportamento está certo (a `Hud` esconde em `hunt_ended`), o comentário é que mente.
