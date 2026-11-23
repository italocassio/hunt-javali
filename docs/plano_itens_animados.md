# Caçada ao Javali — Itens com gesto na mão (plano e contrato)

Versão do contrato: **1.8** de `docs/arquitetura.md` (jogo **0.9.10**, uma só fase) · complementa
`docs/arquitetura.md`. Onde este documento contradiz o contrato geral, vale este, até a fase fechar e o contrato ser
atualizado.

Retomada em sessão fria: leia `CLAUDE.md`, este documento inteiro e as seções de `docs/arquitetura.md` citadas
(§7.3, §7.13, §8.11, §9.3). Não rederive o que está aqui. Identificadores em inglês; texto do jogador em PT-BR
**exatamente** como na §2.5.

---

## 0. Estado

| Pacote | O quê | Agente | Estado |
|---|---|---|---|
| S | `data/equipment.json`: `use_time_s` e `effect_at` nos quatro consumíveis, descrições | game-systems | feito |
| A1 | `ItemBelt`: uso com tempo para todos os consumíveis, efeito no beat | game-developer | feito |
| A2 | `ItemHands` + `Player`: mostrar a view, esconder a arma, cancelar | game-developer | feito |
| ART1 | As quatro views de primeira pessoa (`assets/models/items/`) | art-director | feito |
| ART2 | Prop do drone (`scout_drone`) + três sons novos | art-director | feito |
| B | Drone que sobe e voa pelo mapa | game-developer | feito |
| QA | Testes, screenshots e validação | qa-tester | feito |

Quem fecha o pacote troca "pendente" por "feito" e anota resíduos no fim deste documento.

---

## 1. O pedido e as decisões

**Pedido do dono:** curar, energético, drone e ceva precisam de **movimento visível** — a cura mostrando o caçador
enrolando um curativo, o drone saindo voando, o energético o caçador bebendo, a ceva o milho sendo jogado no chão.

Decisões já tomadas (não rederivar):

1. **Gesto = tempo de uso.** Todo consumível passa a ter `use_time_s`, não só o kit. Enquanto o gesto roda o caçador
   **não atira, não mira, não recarrega e não troca de arma** — isso já é o comportamento de `_items_busy()` do
   `Player` para o kit, e passa a valer para os quatro. Mover e olhar continuam liberados.
2. **O efeito cai no meio do gesto, não no começo.** Cada item traz `effect_at` (fração de `use_time_s`): a ceva só
   existe no chão quando a mão solta o milho, o drone só revela quando sai da mão, o energético só enche o fôlego no
   último gole. Cancelar antes do beat **não gasta o item**.
3. **Durações curtas, e em dados.** Kit 1,5 s (sem mudança), energético 1,5 s, drone 1,2 s, ceva 0,9 s. Estão em
   `data/equipment.json` justamente para o dono afinar sem mexer em código.
4. **A arma sai da tela durante o gesto.** As mãos estão ocupadas: a view da arma esconde e volta com `play_draw` no
   fim, como depois da luneta. Se a faca estiver na mão, ela **volta para o cinto** antes do gesto começar, e no fim
   quem volta é a arma (não a faca).
5. **O drone é um objeto do mundo.** A mão só o lança; quem sobe e voa é um nó do Pacote B, criado em
   `item_used(scout_drone)`. Assim os outros jogadores do cooperativo o veem sem nenhuma mensagem nova de rede.
6. **Binóculo não muda.** Continua instantâneo, alternando a visão 6x.
7. **Sem arte raster nova.** Tudo procedural, no padrão do `knife_view.gd`.

---

## 2. Contrato

### 2.1 Dados — `data/equipment.json` (§9.3; dono: game-systems)

Dois campos novos no `effect` dos consumíveis:

| Campo | Tipo | Significado |
|---|---|---|
| `use_time_s` | float | segundos do gesto. Ausente ou ≤ 0 = uso instantâneo (é o caso do binóculo) |
| `effect_at` | float | fração 0..1 de `use_time_s` em que o efeito cai. Ausente = 1,0 (no fim) |

