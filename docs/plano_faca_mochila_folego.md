# Caçada ao Javali — Faca, mochila e fôlego (plano e contrato)

Versão do contrato: **1.7** de `docs/arquitetura.md` (jogo **0.9.5 a 0.9.8**, uma versão por fase) · complementa
`docs/arquitetura.md` e `docs/multiplayer.md`. Onde este documento contradiz um deles, vale este, até a fase fechar e o
contrato geral ser atualizado.

Retomada em sessão fria: leia `CLAUDE.md`, este documento inteiro e as seções de `docs/arquitetura.md` que a fase cita.
Não rederive o que está aqui. Regras de sempre: o mínimo necessário, nada de API inventada, relatar contrato errado.
Identificadores em inglês; texto do jogador em PT-BR **exatamente** como na §2.11.

---

## 0. Estado das fases

| Fase | O quê | Versão | Estado |
|---|---|---|---|
| F1 | Mochila: níveis na loja, espaços de equipamento, save | 0.9.5 | publicada em 23/11/2026 (main `cbde11c`, gh-pages `5adaf79`). Resíduo: `UpgradeCard` já traz os ramos de texto/retrato da faca (ativam na F4); `SaveService.item_slots_for_level(level)` é helper estático extra |
| F2 | Fôlego: corrida gasta, cansaço, barra no HUD | 0.9.6 | publicada em 23/11/2026 (main `9ec2d09`, gh-pages `e2928d9`). Resíduo: a marca do limiar é o nó irmão `StaminaMark` (`ColorRect` sob a `HealthStrip`, não filho de `Stamina`); `breath_tired` é sintetizado sob demanda (`SynthWeapons.LAZY_IDS`), sem MP3; `debug_set_stamina` não zera `_regen_wait`; `net_unit` ganhou também `player_horde2` |
| F3 | Energético: consumível que enche o fôlego | 0.9.7 | publicada em 23/11/2026 (main `2776b61`, gh-pages `404ee18`). Resíduo: a lista de 4 acessórios sobrepunha o botão `interact`, então o botão do toque **Levantar/Pegar** passou de `ox 410` para `ox 340` (§2.7, remédio de choque; `oy 380`, `d 100` iguais; §14 de `arquitetura.md` já corrigida, main `0d52deb`); `ItemBelt.stamina_restore_frac` é lido com `maxf` entre os consumíveis; `sfx_library.gd` não precisou mudar (o som entrou por `SynthWeapons.LAZY_IDS`); `Hud._update_energy_hint` exige também caçador vivo |
| F4 | Faca: golpe rápido sem slot, níveis de dano na loja, rede | 0.9.8 | pendente |

Quem fecha uma fase troca "pendente" por "publicada em DD/MM/AAAA (main `<hash>`, gh-pages `<hash>`)" e anota resíduos.

---

## 1. Resumo e decisões de design

O que existe hoje e foi conferido no código (não presuma outra coisa):
- Loadout: 2 armas (`game.loadout.weapon_slots`), até **3 equipamentos** (`game.loadout.item_slots`), 0–1 cão. O limite de
  equipamentos é lido em `Profile.set_loadout_items`/`_auto_equip` (`src/systems/profile.gd`), `SaveService.sanitize` e
  `_migrate_v1_to_v2` (`src/systems/save_service.gd`) e `LoadoutPanel` (`src/ui/common/loadout_panel.gd`). Não existe
  outro conceito de capacidade: a mochila **estende** esse número.
- Corrida já existe: ação `sprint` (Shift; no toque, analógico > 90% por 0,3 s ou trava de corrida ao empurrar além do
  anel, `virtual_joystick.gd`), `Player._sprinting` (`player.gd:890`), velocidade `player.sprint_speed_mps` 6,5 m/s,
  ruído `noise_radius_sprint_m`, bit `HF_SPRINT` no estado de rede. Não há gasto nem cansaço.
- Itens usáveis: um por ação (`InputSetup.ITEM_ACTIONS`), `ItemBelt.use_item(id)`, `GameEvents.item_used` só para
  consumíveis, o `HuntController` soma `consumables_used` de qualquer id e o `Profile` desconta no fim. No toque: botão
  Cura (kit) e botão Acessórios (os outros itens de `ITEM_ACTIONS`, com lista para cima).
- Tiro: `Weapon.fire` → `Hitscan.cast` → `HitZone.receive_hit(HitInfo)` → `Boar` aplica multiplicador de zona. Em rede o
  cliente fecha um `C_SHOT` a cada `GameEvents.shot_fired`; o anfitrião valida dano, bagos e alcance pela definição da arma
  (`hunt_host_sync.gd:_apply_shot`). O byte `weapon` é o índice em `Data.get_weapon_ids()` (hoje 0–4).
- Retratos das armas: `tools/render_weapon_art.gd` (dono: art-director, §7.9) renderiza `showcase/<id>_hd.gd` para
  `assets/ui/weapons/<id>.png` a partir da lista fixa `WEAPON_IDS`. A faca entra nela (§2.10).
- Ações de input não vivem em `project.godot` (não há seção `[input]`): `InputSetup` registra em código. Logo, nenhuma
  fase muda `project.godot` além de `config/version`.

### 1.1 Mochila (F1)

| Decisão | Valor |
|---|---|
| Id | `backpack` (`Ids.BACKPACK`), em `data/upgrades.json` (arquivo novo de melhorias compradas com dinheiro) |
| Nível inicial | 1 para todo perfil, novo ou antigo (save antigo sem o bloco = nível 1) |
| Espaços | `game.loadout.item_slots` (3, base) + `bonus_item_slots` do nível: **3 / 4 / 5 / 6** nos níveis 1 / 2 / 3 / 4 |
| Nível máximo | 4 (6 espaços; existem 8 equipamentos com o energético, então ainda há escolha) |
| Preço do nível | 0 (nv1) / **R$ 2.000** / **R$ 5.000** / **R$ 10.000**; compra sempre o próximo nível; moeda `money` |
| O que ocupa espaço | todo equipamento escolhido (passivo, ativo ou consumível); uma pilha de consumível = 1 espaço |
| Armas, cão, faca | não ocupam espaço da mochila |
| Na caçada | nada novo: a mochila só muda quantos itens entram no `HuntRequest`. Sem botão de mochila na caçada |

### 1.2 Fôlego (F2)

| Decisão | Valor (`data/game.json` → `stamina`) |
|---|---|
| Fôlego máximo | `max` 100 |
| Gasto | `sprint_drain_per_s` 10 por segundo enquanto `_sprinting` (10 s de corrida contínua) |
| Recuperação | `regen_per_s` 6 por segundo, só depois de `regen_delay_s` 1,0 s sem correr (vazio → cheio ≈ 17,7 s) |
| Cansaço | fôlego chega a 0 → cansado: não corre (anda a `walk_speed_mps`), ruído de caminhada |
| Limiar | `recover_threshold` 35: sai do cansaço quando o fôlego volta a ≥ 35 (≈ 6,8 s depois de esgotar) |
| Aviso | ao ficar cansado, mensagem de HUD por `exhausted_message_s` 2,5 s, no máximo a cada `exhausted_message_interval_s` 30 s |
| Som | `breath_tired` a cada `BREATH_INTERVAL_S` (1,4 s, constante do `Player`) enquanto cansado, só local |
| Barra | dentro da `HealthStrip`, faixa fina sob a barra de vida; aparece só com fôlego < 100% ou cansado |
| Toque | sem botão novo: a corrida do analógico (e a trava de corrida) continua; cansado, o caçador anda e volta a correr sozinho ao passar do limiar se o dedo/trava continuar |
| Teclado | Shift como hoje; segurando Shift cansado = anda; volta a correr ao passar do limiar |
| Reinício | fôlego cheio no `setup` e ao ser levantado (horda nível 2) |
| Vale para | contrato, horda e bots (realista; ver R6) |

### 1.3 Energético (F3)

| Decisão | Valor |
|---|---|
| Id / tipo | `energy_drink` (`Ids.I_ENERGY_DRINK`), equipamento `consumable` em `data/equipment.json` |
| Preço | **R$ 150** por unidade, moeda `money` |
| Por caçada / estoque | `max_per_hunt` **3**; estoque até `shop.max_consumable_owned` (9), como os outros consumíveis |
| Espaço | **ocupa 1 espaço da mochila** quando escolhido (a pilha inteira), como o kit |
| Efeito | `effect.stamina_restore_frac` 1,0: fôlego cheio **na hora** e sai do cansaço; uso instantâneo (sem tempo de uso, sem véu) |
| Recusa | com fôlego cheio não gasta: "Seu fôlego já está cheio." |
| Teclado | ação `use_energy_drink`, tecla **T**; espaço próprio na `Quickbar` (último, pela ordem de `ITEM_ACTIONS`) |
| Toque | entra na lista do botão **Acessórios** (último). Ao ficar cansado com energético na mochila, o Acessórios passa sozinho a mostrar o energético e pisca (um toque bebe); ao sair do cansaço volta ao acessório anterior |
| Perfil novo | não ganha energético grátis |

### 1.4 Faca (F4)

| Decisão | Valor |
|---|---|
| Id | `knife` (`Ids.KNIFE`), em `data/upgrades.json`; também é o `HitInfo.weapon_id` do golpe |
| Slot | nenhum: não é arma do loadout, não ocupa espaço da mochila, não entra em `get_weapon_ids()` nem na fileira de armas |
| Uso | **golpe rápido sem trocar de arma**: aperta a ação `knife` (tecla **X**; no toque, botão **Faca**), a arma some, a faca golpeia, a arma volta. Um golpe por aperto |
| Dano por golpe (antes da zona) | nível 1 **30** / 2 **45** / 3 **65** / 4 **90**; zonas como as balas (cabeça ×2,5, vitais ×2,0, corpo ×1,0, traseiro ×0,6) |
| Preço do nível | 0 (nv1, todo caçador já tem) / **R$ 1.500** / **R$ 4.000** / **R$ 8.000**; moeda `money` |
| Alcance | `reach_m` **2,2 m** a partir do olho (raio); se o raio não pega `HitZone`, ajuda de mira: esfera de `assist_radius_m` **0,35 m** no fim do alcance |
| Cadência | `swing_interval_s` **0,6 s** (1,67 golpe/s); animação e trava `swing_s` **0,45 s** |
| Ruído | `noise_radius_m` **0** (javali só reage se for atingido) |
| Durante o golpe | sem tiro, sem mira (cai como se soltasse), sem recarga, sem troca de arma, sem item; andar e correr seguem. O golpe **cancela a recarga** em andamento |
| Bloqueios | morto/caído, espectador, binóculo, kit em uso, levantando aliado, troca de arma em curso, faca em recarga |
| Referência | nv1 nos vitais (60) mata quase todo leitão (30–54 de vida); nv4 nos vitais (180) mata fêmeas e machos até 128 kg; cachaço (396–572) pede 3+ golpes |
| Abate | regras de hoje: `one_shot` se um golpe só; `clean` se cabeça/vitais. Golpes contam como disparos na precisão do resultado |
| Retrato | `assets/ui/weapons/knife.png`, gerado pela mesma ferramenta das armas |

### 1.5 Rede (quem é autoritativo, o que sincroniza)

| Sistema | Autoridade | No fio |
|---|---|---|
| Mochila | máquina do dono (loadout local, como hoje) | nada (`L_READY` não muda) |
| Fôlego / cansaço | máquina do dono (movimento já é do dono) | nada novo; `HF_SPRINT` já reflete a corrida real |
| Energético | máquina do dono (consumível local) | nada (`item_used` local; `consumables_used` por máquina) |
| Faca | "favor the shooter", como o tiro: o golpe acerta na tela de quem golpeia | o mesmo `C_SHOT`, com `weapon = NetCodec.KNIFE_WEAPON_INDEX` (254); o anfitrião valida contra o dano do **nível máximo** e o alcance da faca |

Aliados não veem animação da faca (o golpe não incrementa `shot_seq`, então ninguém ouve tiro). `PROTOCOL_VERSION`
continua 1; `config/version` 0.9.8 separa as salas.

### 1.6 Horda e cães

- Horda (`docs/horda.md`): equipamentos vêm do inventário (horda §1), então a mochila vale; fôlego, energético e faca valem
  igual (inclusive no cercado do nível 2). Nenhuma regra de horda muda; `docs/horda.md` não é editado.
- Cães: a faca usa `Layers.MASK_WEAPON_RAY` e só acerta `HitZone` de javali; cão não tem corpo, então nunca é atingido. Javali
  acuado (foxhound) ou agarrado (dogo) é o alvo natural da faca. Crédito do abate: quem dá o golpe final, como hoje.

### 1.7 Orçamento Web/mobile (§13.1 de `arquitetura.md`)

- Faca em 1ª pessoa: ≤ 4000 triângulos com o braço, ≤ 3 `MeshInstance3D`, ≤ 3 materiais com os mesmos recursos dos materiais
  dos braços/metal das armas, `cast_shadow` OFF. Visível só no golpe. Fica visível (pose de repouso) do `Player.setup` até
  `hunt_started` para que o pré-aquecimento compile os materiais atrás do overlay (sem travada no 1º golpe).
- Golpe: 1 raio + no máximo 1 consulta de esfera por golpe (≤ 1,7/s). Fôlego: aritmética por quadro. Barra: 1 `ProgressBar`.
- Retrato `knife.png` só na loja/preparação (o HUD não carrega retrato da faca). Sons novos: 4 sínteses curtas.
- Nenhuma thread, nenhum `SubViewport`, nada de shader novo. Sem custo de rede novo.

---

## 2. Contrato

### 2.1 `src/core/` — acréscimos (coordenação aplica, verbatim; ninguém mais edita)

| Fase | Arquivo | Acréscimo |
|---|---|---|
| F1 | `ids.gd` (fim do arquivo) | `# Upgrades bought with money (docs/plano_faca_mochila_folego.md). KNIFE is also HitInfo.weapon_id of a knife hit.`<br>`const BACKPACK: StringName = &"backpack"`<br>`const KNIFE: StringName = &"knife"` |
| F3 | `ids.gd` (bloco `# Equipment`, depois de `I_SCOUT_DRONE`) | `const I_ENERGY_DRINK: StringName = &"energy_drink"` |
| F4 | `hunt_request.gd` (depois de `horde_level`) | `var knife_level: int = 1                              ## Knife upgrade level (1-based), from Profile.build_hunt_request` |
| F4 | `weapon_view_base.gd` (depois de `play_draw`) | `func play_melee(_duration_s: float) -> void:   ## knife swing (knife view only); guns ignore it`<br>`	pass` |
| F4 | `net_codec.gd` (depois de `C_AMMO_CRATE`) | `const KNIFE_WEAPON_INDEX: int = 254    ## C_SHOT weapon byte of a knife swing (data/weapons.json never reaches 254 entries)` |
| F4 | `player_base.gd` (depois de `bot_fire`) | `func bot_knife() -> bool:   ## one knife swing (tests); true if the swing happened`<br>`	return false` |

`make_debug` de `HuntRequest` não muda (a faca fica no nível 1). `GameEvents` **não** ganha sinal: o fôlego é lido direto do
`Player` pelo HUD (mesmo pacote), o energético usa `item_used`, a faca usa `shot_fired`/`boar_hit`, e as compras usam
`wallet_changed`, `inventory_changed` e `loadout_changed`. Depois de aplicar, a coordenação atualiza o Apêndice A de
`arquitetura.md` ("Acréscimos 1.7") no fecho de cada fase.

### 2.2 Dados (dono: game-systems)

#### `data/upgrades.json` (novo, F1; a faca entra em F4)

Raiz `{"version": 1, "upgrades": [...]}`. Cada melhoria:

| Campo | Tipo | Regra |
|---|---|---|
| `id` | string | `"backpack"` ou `"knife"` (únicos aceitos); único; não pode repetir id de arma, equipamento ou cão |
| `name`, `short_name`, `description` | string PT-BR | não vazios; `short_name` ≤ 9 caracteres (`Data.SHORT_NAME_MAX_CHARS`) |
| `currency` | string | só `"money"` |
| `stats` | objeto | `backpack`: `{}`; `knife`: `reach_m` > 0, `0 ≤ assist_radius_m < reach_m`, `swing_s` > 0, `swing_interval_s ≥ swing_s`, `noise_radius_m ≥ 0` |
| `levels` | array ≥ 1 | `levels[i].level == i + 1`; `levels[0].price == 0`; `levels[i].price` inteiro > 0 para i ≥ 1 |
| `levels[i].bonus_item_slots` | int (só `backpack`) | ≥ 0; `levels[0]` = 0; não decrescente |
| `levels[i].damage` | float (só `knife`) | > 0; estritamente crescente |