Valores desta fase (só estas linhas mudam; preços, `max_per_hunt` e os outros campos do `effect` ficam):

```json
{"id": "medkit", "name": "Kit de primeiros socorros", "short_name": "Kit", "description": "Recupera 50 de vida. Consumível.",
 "kind": "consumable", "price": 300, "currency": "money", "max_per_hunt": 3,
 "effect": {"heal": 50.0, "use_time_s": 1.5, "effect_at": 1.0}},
{"id": "energy_drink", "name": "Energético", "short_name": "Energia", "description": "Recupera todo o fôlego. Consumível.",
 "kind": "consumable", "price": 150, "currency": "money", "max_per_hunt": 3,
 "effect": {"stamina_restore_frac": 1.0, "use_time_s": 1.5, "effect_at": 0.8}},
{"id": "corn_bait", "name": "Ceva de milho", "short_name": "Ceva", "description": "Atrai javalis próximos por 45 s, longe da lavoura. Consumível.",
 "kind": "consumable", "price": 400, "currency": "money", "max_per_hunt": 2,
 "effect": {"duration_s": 45.0, "attract_radius_m": 80.0, "max_boars": 4, "use_time_s": 0.9, "effect_at": 0.45}},
{"id": "scout_drone", "name": "Drone batedor", "short_name": "Drone", "description": "Revela todos os javalis no minimapa por 10 s. Consumível.",
 "kind": "consumable", "price": 400, "currency": "money", "max_per_hunt": 3,
 "effect": {"reveal_s": 10.0, "use_time_s": 1.2, "effect_at": 0.7}}
```

A descrição do energético perde o "na hora" (ele deixou de ser instantâneo). Nenhum outro texto de loja muda.

### 2.2 `ItemBelt` — uso com tempo para todos os consumíveis (`src/player/item_belt.gd`, Pacote A)

`use_item(item_id)` continua sendo o único ponto de uso e continua devolvendo `true` quando o uso **começou**. O que
muda é que o caminho com tempo vale para qualquer consumível com `use_time_s > 0`:

- As recusas de hoje ficam **antes** de começar o gesto e não mudam: item não trazido, `is_busy()`, contagem zerada
  ("Acabou: …"), kit com vida cheia ("Sua vida já está cheia."), energético com fôlego cheio ("Seu fôlego já está
  cheio."). Mensagens em PT-BR idênticas às de hoje.
- Começou: `_busy_item = item_id`, `_busy_left = use_time_s`, e `use_started.emit(item_id, use_time_s)` — agora para os
  quatro, não só para o kit.
- **No beat** (`effect_at` de `use_time_s`, contado uma vez só por uso): aplica o efeito **e** só então chama
  `_consume(item_id, …)`, que desconta a unidade e emite `GameEvents.item_used`. Um `effect_at` de 1,0 cai no mesmo
  frame em que o uso termina, e nessa ordem: efeito, `item_used`, `use_finished`.
  - `medkit`: `_player.heal(heal)` com o caçador vivo, posição `_player.global_position` (igual a hoje).
  - `energy_drink`: `hunter.restore_stamina(stamina_restore_frac)`, posição do caçador.
  - `corn_bait`: posição `_bait_position()` **calculada no beat** (a mão solta o milho olhando para onde o caçador
    olha agora, não para onde olhava no aperto).
  - `scout_drone`: `drone_reveal_s = reveal_s` e `Sfx.play(&"drone_buzz")` no beat, posição do caçador.
- `use_finished.emit(item_id)` no fim da duração, como hoje.
- `cancel_use()` antes do beat: nada de efeito, **nada consumido**, `use_finished.emit(&"")`. Depois do beat: o efeito
  já valeu e o item já foi gasto; só o gesto é cortado.
- O caçador que morre ou cai no meio do gesto não cura e não bebe: o `Player` chama `cancel_use()` (§2.3), e o
  `_process` do cinto nunca aplica efeito com `_player.is_alive() == false`.
- `get_busy_item()`, `get_busy_progress()` e `is_busy()` não mudam de assinatura — e por isso `Quickbar`,
  `TouchControls` e `HintDirector` já mostram o progresso dos quatro sem precisar de mudança. **Confirmar** isso, não
  reescrever: se algum deles tiver um `if item_id == Ids.I_MEDKIT`, aí sim generalize.

### 2.3 `ItemHands` e `Player` (Pacote A)

Classe nova `ItemHands` — `src/player/item_hands.gd`, filha do `Player`, mesma relação que o `Knife` tem com a view:

```gdscript
class_name ItemHands
extends Node
## Mãos de item em primeira pessoa: cria uma ItemViewBase por consumível trazido que tenha arte e toca o
## gesto enquanto o ItemBelt estiver ocupado com aquele item (docs/plano_itens_animados.md §2.3).

func setup(belt: ItemBelt, holder: Node3D) -> void   ## views como filhas do WeaponHolder; conecta-se ao cinto
func is_showing() -> bool                            ## um gesto está na tela agora
func set_rest_visible(on: bool) -> void              ## igual ao Knife: pré-aquecimento antes de hunt_started
func cancel() -> void                                ## corta o gesto e esconde a view
func get_view(item_id: StringName) -> ItemViewBase   ## só para testes; null quando não há arte
```

- Cria a view com `AssetLoader.exists(ScenePaths.item_view(item_id))` + `AssetLoader.instantiate`, e **só** para os
  ids de `belt.get_usable_ids()` que são consumíveis. Sem arte: nenhuma view, nenhum erro, e aí a arma **não** esconde
  (nunca deixe a tela vazia).
- Conecta `belt.use_started` → mostra a view do item e chama `play_use(duration_s, effect_at)`; `belt.use_finished` →
  esconde a view (e `cancel_use()` nela quando o id vier `&""`).
- Pré-aquecimento (risco R3 do contrato): as views ficam visíveis desde o `setup` até `hunt_started`, atrás da tela de
  carregamento, para os materiais compilarem. O `Player` chama `_hands.set_rest_visible(false)` no mesmo ponto em que
  já chama `_knife.set_rest_visible(false)`.

No `Player` (`src/player/player.gd`):
- Cria o `ItemHands` depois do `ItemBelt` e do `WeaponHolder`, passando `_holder`.
- `_update_aim`: a arma esconde também quando `_hands.is_showing()`, e volta com `_holder.play_draw(DRAW_TIME_S)` no
  `use_finished` (já existe `_on_item_use_finished`).
- Antes de começar um uso com a faca na mão: `set_knife_equipped(false)`. Se isso falhar (golpe em curso), o uso nem
  começa — hoje o laço de itens já ignora o aperto com `is_knife_swinging()`.
- `cancel_use()` do cinto quando o caçador cai (`_downed`), morre ou a caçada acaba; `_hands.cancel()` logo depois.
- Nada muda em `bot_use_item`: o bot segue chamando `use_item` e agora fica ocupado o tempo do gesto.

### 2.4 Arte: as quatro views (`assets/models/items/`, art-director) — §7.13

Raiz `Node3D` estendendo `ItemViewBase` (`src/core/item_view_base.gd`), um `<item_id>_view.tscn` por item
(`ScenePaths.item_view`), script compartilhado `assets/models/items/item_view.gd` permitido, no molde do
`knife_view.gd`: poses em espaço de câmera, interpolação por frações do gesto, `set_process(false)` em repouso.

Ids e o que o jogador precisa **ler na primeira vez**:

| Id | Gesto |
|---|---|
| `medkit` | antebraço esquerdo atravessa a tela; a mão direita **enrola a faixa** duas voltas em volta dele e dá o aperto final no beat; as mãos saem |
| `energy_drink` | lata na mão direita sobe ao centro-baixo da tela, inclina para trás, **dois goles**, desce; no beat o último gole |
| `scout_drone` | as duas mãos trazem o quadricóptero à altura do peito, as hélices giram, as mãos **empurram para cima e para frente**; no beat ele sai da mão (a view some) |
| `corn_bait` | a mão direita com a espiga recua e **joga por baixo** para a frente; no beat a mão fica vazia |

- Orçamento por view: ≤ 3 500 triângulos com braços, ≤ 3 `MeshInstance3D`, ≤ 3 materiais, `cast_shadow = OFF`,
  **sem shader novo**, texturas procedurais ≤ 512 px. Reaproveitar `ArmsHD` (material de luva e as funções de mão),
  `HDMesh` e os materiais de prop já existentes. Paleta do cerrado; a faixa do curativo em bege sujo, a lata em
  cores de energético sem marca nenhuma.
- Repouso = fora da tela (abaixo da borda de baixo). O `ItemHands` só torna a view visível durante o gesto, mas a view
  precisa estar correta em repouso por causa do pré-aquecimento.
- `play_use(duration_s, effect_at)` tem de caber **exatamente** na duração recebida (0,9 s a 1,5 s) e pousar o beat em
  `effect_at`; não assuma 1,5 s.

### 2.5 Arte: prop do drone e sons (art-director)

- `res://assets/models/props/scout_drone.tscn` (§7.4): quadricóptero de ~0,35 m, raiz `Node3D`, ≤ 600 triângulos,
  ≤ 2 `MeshInstance3D`, sem luz e sem física; as quatro hélices giram no `_process` do próprio prop. O mesmo prop
  serve para a mão (a view do item pode instanciá-lo) e para o mundo.
- Sons novos na biblioteca `Sfx` (§7.8, grupo "Jogador (A)"): `bandage_wrap`, `drink_gulp`, `bait_throw`. Procedurais,
  curtos (≤ 0,8 s), no padrão dos outros. `drone_buzz`, `energy_drink`, `bait_drop` e `player_heal` continuam como
  estão.
- Quem toca o quê (Pacote A, no `ItemBelt`): `bandage_wrap` e `drink_gulp` no começo do gesto do kit e do energético;
  `bait_throw` no beat da ceva; `drone_buzz` no beat do drone (já é assim).

### 2.6 Drone no mundo (Pacote B)

`src/world/scout_drone.gd` (`class_name ScoutDrone`, `Node3D`), criado pelo `HuntController._on_item_used` quando
`item_id == Ids.I_SCOUT_DRONE`, na posição recebida + a altura dos olhos:

- Sobe ~10 m em ~1,5 s (suavizado), depois **voa**: um círculo largo e lento em volta do ponto de lançamento,
  sempre acima do terreno (`HuntWorld.get_height`), durante `reveal_s` (10 s) contados do nascimento.
- No fim desce de volta ou se afasta e se libera (`queue_free`). Nenhuma colisão, nenhuma luz, nenhum som próprio.
- Visual pelo prop `scout_drone` com `AssetLoader`; sem o prop, nenhum nó (nem caixa de fallback).
- Vale igual para host, cliente e offline: o gatilho é o `item_used`, que cada máquina já recebe. **Nenhuma mensagem
  nova de rede**, nenhum campo novo no `NetCodec`.

### 2.7 Fora de escopo (não faça)

Gesto do caçador aliado em terceira pessoa (`RemoteHunter`/`hunter_visual`); qualquer mensagem, campo ou sequência
nova de rede; mudar cura, fôlego restaurado, `reveal_s`, preço ou `max_per_hunt`; mexer no binóculo, na faca, nas
armas ou no layout de toque; arte raster nova; `project.godot`, `export_presets.cfg` e `CLAUDE.md` (são da sessão
principal).

---

## 3. Aceite

1. `tools/godot.sh --headless --path . --import`, `check_scripts`, `unit_tests`, `flow_test` e `playthrough` passam.
2. Com janela: um screenshot **no meio** de cada um dos quatro gestos mostrando a mão/o braço e o item, e a arma fora
   da tela. Quatro imagens, uma por item.
3. Um screenshot do drone no ar, visto de baixo, logo depois do lançamento.
4. Ceva: o monte de milho aparece onde a mão apontava **no beat**, não no aperto; `bait_placed` sai no beat.
5. Cancelar o gesto antes do beat (cair ou morrer) não gasta o item, não cura, não enche o fôlego e não cria ceva.
6. Teste automatizado novo de `ItemBelt` com tempo (`tests/unit/`): beat uma vez só, `item_used` no beat,
   `use_finished` no fim, cancelamento antes e depois do beat.
7. 30+ fps no orçamento do contrato (§13.1) em `low`; nenhuma view de item criada para item não trazido.

## 4. Riscos

- **R1** — travar o caçador 1,5 s na horda pode parecer injusto. Mitigação: durações em dados; o dono afina.
- **R2** — primeiro gesto engasgando por compilação de material. Mitigação: pré-aquecimento da §2.3.
- **R3** — a ceva no beat muda levemente o lugar onde ela cai no cooperativo. Aceito: o aperto e o beat ficam a
  menos de meio segundo um do outro.

## 5. Resíduos

**S (dados).** O `medkit` já tinha `use_time_s`; só faltava o `effect_at` (a §2.1 tratava os dois como novos).
`data_registry.gd` não precisou mudar (repassa o `effect` inteiro). O texto do energético em
`src/ui/common/item_card.gd` perdeu o "na hora" ("Fôlego cheio", "Recupera %d%% do fôlego"), decidido pela sessão
principal. Dar `use_time_s` ao energético derrubou três testes de `tests/`, que o pacote QA conserta:
`test_item_hud::use_item_ok_consumes_and_announces` e `quickbar_exhausted_slot_dims_and_shows_zero` (precisam avançar o
tempo do gesto antes de olhar a contagem) e `item_card_stats_text_of_the_energy_drink` (texto novo).

**ART2 (prop e sons).** ≤ 2 `MeshInstance3D` com quatro hélices girando não cabe ao pé da letra: ficou 1
`MeshInstance3D` (corpo, 380 tris) + 1 `MultiMeshInstance3D` (4 hélices, 36 tris cada), 524 triângulos no total,
aceito pela sessão principal. `MeshKit.count_triangles` não vê o `MultiMeshInstance3D`: quem auditar o orçamento soma
4 × 36. Os sons entraram por `assets/audio/synth/synth_weapons.gd` (`LAZY_IDS`/`build_lazy`, o padrão de
`energy_drink` e `knife_swing`), sintetizados na primeira vez que toca; `sfx_library.gd` não mudou. O prop expõe
`rotor_speed` (padrão 70 rad/s) e gira as hélices sozinho. Extra fora do pedido: `assets/preview/preview_drone.tscn`
(aceita `-- --shot=<caminho.png>`).

**A1 (`ItemBelt`).** `_apply_effect(item_id)` nova, usada pelo beat e pelo uso instantâneo; `_end_gesture(id)` encerra o
gesto do caçador que morreu como cancelamento (não cura, não gasta, `use_finished(&"")`). `_busy_total()` passou a ler o
total guardado, não o `Data`. Decisões aceitas: efeito inútil no beat (fôlego que regenerou sozinho durante o gole) gasta
o item do mesmo jeito — a recusa "já está cheio" só vale no aperto; consumível sem `use_time_s` vira instantâneo (o kit
tinha padrão 1,0 antes). `Quickbar`, `TouchControls`, `HintDirector` e `hud.gd` não precisaram de mudança; a dica de
aprendizado do item passa a ser marcada no beat.

**A2 (`ItemHands`/`Player`).** A faca só vai para o cinto no `use_started`, não antes de `use_item`: assim uma recusa não
desarma o caçador à toa (aceito). Acréscimo aceito fora do contrato: o começo do gesto cancela a recarga e descarta o
tiro em buffer, como o golpe de faca. O `Player` guarda `_weapon_hidden_by_hands` em vez de reconsultar `is_showing()`,
para não depender da ordem das conexões. Extras: `--item_use=<id>` no sandbox do jogador (com `--hp=50` para o kit e
`--stamina=40` para o energético) e `src/player/debug/player_items_test.tscn` (73 verificações com views falsas).

**B (`ScoutDrone`).** `launch(parent, world, from, life_s)` é estática e devolve `null` sem o prop. Sobe 10 m em 1,5 s,
circula a 12 m de raio **à frente da câmera no nascimento** (a §2.6 não dizia o lado), nunca a menos de 6 m do terreno, e
nos últimos 2 s sobe mais 14 m abrindo o raio para 30 m antes de se liberar. Os números de voo são `const` no script, não
dados — se o dono quiser afinar, o game-systems cria as chaves em `equipment.json`. O drone é filho do `HuntController`,
então morre com a cena; não é liberado no `_finish` (caçada que acaba com ele no ar não foi exercitada). Extra: caso
`drone` em `src/hunt/debug/hunt_selftest.gd` (`-- --fallback-player --only=drone`).

**ART1 (views).** Script único `assets/models/items/item_view.gd` com `get_budget()` para preview e testes. Orçamento
medido: kit 2 640 tris / 3 nós, energético 1 452 / 1, drone 2 900 / 3 (inclui o prop, cujas hélices são um
`MultiMeshInstance3D`), ceva 1 232 / 2; 2 materiais cada (luva do `ArmsHD` + material de prop), nenhum shader e nenhuma
textura nova. Com `effect_at` 1,0 (o kit) não sobra tempo depois do beat, então a view limita o beat **visual** a 0,9
da duração (`MAX_VISUAL_BEAT`, piso 0,15): no kit o aperto aparece em 0,9 e a cura cai em 1,0 — decidido manter o dado
em 1,0, sem mudança de balanceamento. A view do drone usa o prop real e tem corpo de reserva próprio (caminho não
exercitado). A faixa do curativo é bege (0,92/0,90/0,80) e parece alaranjada sob o pôr do sol do mapa de preview.
Extra: `assets/preview/items_preview.tscn` (`-- --out=<dir>`).

**QA.** `unit_tests` 586/0 em 5 rodadas seriais; `flow_test` 24/24; `playthrough` 22/22; `player_items_test` 73/73;
`player_stamina_test` 130/130; `player_knife_test` 332/332; `hud_hints_test` 154/154; `hunt_selftest --only=drone` 8/8.
O `SCRIPT ERROR: Invalid access of index '0' on 'Array'` era do próprio teste (`test_item_hud.gd:281` supunha mensagem
no aperto), não do jogo. As falhas de `test_save.json` eram execução paralela de agentes: somem em rodada serial.
Testes novos: `tests/unit/test_item_belt_timed.gd` (20) e `tests/unit/test_item_gestures_player.gd` (9, com `Player`
real), mais a ferramenta de screenshot `tests/shots/item_shot.tscn` (`--item_use=`, `--at=`, `--air=`, `--out=`).
Observações aceitas sem correção: o binóculo levantado solta o zoom durante o gesto e volta sozinho depois (já era
assim com o kit); vida enchida por outra fonte no meio do gesto gasta o kit sem ganho (a recusa só vale no aperto); a
view do drone cobre a Quickbar na metade do gesto (cosmético).
**Não verificado por ninguém:** 30+ fps em `low`, exportação Web no navegador, toque real em celular, e o item 4 do
aceite dentro do `HuntController` (a ceva no beat, com `bait_placed`) além do que o teste de unidade prova no cinto.