Seed (F1 grava só a entrada `backpack`; F4 acrescenta `knife` **depois** dela):
```json
{
  "version": 1,
  "upgrades": [
    {"id": "backpack", "name": "Mochila", "short_name": "Mochila",
     "description": "Leve mais equipamentos para a caçada. Cada nível dá mais um espaço.",
     "currency": "money", "stats": {},
     "levels": [
       {"level": 1, "price": 0, "bonus_item_slots": 0},
       {"level": 2, "price": 2000, "bonus_item_slots": 1},
       {"level": 3, "price": 5000, "bonus_item_slots": 2},
       {"level": 4, "price": 10000, "bonus_item_slots": 3}]},
    {"id": "knife", "name": "Faca de caça", "short_name": "Faca",
     "description": "Sempre na cintura, não ocupa espaço da mochila. Golpe de perto: cada nível corta mais fundo.",
     "currency": "money",
     "stats": {"reach_m": 2.2, "assist_radius_m": 0.35, "swing_s": 0.45, "swing_interval_s": 0.6, "noise_radius_m": 0.0},
     "levels": [
       {"level": 1, "price": 0, "damage": 30.0},
       {"level": 2, "price": 1500, "damage": 45.0},
       {"level": 3, "price": 4000, "damage": 65.0},
       {"level": 4, "price": 8000, "damage": 90.0}]}
  ]
}
```
`include_filter="data/*.json"` do preset Web já exporta o arquivo novo: `export_presets.cfg` não muda.

#### `data/game.json` (F2) — bloco novo `stamina`, depois de `player`
```json
"stamina": {
  "max": 100.0,
  "sprint_drain_per_s": 10.0,
  "regen_per_s": 6.0,
  "regen_delay_s": 1.0,
  "recover_threshold": 35.0,
  "exhausted_message_s": 2.5,
  "exhausted_message_interval_s": 30.0
}
```
Validação (`get_load_errors()`): bloco presente; `max`, `sprint_drain_per_s`, `regen_per_s`, `exhausted_message_s` > 0;
`regen_delay_s` ≥ 0; `0 < recover_threshold ≤ max`; `exhausted_message_interval_s` ≥ 0. `loadout.item_slots` **não muda**
(continua 3 e passa a significar "espaços da mochila nível 1").

#### `data/equipment.json` (F3) — entrada nova, logo depois de `medkit`
```json
{"id": "energy_drink", "name": "Energético", "short_name": "Energia", "description": "Recupera todo o fôlego na hora. Consumível.",
 "kind": "consumable", "price": 150, "currency": "money", "max_per_hunt": 3, "effect": {"stamina_restore_frac": 1.0}},
```
Validação: `effect.stamina_restore_frac` em (0, 1].

### 2.3 API do `Data` (F1; `src/systems/data_registry.gd`)
```gdscript
func get_upgrade_ids() -> Array[StringName]                         # ordem do arquivo; [] sem upgrades.json
func get_upgrade(id: StringName) -> Dictionary                       # {} + push_error se não existir
func get_upgrade_level_count(id: StringName) -> int                  # levels.size(); 0 se não existir (sem push_error)
func get_upgrade_level_def(id: StringName, level: int) -> Dictionary # levels[level - 1]; {} fora de 1..count (sem push_error)
```
`FILES` ganha `"upgrades": "res://data/upgrades.json"` e `LISTS` ganha `"upgrades": "upgrades"`. `get_item_def` e
`get_item_category` **não** veem melhorias (`get_item_category(&"knife") == &""`): faca e mochila não são itens.

### 2.4 `Profile`, `Inventory`, `Shop`, `SaveService` (F1; F4 só `build_hunt_request`)

```gdscript
# Profile (autoload)
func get_item_slots() -> int                                    # game.loadout.item_slots + bonus_item_slots do nível atual da mochila. stub 3
func get_upgrade_level(upgrade_id: StringName) -> int           # 1..max; id fora de Data.get_upgrade_ids() = 0. stub 1
func get_upgrade_max_level(upgrade_id: StringName) -> int       # = Data.get_upgrade_level_count(upgrade_id)
func can_buy_upgrade(upgrade_id: StringName) -> StringName      # mesmos códigos de buy_upgrade, sem efeito
func buy_upgrade(upgrade_id: StringName) -> StringName          # &"ok" | &"insufficient_funds" | &"max_reached" | &"unknown_item"
```
- `buy_upgrade`: id desconhecido → `unknown_item`; nível atual ≥ máximo → `max_reached`; preço de
  `get_upgrade_level_def(id, nível + 1).price` sem saldo → `insufficient_funds`; senão gasta, sobe **um** nível, `save()`,
  emite `wallet_changed`, `inventory_changed` e `loadout_changed`.
- `get_item_slots()` substitui a leitura de `loadout.item_slots` em `set_loadout_items`, `_auto_equip` e `LoadoutPanel`.
- F4: `build_hunt_request` grava `r.knife_level = maxi(1, get_upgrade_level(Ids.KNIFE))`.
- `Inventory` (`src/systems/inventory.gd`): `var upgrades: Dictionary` (StringName → int); `get_upgrade_level(id) -> int`
  (`int(upgrades.get(id, 1))`); `to_dict()` devolve também `"upgrades": {id String: int}`; `from_dict` lê o bloco.
- `Shop` (`src/systems/shop.gd`): `static func check_upgrade(upgrade_id: StringName, wallet: Wallet, inventory: Inventory) -> StringName`
  e `static func buy_upgrade(upgrade_id: StringName, wallet: Wallet, inventory: Inventory) -> StringName` (regras acima, sem salvar).

**Save (`SaveService`, §10 de `arquitetura.md`).** Bloco novo de topo, ao lado de `inventory` e `loadout`:
```json
"upgrades": {"backpack": 1, "knife": 1}
```
Migração **pelo `sanitize`, sem subir a versão** (continua 2; mesma regra de `player_name` e `onboarding.learned`):
1. `sanitize` lê `upgrades` **antes** do loadout: para cada id de `Data.get_upgrade_ids()`, `nível = clampi(_int(valor, 1), 1,
   count)`; bloco ausente ou com tipo errado → todos 1; ids fora de `get_upgrade_ids()` são descartados.
2. O limite de `loadout.items` passa a ser `game.loadout.item_slots + bonus_item_slots(nível da mochila sanitizado)`.
3. `new_save()` → todos no nível 1. `reset_progress()` volta tudo a 1. `_migrate_v1_to_v2` continua usando a base 3 (save v1
   não tem mochila).
Save de hoje (sem bloco) abre com mochila nível 1 = 3 espaços: nada muda para quem já joga. Quando a F4 acrescenta `knife`
aos dados, saves da F1 ganham `"knife": 1` pelo mesmo `sanitize`.

### 2.5 Entrada (`InputSetup`, A)

| Fase | Ação | Teclado | Toque |
|---|---|---|---|
| F3 | `use_energy_drink` | T | botão Acessórios (o energético entra na lista) |
| F4 | `knife` | X | botão Faca |

- `ACTIONS` ganha, no fim e nessa ordem, `"use_energy_drink"` (F3) e `"knife"` (F4). `_KEYS`: `"use_energy_drink": [KEY_T]`,
  `"knife": [KEY_X]`. T e X não colidem com nenhuma tecla de hoje.
- F3: `ITEM_ACTIONS` ganha `&"energy_drink": &"use_energy_drink"` **no fim** (depois de `binoculars`): espaço da `Quickbar`
  e linha da lista de Acessórios ficam por último.
- `knife` não é item: não entra em `ITEM_ACTIONS`. O `Player` lê `Input.is_action_just_pressed(&"knife")` em `_update_input`
  (vivo, input aberto, sem bot), como as teclas de item.

### 2.6 `Player` / `ItemBelt` / `Knife` (A)

Membros públicos novos do `Player` (`src/player/player.gd`; acrescentar à linha do `Player` em §6.8 no fecho):
```gdscript
# F2 — fôlego
func get_stamina_frac() -> float           # 0..1
func get_stamina_recover_frac() -> float   # recover_threshold / max (marca na barra)
func is_exhausted() -> bool
func restore_stamina(frac: float) -> void  # soma frac × max (preso ao máximo); >= limiar sai do cansaço; morto/caído: nada
func debug_set_stamina(value: float) -> void   # só sandbox/tests: clamp 0..max; 0 liga o cansaço, >= limiar desliga
# F4 — faca
func get_knife_level() -> int              # 0 se não há faca nos dados
func get_knife_damage() -> float
func is_knife_swinging() -> bool
func get_knife_cooldown_frac() -> float    # 1 logo após o golpe .. 0 pronto
func bot_knife() -> bool                   # override de PlayerBase
```

**Fôlego (F2), por quadro de física, só vivo e não caído**, nesta ordem:
1. `pode_correr` = as condições de hoje (`player.gd:891`) **e** `not _exhausted`; `_sprinting = pode_correr`.
2. Se `_sprinting`: `_stamina = maxf(0, _stamina − sprint_drain_per_s × delta)`, `_regen_wait = regen_delay_s`; se chegou a 0:
   `_exhausted = true` e, se passou `exhausted_message_interval_s` desde a última, `GameEvents.hud_message_requested(texto,
   exhausted_message_s)` (texto na §2.11).
3. Senão: `_regen_wait = maxf(0, _regen_wait − delta)`; com `_regen_wait == 0`, `_stamina = minf(max, _stamina + regen_per_s × delta)`.
4. `_exhausted` e `_stamina >= recover_threshold` → `_exhausted = false`.
5. Cansado: `Sfx.play(&"breath_tired")` a cada `BREATH_INTERVAL_S` (1,4 s; mesmo padrão do `heartbeat`).
`setup` e `revive` deixam cheio e sem cansaço. Bot obedece igual. Leituras de `Data.get_game().get("stamina", {})` com fallback
igual ao seed.

**Energético (F3), `ItemBelt.use_item(&"energy_drink")`**, além das regras gerais de hoje ("Você não trouxe este item: …",
"Acabou: …", ocupado = `false`): `player.get_stamina_frac() >= 1.0` → `false` +
`hud_message_requested("Seu fôlego já está cheio.", MESSAGE_S)`; senão count − 1, `counts_changed`, `item_used(&"energy_drink",
posição do jogador)`, `Sfx.play(&"energy_drink")`, `player.restore_stamina(stamina_restore_frac)`, `true`. Sem
`use_started`/`use_finished`. `ItemBelt` ganha `var stamina_restore_frac: float` (lido do `effect`, como `damage_reduction`).

**Faca (F4).** Classe interna `Knife` (`src/weapons/knife.gd`, `class_name Knife extends Node`; nome reservado), criada pelo
`Player.setup` com `request.knife_level` preso em 1..`Data.get_upgrade_level_count(Ids.KNIFE)`; sem faca nos dados = sem
golpe e sem botão. `Weapon` ganha `static func take_shot_id(shooter_slot: int) -> int` (usa e incrementa `_next_shot_id`;
`fire` passa a usá-la) para tiros e golpes nunca repetirem `shot_id`. Um golpe:
1. Portas (§1.4 "Bloqueios"); cooldown = `swing_interval_s`; `swinging` = `swing_s`.
2. `cancel_reload()` da arma atual; zera o buffer de tiro; esconde a view da arma; mostra a view da faca
   (`AssetLoader.instantiate(ScenePaths.weapon_view(Ids.KNIFE))`, filha do `WeaponHolder`) e chama `play_melee(swing_s)`;
   `Sfx.play(&"knife_swing")`. Ao fim de `swing_s`: esconde a faca, mostra a arma (sem `play_draw`). Sem a cena: golpe sem
   visual de faca (a arma some e volta).
3. Acerto **na hora**: `shot_id = Weapon.take_shot_id(Net.get_local_slot())`; `Hitscan.cast(space, olho, frente, reach_m, [RID
   do jogador])`. `HitZone` → `HitInfo` (`shot_id`, `shooter_slot`, `weapon_id = Ids.KNIFE`, `damage = damage do nível`, sem
   queda por distância, `origin`, `position`, `normal`, `direction`, `distance_m` = distância do raio) e `receive_hit`;
   efeito `impact_blood` + som `impact_flesh`. Terreno/estático no alcance: só o som (`impact_dirt` / `impact_wood`). Raio sem
   `HitZone`: `intersect_shape` com `SphereShape3D(assist_radius_m)` em `olho + frente × (reach_m − assist_radius_m)`,
   `collide_with_areas = true`, `collide_with_bodies = false`, máscara `Layers.BOAR_HITZONE`, até 8 resultados; escolhe a
   `HitZone` cujo `global_position` está mais perto da reta do olhar (empate: mais perto do olho); `position` = esse
   `global_position`, `distance_m = minf(olho.distance_to(position), reach_m)`.
4. **Depois** do acerto: `GameEvents.shot_fired.emit(Ids.KNIFE, olho, frente, noise_radius_m)` (fecha o `C_SHOT` no cliente;
   o B conta como disparo). **Nunca** incrementa `_net_shot_seq` nem muda a arma do `HUNTER_STATE`.
5. Durante `swing_s`: tiro, mira, recarga, troca de arma e itens bloqueados; movimento e corrida livres; ADS cai como se o botão
   fosse solto e volta ao estado do botão no fim.
6. A view da faca fica visível (pose de repouso, atrás do overlay) do `setup` até `GameEvents.hunt_started`; depois escondida.

### 2.7 HUD e toque (A)

**Barra de fôlego (F2), dentro da `HealthStrip`.** `HEIGHT_PX` continua 28 (nada do layout muda). `Bar` (vida) sobe 2 px
(y 5–19 dentro da faixa); filho novo `Stamina` (`ProgressBar`, 4 px de altura, y 21–25, mesmo x e largura de `Bar`, sem texto).
Constantes: `STAMINA_BAR_H_PX = 4.0`, `STAMINA_GAP_PX = 2.0`, `COLOR_STAMINA = Color("#8EC3E6")`, cansado `COLOR_DANGER`
(`#D9452B`); marca de 1 px `COLOR_TEXT` em `recover_frac`, só cansado. Visível só com fôlego < 1 ou cansado.
```gdscript
func set_stamina(frac: float, exhausted: bool, recover_frac: float) -> void   # o Hud chama todo quadro (o desenho só muda quando os valores mudam)
func get_stamina_fill_pct() -> float      # tests: 0..100
func is_stamina_visible() -> bool         # tests
func get_stamina_color() -> Color         # tests
```

**Energético (F3).** `Hud`, na borda de `is_exhausted()`:
- subiu e o `ItemBelt` tem `get_count(&"energy_drink") > 0`: desktop `Quickbar.flash(&"energy_drink", true)`; toque: guarda
  `prev = get_accessory_current()`, `select_accessory(&"energy_drink")` e `flash_slot(&"energy_drink", true)`;
- desceu (ou o energético zerou): `flash(..., false)` / `flash_slot(..., false)`; no toque, se o atual ainda é o energético e
  `prev` ainda está entre os acessórios com contagem ≠ 0, `select_accessory(prev)`.
`TouchControls` ganha `func select_accessory(item_id: StringName) -> bool` (torna atual sem usar, fecha a lista; `false` se o
item não está entre os acessórios). A mensagem de cansaço passa a citar o energético (§2.11) quando ele está na mochila
com contagem > 0.

**Botão Faca (F4), em `TouchControls.BUTTONS`:**
`{"id": &"knife", "action": &"knife", "d": 68.0, "label": "Faca", "icon": &"btn_knife", "from": "br", "ox": 100.0, "oy": 190.0, "mode": "hold"}`
→ centro (1180, 530) a 1280×720, (1432, 530) a 1532×720, (1180, 770) a 1280×960. Folgas calculadas: Tiro direito 145 px
(mínimo 110), Mira 152 (mín. 88), Agachar 205, Cão 206. Existe só com faca nos dados e caçador vivo (some caído/espectador,
como Recarga). Com `get_knife_cooldown_frac() > 0`, véu e setor de "ocupado" (mesmo desenho do Cura) com progresso
`1 − frac`. Sem ícone: o texto "Faca". `get_button_center(&"knife")` vale. Se o teste de sobreposição acusar choque numa das
3 telas, o A ajusta `ox`/`oy` no mínimo necessário e relata os valores finais (que passam a ser o contrato).
**Legenda (F4):** `ControlsLegend` ganha a linha `ROW_KNIFE = &"knife"` (ações `[&"knife"]`, texto "Faca") logo depois de
`weapons`. A `Quickbar` e o `WeaponPanel` não mostram a faca.

### 2.8 Rede (B, F4)

- `hunt_replica.gd` `_on_shot_fired`: `weapon_index = NetCodec.KNIFE_WEAPON_INDEX if weapon_id == Ids.KNIFE else
  _weapon_ids.find(weapon_id)`.
- `hunt_host_sync.gd` `_apply_shot`: com `weapon_index == NetCodec.KNIFE_WEAPON_INDEX`, `weapon_id = Ids.KNIFE` e `def` =
  dicionário montado uma vez no setup: `{"damage": <damage do último nível>, "pellets": 1, "max_range_m": stats.reach_m,
  "noise_radius_m": stats.noise_radius_m}` (faca ausente dos dados → `{}` → golpe rejeitado como hoje). Todo o resto do
  `_apply_shot` vale sem mudança (javali vivo, zona, `DAMAGE_SLACK`, `DIST_SLACK_M`, `hit_claim_tolerance_m`,
  `hit.damage = minf(damage, def.damage)`, `notify_shot` com ruído 0).
- Nenhum registro novo, nenhum byte novo; `docs/multiplayer.md` §4.5 registra o índice 254.

### 2.9 Loja e Preparação (game-systems)

- `UpgradeCard` (`src/ui/common/upgrade_card.gd`, `class_name UpgradeCard extends PanelContainer`, F1): `setup(upgrade_id:
  StringName, on_buy: Callable) -> void`, `refresh() -> void`, `var buy_button: Button` (nome `Buy_<upgrade_id>`), para
  tests `get_level_text() -> String` e `get_next_text() -> String`. Visual do `ItemCard`: imagem à esquerda (mochila:
  `UiKit.icon_rect(&"backpack", ItemCard.ICON_SIZE)`; faca: `UiKit.weapon_art_rect(&"knife", ItemCard.WEAPON_ART_WIDTH)`
  com fallback no ícone), nome + etiqueta, descrição, linha de nível, linha do próximo nível, preço do próximo nível, botão.
- Loja (`src/ui/shop/shop.gd`): o cartão da mochila é o **primeiro** da aba Equipamentos (F1); o da faca, o **primeiro** da
  aba Armas (F4). Abas não mudam. Compra pelo `Profile.buy_upgrade` com mensagens da §2.11; depois, `refresh` de todos os cartões.
- `LoadoutPanel` (Preparação e lobby): `_item_slots()` passa a `Profile.get_item_slots()`; cabeçalho e dica de limite da §2.11.
- `ItemCard.stats_text` (F3): caso `&"energy_drink"` (§2.11).

### 2.10 Arte e som (art-director)

| Fase | Entrega | Contrato |
|---|---|---|
| F1 | `assets/ui/icons/backpack.svg` | 128×128, mochila de lona cáqui com fivela; legível a 96 px no cartão da loja |
| F2 | som `breath_tired` | ~0,9 s, expiração ofegante; síntese procedural; entrada em `sfx_prompts.json`; `Sfx.has_sound` verdadeiro |
| F3 | `assets/ui/icons/energy_drink.svg` | lata; regra dos ícones de item (§7.9): legível a 40 px sobre `HudPanel` e sobre o círculo do toque, silhueta `#F4EFE6` com no máximo um acento da paleta |
| F3 | som `energy_drink` | ~0,8 s, lata abrindo + gole; síntese procedural |
| F4 | `assets/models/weapons/knife_view.tscn` + `knife_view.gd` | raiz `Node3D` estendendo `WeaponViewBase`; braço direito com luva no estilo de `showcase/arms_hd.gd` segurando a faca; filhos `Muzzle` (ponta da lâmina) e `AdsAnchor` (exigido pela base, não usado); repouso no canto inferior direito; `play_melee(duration_s)`: estocada/corte do canto para o centro e volta, inteiro em `duration_s`, ponta passando pelo centro da tela a ~30% do tempo; orçamento da §1.7; `play_fire`/`play_cycle`/`play_reload`/`play_draw` no-op |
| F4 | `assets/models/weapons/showcase/knife_hd.gd` | malha procedural HD: lâmina ~0,20 m, cabo de madeira ~0,12 m; ponta em −Z, cabo em +Z; `set_hip_pose(on: bool)` e `set_cast_shadows(on: bool)` (os dois que a ferramenta chama) |
| F4 | `tools/render_weapon_art.gd` + `assets/ui/weapons/knife.png` | `WEAPON_IDS` ganha `"knife"`; rodar `--only=knife` (com janela, Forward+, como o cabeçalho da ferramenta) e `--import`; 1024×512 RGBA, cabo à esquerda, ponta à direita, ~92% da largura |
| F4 | `assets/ui/icons/knife.svg`, `assets/ui/icons/btn_knife.svg` | 128×128; `btn_knife` segue os botões do toque (silhueta clara) |
| F4 | som `knife_swing` | ~0,25 s, assobio de lâmina; síntese procedural |
| F4 | `assets/preview/knife_preview.tscn` | a view em repouso e no meio do golpe, para screenshot |

Sons: entradas em `assets/audio/sfx_prompts.json` (MP3 opcional depois, como sempre). O acerto da faca reutiliza
`impact_flesh` e `impact_blood`.

### 2.11 Textos PT-BR exatos

| Onde | Texto |
|---|---|
| Cartão da mochila: etiqueta / nível / próximo | `"Melhoria permanente"` / `"Nível %d de %d · %d espaços de equipamento"` / `"Próximo nível: %d espaços"` |
| Cartão da faca: etiqueta / nível / próximo / números | `"Arma branca, sempre com você"` / `"Nível %d de %d · Dano %d"` / `"Próximo nível: dano %d"` / `"Alcance %s m  \|  %s golpes/s"` |
| Cartão de melhoria no máximo | linha do próximo: `"Nível máximo"`; botão desabilitado `"Nível máximo"`; sem preço |
| Botão do cartão de melhoria | `"Comprar nível %d"`; sem saldo: `"Saldo insuficiente"` + status `"Faltam %s"` (`UiKit.price_text`) |
| Loja, mensagens de melhoria | ok `"Comprado: %s nível %d."`; `max_reached` `"%s já está no nível máximo."`; `insufficient_funds` `"%s Saldo insuficiente."`; `unknown_item` `"%s Item indisponível."` (`%s` = `name`) |
| Preparação, cabeçalho | `"Equipamentos (mochila nível %d: até %d)"` |
| Preparação, limite | abaixo do máximo `"Mochila cheia (%d). Desmarque um ou compre uma mochila maior na Loja."`; no máximo `"Mochila cheia (%d). Desmarque um para trocar."` |
| Energético na loja (`stats_text`) | `stamina_restore_frac >= 1` → `"Fôlego cheio na hora"`; senão `"Recupera %d%% do fôlego na hora"` |
| HUD, cansou (F2) | `"Sem fôlego! Ande para recuperar."` |
| HUD, cansou com energético (F3) | teclado `"Sem fôlego! Tome um energético (%s) ou ande para recuperar."` (`get_key_label(&"use_energy_drink")`); toque `"Sem fôlego! Toque no energético ou ande para recuperar."` |
| Energético com fôlego cheio | `"Seu fôlego já está cheio."` |
| Botão do toque / legenda | `"Faca"` |

---

## 3. Fases

Regra comum: cada fase é uma sessão nova do Claude Code com a sessão principal coordenando (ela não implementa; delega).
Pacotes de uma mesma fase rodam em paralelo, exceto QA, que espera os outros. Toda entrega: `check_scripts` verde e as
suítes afetadas sem regressão no modo contrato, na horda nível 1 e 2 e no cooperativo. Comandos (da raiz, ver `CLAUDE.md`):
```bash
tools/godot.sh --headless --path . --import          # quando há arquivo novo (class_name, SVG, PNG, JSON)
tools/godot.sh --headless --path . res://tests/check_scripts.tscn
tools/godot.sh --headless --path . res://tests/unit_tests.tscn
tools/godot.sh --headless --fixed-fps 60 --path . res://tests/flow_test.tscn
tools/godot.sh --headless --fixed-fps 60 --path . res://tests/playthrough.tscn
tools/godot.sh --headless --path . res://tests/net_unit.tscn -- --only=<sandboxes>
tools/godot.sh --headless --path . --export-release "Web" build/web/index.html
python tests/web/mobile_probe.py
```

**Publicação (todas as fases, coordenação):** subir `config/version` em `project.godot` (única mudança nele em todo o
plano); escrever a entrada em `docs/changelog.md`; atualizar o §0 deste plano e, se a fase fechou contrato, `arquitetura.md`
(Apêndice A, §6.8, §14); commit **por caminho** (nunca `git add -A`: a árvore tem trabalho de outras sessões); worktree limpo
para as 4 suítes, `net_unit`, export Web e `mobile_probe.py` (build no worktree via `JAVALI_BUILD_DIR`); push na `main`;
`build/web` no `gh-pages`; conferir o Content-Length do `index.pck` publicado. Procedimento detalhado em
`docs/plano_hud_gameplay.md` ("Como rodar cada fase", item 5).

### F1 — Mochila (0.9.5)

**Objetivo:** mochila nível 1–4 comprável na loja, espaços de equipamento 3–6, save com migração silenciosa.

| Pacote | Agente / modelo | Arquivos | Espera |
|---|---|---|---|
| Núcleo | coordenação | `src/core/ids.gd` (§2.1 F1) | — |
| S1 | game-systems / Sonnet | `data/upgrades.json` (novo, só `backpack`), `src/systems/data_registry.gd`, `src/systems/profile.gd`, `src/systems/inventory.gd`, `src/systems/shop.gd`, `src/systems/save_service.gd`, `src/ui/common/upgrade_card.gd` (novo), `src/ui/shop/shop.gd`, `src/ui/common/loadout_panel.gd` | Núcleo |
| ART1 | art-director / Sonnet | `assets/ui/icons/backpack.svg` | — |
| QA1 | qa-tester / Sonnet | `tests/lib/contract_sigs.gd`, `tests/unit/test_data.gd`, `tests/unit/test_save.gd`, `tests/unit/test_economy.gd`, `tests/unit/test_assets.gd`, `tests/unit/test_item_hud.gd`, `tests/flow_test.gd` | S1, ART1 |

Fora do escopo: faca (nem entrada nos dados), energético, fôlego, HUD, `Player`, toque, rede, `ItemCard` (fora o que o
`UpgradeCard` reaproveitar sem mudar).

Aceite:
- **S1:** `Data.get_load_errors()` vazio; `get_upgrade_ids() == [&"backpack"]`; `get_upgrade_level_count(&"backpack") == 4`;
  `get_upgrade_level_def(&"backpack", 2).bonus_item_slots == 1`; `get_upgrade_level_def(&"backpack", 5) == {}`; cada regra da
  §2.2 quebrada (nível fora de ordem, preço do nv1 ≠ 0, bônus decrescente, id `"pa"`, id igual a `"medkit"`, moeda `"gold"`)
  gera erro. Perfil novo: nível 1, `get_item_slots() == 3`. Com R$ 2.000: `buy_upgrade(&"backpack") == &"ok"`, dinheiro −2000,
  nível 2, `get_item_slots() == 4`, `set_loadout_items` com 4 ids possuídos `true` e com 5 `false`. Nível 4 → `max_reached`;
  sem saldo → `insufficient_funds` sem efeito; `&"foo"` → `unknown_item`; `can_buy_upgrade` dá os mesmos códigos sem efeito;
  `reset_progress()` → nível 1. Save sem `upgrades` → nível 1 e loadout igual; `{"backpack": 9}` → 4; `{"backpack": "x"}` → 1;
  `{"foo": 2}` descartado; nível 2 com 5 itens no loadout → 4 itens (os 4 primeiros); ida e volta mantém o nível; versão gravada
  continua 2. Loja: `Buy_backpack` é o 1º cartão de Equipamentos, textos da §2.11; Preparação: cabeçalho e dica da §2.11.
  Screenshots com janela da loja e da Preparação a 1280×720 e 2340×1080 sem corte.
- **ART1:** `unit_tests -- --strict` sem falta do ícone.
- **QA1:** tudo acima automatizado; `flow_test`: com dinheiro somado por `Profile.add_money`, compra `Buy_backpack`, volta à
  Preparação, marca 4 `Item_<id>`, `%StartHuntButton` → `request.item_ids.size() == 4`; `test_item_hud`: `Quickbar` com 4 itens
  usáveis + cão (5 espaços) a 1280×720 não encosta no `WeaponFrame` nem na mensagem de abate.
- Suítes: `check_scripts`, `unit_tests`, `flow_test`, `playthrough`. `mobile_probe.py` recomendado (a Preparação está no
  caminho do probe).

`project.godot`: `config/version="0.9.5"`. Mais nada.

> **Prompt para abrir a sessão (F1):** Execute a fase F1 (Mochila) de `docs/plano_faca_mochila_folego.md`. Leia `CLAUDE.md` e
> o plano inteiro; não rederive decisões. Aplique a mudança de `src/core/ids.gd` da §2.1 (F1). Lance em paralelo S1
> (game-systems, Sonnet) e ART1 (art-director, Sonnet) com os arquivos, o fora de escopo e o aceite da F1; depois QA1
> (qa-tester, Sonnet). Revise, rode as validações da F1, suba `config/version` para "0.9.5", atualize `docs/changelog.md` e
> o §0 do plano, commit por caminho e publique a partir de worktree limpo.

### F2 — Fôlego (0.9.6)

**Objetivo:** correr gasta fôlego; zerado, o caçador cansa e só anda até passar do limiar; barra no HUD; respiração ofegante.

| Pacote | Agente / modelo | Arquivos | Espera |
|---|---|---|---|
| S2 | game-systems / Sonnet | `data/game.json` (bloco `stamina`), `src/systems/data_registry.gd` (validação) | — |
| A2 | game-developer / Sonnet | `src/player/player.gd`, `src/hud/health_strip.gd`, `src/hud/hud.gd`, `src/player/debug/player_stamina_test.gd` + `.tscn` (novos), `src/player/debug/sandbox_world.gd` (flag `--stamina=<0..100>`) | — (fallbacks iguais ao seed) |
| ART2 | art-director / Sonnet | `assets/audio/sfx_library.gd`, `assets/audio/synth/*`, `assets/audio/sfx_prompts.json` (`breath_tired`) | — |
| QA2 | qa-tester / Sonnet | `tests/lib/contract_sigs.gd`, `tests/unit/test_data.gd`, `tests/unit/test_weapon_health_hud.gd`, `tests/unit/test_assets.gd`, `tests/net_unit.gd` (registrar `player_stamina`) | S2, A2, ART2 |

Fora do escopo: energético, faca, `TouchControls`, `VirtualJoystick` (a corrida do toque não muda), rede, B, `src/core/`.

Aceite:
- **A2 (`player_stamina_test`, `--fixed-fps 60`):** bot correndo para frente a partir do cheio fica cansado em 10,0 s ± 2
  quadros; cansado, velocidade horizontal ≤ `walk_speed_mps` e `get_noise_radius()` = ruído de caminhada com `sprint`
  apertado; sem correr, o fôlego não sobe no 1º segundo e depois sobe 6/s; volta a correr 1 + 35/6 s (≈ 6,83 s) depois de
  esgotar, ± 2 quadros; agachado ou mirando não gasta; `restore_stamina(1.0)` → `get_stamina_frac() == 1` e não cansado;
  `debug_set_stamina(0)` → cansado; mundo falso de horda nível 2 com 2 caçadores: cair e ser levantado → fôlego cheio; a
  mensagem `"Sem fôlego! Ande para recuperar."` sai 1× e não repete antes de 30 s; `player_horde2_test` e `remote_sandbox`
  sem regressão. HUD: faixa escondida com fôlego cheio; visível < 1; cor `#8EC3E6` / `#D9452B` cansado; marca só cansado;
  `HealthStrip.HEIGHT_PX == 28`; `get_value_text`/`get_fill_pct` da vida iguais a antes. Screenshot com janela do
  `player_sandbox --stamina=20` a 1280×720 nos dois modos (`--touch=on|off`).
- **S2:** seed sem erro; cada regra da §2.2 (bloco `stamina`) quebrada gera erro.
- **ART2:** `Sfx.has_sound(&"breath_tired")`.
- **QA2:** acima automatizado; `net_unit --only=player_stamina,hud_net,hud_hints`.
- Suítes: `check_scripts`, `unit_tests`, `flow_test`, `playthrough` (a corrida do bot agora cansa: se o tempo do playthrough
  subir perto do vigia de 300 s, relatar antes de mexer no bot). `mobile_probe.py` obrigatório (HUD do toque mudou).

`project.godot`: `config/version="0.9.6"`.

> **Prompt para abrir a sessão (F2):** Execute a fase F2 (Fôlego) de `docs/plano_faca_mochila_folego.md`. Leia `CLAUDE.md` e
> o plano inteiro; não rederive decisões. Não há mudança em `src/core/`. Lance em paralelo S2 (game-systems, Sonnet), A2
> (game-developer, Sonnet) e ART2 (art-director, Sonnet) com os arquivos, o fora de escopo e o aceite da F2; depois QA2
> (qa-tester, Sonnet). Revise os screenshots, rode as validações e o `mobile_probe.py`, suba `config/version` para "0.9.6",
> atualize `docs/changelog.md` e o §0 do plano, commit por caminho e publique a partir de worktree limpo.

### F3 — Energético (0.9.7) — depende de F2

**Objetivo:** consumível da loja que enche o fôlego na hora, na `Quickbar` (T) e na lista de Acessórios do toque.

| Pacote | Agente / modelo | Arquivos | Espera |
|---|---|---|---|
| Núcleo | coordenação | `src/core/ids.gd` (§2.1 F3) | — |
| S3 | game-systems / Sonnet | `data/equipment.json`, `src/systems/data_registry.gd` (efeito), `src/ui/common/item_card.gd` (`stats_text`) | Núcleo |
| A3 | game-developer / Sonnet | `src/input/input_setup.gd`, `src/player/item_belt.gd`, `src/player/player.gd` (texto do cansaço), `src/hud/hud.gd`, `src/hud/touch/touch_controls.gd` (`select_accessory`), `src/player/debug/player_stamina_test.gd` (casos do energético) | Núcleo |
| ART3 | art-director / Sonnet | `assets/ui/icons/energy_drink.svg`, `assets/audio/sfx_library.gd`, `assets/audio/synth/*`, `assets/audio/sfx_prompts.json` (`energy_drink`) | — |
| QA3 | qa-tester / Sonnet | `tests/lib/contract_sigs.gd`, `tests/unit/test_input.gd`, `tests/unit/test_item_hud.gd`, `tests/unit/test_data.gd`, `tests/unit/test_economy.gd`, `tests/unit/test_assets.gd`, `tests/unit/test_onboarding.gd`, `tests/flow_test.gd` | S3, A3, ART3 |

Fora do escopo: faca, mudanças na regra do fôlego (F2), dicas novas de onboarding, B, rede, `src/core/` além da linha da F3.

Aceite:
- **A3:** `InputSetup.get_item_action(&"energy_drink") == &"use_energy_drink"`; `get_key_label` = "T"; `ITEM_ACTIONS` termina em
  `energy_drink`; sem o item: "Você não trouxe este item: Energético."; com fôlego cheio: recusa e mensagem, contagem igual;
  cansado: contagem −1, `item_used` 1×, fôlego cheio, não cansado, sem `use_started`; contagem 0: "Acabou: Energético.";
  cansar com energético: `Quickbar` pisca o espaço; no toque o Acessórios passa ao energético e pisca, e volta ao anterior ao
  sair do cansaço; mensagem de cansaço com o energético nos dois modos (§2.11). Screenshots com janela do `player_sandbox
  --touch=on --items=corn_bait,scout_drone,binoculars,energy_drink --stamina=0` a 1532×720, 1280×720 e 1280×960 com a lista
  aberta: nada se sobrepõe.
- **S3:** seed sem erro; `stamina_restore_frac` 0 ou 1,5 gera erro; cartão da loja com `"Fôlego cheio na hora"`.
- **QA3:** acima automatizado; `test_item_hud`: lista de Acessórios com 4 linhas e `Quickbar` com 5 usáveis + cão (6 espaços)
  sem sobreposição nas 3 telas; `test_onboarding`: `"energy_drink"` é id de dica válido; `flow_test`: comprar 2 energéticos,
  equipar, `request.item_counts[&"energy_drink"] == 2`; `test_economy`: `apply_hunt_result` desconta o energético usado.
- Suítes: as 4 + `net_unit --only=player_stamina,hud_net,hud_hints`. `mobile_probe.py` obrigatório.

`project.godot`: `config/version="0.9.7"`.

> **Prompt para abrir a sessão (F3):** Execute a fase F3 (Energético) de `docs/plano_faca_mochila_folego.md` (a F2 já está
> publicada). Leia `CLAUDE.md` e o plano inteiro; não rederive decisões. Aplique a linha de `src/core/ids.gd` da §2.1 (F3).
> Lance em paralelo S3 (game-systems, Sonnet), A3 (game-developer, Sonnet) e ART3 (art-director, Sonnet) com os arquivos, o
> fora de escopo e o aceite da F3; depois QA3 (qa-tester, Sonnet). Revise os screenshots, rode as validações e o
> `mobile_probe.py`, suba `config/version` para "0.9.7", atualize `docs/changelog.md` e o §0 do plano, commit por caminho e
> publique a partir de worktree limpo.

### F4 — Faca (0.9.8) — depende de F1

**Objetivo:** golpe de faca sem slot, níveis de dano na loja, funcionando no solo, na horda e no cooperativo.

| Pacote | Agente / modelo | Arquivos | Espera |
|---|---|---|---|
| Núcleo | coordenação | `src/core/hunt_request.gd`, `src/core/weapon_view_base.gd`, `src/core/net_codec.gd`, `src/core/player_base.gd` (§2.1 F4); `CLAUDE.md` (exceção de raster passa a citar o retrato da faca, ver D12) | — |
| S4 | game-systems / Sonnet | `data/upgrades.json` (entrada `knife`), `src/systems/data_registry.gd` (regras da faca), `src/systems/profile.gd` (`build_hunt_request`), `src/ui/common/upgrade_card.gd` (linhas da faca, retrato), `src/ui/shop/shop.gd` (cartão na aba Armas) | Núcleo |
| A4 | game-developer / **Opus** (combate e caminho de acerto compartilhado com o tiro) | `src/weapons/knife.gd` (novo), `src/weapons/weapon.gd` (`take_shot_id`), `src/player/player.gd`, `src/player/player.tscn` (só se precisar), `src/input/input_setup.gd`, `src/hud/touch/touch_controls.gd`, `src/hud/hud.gd` (só se precisar), `src/hud/controls_legend.gd`, `src/player/debug/player_knife_test.gd` + `.tscn` (novos), `src/player/debug/sandbox_world.gd` (`--knife=<1..4>`) | Núcleo |
| B4 | game-developer / Sonnet | `src/hunt/hunt_replica.gd`, `src/hunt/hunt_host_sync.gd`, `src/hunt/debug/hunt_selftest.gd`, `src/hunt/debug/net_knife_test.gd` + `.tscn` (novos) | Núcleo |
| ART4 | art-director / Sonnet | os arquivos da §2.10 (F4) | — |
| QA4 | qa-tester / Sonnet | `tests/lib/contract_sigs.gd`, `tests/check_scripts.gd`, `tests/unit/test_core.gd`, `tests/unit/test_data.gd`, `tests/unit/test_economy.gd`, `tests/unit/test_input.gd`, `tests/unit/test_item_hud.gd`, `tests/unit/test_assets.gd`, `tests/net_unit.gd` (registrar `player_knife`, `net_knife`), `tests/net_test.gd` (cenário com golpe do cliente), `tests/flow_test.gd` | S4, A4, B4, ART4 |

Fora do escopo: animação da faca em 3ª pessoa (`HunterVisualBase`, `RemoteHunter`), som da faca para aliados, mensagem
especial de abate na faca, níveis com modelo visual diferente, faca no `WeaponPanel`/`Quickbar`, mudança em `Boar`/IA.

Aceite:
- **A4 (`player_knife_test`, `HitZone` de teste à frente na altura do olhar menos 0,5 m):** a 1,5 m `bot_knife()` → 1
  `hit_received` com `weapon_id == &"knife"`, `damage` = dano do nível (`--knife=1..4`: 30/45/65/90), `distance_m ≤ 2,2`;
  a 3,0 m nenhum acerto; zona 0,3 m ao lado da reta a 2,0 m acertada pela ajuda de mira; 2º golpe antes de 0,6 s → `false`;
  `shot_fired` 1× por golpe com `Ids.KNIFE` e ruído 0, emitido **depois** do `hit_received`; `shot_id` diferente do último
  tiro; `_net_shot_seq` e a arma do estado de rede iguais; recarga em curso cancelada; com o kit em uso, binóculo ligado,
  trocando de arma ou caído → `false`; durante 0,45 s `bot_fire()` → `false`; view da arma volta visível ao fim. Toque:
  `get_button_center(&"knife")` = (1180, 530) a 1280×720; sem sobreposição nas 3 telas (ou os valores ajustados relatados).
  Legenda com a linha `knife` ("X", "Faca"). Screenshot com janela no meio do golpe (`player_sandbox --knife=4`).
- **B4:** `hunt_selftest` (request com `knife_level = 4`): `bot_teleport` a 1,5 m do primeiro javali vivo
  (`get_alive_boar_ids()`), `bot_look_at` no centro dele, `bot_knife()` → 1 `boar_hit` desse javali com `damage` = 90 ×
  multiplicador da zona atingida (`data/boars.json`); `shots_fired` do resultado +1; um javali com vida ≤ esse dano morre com
  `one_shot`. `net_knife_test` (anfitrião + cliente no mesmo processo):
  golpe do cliente num javali → `C_SHOT` com `weapon = 254`, anfitrião aplica o dano; dano acima do nível máximo + folga ou
  `dist` > 2,2 m + folga → rejeitado (`hits_rejected` +1); sem faca nos dados → rejeitado; tiro de arma continua igual
  (`net_sync_test`, `net_horde2_test` sem regressão).
- **S4:** seed sem erro; regras da faca da §2.2 quebradas geram erro; `build_hunt_request(...).knife_level` = nível comprado;
  `Buy_knife` é o 1º cartão da aba Armas, com retrato (ou ícone) e textos da §2.11.
- **ART4:** `unit_tests -- --strict`: `knife_view.tscn` com `Muzzle`, `AdsAnchor`, ≤ 4000 tris, ≤ 3 `MeshInstance3D`,
  sombras desligadas; `knife.png` 1024×512; os 2 SVGs; `Sfx.has_sound(&"knife_swing")`; screenshot do preview.
- **QA4:** acima automatizado; `test_core`: `HuntRequest.new().knife_level == 1`, `NetCodec.KNIFE_WEAPON_INDEX == 254`,
  `PlayerBase.new().bot_knife() == false`; `test_input`: X → `knife`; `flow_test`: comprar `Buy_knife`, iniciar caçada, request
  com `knife_level == 2`; `net_test` (dois processos): cliente abate com a faca, resultado igual nas duas máquinas.
- Suítes: as 4 + `net_unit` inteiro + `net_test`. Export Web, `mobile_probe.py` obrigatório, `coop_probe.py` recomendado.

`project.godot`: `config/version="0.9.8"`.

> **Prompt para abrir a sessão (F4):** Execute a fase F4 (Faca) de `docs/plano_faca_mochila_folego.md` (a F1 já está
> publicada). Leia `CLAUDE.md` e o plano inteiro; não rederive decisões. Aplique as mudanças de `src/core/` da §2.1 (F4) e o
> ajuste de `CLAUDE.md` da D12. Lance em paralelo S4 (game-systems, Sonnet), A4 (game-developer, **Opus**), B4
> (game-developer, Sonnet) e ART4 (art-director, Sonnet) com os arquivos, o fora de escopo e o aceite da F4; depois QA4
> (qa-tester, Sonnet). Revise os screenshots, rode as validações, `net_unit`, `net_test`, export e `mobile_probe.py`, suba
> `config/version` para "0.9.8", atualize `docs/changelog.md`, o §0 do plano e `arquitetura.md` (Apêndice A, §6.8, §14),
> commit por caminho e publique a partir de worktree limpo.

---

## 4. Ordem e dependências

```
F1 Mochila ──────────────► F4 Faca          (F4 reaproveita upgrades.json, Data/Profile/save e UpgradeCard da F1)
F2 Fôlego ──► F3 Energético                  (o energético só faz sentido com o fôlego)
```
- Ordem recomendada: **F1 → F2 → F3 → F4** (uma versão por fase; a mais arriscada por último).
- Também válidas: F2 → F1 → F3 → F4, ou F2 → F3 → F1 → F4. F3 nunca antes de F2; F4 nunca antes de F1.
- **Não rodar duas fases ao mesmo tempo:** F1, F3 e F4 mexem em `data_registry.gd`/`profile.gd`/`shop.gd`; F2, F3 e F4 em
  `player.gd` e `hud.gd`; cada fase publica uma versão a partir da `main`. Dentro de uma fase, os pacotes da tabela rodam em
  paralelo (pastas sem sobreposição) e o QA vem por último.

---

## 5. Riscos e tradeoffs

- **R1 — Build antigo em cache apaga as melhorias.** O `sanitize` de um build anterior descarta o bloco `upgrades` e regrava o
  save: quem abrir 0.9.4 em cache depois de comprar mochila perde o nível. Vale para qualquer bloco novo de save (já valia para
  `onboarding`); a versão na tela inicial ajuda a perceber. Mitigação futura possível: fazer o `sanitize` preservar chaves
  desconhecidas (fora deste plano).
- **R2 — Faca em rede confia no cliente.** O anfitrião aceita dano até o do nível 4 (não conhece o nível do cliente). Coerente
  com o "favor the shooter" de hoje; o cooperativo é privado e sem PvP.
- **R3 — Travada no 1º golpe na Web** se os materiais da faca forem novos. Mitigação: materiais iguais aos das armas e view
  visível atrás do overlay durante o pré-aquecimento (§1.7). Conferir com `perf_ab.py`/`load_ab.py` se houver dúvida.
- **R4 — HUD mais cheio.** Até 6 espaços na `Quickbar`, 4 linhas na lista de Acessórios e 15 linhas na legenda de teclas a
  720 de altura. Coberto pelos testes de sobreposição de F1/F3/F4; se a legenda encostar no painel da arma, ela já é recolhível (H).
- **R5 — Botão Faca perto do Tiro** pode receber toque por engano; posição escolhida com folga ≥ 35 px além do mínimo. Ajuste
  fino só com teste no celular.
- **R6 — Fôlego vale para bots.** Testes que correm muito (`player_horde2_test`, playthrough) ficam mais lentos ou mudam de
  ritmo. O aceite da F2 pede relato antes de mexer no bot.
- **R7 — Balanceamento sem teste com gente:** preços, dano da faca, 10 s de corrida, limiar 35, R$ 150 do energético. Tudo em
  dados (`upgrades.json`, `game.json`, `equipment.json`).
- **R8 — Seleção automática do energético no toque** pode surpreender quem ia usar a ceva; volta sozinha ao sair do cansaço.
- **R9 — Golpe conta como disparo** na precisão do resultado (o `C_SHOT` depende de `shot_fired`). Tradeoff aceito para não
  criar sinal novo.
- **R10 — Faca fora do catálogo de armas (escolha de arquitetura).** Pôr a faca em `weapons.json` daria índice de rede e
  validação de graça, mas a colocaria na fileira de armas, nos slots do loadout, na loja de armas compradas uma vez e nas
  "todas as armas" da horda, exigindo filtros em muitos lugares. Arquivo próprio de melhorias + índice reservado 254 é menor.
- **R11 — Golpe instantâneo.** O acerto sai no aperto, antes do fim da animação: resposta imediata e rede simples, ao custo de
  a lâmina "chegar" depois do sangue em câmera lenta. Aceito.

---

## 6. Decisões para o dono confirmar

Escolhidas pelo padrão mais próximo do PUBG Mobile e do que o jogo já faz; o plano segue com elas até o dono dizer o contrário.

- **D1** Mochila com 4 níveis: 3 / 4 / 5 / 6 espaços; R$ 0 / 2.000 / 5.000 / 10.000. Todo mundo começa no nível 1 (= os 3 de hoje).
- **D2** Energético ocupa 1 espaço da mochila (como o kit), até 3 por caçada, R$ 150, sem unidade grátis no perfil novo.
- **D3** Energético só enche o fôlego, na hora; não cura nem dá velocidade extra (diferente do "boost" do PUBG).
- **D4** Fôlego: 10 s de corrida contínua; recupera 6/s depois de 1 s parado de correr; cansado só volta a correr com 35%.
  Vale no contrato, na horda e para os bots.
- **D5** Faca com 4 níveis, dano 30 / 45 / 65 / 90 por golpe; R$ 0 / 1.500 / 4.000 / 8.000; alcance 2,2 m; 1,67 golpe/s;
  silenciosa; golpe rápido sem trocar de arma, que cancela a recarga.
- **D6** Teclas: **X** faca, **T** energético.
- **D7** Toque: botão **Faca** à direita, entre o Tiro e a borda (centro 100 px da direita, 190 px de baixo); energético na
  lista de Acessórios, selecionado sozinho quando o caçador cansa.
- **D8** Sem aba nova na loja: faca no topo de Armas, mochila no topo de Equipamentos.
- **D9** A mochila não tem botão na caçada; o canto reservado "Mochila (futuro)" do toque continua vazio.
- **D10** Aliados não veem o golpe de faca nem ouvem som (sem animação em 3ª pessoa).
- **D11** Abate com um golpe ganha "Um tiro só!"; golpes contam como disparos na precisão do resultado.
- **D12** O retrato da faca (`assets/ui/weapons/knife.png`) é gerado pela mesma ferramenta das armas e entra na exceção de
  raster do `CLAUDE.md` (a coordenação acrescenta "e da faca" na frase dos retratos).
- **D13** A barra de fôlego só aparece quando não está cheia, como fina faixa azul sob a vida (vermelha quando cansado).
