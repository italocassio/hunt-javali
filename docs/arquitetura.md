# Caçada ao Javali — Contrato de Arquitetura

Versão do contrato: **1.6** (1.2 = jogo 0.5.0: modo Horda Javali, contrato em `docs/horda.md`; 1.3 = frente
HUD/onboarding, fases 1 e 2: teclas fixas por item, barra de itens, botões de item no toque, dicas das primeiras
caçadas; §4, §6.3, §6.8, §8.4, §8.11, §9.1, §9.3, §10, §11, §14; fase 4, jogo 0.8.2: ação `help`, objetivos e
legenda de teclas, nomes nos botões de toque; §4, §6.8, §8.4, §9.1, §14; 1.4 = fase 5, jogo 0.8.3: bússola com
graus e colaterais, marcadores comuns à bússola e ao minimapa, minimapa com imagem do mapa gerada na CPU, Preparação
sem teclas de atalho; §2, §6.8, §6.9, §6.10, §8.1, §8.4, §9.1, §11, §12, §13.1, §14, Apêndice A; 1.4 (implementado
em 0.8.3): divergências aceitas pelo coordenador registradas em §6.8, §6.10, §8.4, §11, §12, §13.1 e §14; 1.5 = fase 6,
jogo 0.8.4: painel da arma com retrato, munição grande e fileira de armas 1–5 (`WeaponPanel`), vida em barra larga
embaixo no centro (`HealthStrip`), barra de itens sobe 26 px, FPS sozinho no canto superior esquerdo, painel da arma
na coluna da esquerda no toque; §2, §4, §6.8, §7.9, §8.4, §12, §13.1, §14; 1.5 (implementado para 0.8.4):
divergências aceitas pelo coordenador registradas em §6.8, §8.4, §12 e §14, e as folgas do toque refeitas no canvas
virtual (4:3 = 1280×960, não 960×720); 1.6 = HF7, só modo toque: layout estilo PUBG Mobile, dois botões de Tiro, botão
Cura, botão Acessórios com lista, cartões de arma, chip do colete; §6.8, §8.4, §14) · Godot **4.7.2** ·
GDScript tipado · Renderer **Compatibility** · Web sem threads.

**1.7 (F1 mochila publicada em 0.9.5; F2–F4 pendentes, jogo 0.9.6–0.9.8): faca, mochila e fôlego.** Plano, contrato completo e fases F1–F4 em
`docs/plano_faca_mochila_folego.md` (§2 é o contrato). Aqui ficam só os pontos de entrada: §1, §4, §6.2, §6.3, §9.11, §10 e
§14; cada trecho diz a fase. Até a fase fechar, vale o plano; no fecho, a coordenação completa §6.8, §8.4, §8.11, §8.12 e o
Apêndice A.

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
até 2 armas, até 3 equipamentos (1.7: 3 a 6, pelo nível da mochila), 0–1 cão) → Caçada → Resultado → Loja → Preparação…

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

**Horda Javali (0.5.0):** segundo modo, escolhido pelo anfitrião na sala (1 a 4 jogadores; não existe no menu
solo). Mato Grosso; os caçadores defendem o **celeiro** e o seu estoque de milho (100% → 0%, que ocupa o
lugar da saúde da lavoura em todo o caminho de dados) contra ondas de javalis definidas em `data/horde.json`,
a última com cachaço alfa. Os javalis correm direto ao celeiro e não fogem; fêmeas, machos e alfa investem
pelas regras de hoje. Vitória: todas as ondas abatidas. Derrota: estoque em 0 ou todos os caçadores caídos.
Todas as armas, reserva de munição infinita, prêmio de abate reduzido, bônus de defesa na vitória, nunca conta
para a progressão. `HuntRequest.mode` (`&"contract"` | `&"horde"`) liga o modo; com `&"contract"` nenhum código
de horda executa. Contrato completo: `docs/horda.md`.

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
│   ├── multiplayer.md            detalhe do protocolo do modo cooperativo
│   └── horda.md                  contrato do modo Horda Javali (0.5.0)
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
│   ├── net.json
│   └── horde.json                (0.5.0, docs/horda.md §3)
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
│   │   ├── map_environment_base.gd class MapEnvironmentBase
│   │   └── corn_stock_visual_base.gd class CornStockVisualBase (0.5.0, horda)
│   ├── input/                    game-developer Pacote A
│   ├── player/                   game-developer Pacote A
│   │   └── debug/                (sandbox do pacote A)
│   ├── weapons/                  game-developer Pacote A
│   ├── hud/                      game-developer Pacote A
│   │   ├── quickbar.gd           class Quickbar (barra de itens, §8.4)
│   │   ├── hint_director.gd      class HintDirector (gatilhos das dicas, sem UI, §8.4)
│   │   ├── hint_banner.gd        class HintBanner (faixa da dica, §8.4)
│   │   ├── dog_card.gd           class DogCard (cartão do cão, §8.4)
│   │   ├── objectives_panel.gd   class ObjectivesPanel (objetivos das primeiras caçadas, §8.4)
│   │   ├── controls_legend.gd    class ControlsLegend (legenda de teclas das primeiras caçadas, §8.4)
│   │   ├── map_markers.gd        class MapMarkers (formas e cores comuns à bússola e ao minimapa, §8.4, 1.4)
│   │   ├── weapon_panel.gd       class WeaponPanel (arma ativa, munição, fileira de armas, §8.4, 1.5)
│   │   ├── health_strip.gd       class HealthStrip (barra de vida larga embaixo, §8.4, 1.5)
│   │   ├── debug/                (sandboxes do HUD; hud_hints_test.tscn|.gd, §14)
│   │   └── touch/
│   ├── hunt/                     game-developer Pacote B
│   │   └── debug/
│   ├── world/                    game-developer Pacote B
│   │   ├── minimap_baker.gd      class MinimapBaker (imagem do minimapa na CPU, §8.4, 1.4)
│   │   ├── debug/                (1.4: minimap_selftest.tscn|.gd, §14)
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
3d_physics/layer_5="fence"

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
| 3 | 4 | player | `CharacterBody3D` do jogador | `terrain | static | fence` (19, `Layers.MASK_PLAYER_BODY`) |
| 4 | 8 | boar_hitzone | `HitZone` (Area3D, `monitoring=false`, `monitorable=true`) | 0 |
| 5 | 16 | fence | paredes invisíveis que confinam o caçador à fazenda (Horda nível 2); só bloqueiam o corpo do jogador | 0 |

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
| `weapon_3`, `weapon_4`, `weapon_5` (0.5.0) | 3, 4, 5 | — | — (slot inexistente = nada; na horda há 5 armas, `docs/horda.md` §7) |
| `weapon_swap` | — | — | botão Trocar arma (cicla todas as armas carregadas) |
| `dog_command` | E | — | botão Cão (só existe com cão na caçada, §8.4) |
| `use_medkit` | Q | — | botão do kit (só se equipado) |
| `use_corn_bait` | G | — | botão da ceva (só se equipada) |
| `use_scout_drone` | V | — | botão do drone (só se equipado) |
| `use_binoculars` | B | — | botão do binóculo (só se equipado; liga/desliga) |
| `spectate_next` | F | — | — (no toque o espectador troca com Tiro ou Trocar) |
| `pause` | Esc, P | — | botão Pausa |
| `help` (jogo 0.8.2) | H | — | — (no toque não há legenda; os botões trazem os nomes, §8.4) |
| `use_energy_drink` (1.7, F3, pendente) | T | — | botão Acessórios (o energético entra na lista) |
| `knife` (1.7, F4, pendente) | X | — | botão Faca |

1.7 (`docs/plano_faca_mochila_folego.md` §2.5): `ACTIONS` ganha no fim, nessa ordem, `"use_energy_drink"` (F3) e `"knife"`
(F4), depois de `"interact"`; `ITEM_ACTIONS` ganha `&"energy_drink": &"use_energy_drink"` no fim (F3). `knife` não é item.

O olhar (mouse e arrasto na metade direita) **não é ação**: é tratado pelo `Player` diretamente.

**Itens com tecla fixa (1.3).** Não existe item selecionado nem ciclo: cada item usável tem a sua ação
(`use_<item_id>`) e a sua tecla. As ações `use_item` e `item_next` **deixaram de existir** (removidas de
`ACTIONS`, do `Player`, do `TouchControls` e dos testes). F ficou só para o espectador (`spectate_next`, §11).
Apertar a tecla de um item que não veio na caçada mostra "Você não trouxe este item: <nome>." (ver
`ItemBelt.use_item`, §8.11). G, V e B não colidem com nenhuma tecla anterior.

**Ajuda (jogo 0.8.2).** `help` (H) abre e recolhe a legenda de teclas das primeiras caçadas (`ControlsLegend`,
§8.4). Quem trata a tecla é o `Hud` (`_unhandled_input`, ignora eco, só com a legenda visível); fora das primeiras
caçadas, no toque, com `?hints=0` ou com a árvore pausada, H não faz nada. Nenhuma outra tecla mudou.

**Fileira de armas (1.5, jogo 0.8.4).** Nenhuma ação nova. O `WeaponPanel` (§8.4) mostra, em cada arma carregada de
índice `i` (0 = primeira), o rótulo `InputSetup.get_key_label(StringName("weapon_%d" % (i + 1)))` ("1"…"5"), só no
teclado/mouse. É só vista: quem troca de arma continua sendo o `Player` (`weapon_1`…`weapon_5`, `weapon_swap`); a
fileira não é tocável no toque (o botão Trocar já existe).

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
	"zoom_in","zoom_out","reload","sprint","crouch","weapon_1","weapon_2","weapon_3","weapon_4","weapon_5",
	"weapon_swap","dog_command","use_medkit","use_corn_bait","use_scout_drone","use_binoculars",
	"spectate_next","pause","help"]
## Usable item id -> its action. The insertion order is THE order of the item slots (quickbar, touch row).
const ITEM_ACTIONS: Dictionary = {&"medkit": &"use_medkit", &"corn_bait": &"use_corn_bait",
	&"scout_drone": &"use_scout_drone", &"binoculars": &"use_binoculars"}
func register_actions() -> void          # chamado no _ready; idempotente
func is_touch_mode() -> bool
func set_touch_override(mode: String) -> void   # "auto" | "on" | "off"; reaplica e emite se mudou
func release_all_actions() -> void       # Input.action_release em todas (fim de caçada / pausa)
func get_item_action(item_id: StringName) -> StringName   # ITEM_ACTIONS.get(item_id, &""); &"" = item sem ação (passivo)
func get_key_label(action_name: StringName) -> String     # OS.get_keycode_string da 1ª tecla da ação ("Q", "E"); "" se não tem tecla
```
`get_key_label` é a **única** fonte do texto de tecla mostrado ao jogador (barra de itens, dicas, tela de
equipamento). Ninguém escreve "Q" ou "E" literal em texto de UI.

---

## 5. Barramento `GameEvents`

Arquivo `res://src/core/game_events.gd` (código verbatim no Apêndice A). Só declara sinais; nenhum estado.
Emite-se com `GameEvents.<sinal>.emit(...)`. Regra: quem é dono do fato emite; ninguém emite sinal de outro.

| Sinal | Emissor | Ouvintes | Quando |
|---|---|---|---|
| `hunt_started(request: HuntRequest)` | B `HuntController` | A `Hud`/`Player`/`HintDirector`, tests | mundo pronto, jogador posicionado, contagem inicial emitida |
| `hunt_ended(result: HuntResult)` | B `HuntController` | A (solta mouse, desliga input, some com controles de toque), tests | uma única vez, no frame em que a condição de fim é detectada |
| `hunt_paused_changed(paused: bool)` | A `PauseOverlay` | tests | ao pausar/despausar |
| `hunt_abandon_requested()` | A `PauseOverlay` ("Desistir") | B `HuntController` | B encerra com `ABANDONED` |
| `shot_fired(weapon_id: StringName, origin: Vector3, direction: Vector3, noise_radius_m: float)` | A `Weapon` | B (alerta javalis; conta tiros) | uma vez por puxada de gatilho (não por bago) |
| `player_damaged(amount: float, source_position: Vector3, health_after: float)` | A `Player.apply_damage` | A `Hud` (indicador direcional), tests | dano já reduzido pelo colete |
| `player_healed(amount: float, health_after: float)` | A `Player` | A `Hud` | kit usado |
| `player_died()` | A `Player` | B `HuntController` | vida chegou a 0 (uma vez) |
| `item_used(item_id: StringName, position: Vector3)` | A `ItemBelt` | B (ceva; conta consumíveis), A `HintDirector` (aprendido), tests | **só consumíveis** (`medkit`, `corn_bait`, `scout_drone`), após decrementar |
| `thermal_vision_changed(active: bool)` | A `Player` | B (`BoarVisualBase.set_highlight`) | mira térmica equipada e entrou/saiu da mira |
| `dog_command_requested()` | A (tecla E / botão Cão) | B `Dog` | B decide se é "Pega!" ou "Volta!" |
| `boar_spawned(boar_id: int, type_id: StringName, weight_kg: float)` | B | tests | javali entrou no mapa |
| `boar_hit(boar_id: int, zone: StringName, damage: float, hit_position: Vector3, shot_id: int)` | B `Boar` | A `Hud` (hitmarker, dedup por `shot_id`), tests | por bago/bala que acertou; `damage` já com multiplicador de zona |
| `boar_state_changed(boar_id: int, state: StringName)` | B `Boar` | tests | toda transição da FSM (`Ids.BS_*`) |
| `boar_killed(kill: KillInfo)` | B `HuntController` | A `Hud` (mensagem de abate), tests | morte, já com `reward_money` |
| `boar_counts_changed(killed: int, total: int)` | B | A `Hud` | no início e a cada morte |
| `crop_health_changed(pct: float)` | B `CropManager` | A `Hud` | quando variou ≥ `hunt.crop_health_signal_step_pct` desde o último envio, e ao chegar a 0 |
| `crop_under_attack(active: bool)` | B `CropManager` | A `Hud` ("Javalis na lavoura!" + `crop_alarm`), A `HintDirector` (dica da ceva) | nº de javalis comendo passa de 0→>0 (true) ou >0→0 (false) |
| `bait_placed(position: Vector3, duration_s: float)` | B | A `Hud` (minimapa), tests | ceva instanciada |
| `dog_state_changed(state: StringName)` | B `Dog` | A `Hud` | transição (`Ids.DS_*`) |
| `dog_health_changed(pct: float)` | B `Dog` | A `Hud` | vida do cão mudou (0–100) |
| `dog_marked_boar(position: Vector3, duration_s: float)` | B `Dog` | A `Hud` (bússola + minimapa) | cão apontou/acuou/agarrou |
| `dog_command_executed(command: StringName)` | B `Dog` | A `Hud` (balão "Pega!"/"Volta!"), A `HintDirector` (aprendido) | `Ids.CMD_ATTACK` ou `Ids.CMD_RECALL` |
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
| `net_reconnect_changed(active: bool)` | `Net` | A `Hud`, A `Player`, B `HuntController` | F8: cliente tentando voltar à caçada (`docs/multiplayer.md` §4.7) |
| `hunter_away_changed(slot: int, away: bool)` | B `HuntController` | A `Hud` | F8: bit `HF_AWAY` de um aliado mudou |
| `horde_wave_changed(wave: int, wave_count: int, phase: StringName, countdown_s: float)` | B `HuntController` | A `Hud`, tests | só em horda: mudança de fase da onda (`docs/horda.md` §4.1) |
| `horde_wave_progress(remaining: int, wave_total: int)` | B `HuntController` | A `Hud`, tests | só em horda: início de onda e cada abate dela, depois de `boar_counts_changed` |

Em horda, `crop_health_changed`/`crop_under_attack` carregam o **estoque do celeiro** e `boar_counts_changed` continua
contando a partida inteira (todas as ondas).

As dicas das primeiras caçadas (§8.4) **não** têm sinal no barramento: são locais ao Pacote A (sinais do próprio
`HintDirector`) e não mudam `src/core/`. Em rede cada máquina tem o seu `Profile` e vê só as próprias dicas.

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
func get_horde() -> Dictionary                        # data/horde.json inteiro (§9.10); {} se ausente
func get_item_def(id: StringName) -> Dictionary       # procura em weapons, equipment e dogs
func get_item_category(id: StringName) -> StringName  # &"weapon" | &"equipment" | &"dog" | &""
# 1.7 (F1, jogo 0.9.5): data/upgrades.json, melhorias compradas com dinheiro (mochila, faca). Não são itens:
# get_item_def/get_item_category não as veem. docs/plano_faca_mochila_folego.md §2.2–2.3.
func get_upgrade_ids() -> Array[StringName]                         # ordem do arquivo; [] sem o arquivo
func get_upgrade(id: StringName) -> Dictionary                       # {} + push_error se não existir
func get_upgrade_level_count(id: StringName) -> int                  # 0 se não existir
func get_upgrade_level_def(id: StringName, level: int) -> Dictionary # levels[level - 1]; {} fora de 1..count
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
func get_loadout_items() -> Array[StringName]             # até game.loadout.item_slots (3); 1.7: até get_item_slots()
func set_loadout_items(item_ids: Array[StringName]) -> bool
# melhorias (1.7, F1, jogo 0.9.5; docs/plano_faca_mochila_folego.md §2.4)
func get_item_slots() -> int                              # loadout.item_slots + bonus_item_slots da mochila. stub 3
func get_upgrade_level(upgrade_id: StringName) -> int     # 1..máximo; id desconhecido = 0. stub 1
func get_upgrade_max_level(upgrade_id: StringName) -> int
func can_buy_upgrade(upgrade_id: StringName) -> StringName   # mesmos códigos de buy_upgrade, sem efeito
func buy_upgrade(upgrade_id: StringName) -> StringName    # &"ok" | &"insufficient_funds" | &"max_reached" | &"unknown_item"; sobe 1 nível, salva
# progressão
func get_unlocked_contract_count(map_id: StringName) -> int        # >= 1 para mapa disponível
func is_contract_unlocked(map_id: StringName, index: int) -> bool
func is_contract_completed(map_id: StringName, index: int) -> bool
func get_stats() -> Dictionary                            # cópia do bloco "stats" do save
# ponte com a caçada
func build_hunt_request(map_id: StringName, contract_index: int) -> HuntRequest   # stub: HuntRequest.make_debug(map_id, contract_index)
func kill_reward(type_id: StringName, weight_kg: float, killing_zone: StringName, one_shot: bool, map_id: StringName, contract_index: int) -> int   # stub 0
func contract_bonus(map_id: StringName, contract_index: int, crop_health_pct: float) -> int                                                       # stub 0
func horde_kill_reward(type_id: StringName, weight_kg: float, killing_zone: StringName, one_shot: bool) -> int   # stub 0; docs/horda.md §10.1
func horde_bonus(stock_pct: float) -> int                                                                         # stub 0; docs/horda.md §10.1
func apply_hunt_result(result: HuntResult) -> void        # ÚNICO ponto que credita a caçada; salva
# doações
func is_code_redeemed(code: String) -> bool
func mark_code_redeemed(code: String) -> void
# settings
func get_setting(key: String) -> Variant                  # stub: valor default da tabela §10
func set_setting(key: String, value: Variant) -> void     # valida, emite settings_changed, salva
# onboarding (dicas das primeiras caçadas, §8.4; 1.3)
func is_onboarding_active() -> bool                       # stats.hunts_played < game.onboarding.max_hunts. stub false
func is_hint_learned(hint_id: StringName) -> bool         # hint_id está em onboarding.learned. stub false
func mark_hint_learned(hint_id: StringName) -> void       # idempotente; só memória (NÃO salva); id inválido → push_warning e ignora
```
Onboarding: `hint_id` válido = id de equipamento de `data/equipment.json` com `kind` `"active"` ou
`"consumable"`, ou `"dog_command"` (a mesma regra vale no `sanitize`, §10). `mark_hint_learned` não grava para
não escrever no IndexedDB no meio da caçada: o aprendido entra no próximo `save()`, que sempre acontece em
`apply_hunt_result` (toda caçada termina nele, inclusive desistência). Aba fechada no meio da caçada perde o
aprendido daquela caçada, igual a `hunts_played`. `reset_progress()` zera `onboarding.learned`.
`apply_hunt_result`: `money += result.total_money`; subtrai `result.consumables_used` do inventário;
se `VICTORY` **e `result.counts_for_progression`**: marca o contrato vencido e desbloqueia o próximo
(`index + 1`, se existir); atualiza stats; `save()`. Chamado só por `Router.finish_hunt`. Settings novo:
`player_name` (String, §10). Horda: o `HuntResult` chega com `counts_for_progression = false` e
`contract_bonus` = bônus de defesa; `apply_hunt_result` não muda.

### 6.4 Autoload `InputSetup` — `res://src/input/input_setup.gd` — dono: Pacote A
API em §4. Stub: `register_actions()` vazio, `is_touch_mode()` → `false`.

### 6.5 Autoload `Sfx` — `res://assets/audio/sfx_library.gd` — dono: art-director
API e ids em §7.8. Stub: tudo no-op, `has_sound()` → `false`.

### 6.6 Autoload `Router` — `res://src/systems/router.gd` — dono: game-systems
```gdscript
var selected_map_id: StringName = &"mato_grosso"
var selected_contract_index: int = 0
var last_result: HuntResult = null

func goto(scene_path: String) -> void                 # despausa a árvore, release_all_actions, música (Sfx.play_music se a cena está em game.music.scenes, senão Sfx.stop_music com game.music.fade_out_s), change_scene_to_file deferred
func get_current_scene_path() -> String
func scene_has_music(scene_path: String) -> bool      # true se game.json "music.scenes" lista a cena
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
| `CornStockVisualBase` | `src/core/corn_stock_visual_base.gd` | Node3D | API do estoque de milho do celeiro (horda, `docs/horda.md` §11.1) + fallback |

### 6.8 Pacote A — classes públicas (dono: game-developer A)

| class_name | Arquivo | Extends | API pública relevante para outros |
|---|---|---|---|
| `Player` | `src/player/player.gd` (cena `src/player/player.tscn`) | PlayerBase | toda a API de `PlayerBase`; 1.5: `get_weapon_ids() -> Array[StringName]` (cópia, na ordem dos slots: o índice `i` é a ação `weapon_{i+1}` e o valor de `get_weapon_slot()`; não muda durante a caçada), `debug_set_health(hp: float) -> void` (só sandbox/tests: `_health = clampf(hp, 1.0, get_max_health())`, sem sinal, sem dano, nunca mata) |
| `Weapon` | `src/weapons/weapon.gd` | Node | interna ao A |
| `WeaponHolder` | `src/weapons/weapon_holder.gd` | Node3D | interna |
| `Hitscan` | `src/weapons/hitscan.gd` | RefCounted (static) | `static func cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, max_range_m: float, exclude: Array[RID]) -> Dictionary` |
| `ItemBelt` | `src/player/item_belt.gd` | Node | interna ao A; API em §8.11 (usada por `Player`, `Hud`, `Quickbar`, `TouchControls`, `HintDirector` e tests) |
| `Hud` | `src/hud/hud.gd` (cena `src/hud/hud.tscn`) | CanvasLayer | `func bind(player: PlayerBase, world: HuntWorld) -> void` |
| `Quickbar` | `src/hud/quickbar.gd` | HBoxContainer | barra de itens do desktop (§8.4). `const DOG_SLOT: StringName = &"dog_command"`; `bind(items: ItemBelt) -> void` (cria `Slot_<item_id>` para cada `items.get_usable_ids()`, na ordem; conecta `counts_changed`, `binoculars_changed`, `use_started`, `use_finished`); `set_dog_present(present: bool) -> void` (cria/remove `Slot_dog_command`, sempre o último); `set_dog_state(state: StringName) -> void` (espaço do cão apagado em `Ids.DS_RETREAT`); `flash(slot_id: StringName, on: bool) -> void` (pisca a borda até `flash(id, false)`; id inexistente = nada); `get_slot_ids() -> Array[StringName]` (ordem da tela) |
| `HintDirector` | `src/hud/hint_director.gd` | Node | lógica das dicas, **sem nenhum `Control`** (§8.4). `signal hint_shown(hint_id: StringName, text: String, slot_id: StringName)` (`slot_id` = `&""` na abertura); `signal hint_hidden(hint_id: StringName)`; `const OPENING: StringName = &"opening"`; `setup(player: PlayerBase, items: ItemBelt, world: HuntWorld) -> void` (lê `Profile.is_onboarding_active()` e `game.onboarding` uma vez; inativo = não conecta nada e `set_process(false)`); `is_active() -> bool`; `get_current_hint() -> StringName` (`&""` = nenhuma); `get_queue() -> Array[StringName]` (cópia, tests); `get_shown_this_hunt() -> Array[StringName]` (cópia, tests) |
| `HintBanner` | `src/hud/hint_banner.gd` | PanelContainer | faixa da dica (§8.4). `show_hint(text: String) -> void`, `hide_hint() -> void`, `is_showing() -> bool`, `get_text() -> String`. Não tem relógio: quem decide quando some é o `HintDirector` |
| `DogCard` | `src/hud/dog_card.gd` | HBoxContainer | cartão do cão do HUD (§8.4, 1.3, jogo 0.8.1); só vista, quem o alimenta é o `Hud`. `set_breed(dog_id: StringName) -> void` (retrato `ScenePaths.icon(dog_id)` e nome de `Data.get_dog(dog_id).name`; id vazio/desconhecido = cartão genérico "Cão" sem retrato), `set_state(state: StringName) -> void`, `set_health_pct(pct: float) -> void`, `set_touch(touch: bool) -> void`, `get_state_text() -> String`, `get_action_text() -> String`, `get_breed_text() -> String` (os três últimos para tests). Filhos: `Portrait`, `Info/Name`, `Info/State`, `Info/HealthBar`, `Info/Action` |
| `ObjectivesPanel` | `src/hud/objectives_panel.gd` | VBoxContainer | objetivos das primeiras caçadas (§8.4, jogo 0.8.2); só vista, quem a alimenta é o `Hud`. `enum State { PENDING, OK, DONE, FAIL }`; `const ROW_DOG/ROW_DRONE/ROW_KILLS/ROW_CROP: StringName` (`&"dog"`, `&"drone"`, `&"kills"`, `&"crop"`); `set_dog_present(present: bool) -> void`, `set_drone_present(present: bool) -> void` (a linha só existe com cão / drone); `set_kills(killed: int, total: int) -> void`; `set_crop_pct(pct: float) -> void`; `mark_dog_ordered() -> void`, `mark_drone_used() -> void`; `set_touch(touch: bool) -> void` ("(E)" vira "(botão Cão)"); para tests: `get_row_ids() -> Array[StringName]` (linhas visíveis, em ordem), `get_row_text(row_id: StringName) -> String`, `get_row_state(row_id: StringName) -> int` (um `State`), `get_kills_goal() -> int`, `get_crop_min_pct() -> float`. Filhos: `Row_dog`, `Row_drone`, `Row_kills`, `Row_crop` (cada um com `Mark` e `Text`). Lê `game.onboarding.objective_kills` e `objective_crop_min_pct` no `_init` (fallbacks 3 e 50.0) |
| `ControlsLegend` | `src/hud/controls_legend.gd` | VBoxContainer | legenda de teclas das primeiras caçadas, só teclado/mouse (§8.4, jogo 0.8.2); só vista. `set_items(item_ids: Array[StringName]) -> void` (uma linha por item usável, na ordem de `get_usable_ids()`), `set_dog_present(present: bool) -> void`, `set_open(open: bool) -> void`, `toggle() -> void`, `is_open() -> bool` (começa aberta); para tests: `get_row_ids() -> Array[StringName]`, `get_key_text(row_id: StringName) -> String`, `get_row_text(row_id: StringName) -> String`, `get_tab_text() -> String`. Ids de linha: `move`, `mouse_buttons`, `reload`, `sprint`, `crouch`, `weapons`, o id de cada item, `dog_command`, `help`. Filhos: `Tab` (visível só recolhida) e `Rows` (grade; cada linha é uma etiqueta de tecla `Key_<id>` e uma de texto `Text_<id>`) |
| `Compass` | `src/hud/compass.gd` | Control | faixa da bússola (§8.4; 1.4: graus, colaterais, rumo no centro). `update_state(origin: Vector3, yaw_rad: float, marks: Array[Dictionary]) -> void` (assinatura de antes; `marks` = `{pos: Vector3, kind: StringName}`, `kind` de `MapMarkers`; `&"ally"` também tem `color: Color` e `down: bool`); `var objective: Vector3`, `var objective_icon: Texture2D` (horda, como antes); `static func bearing_of(dx: float, dz: float) -> float` (como antes); 1.4: `static func heading_deg_of(yaw_rad: float) -> int` (= `posmod(roundi(rad_to_deg(-yaw_rad)), 360)`), `static func label_for(deg: int) -> String` (múltiplo de 45 → "N", "NE", "L", "SE", "S", "SO", "O", "NO"; outro múltiplo de 15 → o número, ex. "105"; demais → ""), `get_heading_deg() -> int`, `get_heading_text() -> String` (ex. "135°") |
| `Minimap` | `src/hud/minimap.gd` | Control | minimapa 180×180, centrado no caçador, norte para cima (§8.4). Membros de antes (`map_rect`, `crop_rects`, `dog_position`, `dog_target`, `marked`, `revealed`, `baits`, `objective`, `objective_icon`, `allies`, `ally_colors`, `ally_yaws`, `ally_down`, `center_color`, `update_player`, `is_in_view`); 1.4: `var map_texture: Texture2D = null` (imagem do mapa inteiro; `null` = fundo liso de antes), `get_map_src_rect() -> Rect2` (fatia da textura em texels) e `get_map_dst_rect() -> Rect2` (onde ela é desenhada, px do controle), recalculadas em `update_player` e quando `map_texture`/`map_rect` mudam; `Rect2()` sem textura ou fora do mapa |
| `MapMarkers` | `src/hud/map_markers.gd` | RefCounted (static) | 1.4: única fonte das formas e cores dos marcadores da bússola e do minimapa (tabela em §8.4). Constantes `KIND_*` (StringName), `COLOR_*`, `OUTLINE_PX`, `DRAW_ORDER: Array[StringName]`; `static func draw(ci: CanvasItem, kind: StringName, at: Vector2, color: Color, half_px: float) -> void` (desenha a forma do tipo, com contorno preto, centrada em `at`; `half_px` = meia-largura / raio); `static func color_of(kind: StringName) -> Color` (implementado em 0.8.3: a cor do tipo pela tabela de §8.4; `&"ally"` não tem cor própria, a cor é a do slot); anel `dog_target`: `RING_WIDTH_FRAC = 0.25` (largura = 0,25 × `half_px`) e `RING_OUTLINE_LESS_PX = 0.5` (contorno = largura − 0,5). `&"ally"` não passa por aqui (losango na bússola, seta no minimapa, como antes) |
| `WeaponPanel` | `src/hud/weapon_panel.gd` | VBoxContainer | 1.5, jogo 0.8.4: painel da arma (§8.4, "Painel da arma e barra de vida"); só vista, quem o alimenta é o `Hud`, que o põe dentro de um `HudPanel` (`Hud/Root/WeaponFrame`). `set_weapons(weapon_ids: Array[StringName]) -> void` (uma vez, no `bind`: cria `Row/Chip_<n>` para cada id, `n` = índice + 1, e carrega os retratos; chamar de novo refaz tudo; lista vazia = painel sem arma, sem fileira; lista não vazia ativa o índice 0 sozinha, como `set_active(0)`, implementado em 0.8.4), `set_active(index: int) -> void` (retrato e nome da arma `index`, chip realçado; fora da faixa = nada), `set_ammo(in_mag: int, reserve: int, infinite: bool, mag_size: int) -> void` (só reescreve texto quando algum valor muda), `set_reload(active: bool, progress: float) -> void` (`progress` 0–1), `set_touch(touch: bool) -> void` (esconde as teclas dos chips; 1.6: no toque, dois cartões de arma no lugar de nome, retrato, munição, recarga e fileira); para tests: `get_weapon_ids() -> Array[StringName]` (cópia), `get_active_index() -> int` (-1 sem arma), `get_name_text() -> String`, `get_mag_text() -> String`, `get_reserve_text() -> String`, `is_ammo_low() -> bool`, `get_chip_key_text(index: int) -> String` (`""` no toque, fora da faixa ou sem tecla), `get_portrait_path() -> String` (caminho da textura do retrato ativo: o PNG, o SVG de fallback ou `""`), `is_row_visible() -> bool`; 1.6 (HF7, toque): `set_card_width(width_px: float) -> void`, `set_weapon_ammo(index: int, in_mag: int, reserve: int, infinite: bool, mag_size: int) -> void` (munição da arma do bolso, para o cartão), `get_card_count() -> int`, `get_card_weapon_indices() -> Array[int]`, `is_cards_visible() -> bool`. Filhos: `Cards` (HBoxContainer, só no toque) com `Card_<n>` (classe interna `Card`, desenhada em `_draw`), `Name` (Label), `Main/Portrait` (TextureRect), `Main/Ammo/Mag`, `Main/Ammo/Reserve` (Labels), `ReloadBar` (ProgressBar), `Row` (HBoxContainer) com `Chip_<n>`, cada um com `Portrait` e `Key` |
| `HealthStrip` | `src/hud/health_strip.gd` | Control | 1.5, jogo 0.8.4: barra de vida larga (§8.4); só vista. `const HEIGHT_PX: float = 28.0`; `set_health(hp: float, max_hp: float) -> void` (barra = `hp / maxf(max_hp, 1) × 100`, cor pela fração, número `ceili(hp)`; texto só reescrito quando o inteiro muda), `set_vest(on: bool) -> void`, `set_touch(touch: bool) -> void` (largura 400 → a do `set_touch_width`, padrão 342 px; no toque o colete sai da barra e vira um chip à esquerda dela, 1.6), `set_touch_width(width_px: float) -> void`, `set_vest_reduction(fraction: float) -> void` (chip "35%" no toque; sem redução, "Colete"), `get_vest_text() -> String`, `get_chip_rect() -> Rect2`; para tests: `get_value_text() -> String`, `get_fill_pct() -> float` (0–100), `get_fill_color() -> Color`, `has_vest() -> bool`. Filhos: `Vest` (HBoxContainer com `Icon` e `Text`), `Bar` (ProgressBar, variação `HealthBar`), `Value` (Label). Comportamento (0.8.4): recém-criada mostra "1", barra cheia e verde (`_init` chama `set_health(1.0, 1.0)`) até o primeiro `set_health`; o `Hud.bind` a atualiza antes do primeiro quadro, então o jogador nunca vê esse "1" |
| `PauseOverlay` | `src/hud/pause_overlay.gd` (cena `.tscn`) | CanvasLayer | interna |
| `TouchControls` | `src/hud/touch/touch_controls.gd` (cena `.tscn`) | CanvasLayer | interna ao A. Públicos (1.3): `bind(player: Player)` (cria o botão Cura e o botão Acessórios, §8.4), `set_dog_present(present: bool) -> void`, `set_dog_state(state: StringName) -> void`, `flash_slot(slot_id: StringName, on: bool) -> void` (mesmos ids da `Quickbar`), `set_action_labels(on: bool) -> void` / `has_action_labels() -> bool` (jogo 0.8.2: com `true`, Tiro, Mira, Recarga e Agachar mostram o nome junto do círculo (acima dele perto da borda de baixo), como os botões de item e o do cão já mostram; o botão Pausa nunca; padrão `false`, quem liga é o `Hud`), `get_button_center(action_name: StringName) -> Vector2` / `get_button_radius(...)` (o argumento é o **id do botão**: a ação, ou `fire_left` para o segundo Tiro; valem para `use_*` e `dog_command`; `Vector2.INF` / 0 se o botão não existe); 1.6 (HF7, §8.4 "Layout de toque estilo PUBG"): `signal layout_changed()`, `set_weapon_card_rects(rects: Array[Rect2], actions: Array[StringName] = []) -> void`, `get_weapon_card_rects() -> Array[Rect2]`, `get_bottom_block() -> Dictionary` e `static compute_bottom_block(screen: Vector2, left_limit: float) -> Dictionary` (`{center_x, card_w, cura_x, acc_x}`), `get_probe_buttons() -> Dictionary` (`{id: Vector3(x, y, raio)}`), `get_accessory_current() -> StringName`, `get_accessory_ids() -> Array[StringName]`, `is_accessory_menu_open() -> bool` |
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
| `MapRoot` | `src/world/map_root.gd` | Node3D | raiz de toda cena de mapa (§8.5). 1.4: `build_minimap(cfg: Dictionary) -> void` (depois de `build_flora`; `cfg` = `Data.get_game().get("minimap", {})`; chama `MinimapBaker.bake`, guarda a `Image` e cria o `ImageTexture`), `get_minimap_texture() -> Texture2D` e `get_minimap_image() -> Image` (`null` antes de `build_minimap`) |
| `MinimapBaker` | `src/world/minimap_baker.gd` | RefCounted (static) | 1.4: `static func bake(map: MapRoot, cfg: Dictionary) -> Image` (§8.4 "Imagem do mapa"; exige o mapa montado até `build_flora`); `static func world_to_pixel(map_rect: Rect2, image_px: int, x: float, z: float) -> Vector2i` (coluna 0 = oeste/`map_rect.position.x`, linha 0 = norte/`map_rect.position.y`; fora do mapa = valor preso à borda) |
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
| `Dog` | `src/dogs/dog.gd` (cena `src/dogs/dog.tscn`) | Node3D | FSM do cão; `setup(p_breed_id: StringName, world: HuntWorld, spawn_position: Vector3, p_owner_slot: int = 0)`, `command()` público; `get_target_position() -> Vector3` (1.3, jogo 0.8.1: onde está o javali vivo que o cão persegue; `Vector3.INF` sem alvo vivo, isto é, em `follow`, `retreat` e `return`) |

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
- 1.4 (minimapa): `Heightmap.get_grid_data() -> PackedFloat32Array` (a própria grade, `resolution²` alturas, índice
  `j * resolution + i`; quem chama só lê); `Terrain.get_grid_mask() -> PackedColorArray` (`resolution²` máscaras r/g/b
  de `_mask_at` em cada vértice da grade, mesmo índice; preenchida em `_build_meshes` **antes** da troca por albedo do
  fallback, então vale com e sem o material de arte; vazia antes de `build`); `HuntController.get_minimap_texture()`
  (override de `HuntWorld`, devolve `_map.get_minimap_texture()` ou `null` sem mapa).

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

| `LoadoutPanel` | `src/ui/common/loadout_panel.gd` | VBoxContainer | painel de equipamento da Preparação, reaproveitado pelo lobby (`%WeaponSlot0`, `%WeaponSlot1`, `%DogOption`, `Item_<id>`; `ItemKey_<id>` e `%DogKeyLabel` existiram de 1.3 a 0.8.2 e **saem** em 1.4, §11; desde 0.8.3 o painel não cita tecla nenhuma, nem na frase do cão `_dog_hint` = "Na caçada, mande o cão: Pega! / Volta!", e não ouve `GameEvents.touch_mode_changed`) |

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
func host_select_mode(mode: StringName) -> bool   # 0.5.0: só anfitrião, só em LOBBY; &"contract" | &"horde" (docs/horda.md §9.1)
func get_selected_mode() -> StringName  # (&"contract") modo da sala; volta a &"contract" ao criar/entrar/sair
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
`player_count`, `map_id`, `contract_index` e `mode` (= `get_selected_mode()`); em horda, também
`map_id = Data.get_horde()["map_id"]` e `contract_index = 0`. O modo trafega num byte no fim de `L_LOBBY` e de
`L_START` (`NetCodec.MODES`); `roster_changed` também avisa mudança de modo.

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
- Orçamento (HD, LOD por `visibility_range`; malhas compartilhadas entre instâncias do mesmo tipo):
  - perto (≤ 25 m): ≤ 3 000 triângulos, ≤ 7 `MeshInstance3D` visíveis (corpo, cabeça, 4 pernas, rabo);
  - médio (25–60 m): ≤ 900 triângulos, ≤ 7 `MeshInstance3D` visíveis;
  - longe (> 60 m): ≤ 300 triângulos, ≤ 2 `MeshInstance3D` visíveis, sem pernas animadas;
  - as distâncias de LOD acompanham o zoom da câmera: multiplicadas por
    `k = max(tan(base_fov/2) / tan(fov_atual/2), 1)` (`base_fov` = `player.base_fov_deg`), para o javali
    visto na luneta manter o detalhe do tamanho em que aparece na tela; recalculadas só quando `k` muda > 3%;
  - ≤ 1 material por tipo (4 no total, compartilhados); `cast_shadow` ligado só no corpo;
  - montagem a frio ≤ 40 ms por tipo (desktop), ≈ 0 em cache (javalis nascem no meio da caçada).
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
- Orçamento (HD, mesmo padrão do javali §7.1: LOD por `visibility_range` esticado pelo zoom, malhas
  compartilhadas entre instâncias da mesma raça):
  - perto (≤ 20 m): ≤ 2 500 triângulos, ≤ 8 `MeshInstance3D` visíveis (corpo, cabeça, 4 pernas, rabo, orelhas);
  - médio (20–50 m): ≤ 800 triângulos, ≤ 8 `MeshInstance3D` visíveis;
  - longe (> 50 m): ≤ 250 triângulos, ≤ 2 `MeshInstance3D` visíveis, sem pernas animadas;
  - 1 material compartilhado (pelagem por cor de vértice + shader de pelo); `cast_shadow` só no corpo;
  - montagem a frio ≤ 40 ms por raça (desktop), ≈ 0 em cache.
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
  `position = (0,0,0)` a arma aparece na **posição de quadril** (canto inferior direito, origem do cano ≈
  (0.21, -0.08, -0.24)).
- FOV próprio da arma: o nó interno `Gun` é escalado em (1, 1, k), com k ≈ 0,55, em torno do olho. Isso equivale
  a FOV ≈ 46° só para a arma (o mundo segue em 75°). A raiz da view não é escalada. O z de `Muzzle`/`AdsAnchor`
  já vem comprimido; para a mira só x e y valem.
- Filhos obrigatórios:
  - `Muzzle` (`Marker3D`) na boca do cano, -Z para fora. Origem dos efeitos visuais; **o raio do tiro sai da câmera**, não do Muzzle.
  - `AdsAnchor` (`Marker3D`) no ponto da linha de mira (alça/massa ou centro da ocular). Na mira, o A move a
    raiz para `Vector3(-AdsAnchor.position.x, -AdsAnchor.position.y, 0.0)`.
- Inclui braços (manga cáqui, mãos de pele). Comprimento: .22 ≈ 0,95 m; 12 ≈ 1,0 m; rifles ≈ 1,1 m; luneta
  visível no .308/.30-06/.338.
- Orçamento: ≤ 12 000 triângulos com braços; ≤ 4 `MeshInstance3D`; ≤ 4 materiais; texturas procedurais
  ≤ 1024 px; `cast_shadow = OFF`; sem luz no flash.
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
| `farmhouse` | 12 × 6 × 8 | sede: alvenaria branca, telhado de telha, varanda (frente -Z) | 3000 |
| `barn` | 16 × 7 × 10 | galpão de madeira/zinco aberto na frente | 2400 |
| `water_tank` | 3 × 8 × 3 | caixa d'água em torre de madeira | 1000 |
| `fence_segment` | 4 × 1,3 × 0,15 | cerca de arame com 2 mourões, ao longo de X | 240 |
| `gate` | 4 × 1,4 × 0,2 | porteira de madeira | 400 |
| `corn_bait` | 1,0 × 0,3 × 1,0 | monte de milho em espiga (ceva) | 500 |
| `feed_trough` | 3 × 0,6 × 0,8 | cocho | 300 |

Por prop: ≤ 4 `MeshInstance3D`; materiais compartilhados entre props; montagem de todos os props ≤ 150 ms.
Mourões e esteios podem descer até 0,15 m abaixo de Y=0 (enterrados); as dimensões da tabela valem para a parte
acima do chão.

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
| `shrub` | arbusto do cerrado 1,0 alt. × 1,2 larg. | 150 | — |
| `cerrado_tree` | árvore retorcida 4,5 m, tronco r 0,2, copa 3 m | 600 | cilindro r 0,2 × 3 m |
| `ipe` | ipê-amarelo 7 m, tronco r 0,3, copa amarela 5 m | 750 | cilindro r 0,3 × 4 m |
| `buriti` | palmeira 12 m, tronco r 0,25, leque 6 m | 600 | cilindro r 0,25 × 6 m |
| `termite_mound` | cupinzeiro 1,2 alt. × 1,2 base, terra vermelha | 200 | cilindro r 0,6 × 1,2 m |
| `soy_patch` | moita de soja cobrindo 2×2 m, 0,6 m alt. | 24 | — |
| `soy_eaten` | soja revirada 2×2 m, 0,15 m alt. | 16 | — |
| `corn_patch` | milho cobrindo 2×2 m, 2,0 m alt. | 36 | — |
| `corn_eaten` | milho quebrado 2×2 m, 0,5 m alt. | 20 | — |

Grama e lavoura mantêm os triângulos: a melhora vem de shader (cor, vento, translucidez falsa, variação por
instância). Tudo em `MultiMesh`, sem alpha blend; alpha scissor só com justificativa (overdraw no celular).
`build_mesh` de todos os ids somado ≤ 200 ms.
A base pode descer até 0,15 m abaixo de Y=0 (cupinzeiro, raízes) para não flutuar em declive. Árvores: a soma de
triângulos de árvores do mapa inteiro fica ≤ 1,5 × a da 0.6.0 (≈ 70 k); o limite por id é teto, não meta.
Shader de vento (vértice) permitido em grama, arbusto, lavoura e copas. Fallback (B): `CylinderMesh`/
`BoxMesh`/`QuadMesh` coloridos nas dimensões da tabela.

### 7.6 Materiais de terreno e água
- `res://assets/materials/terrain.tres` — `ShaderMaterial` (shader em `assets/shaders/terrain.gdshader`).
  Entrada definida pelo B: **vertex color** `COLOR.r` = máscara de lavoura (terra arada/verde),
  `COLOR.g` = terra vermelha exposta (estradas, carreiros), `COLOR.b` = margem úmida; resto = capim do
  cerrado; `COLOR.a` = 1. `UV` = posição mundo XZ / 4,0 (repete a cada 4 m). Normais fornecidas.
- `res://assets/materials/water.tres` — `ShaderMaterial` para o açude; o B cria um `PlaneMesh` circular
  (`radius_m` do `WaterBody`) 0,3 m abaixo da borda.
- Orçamento de fragmento (o terreno cobre quase toda a tela; medido com o hook de diagnóstico da Etapa 0):
  terreno ≤ +1 ms sobre o shader de 0.6.0, ≤ 4 leituras de textura por pixel, sem triplanar; água ≤ +0,5 ms.
  Ambiente (§7.7): nenhum passe de tela cheia (sem `adjustment`, glow, SSAO, SSR); cor vem de shader e luz.
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
Toca os MP3 gravados em `res://assets/audio/sfx/<id>.mp3` (um por id; gerados com ElevenLabs a partir de
`assets/audio/sfx_prompts.json`; carregados no `_ready()`, ~35 ms em desktop, ~2,2 MB). Para cada id sem
arquivo, cai na síntese procedural (`AudioStreamWAV` 22050 Hz, mono, 16 bits; só roda se faltar arquivo;
≤ 400 ms de CPU em desktop). Os ids com loop (`amb_cerrado_loop`, `amb_wind_loop`) tocam com
`AudioStreamMP3.loop = true`. Exceção explícita à regra de arte 100% procedural: estes MP3 são os únicos
binários de áudio permitidos (`check_scripts` os isenta). Os barramentos `SFX`, `Ambience`, `UI` (filhos de `Master`) são declarados em
`res://default_bus_layout.tres`: na Web (modo "sample"), barramento criado em código com `AudioServer.add_bus`
não chega ao `Master` e o som some. O `Sfx` só os cria em código se faltarem (rede de segurança).
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
func play_music(id: StringName, volume_db: float = 0.0, fade_s: float = 1.0) -> void   # música em loop; idempotente
func stop_music(fade_s: float = 1.0) -> void
func is_music_playing(id: StringName = &"") -> bool    # true se há música pedida (qualquer uma, ou exatamente esse id)
```
**Música:** `res://assets/audio/music/<id>.mp3` (um arquivo por id de música, gerados com ElevenLabs;
instrumental, 90 s, termina em cordas suaves para repetir) toca num único `AudioStreamPlayer` (2D, não
posicional) dedicado, **fora do pool de efeitos**, no barramento `Ambience` (obedece `volume_ambience`; não há
barramento novo, e continua sem efeitos de barramento). A stream é carregada sob demanda no primeiro
`play_music` (não no `_ready`) e fica em cache, com `AudioStreamMP3.loop = true`. `play_music` é idempotente:
o mesmo id já tocando não reinicia, só ajusta o volume; outro id faz fade-out da atual (metade de `fade_s`) e
fade-in da nova (outra metade), via Tween. `stop_music` faz fade-out e para. Id sem arquivo: um `push_warning`
por id e nada muda (não há fallback sintético para música). `stop_all_loops()` não para a música. Na Web,
`play_music` chamado antes de `unlock_audio()` fica pendente e começa a tocar quando o áudio é desbloqueado.
`has_sound` não inclui ids de música. Os mp3 de `music/` também são isentos do `check_scripts`. Ids de
música: `music_menu` (todas as telas de menu até a caçada começar; quem decide onde toca é o `Router`, ver §6.6 e §9.1).
`has_sound` é verdadeiro apenas para os ids de efeito da tabela abaixo (não para música). Id desconhecido: um `push_warning` por id, sem som. Volumes iniciais e mudanças: lê `Profile.get_setting`
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
| Horda (A, HUD; 0.5.0) | `horde_wave_start`, `horde_wave_clear` (`docs/horda.md` §11.2) |
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
  `dog_paw`, `app_icon`, `barn` (0.5.0, horda); mapas `map_mato_grosso`, `map_pantanal`, `map_campanha_gaucha`,
  `map_triangulo_mineiro`; toque `btn_fire`, `btn_aim`, `btn_reload`, `btn_swap`, `btn_dog`,
  `btn_crouch`, `btn_pause`, `joystick_base`, `joystick_knob`. Fallback: sem ícone (texto) / círculos
  desenhados com `draw_circle`. `btn_item` saiu da lista em 1.3 (o botão Item genérico acabou; o arquivo pode
  ser apagado pelo art-director).
- **Ícones da barra de itens e dos botões de item** (1.3): **sem ids novos**. Itens usam `ScenePaths.icon(<item_id>)`
  (`medkit`, `corn_bait`, `scout_drone`, `binoculars`, os mesmos da loja) e o cão usa `btn_dog`. Requisito novo
  para esses 5 SVGs: legíveis a 40 px sobre `HudPanel` e sobre o círculo translúcido do toque (silhueta clara
  `#F4EFE6` com no máximo um acento de cor da paleta, sem detalhe abaixo de 6 px na escala 128). Continuam
  servindo à loja. Fallback: o nome curto (`short_name`, §9.3; "Cão" para o cão) escrito no espaço.
- **Fundos de menu** (0.7.3) `ScenePaths.MENU_BACKGROUND` = `res://assets/ui/main_menu_cerrado.png` (boot e
  menu principal) e `ScenePaths.PREPARATION_BACKGROUND` = `res://assets/ui/preparation_cerrado.png` (seleção de
  mapa e preparação). Pinturas 16:9 fornecidas pelo dono do jogo: única exceção à arte procedural. Importadas
  como WebP com perda. A UI as mostra via `UiKit.build_page(..., background_path)` / `UiKit.add_background()`:
  `TextureRect` em modo cobrir + véu escuro, `mouse_filter` ignorado. Fallback: o fundo chapado de sempre.
- **Retratos das armas** (0.7.4) `ScenePaths.weapon_art(weapon_id)` = `res://assets/ui/weapons/<weapon_id>.png`,
  um por arma de `data/weapons.json`. Renderizados dos modelos HD procedurais (`assets/models/weapons/showcase/`)
  pela ferramenta reproduzível `tools/render_weapon_art.gd` (dono: art-director); o PNG é saída dela, nunca
  editado à mão. Pedido do dono do jogo: segunda exceção à regra de nenhum raster. Formato: 1024×512 RGBA, fundo
  transparente, perfil direito (lado do ferrolho), coronha à esquerda e cano à direita, arma centrada ocupando ~92% da largura.
  Importação: WebP com perda (`lossy_quality` 0.82) com mipmaps; quem exibe usa
  `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` (o cano fino serrilha sem mipmap). Consumidos pelo cartão da loja
  (`ItemCard`), pela escolha de armas (`LoadoutPanel`) e, desde 1.5, pelo painel da arma do HUD (`WeaponPanel`, §8.4;
  orçamento em §13.1). Fallback: o ícone SVG `ScenePaths.icon(weapon_id)`. Nenhum asset novo na Fase 6.
- **Menu principal estilo pôster** (0.7.3). Do art-director, consumidos por `src/ui/main_menu/`:
  - Fonte de destaque `res://assets/ui/fonts/display_font.tres` (`ScenePaths.DISPLAY_FONT`): `FontVariation` da
    fonte padrão (negrito + itálico + condensado sintéticos). Nenhum arquivo de fonte externo.
  - Variações de tema: `MenuPrimaryButton` e `MenuListButton` (Button, caixa inclinada via `StyleBoxFlat.skew`,
    fonte de destaque, texto e ícone alinhados à esquerda), `MenuHeaderLabel` (Label, fonte de destaque âmbar),
    `BadgeLabel` (Label pequeno em pílula âmbar, ex. "BETA"), `TopBarPanel` (PanelContainer em pílula escura),
    `IconButton` (Button só de ícone, sem caixa no estado normal), `ProfileCardPanel` (PanelContainer).
  - Ícones novos (`ScenePaths.icon`): `play`, `shop`, `heart`, `settings`, `exit`, `profile`, `trophy`, `target`,
    `weight`, `coins`, `hunter_badge`.
  - Logo `res://assets/ui/game_logo.tscn` (`ScenePaths.GAME_LOGO`): raiz `Control` "GameLogo" com
    `custom_minimum_size` 600×300, `mouse_filter` ignorado, tudo dentro desse retângulo (texto real + SVG, sem
    raster). Fallback: `TitleLabel` com o nome do jogo.
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
- Orçamento: ≤ 5000 triângulos, ≤ 10 `MeshInstance3D`, materiais compartilhados entre instâncias (cor por
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

### 7.12 Estoque de milho do celeiro (horda) — `res://assets/models/props/barn_corn.tscn` (`ScenePaths.BARN_CORN`)
Raiz `Node3D` estendendo `CornStockVisualBase` (`res://assets/models/props/barn_corn.gd`), no referencial do prop
`barn`. API `setup(ring_radius_m)`, `set_stock_pct(pct)`, `set_under_attack(on)`, estágios por
`CornStockVisualBase.stage_for(pct)`; ≤ 1 800 tris, ≤ 8 `MeshInstance3D`. Fallback:
`CornStockVisualBase.create_fallback()`. Contrato completo: `docs/horda.md` §11.1.

---

## 8. Costuras entre pacotes

### 8.1 Montagem da caçada (B ↔ A)
`HuntController._ready()` (B), em etapas separadas por `await get_tree().process_frame`, com um
`CanvasLayer` `LoadingOverlay` (layer 30, "Preparando a caçada…") visível:
1. `request = Router.get_pending_request()`; se `null`, `HuntRequest.make_debug()`.
2. Carrega o mapa: `load(ScenePaths.map_scene(request.map_id)) as PackedScene` (cena do próprio B; sem
   fallback: se faltar, `push_error` e encerra com `ABANDONED`), instancia e `add_child` com nome `Map`. Gera terreno, água, props, flora, lavoura.
   1.4: entre a flora e a lavoura, uma etapa própria (um `_next_frame` antes e outro depois, `_lap("minimap", t)`):
   `_map.build_minimap(Data.get_game().get("minimap", {}))`. Roda em **todos** os papéis (solo, anfitrião e cliente:
   o cliente monta o mesmo mapa pela mesma cena e, com `sync_layout`, as mesmas árvores), antes da etapa do jogador,
   então `Hud.bind` já encontra a textura.
3. Ambiente: `AssetLoader.instantiate(ScenePaths.environment(map_id))` ou `MapEnvironmentBase.create_fallback()`;
   `apply_quality(qualidade)`. Qualidade = `Profile.get_setting("quality")`; `"auto"` → `Ids.Q_LOW` se
   `InputSetup.is_touch_mode()`, senão `Ids.Q_MEDIUM`. Aplica também `get_viewport().scaling_3d_scale =
   render_scale` (1,0 em todos: abaixo de 1 custa um passe fixo de escala na Web) e densidade de flora.
   Na Web, limita `window.devicePixelRatio` a `max_pixel_ratio` só durante a caçada (menus no DPR nativo),
   restaurando em `_exit_tree`.
4. Jogador: `AssetLoader.instantiate(ScenePaths.PLAYER)`; se `null` ou não `PlayerBase`, `FallbackPlayer.new()`.
   `add_child(player)`; `player.global_position` = `PlayerSpawn` com Y = `get_height`; `player.rotation.y` =
   yaw do `PlayerSpawn`; **depois** `player.setup(request, self)`.
5. Cão (se `request.dog_id != &""`), ao lado do jogador.
6. Agenda os grupos do contrato (`delay_s`). Emite `boar_counts_changed(0, total)`,
   `crop_health_changed(100.0)`, marca `is_world_ready() = true`, emite `world_ready` e
   `GameEvents.hunt_started(request)`. Esconde o `LoadingOverlay`.

**Pré-aquecimento de shaders (0.7.2).** Entre o aquecimento de malhas do javali (5b) e o passo 6, ainda com o
overlay visível, o controlador faz o navegador compilar os shaders aos poucos, para que nenhum quadro trave
tudo de uma vez e para que o overlay só suma com a cena pronta:
- revela o mundo por partes, uma por quadro (terreno, água, props, flora, lavoura), com a câmera do jogador ativa;
- mostra diante da câmera, um por quadro, um visual de cada tipo de javali e o cão (os materiais que aparecem
  depois do início), e então os libera;
- gira a câmera em `loading.warmup_yaw_steps` direções (um quadro cada) e volta à orientação do spawn;
- espera `loading.settle_frames` quadros seguidos abaixo de `loading.settle_frame_ms`, com teto de
  `loading.warmup_max_s`.
Depois do aquecimento, os loops de ambiente (`Sfx.play_loop`) começam um por quadro, ainda atrás do overlay (criar o stream custa ~100 ms no navegador). O jogador fica com `set_input_enabled(false)` durante toda a montagem e é liberado em `_announce_start` (offline) ou por `hunt_go` (rede). Implementação: `src/hunt/shader_warmup.gd` (`ShaderWarmup`) e `src/hunt/loading_progress.gd` (`LoadingProgress`); flag de linha de comando `--no-warmup` só para medição A/B.
Só então segue para o passo 6 (o spawner começa e o relógio da caçada corre depois do overlay sumir). Na rede,
o cliente faz o mesmo antes de avisar que carregou.

**Progresso.** O `LoadingOverlay` contém, abaixo do texto, o widget `res://assets/ui/loading_boar.tscn`
(art-director): raiz `Control` com script `LoadingBoar` e `func set_progress(value: float) -> void` (0–1).
Desenha só em 2D (`_draw`, sem 3D nem shader novo): um javali em silhueta correndo em loop, uma trilha de
progresso e a porcentagem inteira ("42%"). Anima sozinho em `_process`, sem depender do controlador.
O controlador calcula o progresso por pesos de etapa (`loading.step_weights` em `data/game.json`: chave =
nome da etapa do `_lap`, valor = peso relativo, na ordem da montagem; 1.4: `"minimap": 1` entre `"flora"` e `"crop"`;
etapa sem peso nos dados não move a barra, então o código não depende dessa chave; o pré-aquecimento reparte o seu peso pelos sub-passos), nunca
regride e chega a 1 imediatamente antes de esconder o overlay. Fallback: sem o widget, o `Label` mostra
"Preparando a caçada… 42%".

Orçamento: nenhuma etapa de CPU > 700 ms em celular intermediário (estimado como desktop × 5); o quadro do
overlay deve se atualizar ao menos a cada 1,5 s durante a montagem em CPU (as compilações de shader podem
travar um quadro por mais tempo, e por isso são repartidas).

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
- Do próprio pacote A (leitura direta, todo frame): vida, munição, arma, mira/zoom. Itens: por sinais do
  `ItemBelt` (§8.11), sem polling, exceto o preenchimento do uso em andamento (`get_busy_progress`, só enquanto
  `is_busy()`).
- Do mundo via `HuntWorld` (polling a 10 Hz, sem alocar por frame além de um `PackedVector3Array`):
  minimapa (`get_map_rect`, `get_crop_rects`, `get_dog_position`, `get_dog_target_position`, `get_alive_boar_ids` +
  `get_boar_position` **só** durante revelação do drone), bússola (`get_nearest_boar_position` quando o cão
  é `caramelo`, marcações do cão, `get_dog_position` e `get_dog_target_position`; 1.4: também talhões, cevas e
  javalis revelados, ver "Bússola, marcadores e minimapa" abaixo). Uma vez, no `bind`: `get_map_rect`,
  `get_crop_rects` e (1.4) `get_minimap_texture`.
- Por eventos (§5): contagem, lavoura, aviso de lavoura, abates, hitmarker, estado/vida do cão, mensagens.
- Ao `bind`, o HUD lê o estado inicial de `world` (`get_crop_health_pct`, `get_boars_killed`,
  `get_boars_total`, `has_dog`) para não depender da ordem dos sinais.

Layout do HUD (referência 1280×720, âncoras; respeita margem de 24 px nas laterais):
topo-esquerda contador de FPS (1.5; antes vida + colete, que desceram) + botão pausa (toque); topo-centro bússola (480×54 px desde 1.4: graus a cada
15°, cardeais e colaterais, rumo em graus no centro, marcadores da tabela abaixo) com barra "Lavoura 87%" abaixo e
aviso "Javalis na lavoura!" piscando; topo-direita minimapa 180×180 (1.4: sobre a imagem do mapa) e "Javalis 3/8"; centro mira; centro-baixo mensagem de abate ("Macho abatido — 132 kg ·
R$ 990 · Tiro limpo! · Um tiro só!", 3 s); baixo-direita o painel da arma (1.5: retrato, nome, munição grande
"5 | 30", barra de recarga e fileira de armas; no toque (1.6) são dois cartões embaixo no centro, ver "Layout de toque estilo PUBG"; a linha de item
"Kit de primeiros socorros x2 [Q] [F]" desse painel **saiu** em 1.3); baixo-centro, de baixo para cima, a barra de
vida larga (1.5, nos dois modos) e a barra de itens (só desktop) — ver "Painel da arma e barra de vida" abaixo; faixa
de dica (abaixo); anel de dano direcional em torno do centro (1,2 s); cartão do cão abaixo do minimapa (abaixo).
Toque (CanvasLayer 11, visível só em modo toque): joystick fixo à esquerda, arrastar fora dos botões para olhar
(por índice de toque), botões desenhados pelo `TouchControls` que apertam a ação: dois Tiros, Mira, Recarregar,
Agachar, Pausa, o botão do cão, Cura e Acessórios (1.6, "Layout de toque estilo PUBG" abaixo; o botão Troca saiu). Slider vertical de zoom quando mirando com `ads_zoom_max > ads_zoom_min`. Pausa (CanvasLayer 20,
`process_mode = ALWAYS`): "Retomar", "Configurações" (instancia `ScenePaths.SETTINGS_PANEL` se existir; sinal
`closed`), "Desistir da caçada".

**Espaços de item (1.3).** Um espaço por item de `ItemBelt.get_usable_ids()` (ativos e consumíveis do loadout,
na ordem de `InputSetup.ITEM_ACTIONS`: kit, ceva, drone, binóculo) e, por último, um espaço do cão
(id `&"dog_command"`) enquanto `world.has_dog()`. Passivos (colete, munição extra, mira térmica) nunca entram.
Sem nenhum espaço, a barra fica invisível. Estados de um espaço (iguais no desktop e no toque):

| Estado | Quando | Visual |
|---|---|---|
| normal | — | ícone (§7.9) + quantidade "x2" no canto inferior direito (só consumíveis) |
| esgotado | consumível com `get_count == 0` | ícone e fundo com alfa 0,35; quantidade "0" em `#D9452B`; continua apertável ("Acabou: …") |
| em uso | `use_started(id, s)` até `use_finished` | véu escuro (preto 55%) com setor circular claro crescendo de 0 a 1 por `get_busy_progress()`, sentido horário a partir do topo |
| ligado | binóculo com `is_binoculars_active()` | borda âmbar `#F2C12E` 3 px e ícone em âmbar |
| cão recuando | espaço do cão e estado `Ids.DS_RETREAT` | alfa 0,35 (não obedece "Pega!") |
| piscando | `flash(id, true)` até `flash(id, false)` | borda âmbar alternando a 2 Hz (constante própria `FLASH_HZ = 2.0`, mesmo valor de `Hud.BLINK_HZ`; não referencie `Hud` de dentro da `Quickbar`) |

**Barra de itens (desktop)** — `Quickbar` (`Hud/Root/Quickbar`), visível só com `InputSetup.is_touch_mode() ==
false`. O `Hud` a ancora no centro-baixo, 24 px acima da borda (`MARGIN_PX`) até 0.8.3; **desde 1.5** 50 px acima
da borda, logo acima da barra de vida (`QUICKBAR_BOTTOM_PX`, ver "Painel da arma e barra de vida"). Cada espaço `Slot_<id>` é um
`HudPanel` de 64×64 px, ícone 32 px no centro, quantidade 14 px, letra da tecla (`InputSetup.get_key_label(ação)`, 14 px) numa
etiqueta escura no canto superior esquerdo, separação 8 px. No máximo 4 espaços (`loadout.item_slots` = 3 itens
+ cão) = 280 px; a 1280×720 fica em x 500–780, y 632–696 até 0.8.3 e **y 606–670 desde 1.5**, sem tocar a mensagem de abate (0,72–0,84 da altura, termina em y 604,8) nem o painel da arma. Constantes de
desenho no próprio script (não são balanceamento). Desenho com `draw_*` em `_draw`; `queue_redraw` só quando
um sinal muda o estado e a cada frame apenas enquanto há espaço em uso ou piscando.

**Layout de toque estilo PUBG (HF7, contrato 1.6)** — só `InputSetup.is_touch_mode() == true`; o desktop não muda. Saem os
botões Troca e a fileira de botões de item de 1.3; o kit vai para o botão Cura e ceva, drone e binóculo para um botão
Acessórios. Posições em px do canvas virtual, medidas na foto do dono (celular 2400×1080, canvas 1532×720): "br" = a partir
do canto inferior direito, centros, tudo em constantes nomeadas de `TouchControls`.

| Peça | Posição (centro) | d | id (chave do probe) / ação |
|---|---|---|---|
| Tiro direito (principal) | br (245, 181) | 120 | `fire` / `fire` |
| Tiro esquerdo | 69 da esquerda, 355 de baixo | 100 | `fire_left` / `fire` |
| Joystick | (242, `A − 220`), raio 90 | | (era 190 / 160) |
| Mochila (futuro) | (77, `A − 59`) | | só reservada (constante comentada): nenhum botão nem desenho |
| Cura | bloco de baixo, 277 à esquerda do centro a 1532, y `A − 50` | 64 | `use_medkit` |
| Acessórios | bloco de baixo, 216 à direita do centro a 1532, y `A − 50` | 70 | ação do acessório atual (`use_corn_bait`, ...) |
| Recarregar | br (359, 47) | 64 | `reload` |
| Agachar | br (253, 53) | 72 | `crouch` |
| Mira | br (108, 342) | 76 | `aim` (alterna) |
| Cão | br (235, 346) (350 até 0.9.0; 4 px para não encostar no cartão do cão) | 76 | `dog_command`, só com cão |
| Interagir | br (410, 380) | 100 | `interact`, só com alvo ("Levantar" / "Pegar") |
| Pausa | (56, 56) | 64 | `pause` |

- **Dois Tiros.** `_centers` / `_radii` são indexados pelo **id do botão** (`fire`, `fire_left`, ...); os dois Tiros apertam a ação
  `fire`, com **contagem de dedos** por ação: soltar um não solta `fire` enquanto o outro dedo segue. Os dois giram a câmera
  ao arrastar (`LOOK_BUTTONS = [fire, fire_left, aim]`). `get_button_center(&"fire")` é o botão direito.
- **Bloco de baixo** (`TouchControls.compute_bottom_block(tela, direita_do_joystick)`), da esquerda para a direita: Cura (64),
  6, chip do colete (`HealthStrip.VEST_CHIP_W_PX` = 62), 6, cartão, 8, cartão, 10, Acessórios (70). Cartões de `CARD_W_MAX_PX = 167`
  encolhendo até `CARD_W_MIN_PX = 130` para o bloco caber entre a borda direita do joystick (x 332) e a borda esquerda do
  Recarregar menos 2 × `HIT_PADDING_PX`; centrado na tela quando cabe, senão empurrado para a esquerda. A 1532 ele cai nos números
  da foto; a 1280 de largura os cartões ficam com 157,5 px e o centro em x 631,5.
- **Cartões de arma** (`WeaponPanel` em modo toque, dentro do `WeaponFrame`, que no toque perde o fundo e fica exatamente sobre os
  cartões): retrato (36% da largura), nome (13 px, reticências) e munição "10 | 50"; o da arma na mão com borda âmbar e barra de
  recarga, o outro com `INACTIVE_ALPHA`. Ordem dos slots; **com uma arma só, um cartão só** (centrado); com mais de duas (horda) o da
  arma na mão e o **próximo do ciclo** (tocar nele faz o papel do antigo Troca). O `Hud` posiciona e passa os retângulos
  (fonte única) por `TouchControls.set_weapon_card_rects(rects, actions)`; `actions[i]` = `weapon_<n>` da arma do cartão, `&""` para
  a arma na mão (toque consumido, sem efeito). O `TouchControls` trata o toque por índice, depois dos botões. A munição de cada cartão
  vem dos nós `Weapon_<id>` do `Player` (`Hud._weapon_nodes`). `weapon_swap` continua no teclado.
- **Barra de vida e colete.** Largura = a dos dois cartões, 8 px da borda (`TOUCH_HEALTH_BOTTOM_PX`), cartões 6 px acima
  (`TOUCH_CARDS_GAP_PX`). O colete é um chip (ícone + "35%" = `damage_reduction` do item) colado à esquerda da barra, desenhado fora
  do retângulo da faixa; só visual.
- **Acessórios.** Itens de `InputSetup.ITEM_ACTIONS` sem o kit e que o caçador possui, nessa ordem. O padrão é o primeiro com contagem
  diferente de 0 (o binóculo não tem contagem: nunca zera); se o atual chega a 0 e há outro em estoque, troca sozinho (só nesse
  momento, escolher um zerado à mão o mantém). O botão principal mostra ícone e "x2" (binóculo aceso: anel âmbar) e **usa** o atual
  (aperta a ação dele). Com 2+ acessórios aparece a seta (aba de 44×24 colada no topo do botão, área de toque 56×44) que abre uma lista
  vertical **para cima** (linhas de 60 px, uma por acessório possuído, o atual com anel âmbar); tocar numa linha o torna o atual e fecha,
  **sem usar**; tocar na seta ou em qualquer outro ponto fecha (o toque segue para o que estiver ali). `flash_slot(id)`: o atual pisca o
  botão; outro pisca a seta (e a linha, com a lista aberta). O véu e o setor de "ocupado" valem para o botão principal e para o Cura.
- **Nomes do onboarding** (`set_action_labels`): botões a menos de 130 px da borda de baixo (Cura, Acessórios, Recarga, Agachar) e o
  Tiro direito desenham o nome **acima** do círculo (o de Acessórios, acima da seta); os demais, abaixo.
- **Slider de zoom** (aparece mirando com zoom ajustável): coluna da esquerda, x 32–116, acima do Tiro esquerdo: de y 130
  (a 720 de altura, y 130–299; a 960, y 136–539) até 16 px acima do círculo do Tiro esquerdo. O painel de objetivos continua em x ≥ 128.
- **Posições nas três telas** (centros; `A` = altura; o bloco muda só em x):

| Tela | Cartões (x) | Cura / Acessórios (x) | Chip do colete (x) | Recarregar / Agachar | Tiro dir. / Mira / Cão |
|---|---|---|---|---|---|
| 1532×720 | 595–937 (167) | 489 / 982 | 527–589 | (1173, 673) / (1279, 667) | (1287, 539) / (1424, 378) / (1297, 374) |
| 1280×720 | 470–793 (157,5) | 364 / 838 | 402–464 | (921, 673) / (1027, 667) | (1035, 539) / (1172, 378) / (1045, 374) |
| 1280×960 | 470–793 (157,5) | 364 / 838 | 402–464 | (921, 913) / (1027, 907) | (1035, 779) / (1172, 618) / (1045, 614) |

  Cartões em y `A − 97` … `A − 42`, barra de vida em y `A − 36` … `A − 8`; Cura e Acessórios em y `A − 50`; seta em y 593–637
  (a 720), linhas da lista em y 557, 491, 425 (3 acessórios). Nenhum círculo de toque (raio + `HIT_PADDING_PX`) encosta em outro,
  nos cartões, na barra, no cartão do cão, no minimapa ou na área ativa do joystick (centro `(242, A − 220)`, raio 153), conferido por
  `tests/unit/test_item_hud.gd` (3 telas) e por screenshots (HF7). Folgas conhecidas: com a lista aberta e o botão Interagir
  visível ao mesmo tempo, a linha de cima da lista (a 1280 de largura) e o Interagir ficam a 10,8 px (só o preenchimento do toque
  se sobrepõe, e a lista tem prioridade); o cartão do cão (não interativo) termina 11 px acima do círculo do botão Cão.

Gancho de QA da build Web (`?probe=1`, `Hud._publish_probe`), campos novos em 1.3: `items` (objeto
`{item_id: get_count}`, -1 para o binóculo), `busy_item` (String, `""` = nenhum), `binoculars` (bool),
`hint` (id da dica atual, `""` = nenhuma) e `touch_buttons` (objeto `{ação: [x, y, raio]}` em px do viewport,
para todo botão que existe agora, inclusive `use_*` e `dog_command`; 1.6: também `fire_left`, o botão Acessórios sob a ação do
acessório atual, `accessory_menu` (a seta, só com 2+ acessórios), `accessory_item_<id>` (linhas da lista, só aberta) e
`weapon_card_<n>` com raio = metade da altura do cartão; e os campos `weapon_slot`, `accessory`, `accessory_menu_open`). O
`mobile_probe.py` lê a posição dos botões daí, em vez de constantes. Na Web, `?hints=0` na URL (lido pelo `Hud` do mesmo jeito que
`?probe=1`) deixa o `HintDirector` inativo e, desde o jogo 0.8.2, também esconde os objetivos, a legenda e os nomes dos
botões de toque (a mesma chave): o `mobile_probe.py` abre com `?probe=1&hints=0` para que nada disso apareça no meio dos
diffs de pixel (a faixa da dica cruza a área do diff da mira). A lógica das dicas é testada
pelo sandbox `hud_hints` (§12), não pelo probe.

**Cartão do cão (1.3, jogo 0.8.1)** — `DogCard` (§6.8) dentro de um `HudPanel` (`Hud/Root/TopRight`), no lugar do
antigo "Cão: <estado>", abaixo da contagem de javalis; `visible` só enquanto `world.has_dog()` (o `Hud` liga no
polling de 10 Hz, como antes). Conteúdo, ao lado do retrato de 40 px (`assets/ui/icons/<dog_id>.svg`, `dog_id` do
`HuntRequest`): nome da raça (`data/dogs.json`, 16 px), estado em cor (18 px), barra de vida (a de antes: verde > 50%,
âmbar > 30%, vermelha abaixo) e a linha da próxima ação (16 px):

| Estado (`Ids.DS_*`) | Texto do estado | Cor do estado | Linha de ação |
|---|---|---|---|
| `follow` | "Seguindo" | neutra `#F4EFE6` | "E: Pega!" |
| `seek` | "Procurando" | neutra | "E: Volta!" |
| `point` / `bay` / `hold` | "Apontando" / "Acuando" / "Segurando" | destaque `#F2C12E` | "E: Volta!" |
| `return` | "Voltando" | neutra | "E: Volta!" |
| `retreat` | "Ferido" | perigo `#D9452B` | "Ferido: voltando" (sem tecla, alfa 0,55) |

A tecla vem de `InputSetup.get_key_label(&"dog_command")` (hoje "E"). Em modo toque (`InputSetup.is_touch_mode()`,
`touch_mode_changed`) "E:" vira "Botão Cão:" e a linha do nome da raça some, para o cartão terminar acima do botão
Cão do toque. Textos e cores são constantes de `dog_card.gd`.
**Alvo do cão** (só quando o estado não é `follow`): a cada polling o `Hud` lê `world.get_dog_target_position()`; se
finito, empurra a marca `{pos, kind: &"dog_target"}` na bússola (anel de raio 10 px na cor do cão `#F2C12E`, com
contorno preto; circunda o triângulo do javali quando ele está marcado; preso à borda a 60% de alfa quando fora da
faixa, como as outras marcas) e escreve `minimap.dog_target` (anel de raio 8 px na cor do cão; preso à borda do
minimapa fora da vista). Sem alvo, `Vector3.INF` e nada é desenhado.

**Dicas das primeiras caçadas (Fase 2)** — lógica em `HintDirector`, texto em `HintBanner`, piscar na
`Quickbar` / `TouchControls`. O `Hud` cria os três em `_ready`, chama `director.setup(player, items, world)` em
`bind` e liga: `hint_shown` → `banner.show_hint(text)` + `quickbar.flash(slot_id, true)` +
`touch.flash_slot(slot_id, true)`; `hint_hidden` → `banner.hide_hint()` + `flash(…, false)` nos dois. Só local:
nada de rede novo; em rede cada caçador vê as suas. Números em `game.onboarding` (§9.1).
- **Ativo** só se `Profile.is_onboarding_active()` (as `max_hunts` primeiras caçadas, por `stats.hunts_played`)
  no `setup`. Inativo: nenhuma conexão, nenhum processamento, nenhuma gravação.
- **Ids** (dica = espaço = aprendido): `medkit`, `corn_bait`, `scout_drone`, `dog_command`; mais `opening`, que
  não tem espaço nem aprendido. Uma dica com id aprendido (`Profile.is_hint_learned`) nunca entra na fila.
- **Avaliação** a cada `eval_interval_s` (acumulado por `delta` no `_process`; com a árvore pausada não corre),
  só com o caçador vivo, hunt não encerrado e sem espectador. Condições (todas precisam valer):

| Dica | Condição de disparo |
|---|---|
| `opening` | `opening_delay_s` depois de `hunt_started`, se existe pelo menos um espaço (o `HuntController` chama `player.setup` → `hud.bind` → `director.setup` antes de emitir `hunt_started`; nada é avaliado antes dele) |
| `medkit` | kit equipado com `get_count > 0`, `not items.is_busy()` e `vida / vida máx × 100 < medkit_health_below_pct` |
| `dog_command` | `world.has_dog()`, `world.get_dog_state() == Ids.DS_FOLLOW` e um javali **avistado** nesta avaliação |
| `scout_drone` | drone equipado com `get_count > 0`, `world.get_alive_boar_ids()` não vazio e nenhum javali avistado há `drone_no_sighting_s` (contados desde `hunt_started` ou desde o último avistamento) |
| `corn_bait` | ceva equipada com `get_count > 0` e o último `crop_under_attack` foi `true` |

  **Avistado** (critério barato, sem raio): algum id de `world.get_alive_boar_ids()` com
  `world.get_boar_position(id)` a até `boar_sighted_range_m` (distância XZ) e dentro de
  `boar_sighted_half_angle_deg` da direção do olhar no plano XZ (`player.get_look_direction()`). Não testa
  linha de visão: um javali atrás de uma árvore conta como avistado (aceito para uma dica). Uma alocação de
  `PackedInt32Array` por avaliação (4 por segundo com o valor padrão), nenhuma outra.
- **Fila:** uma dica por vez. Disparou e não está na fila, não é a atual e não foi mostrada nesta caçada → entra
  no fim; se a fila já tem `queue_max` ids, a nova é ignorada (volta a disparar na avaliação seguinte). Exceção:
  `medkit` entra na frente e, se passar do limite, sai o último da fila. A atual dura
  `hint_duration_s` (`opening_duration_s` para a abertura); depois `hint_gap_s` sem dica; então a próxima da
  fila é reavaliada e só aparece se a condição ainda vale (senão é descartada sem contar como mostrada). Cada id
  aparece no máximo uma vez por caçada.
- **Aprendido:** `item_used(id, …)` com `id` em {`medkit`, `corn_bait`, `scout_drone`} e qualquer
  `dog_command_executed(…)` chamam `Profile.mark_hint_learned(id)` (o cão: `&"dog_command"`), tirem a dica da fila
  e, se ela é a atual, a escondem na hora (`hint_hidden`). Vale mesmo sem a dica ter aparecido. A dica do kit já
  some em `ItemBelt.use_started(&"medkit", …)` (o `item_used` só vem ao fim do uso); o aprendido continua no
  `item_used`. Uso cancelado não traz a dica de volta naquela caçada.
- **Fim:** `hunt_ended`, `player_died` e `spectate_changed(slot >= 0)` escondem a atual e esvaziam a fila.
- **Texto** resolvido na hora de mostrar, conforme `InputSetup.is_touch_mode()`; `%s` = `get_key_label` da ação.
  Constantes em `hint_director.gd` (texto de jogador fica no código, como o resto do HUD):

| Dica | Teclado | Toque |
|---|---|---|
| `opening` | "Seus itens ficam na barra embaixo. Aperte a tecla de cada um para usar." | "Cada item tem o seu botão. Toque nele para usar." |
| `medkit` | "%s: Curar" | "Toque no kit para curar" |
| `dog_command` | "%s: Mandar o cão atacar" | "Toque em Cão para mandar o cão atacar" |
| `scout_drone` | "%s: Drone revela os javalis no minimapa" | "Toque no drone: ele revela os javalis no minimapa" |
| `corn_bait` | "%s: Ceva atrai os javalis para longe da lavoura" | "Toque na ceva para atrair os javalis para longe da lavoura" |
| `corn_bait` em horda (`world.is_horde()`) | "%s: Ceva atrai os javalis para longe do celeiro" | "Toque na ceva para atrair os javalis para longe do celeiro" |

- **`HintBanner`** (`Hud/Root/HintBanner`): `HudPanel` com `Label` `HudBigLabel` 24 px centralizado; o fundo
  encolhe até a largura do texto (mais o respiro do painel), centralizado na horizontal, no máximo 60% da largura
  da tela (texto maior quebra linha), verticais 0,30–0,37 da tela, `mouse_filter` ignorado, nos dois modos. Essa faixa fica
  livre durante o jogo vivo: abaixo da mensagem de contexto (0,22–0,30 até 0.8.2; 0,25–0,33 desde 0.8.3, ver
  "Mensagem de contexto" na Fase 5) e acima da mira; as faixas que também a
  usam (derrubado/espectador, 0,30–0,44) só aparecem com o caçador caído, quando as dicas já foram encerradas.
  Aparece e some com fade de 0,2 s (constante de desenho).

**Objetivos e legenda de teclas (Fase 4, jogo 0.8.2)** — `ObjectivesPanel` e `ControlsLegend` (§6.8), mais nomes
nos botões de toque. Só vistas: o `Hud` as cria em `_ready`, decide quando aparecem e as alimenta com o que já ouve.
- **Quando.** `Hud.bind` decide uma vez: `hints ligados (sem ?hints=0) e Profile.is_onboarding_active()` (as
  `onboarding.max_hunts` primeiras caçadas). Desligado: os dois ficam invisíveis e o `TouchControls` não mostra nomes.
  Ligado, o `Hud` aplica `_refresh_onboarding_ui()` toda vez que algo muda: tudo some com o caçador local caído
  (`player_died`), no espectador (`spectate_changed(slot >= 0)`) e no fim da caçada (`hunt_ended`). Na **horda** só a
  legenda aparece (os objetivos falam de lavoura e de total de javalis, que a horda não tem; o painel de ondas já
  dá o objetivo). No toque a legenda não existe e os objetivos e os nomes dos botões aparecem.
- **Objetivos** (`Hud/Root/Objectives`, coluna à esquerda: `margin_top` 132 px, abaixo da faixa da lavoura
  da bússola (desde 1.5 a vida saiu daí; o FPS fica acima, ver "Painel da arma e barra de vida"), e `margin_left` 24 px no teclado / 128 px no toque, à direita do slider de zoom; dentro de um `HudPanel`,
  fonte 17 px). Uma linha por objetivo, com marca redonda desenhada (anel = pendente, bolinha verde = mantendo,
  disco verde com visto = feito, disco vermelho com cruz = falhando) e texto:

| Linha | Existe quando | Texto (teclado / toque) | Feita quando |
|---|---|---|---|
| `dog` | `world.has_dog()` | "Mande o cão atacar (E)" / "…(botão Cão)" | `dog_command_executed(Ids.CMD_ATTACK)`; "Volta!" não conta |
| `drone` | `scout_drone` em `get_usable_ids()` | "Use o drone (V)" / "…(botão Drone)" | `item_used(Ids.I_SCOUT_DRONE, …)` |
| `kills` | sempre | "Abata N javalis (k/N)" ("javali" se N = 1) | `k >= N`; fica feita |
| `crop` | sempre | "Mantenha a lavoura acima de P%" | nunca "feita": verde enquanto `pct >= P`, vermelha (texto e marca) se `pct < P`, volta a verde se a lavoura subir |

  `N = min(onboarding.objective_kills, total de javalis da caçada)` (enquanto o total é desconhecido, 0, vale
  `objective_kills`); `k` é o `boar_counts_changed` do time, não só os abates do jogador. `P =
  onboarding.objective_crop_min_pct`. A tecla vem de `InputSetup.get_key_label`; o nome do botão do drone é o
  `short_name` do item. Linha concluída continua na tela. Entradas: `_on_counts`, `_on_crop_health`,
  `_on_dog_command`, `_on_item_used` do `Hud` (todos já existiam) e `_sync_dog_slots` para a linha do cão; nenhum
  sinal novo no `GameEvents`. Os estados valem por caçada (não usam `Profile.is_hint_learned`).
- **Legenda** (`Hud/Root/TopRight/LegendPanel`, na coluna do minimapa, abaixo do cartão do cão; só teclado/mouse).
  Começa **aberta**: grade de 2 pares tecla/texto por linha (fonte 16 px; a coluna da direita fica a 1280×720 entre
  y 354 e 497 com cão, acima do painel da arma). Linhas, em ordem: "WASD Mover", "Mouse Atirar / Mirar", "R
  Recarregar", "Shift Correr", "Ctrl Agachar", "1–5 Armas", uma por item usável da caçada (tecla da ação de
  `ITEM_ACTIONS`, texto = `short_name`: "Q Kit", "G Ceva", "V Drone", "B Binóculo"), "E Mandar o cão" (só com
  cão) e "H Recolher". **H** (`help`) recolhe a legenda para a aba "H: Ajuda" e reabre. Todo rótulo de tecla vem de
  `InputSetup.get_key_label`; só o rótulo "Mouse" é texto fixo (o mouse não tem ação de teclado). A legenda não tem
  relógio: continua aberta até o jogador apertar H.
- **Botões de toque.** Com `TouchControls.set_action_labels(true)` (o `Hud` liga junto com os objetivos), Tiro (os dois), Mira,
  Recarga e Agachar mostram o nome (16 px, 20 px abaixo da borda do círculo; acima dele perto da borda de baixo, 1.6); o Pausa nunca. Os botões de item e o do cão já mostram o nome sempre. Fora das primeiras caçadas
  ou com `?hints=0` os botões ficam como antes.
- **Sandbox** (`src/player/debug/player_sandbox.tscn`): `--onboarding` (ou `--hunts=N`) troca o perfil por um novo, com N
  caçadas jogadas (padrão 0), em `user://sandbox_save.json` (o save real não é tocado); sem isso o perfil do
  desenvolvedor costuma estar fora das primeiras caçadas e nada aparece. `--help_key` aperta H meio segundo depois
  de abrir (screenshot da legenda recolhida). Screenshots precisam de `--frames=600`: a janela do `screenshot.gd`
  roda sem limite de fps e 240 quadros passam antes dos 0,5 s.

**Bússola, marcadores e minimapa (Fase 5, contrato 1.4, jogo 0.8.3)** — só HUD, mais uma imagem que o mundo gera
uma vez. Nenhum sinal novo no `GameEvents`, nada novo na rede: cada peer gera a própria imagem (mesma cena, mesmas
árvores, ver "Determinismo") e os marcadores vêm do que o `Hud` já lê e ouve.

**Marcadores — tabela única em `MapMarkers`** (constantes; os dois scripts desenham por `MapMarkers.draw`):

| `kind` | Constante | O que é | Fonte no `Hud` (polling 10 Hz) | Forma | Cor | `half_px` bússola | `half_px` minimapa |
|---|---|---|---|---|---|---|---|
| `&"crop"` | `KIND_CROP` | centro de cada talhão | `get_crop_rects()` lido uma vez no `bind`; só no modo contrato; não aparece o talhão que contém o caçador da vista (XZ) | quadrado | `COLOR_CROP` `#3FAF5A` | 6 | 5 (só com textura e só quando o talhão inteiro está fora da vista, preso à moldura; dentro da vista o talhão aparece pelo contorno; sem textura, o preenchimento de antes e nenhum quadrado) |
| `&"bait"` | `KIND_BAIT` | ceva ativa | `_baits` (sinal `bait_placed`, expira por `duration_s`), como hoje | hexágono, vértice para cima | `COLOR_BAIT` `#3CC7B4` | 6 | 5 |
| `&"revealed"` | `KIND_REVEALED` | javali vivo revelado pelo drone | `get_alive_boar_ids` + `get_boar_position` só enquanto `_reveal_left > 0`, como hoje | círculo | `COLOR_REVEALED` `#FF8A65` | 4,5 | 3,5 |
| `&"boar"` | `KIND_BOAR` | javali marcado: `get_marked_boar_positions`, marcas de `dog_marked_boar` e o mais próximo quando o cão é `caramelo` | como hoje | triângulo, vértice para cima | `COLOR_BOAR` `#D9452B` | 7 | 6 |
| `&"dog_target"` | `KIND_DOG_TARGET` | alvo do cão (1.3) | como hoje | anel (só contorno) | `COLOR_DOG` `#F2C12E` | 10 | 8 |
| `&"dog"` | `KIND_DOG` | cão | como hoje | círculo | `COLOR_DOG` `#F2C12E` | 4,5 | 4,5 |
| `&"ally"` | `KIND_ALLY` | outro caçador | como hoje | bússola: losango (caído: vazado); minimapa: seta com o rumo (caído: X; fora da vista: seta na moldura) — desenho próprio de cada script, como hoje | cor do slot | 6 | seta 8 |

- Contorno preto `OUTLINE_PX = 1.5` em toda forma cheia; o anel mantém a largura e o contorno de antes (bússola 2,5 +
  2×2,0 px; minimapa 2,0 + 2×1,5 px). Implementado em 0.8.3 como fórmula: largura = `RING_WIDTH_FRAC` (0,25) ×
  `half_px`, contorno = largura − `RING_OUTLINE_LESS_PX` (0,5), o que dá esses valores com `half_px` 10 e 8. Cor de
  cada tipo por `MapMarkers.color_of(kind)`. Objetivo da horda (celeiro): sem mudança, desenhado antes de tudo pelo membro
  `objective` de cada script.
- **Ordem** `MapMarkers.DRAW_ORDER = [&"crop", &"bait", &"revealed", &"boar", &"dog_target", &"dog", &"ally"]`, de trás
  para a frente, igual nos dois. O `Hud._poll_world` monta `_marks` nessa ordem (hoje o javali do caramelo entra
  depois do cão: passa para o bloco `boar`); `_poll_allies` continua acrescentando os aliados por último. O `Minimap`
  desenha os seus membros na mesma ordem. Javali revelado e marcado ao mesmo tempo: o triângulo cobre o círculo.
- Fora da faixa / da vista: bússola prende à borda com alfa 0,6 (todas as marcas, inclusive talhão e ceva);
  minimapa prende à moldura (como `_dot` hoje).
- Mudanças visíveis em relação a 0.8.2: no minimapa o javali marcado deixa de ser círculo e vira triângulo, a ceva
  deixa de ser círculo `#E8B923` (quase a cor do cão) e vira hexágono `#3CC7B4`, e o revelado ganha cor própria.
- Alocação: `_marks` continua `Array[Dictionary]` reconstruído só no polling de 10 Hz (como desde 1.3; pior caso
  4 talhões + 4 cevas + 26 revelados + marcados + cão, alvo e 3 aliados < 70 dicionários por polling); por quadro,
  nada novo. `Hud` guarda `_crop_centers: PackedVector3Array` e `_crop_rects: Array[Rect2]`, montados no `bind`.

**Bússola (`Compass`, `custom_minimum_size = Vector2(480, 54)`, antes 44).** Constantes no script:
- Faixa de `BAND_H_PX = 34.0` com `COLOR_BG` (o de hoje); `VISIBLE_SPAN_DEG = 180.0` (15° = 40 px a 480 px).
- Traços na base da faixa, largura 2 px, `COLOR_TICK`: a cada `MINOR_TICK_STEP_DEG = 5.0` 4 px; a cada
  `TICK_STEP_DEG = 15.0` 7 px; a cada 45° 10 px.
- Rótulo acima de cada traço de 15° (`label_for(deg)`), centrado em y `LABEL_CENTER_Y_PX = 13.0`: cardeais N, L, S, O
  com `CARDINAL_FONT_PX = 20` e contorno preto 4 px; colaterais NE, SE, SO, NO com `INTERCARDINAL_FONT_PX = 16` e
  contorno 3 px; números (15, 30, 60, 75, 105…345) com `NUMBER_FONT_PX = 13`, sem contorno, `COLOR_TEXT` com alfa
  0,85. N em `COLOR_NORTH` `#D9452B`; os demais em `COLOR_TEXT`. Sempre em português: L e O, nunca E e W.
  Implementado em 0.8.3: rótulo (número, cardeal ou colateral) que não cabe inteiro na largura da faixa é pulado
  naquele quadro; o traço continua.
- Marcadores centrados em y = `BAND_H_PX − 9.0`, sobre os traços (como hoje).
- **Rumo no centro:** caixa `READOUT_W_PX = 56.0` × `READOUT_H_PX = 18.0` centrada em x, de y 36 a 54, fundo
  `COLOR_BG`, texto `get_heading_text()` ("0°" a "359°") com `READOUT_FONT_PX = 15`, `COLOR_TEXT`, centralizado. Um
  entalhe (triângulo de 10 px de base e 6 de altura, `COLOR_TEXT`) sobe da caixa até a base da faixa e substitui o
  ponteiro do topo de antes, que sai. Implementado em 0.8.3 (`NOTCH_BASE_PX = 10.0`, `NOTCH_H_PX = 6.0`): a base do
  entalhe fica no topo da caixa (y 36 = `BAND_H_PX + 2`) e o vértice em y 30, 4 px dentro da faixa. O centro da faixa continua em `rad_to_deg(-yaw)` (float), e
  `heading_deg_of(yaw)` arredonda o mesmo valor, então o número da caixa bate com o rótulo sob o entalhe.
- `queue_redraw` a cada quadro, como hoje (o rumo muda a cada quadro): por quadro ≤ 37 traços, ≤ 13 rótulos, os
  marcadores e um texto; nenhuma alocação além dos `PackedVector2Array` dos polígonos, como hoje.
- Layout: a coluna do topo-centro desce 10 px (faixa da lavoura e aviso "Javalis na lavoura!" incluídos). Nada mais
  se move, salvo a mensagem de contexto (abaixo).
- **Mensagem de contexto (implementado em 0.8.3):** para o aviso "Javalis na lavoura!", que desceu 10 px e termina
  perto de 0,27 da altura a 720 px, não cobri-la, o `Hud` a põe em `CONTEXT_TOP_FRAC = 0.25` (antes 0,22) com
  `CONTEXT_HEIGHT_FRAC = 0.08` (faixa 0,25–0,33, nó `ContextMessage`). Resíduo aceito: com a dica de abertura
  (`HintBanner`, 0,30–0,37), o aviso e o contexto na tela ao mesmo tempo, em 16:9, o texto do contexto encosta uns
  6 px no topo do painel da dica (raro e passageiro).

**Imagem do mapa (`MinimapBaker.bake`).** Uma vez por caçada, na CPU, no thread principal; sem `SubViewport`, sem
câmera, sem ler textura da GPU (funciona em `--headless`). Entradas: `map.heightmap.get_grid_data()`,
`map.terrain.get_grid_mask()`, `map.get_water_bodies()`, `map.get_crop_fields()`, os `PropSpawn` filhos de
`PropSpawns`, `map.get_flora_positions(id)` para cada id de `canopy`. Parâmetros em `game.minimap` (§9.1); o script
tem fallbacks idênticos como constantes `DEFAULT_*` (mesmo padrão de `CropManager.DEFAULT_SIGNAL_STEP_PCT`), então
funciona antes de os dados chegarem. Passos, nesta ordem:
1. **Base na grade.** Amostras `i, j` da grade múltiplas de `grid_stride` (1: 129×129 em Mato Grosso; 2: 65×65); a
   imagem base tem `n = (resolution − 1) / grid_stride + 1` px de lado. Cor de cada amostra: `colors.grass`, depois
   `lerp` para `colors.crop_soil` por `mask.r`, para `colors.road` por `mask.g` e para `colors.wet` por `mask.b` (a
   ordem de `Terrain._albedo_from_mask`, sem o ruído). Relevo: `dx = (h(i+1, j) − h(i−1, j)) / (2·spacing)`,
   `dz = (h(i, j+1) − h(i, j−1)) / (2·spacing)` (vizinhos presos à grade), `n = Vector3(−dx, 1, −dz).normalized()`,
   `L = Vector3(sin(az)·cos(alt), sin(alt), −cos(az)·cos(alt))` com `az = deg_to_rad(hillshade.azimuth_deg)` medido do
   norte no sentido horário (315 = luz de noroeste) e `alt = deg_to_rad(hillshade.altitude_deg)`;
   `shade = clampf(lerpf(1.0, n.dot(L) / sin(alt), hillshade.strength), hillshade.min, hillshade.max)` (chão plano =
   1,0); `tint = lerpf(height_tint.low, height_tint.high, clampf(h / amplitude_m, 0, 1))`; cor × `shade × tint`, canal
   preso a 0–1. Bytes RGB8 escritos num `PackedByteArray` dimensionado uma vez (sem `set_pixel` nesse laço);
   `Image.create_from_data(n, n, false, Image.FORMAT_RGB8, bytes)`.
2. **Escala:** `resize(image_px, image_px, Image.INTERPOLATE_BILINEAR)` (nativo).
3. **Camadas nítidas** na resolução final (`m_per_px = map_rect.size.x / image_px`; Mato Grosso com 256 px: 1 m/px),
   nesta ordem:
   - Água: cada `WaterBody`, pixels com centro a ≤ `radius_m` do centro em `colors.water`, e o anel de 1 px junto à
     borda (`radius_m − m_per_px` < d ≤ `radius_m`) em `colors.water_edge` (laço só na caixa do açude).
   - Talhões: `fill_rect` do retângulo de cada `CropField` em `colors.soy` ou `colors.corn` (pelo `crop`; outro valor
     usa `soy`); com `crop_row_px > 0`, linhas de 1 px em `colors.crop_row` a cada `crop_row_px` px, paralelas ao
     lado maior do talhão. Implementado em 0.8.3: a primeira linha fica 1 px dentro do talhão
     (`CROP_ROW_FIRST_OFFSET_PX = 1`), não na borda.
   - Construções e cercas: cada `PropSpawn` com `collision_size != Vector3.ZERO` → `fill_rect` da pegada XZ
     (`collision_size.x` × `collision_size.z`, trocados se `absf(sin(rotation.y)) > 0.7`; mínimo 1 px) em
     `prop_colors[prop_id]` ou `colors.prop_default`.
   - Copas: para cada id de `canopy` e cada posição de `get_flora_positions(id)`, disco de raio
     `maxf(radius_m / m_per_px, 1)` px em `canopy[id].color`, desenhado com `fill_rect` de 1 px de altura por linha.
   - A estrada não tem camada: vem na máscara `g` da base.
- **Cores exatas (implementado em 0.8.3):** cada cor `#RRGGBB` dos dados é convertida para `Color` somando meio
  degrau de byte a cada canal (`(round(c·255) + 0,5) / 255`), porque `Image.set_pixel`/`fill_rect` truncam `c·255`;
  assim o pixel das camadas nítidas sai exatamente no hex dos dados (o `minimap_selftest` compara por igualdade).
  Na base, o byte é `int(c·255 + 0,5)` (arredondado).
- **Orientação:** pixel (0, 0) = canto noroeste (x mínimo, z mínimo), x cresce para a direita (leste), z para baixo
  (sul). É o sentido de `Minimap._to_map`: nada é espelhado (`MinimapBaker.world_to_pixel` é a referência).
- **Determinismo:** mesma cena e mesmas colocações de flora ⇒ mesmos bytes. Os ids de `canopy` têm de ficar fora de
  `MapRoot.DENSITY_SCALED_IDS` (grama e arbusto mudam com a qualidade). Em rede (`sync_layout = true`) as árvores
  são as mesmas em qualquer qualidade, logo anfitrião e clientes geram a mesma imagem. No solo a imagem acompanha as
  árvores da própria sessão.
- **Orçamento e medição:** etapa `minimap` ≤ 60 ms em desktop nativo (linha `HUNT_TIMING minimap_ms` com
  `-- --hunt-timing`, ou `MINIMAP_BAKE_MS` do `minimap_selftest`) e ≤ 400 ms na Web medida por
  `python tests/web/load_ab.py <build> --throttle=4` (teto de qualquer etapa: 700 ms, §8.1). Memória: `Image` RGB8 de
  256² (192 KiB) guardada no `MapRoot` + a textura. Válvula se a Web passar: `grid_stride = 2` (4× menos amostras na
  base), só nos dados. Medido em 0.8.3 (desktop, headless): `MINIMAP_BAKE_MS` 9,8 e `HUNT_TIMING minimap_ms=10`.

**Minimapa (`Minimap`) sobre a imagem.** `Hud.bind`: `_minimap.map_texture = _world.get_minimap_texture()` logo
depois de `map_rect` (em todos os modos). `_init` põe `texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR`.
`_update_region() -> void` (privado) roda no fim de `update_player` (10 Hz) e nos setters de `map_texture` e
`map_rect` (os dois ganham setter; o valor e o tipo não mudam) e recalcula, sem alocar:
- `scale_px = minf(size.x, size.y) * 0.5 / VIEW_RADIUS_M` (o mesmo de `_to_map`);
- `view = Rect2(Vector2(_origin.x, _origin.z) − size * 0.5 / scale_px, size / scale_px)`; `vis = view.intersection(map_rect)`;
  sem área, sem textura ou com `minf(size.x, size.y) <= 0` (antes do layout) → `_src_rect = Rect2()` e
  `_dst_rect = Rect2()`;
- `_dst_rect = Rect2(_to_map(vis.position.x, vis.position.y), vis.size * scale_px)`;
- `_src_rect = Rect2((vis.position − map_rect.position) * k, vis.size * k)`, `k = map_texture.get_width() / map_rect.size.x`.

`_draw`, de trás para a frente: `COLOR_OUTSIDE` no controle todo → com textura e `_dst_rect` com área,
`draw_texture_rect_region(map_texture, _dst_rect, _src_rect, MAP_MODULATE)` (`MAP_MODULATE = Color(1, 1, 1, 0.92)`);
sem textura, o retângulo `COLOR_BG` de antes → talhões: com textura só o contorno
(`draw_rect(…, MapMarkers.COLOR_CROP, false, CROP_OUTLINE_PX)`, `CROP_OUTLINE_PX = 2.0`), e o talhão inteiro fora da
vista vira o quadrado `crop` preso à moldura (desenhado no passo `crop` da `DRAW_ORDER`, só com textura, como
implementado em 0.8.3); sem textura, o preenchimento `COLOR_CROP` de antes e nenhum quadrado → objetivo da horda →
marcadores na `DRAW_ORDER` → jogador → moldura. Um único `draw_texture_rect_region` por redesenho; continua norte
para cima e centrado em quem a câmera segue (espectador incluído). Na horda a imagem é a mesma (o mapa é o mesmo) e
não há contorno nem marca de talhão (`crop_rects` vazio, como hoje).
Exemplo exato para teste (mapa 256 m, textura 256 px, `size = Vector2(180, 180)` posto pelo teste, `VIEW_RADIUS_M = 90`,
valores depois de `update_player(origem, 0.0)`): origem (0, 0, 0) →
`get_map_src_rect() == Rect2(38, 38, 180, 180)` e `get_map_dst_rect() == Rect2(0, 0, 180, 180)`; origem (−118, 0, 0)
→ `Rect2(0, 38, 100, 180)` e `Rect2(80, 0, 100, 180)`.

**Sandbox** (`src/player/debug/sandbox_world.gd`, do A; argumentos novos depois de `--`):
- `--minimap_tex`: `get_minimap_texture()` devolve uma imagem de teste criada uma vez no `_ready`: 100×100 RGB8
  para o chão de 200 m (2 m/px), fundo `#8C8C50`, linha de 1 px `#6E6E3C` a cada 10 px, o talhão de
  `get_crop_rects()` em `#5E9A3A` e um quadrado 6×6 `#D9452B` nos pixels 0–5 (canto noroeste) para conferir a
  orientação. Sem o argumento, `null` (fundo liso, como antes).
- `--marked`: `get_marked_boar_positions()` devolve a posição do alvo 0.
- `--bait`: emite `GameEvents.bait_placed(Vector3(-30, 0, -40), 600.0)` depois do `setup` do jogador.
- `--reveal`: emite `GameEvents.item_used(Ids.I_SCOUT_DRONE, Vector3.ZERO)` depois do `setup` (o `Hud` liga a
  revelação por `reveal_s`). Cuidado (0.8.3): o `HintDirector` também ouve esse sinal e, no perfil real em
  onboarding, pode marcar a dica do drone como aprendida; para screenshots use junto `--hunts=N` (perfil descartável).
- `--crop_alert` (acrescentado em 0.8.3): depois do `setup` emite `GameEvents.crop_under_attack(true)` e
  `GameEvents.hud_message_requested(TEST_CONTEXT_TEXT, 600.0)`, com `TEST_CONTEXT_TEXT` = "Ceva colocada: os javalis
  vão para longe da lavoura" (aviso e mensagem de contexto juntos, para conferir a sobreposição).
- `--heading=<graus>`: `player.rotation.y = deg_to_rad(-graus)` depois do `setup` (ex. `--heading=135` → caixa
  "135°", SE sob o entalhe).
O mapa real é conferido pelo `src/world/debug/minimap_selftest.tscn` (B, headless, grava PNG) e por screenshot de
`src/hunt/hunt.tscn` (§14, HF5).

**Painel da arma e barra de vida (Fase 6, contrato 1.5, jogo 0.8.4)** — só HUD do Pacote A. Nada novo em
`GameEvents`, na rede, em `data/`, em `src/core/` ou no `TouchControls`. Duas vistas novas, `WeaponPanel` e
`HealthStrip` (§6.8), que não leem nada sozinhas: o `Hud` as alimenta com o que já lê do `Player` todo quadro.

*Ligações no `Hud`* (privados novos: `_weapon_panel: WeaponPanel`, `_weapon_frame: PanelContainer`,
`_health: HealthStrip`, `_last_weapon_slot: int = -1`):
- `_ready`: `_build_top_left()` passa a conter só o `_fps_counter`; `_build_bottom_right()` é substituído por
  `_build_weapon_panel()` (cria `_weapon_panel`, embrulha em `_panel(_weapon_panel, 8)` com nome `WeaponFrame`, filho
  direto de `_root`) e `_build_health()` (cria `_health`, nome `HealthStrip`, filho direto de `_root`).
- `bind`: `_weapon_panel.set_weapons(_player.get_weapon_ids())`, depois `_weapon_panel.set_active(_player.get_weapon_slot())`
  e `_last_weapon_slot = _player.get_weapon_slot()`; `_health.set_vest(items != null and items.damage_reduction > 0.0)`
  (a regra de hoje do `_vest_label`).
- `_update_weapon()` (todo quadro, como hoje): se `_player.get_weapon_slot() != _last_weapon_slot`, atualiza o cache e
  chama `set_active`; depois `set_ammo(w.ammo_in_mag, w.ammo_reserve, _player.has_infinite_reserve(),
  int(w.def.get("mag_size", 1)))` e `set_reload(w.is_reloading(), w.get_reload_progress())`. A regra de munição baixa
  e o texto da horda passam para o `WeaponPanel`.
- `_update_health()` (todo quadro, como hoje): `_health.set_health(_player.get_health(), _player.get_max_health())`.
- `_apply_touch_layout(is_touch)`: `_health.set_touch(is_touch)`, `_weapon_panel.set_touch(is_touch)` e
  `_place_weapon_frame(is_touch)` (âncoras abaixo).
- Saem do `Hud`: `_bottomright_margin`, `_health_bar`, `_health_label`, `_vest_label`, `_weapon_label`, `_ammo_label`,
  `_reload_bar`, `_last_ammo_text`, `TOUCH_BOTTOM_RIGHT_MARGIN_PX` e `HORDE_AMMO_TEXT`. Constantes novas do `Hud`:
  `HEALTH_BOTTOM_PX: float = 14.0`, `BOTTOM_STACK_GAP_PX: float = 8.0`, `QUICKBAR_BOTTOM_PX: float = HEALTH_BOTTOM_PX +
  HealthStrip.HEIGHT_PX + BOTTOM_STACK_GAP_PX` (= 50) e `TOUCH_WEAPON_BOTTOM_PX: float = 320.0`. `OBJECTIVES_TOP_PX`
  (132) e `TOUCH_OBJECTIVES_LEFT_PX` (128) ficam com o mesmo valor (muda só o comentário: abaixo da faixa da lavoura).
- **Visibilidade (regras de hoje, nada novo):** espectador (`spectate_changed(slot >= 0)`) esconde o `WeaponFrame` e a
  mira, como escondia `_bottomright_margin`; `NO_SLOT` os traz de volta. A barra de vida fica sempre visível, como a
  vida de hoje (no espectador e caído mostra a vida do caçador local). Queda sem espectador e fim da caçada não
  escondem nada. Horda: reserva "| ∞". A `Quickbar` continua se escondendo sozinha no espectador e no toque.

*`WeaponPanel`* (constantes de desenho no próprio script, como a `Quickbar`; não são balanceamento):

| Constante | Valor | Uso |
|---|---|---|
| `CONTENT_W_PX` | `224.0` | largura fixa do conteúdo (`custom_minimum_size.x`); o quadro `WeaponFrame` fica com 248 px de largura (margem do stylebox `HudPanel` do tema: 12 px nos lados, 8 px em cima e embaixo; o `margin_px` 8 de `_panel` só vale no fallback sem tema) e altura = conteúdo + 16 |
| `SEPARATION_PX` | `4` | entre as linhas do `VBoxContainer` e entre retrato e munição |
| `NAME_FONT_PX` | `15` | `Name`: `HudLabel`, `COLOR_TEXT`, alinhado à direita, uma linha, `OVERRUN_TRIM_ELLIPSIS` na largura do conteúdo |
| `PORTRAIT_SIZE_PX` | `Vector2(96, 48)` | `Main/Portrait` (2:1, como os retratos) |
| `MAG_FONT_PX` | `36` | `Main/Ammo/Mag`: pente, `HudBigLabel`; `COLOR_DANGER` com munição baixa, senão `COLOR_TEXT` |
| `RESERVE_FONT_PX` | `22` | `Main/Ammo/Reserve`: `RESERVE_FORMAT = "| %d"` ou `INFINITE_RESERVE_TEXT = "| ∞"`; sempre `COLOR_TEXT` |
| `LOW_AMMO_FRAC` | `0.25` | baixa = `in_mag <= 0` ou `float(in_mag) <= float(mag_size) * LOW_AMMO_FRAC` (a regra de hoje, `in_mag * 4 <= mag_size`) |
| `RELOAD_BAR_H_PX` | `6.0` | `ReloadBar`: largura do conteúdo, variação `CropBar`, `modulate` `COLOR_AMBER`; visível só recarregando, valor `progress × 100` |
| `CHIP_SIZE_PX` | `Vector2(40, 28)` | cada `Row/Chip_<n>` |
| `CHIP_ART_SIZE_PX` | `Vector2(36, 18)` | `Chip_<n>/Portrait`, em (2, 8) dentro do chip |
| `CHIP_GAP_PX` | `6` | separação da `Row`; 5 chips = 224 px, cabe exato |
| `CHIP_KEY_FONT_PX` | `12` | `Chip_<n>/Key` em (2, 0), fundo `COLOR_KEY_BG` como a letra da `Quickbar`; invisível no toque |
| `CHIP_BORDER_PX` | `2.0` | borda do chip ativo em `COLOR_AMBER` |
| `INACTIVE_ALPHA` | `0.5` | `modulate.a` dos chips não ativos (o ativo fica em 1,0) |
| cores | `COLOR_TEXT` `#F4EFE6`, `COLOR_AMBER` `#F2C12E`, `COLOR_DANGER` `#D9452B`, `COLOR_CHIP_BG` `Color(0, 0, 0, 0.35)`, `COLOR_KEY_BG` `Color(0, 0, 0, 0.7)` | |

- Ordem de cima para baixo: `Name`; `Main` (`HBoxContainer` alinhado à direita: `Portrait` e `Ammo`, este um
  `HBoxContainer` com `Mag` e `Reserve` alinhados pela base); `ReloadBar`; `Row` (`HBoxContainer`, alinhamento `END`,
  chips da esquerda para a direita na ordem 1…N). Altura aproximada do conteúdo: 75 px só com nome e linha principal,
  107 px com a fileira, 117 px com fileira e recarga.
- **Fileira:** visível só com 2 armas ou mais (com uma arma não há o que escolher). Um chip por arma carregada, nunca
  por slot vazio: na caçada normal até 2 (`loadout.weapon_slots`), na horda 5. Fundo arredondado (raio 4)
  `COLOR_CHIP_BG`, retrato pequeno, tecla `InputSetup.get_key_label(StringName("weapon_%d" % n))` no teclado/mouse
  (§4); o ativo com borda âmbar e alfa 1,0, os outros com `INACTIVE_ALPHA`. Só informativa: `mouse_filter` ignorado em
  tudo, nos dois modos.
- **Retratos:** `set_weapons` carrega uma vez, para cada id, `ScenePaths.weapon_art(id)` se `AssetLoader.exists`; senão
  `ScenePaths.icon(id)` se existir; senão nada (`AssetLoader.load_resource(...) as Texture2D`). Guarda as texturas num
  `Array[Texture2D]` de mesmo índice; `set_active` só troca referências (nenhum carregamento durante o jogo). A mesma
  textura serve ao retrato grande e ao chip. Todo `TextureRect` de retrato usa `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`,
  `EXPAND_IGNORE_SIZE` e `STRETCH_KEEP_ASPECT_CENTERED` (§7.9). Sem textura nenhuma o retrato fica vazio e o nome
  continua. Não usar `UiKit` (é de `src/ui/`, do game-systems; o HUD só depende de `ScenePaths`/`AssetLoader`).
- **Nome:** `String(Data.get_weapon(id).get("name", String(id)))`, lido em `set_weapons`. Os 5 nomes de `weapons.json`
  cabem em 224 px a 15 px salvo talvez "Rifle .30-06 semiautomático", que pode perder as últimas letras para a
  reticência (aceito).
- **Por quadro:** `set_ammo`/`set_active` só tocam `text`/cor quando o valor muda; `set_reload` muda `visible`/`value`.
  Nenhuma alocação por quadro (as strings só nascem quando a munição muda).

*`HealthStrip`* (constantes no script): `HEIGHT_PX = 28.0`, `WIDTH_PX = 400.0` (teclado), `TOUCH_WIDTH_PX = 300.0`,
`PAD_X_PX = 10.0`, `GAP_PX = 8.0`, `BAR_HEIGHT_PX = 14.0`, `VALUE_FONT_PX = 20`, `VALUE_MIN_W_PX = 40.0`,
`VEST_ICON_PX = 20.0`, `VEST_FONT_PX = 15`, `VEST_TEXT = "Colete"`, `WARN_FRAC = 0.5`, `DANGER_FRAC = 0.3`, cores
`COLOR_GOOD` `#3FAF5A`, `COLOR_WARN` `#F2C12E`, `COLOR_DANGER` `#D9452B`, `COLOR_TEXT`, `COLOR_PANEL` (fallback do fundo).
- `extends Control`, `custom_minimum_size = Vector2(WIDTH_PX ou TOUCH_WIDTH_PX, HEIGHT_PX)`, `mouse_filter` ignorado
  em tudo. Fundo: o stylebox `HudPanel` do tema (fallback `StyleBoxFlat` `COLOR_PANEL`, raio 8) desenhado em `_draw`
  no retângulo todo, como o `Quickbar.Slot`. Os filhos são posicionados pelo próprio script (sem `Container` que possa
  crescer a altura): da esquerda para a direita, com `PAD_X_PX` nas pontas e `GAP_PX` entre eles, centrados na
  vertical: `Vest` (só com colete: `Icon` `ScenePaths.icon(Ids.I_LEATHER_VEST)` de 20 px, sem ícone se faltar, e
  `Text` "Colete" 15 px `COLOR_WARN`), `Bar` (ocupa o resto da largura, 14 px de altura, variação `HealthBar`, cor por
  `modulate`) e `Value` (20 px, `COLOR_TEXT`, alinhado à direita, largura mínima 40 px). Reposiciona em `set_vest`,
  `set_touch` e `NOTIFICATION_RESIZED`.
- Cor da barra (a regra de hoje): fração `> WARN_FRAC` verde, `> DANGER_FRAC` âmbar, senão vermelha. Número
  `str(ceili(hp))` (vida 0 = "0").
- O aviso "Colete equipado" do painel antigo vira o par ícone + "Colete" dentro da faixa (mesma condição, mesma cor):
  cabe nos 300 px do toque sem criar uma segunda linha.

*Posições.* Coordenadas no **canvas virtual**, não em pixels da janela. O projeto usa base 1280×720, stretch
`canvas_items` e aspect `expand` (§2): mais largo que 16:9, a altura virtual fica 720 e a largura cresce (janela
1558×720 → canvas 1558×720); mais estreito, a largura virtual fica 1280 e a altura cresce (janela 960×720, iPad 4:3 →
canvas 1280×960, escala 0,75). Em paisagem a largura virtual **nunca é menor que 1280** e a altura nunca menor que 720.
Abaixo, `L` × `A` = tamanho do canvas virtual; os números absolutos são para 1280×720 salvo indicação (correção 1.5: a
versão anterior desta tabela tratava 960×720 como canvas de 960 px de largura, o que não acontece; o layout é o mesmo).

| Peça | Teclado/mouse | Toque |
|---|---|---|
| `HealthStrip` | âncoras x 0,5/0,5, y 1/1; `offset_left = offset_right = 0`, `grow_horizontal = BOTH`; `offset_bottom = −HEALTH_BOTTOM_PX` (−14), `offset_top = −(HEALTH_BOTTOM_PX + HEIGHT_PX)` (−42), `grow_vertical = BEGIN` → x `L/2 ± 200`, y `A − 42` … `A − 14` (1280×720: x 440–840, y 678–706) | 1.6 (HF7): âncoras à esquerda, posição absoluta: largura dos dois cartões, centrada no bloco de baixo, `offset_bottom = −TOUCH_HEALTH_BOTTOM_PX` (−8), y `A − 36` … `A − 8` (1280×720: x 470–793; 1532×720: x 595–937), com o chip do colete à esquerda (x 402–464 a 1280) |
| `Quickbar` | centro-baixo como antes, `offset_bottom = −QUICKBAR_BOTTOM_PX` (−50), `offset_top = −QUICKBAR_BOTTOM_PX − Quickbar.SLOT_SIZE_PX` (−114) → x 500–780, y 606–670 | invisível (como antes) |
| `WeaponFrame` | âncoras 1/1/1/1; `offset_left = offset_right = −MARGIN_PX`, `offset_top = offset_bottom = −MARGIN_PX`; `grow_horizontal = grow_vertical = BEGIN` → x `L − 272` … `L − 24` (248 px), base em `A − 24`, topo ≥ ≈ `A − 157` (5 armas recarregando; 1280×720: x 1008–1256, y ≈ 563–696) | 1.6 (HF7): sem fundo (`StyleBoxEmpty`), exatamente sobre os cartões: x = o da barra de vida, y `A − 97` … `A − 42` (`TOUCH_CARDS_GAP_PX` = 6 acima da barra); a coluna da esquerda e `TOUCH_WEAPON_BOTTOM_PX` saíram |
| `TopLeft` (só o FPS) | (24, 24) | (100, 24), à direita do botão Pausa (`TOUCH_TOPLEFT_MARGIN_PX`) |
| `Objectives` | (24, 132), sem mudança | (128, 132), sem mudança; com 4 linhas termina em y ≈ 256, acima do painel da arma em qualquer proporção |

Folgas conferidas (toque): as do layout de 1.5 (coluna da esquerda, fileira de itens) deixaram de valer com o HF7; as novas estão em "Layout de
toque estilo PUBG" (posições nas três telas). Teclado, sem mudança:
- Teclado a 1280×720: legenda das primeiras caçadas termina em y 497 com cão, acima do `WeaponFrame` (≥ 563); a barra de
  vida (x ≤ 840) e a `Quickbar` (x ≤ 780) não alcançam o painel (x ≥ 1008).

Resíduos aceitos (documentados para não virarem bug):
- Teclado 1280×720: uma mensagem de abate muito longa (> ≈ 750 px a 30 px, combinações "Tiro limpo! · Um tiro só!")
  pode encostar no canto superior esquerdo do `WeaponFrame` (y 541–581 da mensagem contra o topo ≈ 563 do painel).
- Toque (HF7): a faixa da dica (0,30–0,37) cruza o painel de objetivos (x 128–460, y 132–256) quando os dois aparecem, como já
  acontecia antes; as mensagens de abate (0,72–0,84, termina em y 604,8 a 720) ficam acima dos cartões (y ≥ 623).
- FPS ligado em rede com várias ligações (várias linhas) pode encostar no topo dos objetivos (setting de
  desenvolvedor + primeiras caçadas + rede).
- Horda, 1280×720 (anterior à Fase 6, sem tarefa): a faixa "Defenda o celeiro! A horda chega em N s" (`WaveBanner`,
  `HORDE_BANNER_TOP_FRAC = 0.18`, y ≈ 130–180) se sobrepõe ao painel do celeiro no topo.

*Sandbox* (`src/player/debug/sandbox_world.gd`, argumentos novos depois de `--`; os de antes continuam: `--weapons=a,b`,
`--horde`, `--items=…` com `leather_vest` para o colete, `--touch=on`, `--frames=600`). Aplicados depois do `setup`,
nesta ordem (implementado em 0.8.4):
- `--hp=<1-100>`: `player.debug_set_health(player.get_max_health() * N / 100.0)`.
- `--slot=<1-5>`: `player.bot_select_weapon(n − 1)` (chip realçado e retrato da arma `n`).
- `--mag=<n>`: `player.get_weapon().ammo_in_mag = n`, depois do `--slot`, então vale para a arma **na mão** (com
  `--slot=2 --mag=1` é o pente da espingarda; sem `--slot`, o da arma inicial); para ver o pente baixo em vermelho.

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
HUD (1.3, A): o espaço do cão na barra e o botão Cão do toque existem enquanto `has_dog()` (o `Hud` chama
`set_dog_present` no polling de 10 Hz) e repassam `dog_state_changed` a `set_dog_state` (apagado em `retreat`).
A tecla E (`dog_command`) aparece na barra; nada muda no B.
Cartão e alvo do cão (1.3, jogo 0.8.1): `Dog.get_target_position() -> Vector3` devolve onde está o javali que o cão
persegue (`Vector3.INF` sem alvo vivo). `HuntWorld.get_dog_target_position() -> Vector3` (virtual, `Vector3.INF`
por padrão) repassa o do cão local no `HuntController`; o `Hud` o usa na bússola e no minimapa (§8.4) enquanto o
estado do cão não é `follow`. **Limitação:** o cliente de rede só tem o `DogPuppet`, que não conhece o alvo, então
`get_dog_target_position()` devolve `Vector3.INF` e o anel não aparece nele (o cartão funciona igual: estado e vida
já viajam no snapshot). Replicar o alvo exigiria um campo novo no registro `DOG` do snapshot e fica fora desta fase.

**Em rede (F7; detalhe em `docs/multiplayer.md` §6.5).** O anfitrião simula um `Dog` por slot com cão
(`owner_slot`; raça do roster, `NetPeerInfo.dog_id`); o cliente só tem `DogPuppet` (réplica interpolada, seção
`DOG` do snapshot). O cão segue `get_hunter(owner_slot)`; dono morto: larga o javali, ignora comandos e fica
onde está; dono saiu: `leave()`. `command()` é público: só o cão do slot local conecta
`dog_command_requested` e emite `dog_state_changed`, `dog_health_changed` e `dog_command_executed`; o comando
do cliente vai por `C_DOG_CMD` e o "Pega!" aparece no HUD dele depois da ida e volta (`EV_DOG_CMD`), sem
predição local. Mensagens de HUD do cão: no barramento se o dono é local, senão `EV_MESSAGE` ao dono (códigos
3–5, `Dog.NET_MSG_*`/`Dog.MESSAGES`). Marcação: todos emitem `dog_marked_boar` (o anfitrião envia
`EV_DOG_MARK`). `Boar.apply_dog_damage` credita o abate ao dono do cão. `HuntController`: `get_dogs()`,
`get_dog_of(slot)`; `has_dog`/`get_dog_*` respondem pelo cão do jogador local. Limitação conhecida (balanceamento
de vários cães): se dois cães pegam o mesmo javali, o primeiro a soltar libera o javali para os dois.

### 8.11 Itens (A, com efeito no mundo pelo B)
| Item | Tipo | Efeito | Dono do efeito |
|---|---|---|---|
| `binoculars` | ativo | alterna visão 6x sem arma (B, `use_binoculars`); bloqueia tiro | A |
| `leather_vest` | passivo | reduz dano recebido | A |
| `medkit` | consumível | cura `heal` em `use_time_s` (sem atirar) | A; emite `item_used` |
| `corn_bait` | consumível | coloca ceva no chão à frente (2 m) | A emite `item_used`; B cria `Bait` + `bait_placed` |
| `extra_ammo` | passivo | reserva × `reserve_mult` | A |
| `thermal_scope` | passivo | ao mirar, javalis a ≤ `highlight_range_m` destacados | A emite `thermal_vision_changed`; B chama `set_highlight` |
| `scout_drone` | consumível | revela todos os javalis no minimapa por `reveal_s` | A (HUD), emite `item_used` |

Uso direto por id (1.3): o `Player`, em `_update_input`, para cada `(item_id, ação)` de
`InputSetup.ITEM_ACTIONS`, chama `_items.use_item(item_id)` em `Input.is_action_just_pressed(ação)` (vivo, input
aberto, sem bot). Mesmo caminho para teclado e toque (o botão do toque aperta a ação). Não há seleção.

API do `ItemBelt` (`src/player/item_belt.gd`, A):
```gdscript
signal counts_changed()
signal binoculars_changed(active: bool)
signal use_started(item_id: StringName, duration_s: float)   # só o kit (uso com tempo)
signal use_finished(item_id: StringName)                     # &"" = uso cancelado (cancel_use)
const MESSAGE_S: float = 2.0
const BAIT_DISTANCE_M: float = 2.0
var damage_reduction: float; var reserve_mult: float; var thermal_range_m: float; var drone_reveal_s: float
func setup(request: HuntRequest, player: PlayerBase, world: HuntWorld) -> void
func has_item(item_id: StringName) -> bool              # usável (ativo/consumível) equipado
func get_usable_ids() -> Array[StringName]              # ativos+consumíveis equipados, na ordem de InputSetup.ITEM_ACTIONS (não na do loadout)
func get_count(item_id: StringName) -> int              # consumível equipado: restante; ativo ou não equipado: -1
func use_item(item_id: StringName) -> bool              # único ponto de uso; true se começou/teve efeito
func cancel_use() -> void
func is_busy() -> bool
func get_busy_item() -> StringName                      # novo; &"" = nenhum
func get_busy_progress() -> float                       # 0..1
func is_binoculars_active() -> bool
func get_binoculars_zoom() -> float
func set_binoculars(active: bool) -> void
```
**Removidos:** `signal selection_changed()`, `next()`, `get_selected_id()`, `use_selected()` (e o estado
`_selected`). `use_item(id)` com item usável (`kind` `"active"`/`"consumable"`) que não veio na caçada: devolve
`false` e emite `hud_message_requested("Você não trouxe este item: <name>.", MESSAGE_S)` (`name` de
`data/equipment.json`); passivo, id vazio ou desconhecido: `false` sem mensagem. Demais regras de hoje mantidas (kit com vida cheia, "Acabou: …",
ocupado = `false`). `PlayerBase.bot_use_item(item_id)` continua chamando `use_item(item_id)` sem mudança, e o
`FallbackPlayer` não muda.

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
| Reconexão pelo mesmo código | — | 0.4.8: fora; sala trancada recusa `join`. **F8 (contrato pronto, implementação pendente): `docs/multiplayer.md` §4.7.** Cliente que cai em `IN_HUNT` tenta voltar por `net.rejoin_timeout_s` no mesmo slot (`want` + `tok`) e recebe `EV_FULL_SYNC`; o anfitrião guarda o slot por `net.peer_timeout_s` (passa a 45) e só `peer_left` com `clean` remove na hora (muda a linha "Cliente saiu ou caiu"). Os acréscimos ao contrato geral (`GameEvents.net_reconnect_changed` e `hunter_away_changed`, `HuntWorld.net_write_full_sync`, `NetCodec.HF_AWAY`, `Net.is_reconnecting`/`get_traffic`, chaves de `data/net.json`) estão em §4.7.9 de lá, valem desde já e entram neste documento (§5, §6.11, §9.9, Apêndice A) no fecho da F8 |
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

**Horda (0.5.0).** Tudo acima vale; os acréscimos (modo na sala, `EV_HORDE_WAVE`, repetição de onda no
`EV_FULL_SYNC`, `CropManager` em modo estoque, ondas no `BoarSpawner`, desvios H1–H7 da FSM, carcaças
escondidas) estão em `docs/horda.md` §5, §6 e §9.

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
| `music.*` | obj | dB, s | música de fundo: `track` (id do `Sfx`), `scenes` (caminhos `res://` das cenas em que toca: as telas de menu, exceto BOOT e RESULT; nunca HUNT), `volume_db`, `fade_in_s`, `fade_out_s`; lida só pelo Router |
| `onboarding.*` | obj | caçadas, s, %, m, graus, javalis | dicas, objetivos e legenda das primeiras caçadas (1.3, §8.4): lido por `Profile.is_onboarding_active` (`max_hunts`), pelo `HintDirector` (os gatilhos) e pelo `ObjectivesPanel` (`objective_kills`, `objective_crop_min_pct`) |
| `quality_presets.<low|medium|high>` | obj | — | B, ambiente |
| `minimap.*` | obj | px, graus, m, cor `#RRGGBB` | imagem do minimapa (1.4, §8.4): lido só pelo `MinimapBaker` (B) via `HuntController` |
| `loading.step_weights` | obj | — | pesos das etapas da montagem (§8.1); 1.4 ganha `"minimap": 1` entre `"flora"` e `"crop"` |
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
  "music": {
    "track": "music_menu",
    "scenes": [
      "res://src/ui/main_menu/main_menu.tscn", "res://src/ui/map_select/map_select.tscn",
      "res://src/ui/preparation/preparation.tscn", "res://src/ui/shop/shop.tscn",
      "res://src/ui/donate/donate.tscn", "res://src/ui/settings/settings.tscn",
      "res://src/ui/lobby/lobby.tscn"
    ],
    "volume_db": -6.0,
    "fade_in_s": 1.5,
    "fade_out_s": 1.0
  },
  "loadout": {"weapon_slots": 2, "item_slots": 3},
  "shop": {"max_consumable_owned": 9},
  "onboarding": {
    "max_hunts": 3,
    "eval_interval_s": 0.25,
    "opening_delay_s": 2.0,
    "opening_duration_s": 6.0,
    "hint_duration_s": 5.0,
    "hint_gap_s": 1.5,
    "queue_max": 3,
    "medkit_health_below_pct": 50.0,
    "boar_sighted_range_m": 60.0,
    "boar_sighted_half_angle_deg": 35.0,
    "drone_no_sighting_s": 60.0,
    "objective_kills": 3,
    "objective_crop_min_pct": 50.0
  },
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
    "low":    {"shadows": false, "shadow_distance_m": 0,  "flora_density": 0.5,  "render_scale": 1.0,  "max_pixel_ratio": 1.5, "view_distance_m": 160},
    "medium": {"shadows": true,  "shadow_distance_m": 30, "flora_density": 0.75, "render_scale": 1.0,  "max_pixel_ratio": 2.0, "view_distance_m": 220},
    "high":   {"shadows": true,  "shadow_distance_m": 45, "flora_density": 1.0,  "render_scale": 1.0,  "max_pixel_ratio": 2.0, "view_distance_m": 300}
  }
}
```
`coop.*` (B, A, `Net`): `boar_count_mult_by_players` é indexado por `player_count − 1`; os demais campos estão
em §8.12.

`onboarding.*` (1.3): `max_hunts` (int; dicas enquanto `stats.hunts_played < max_hunts`), `eval_interval_s`
(período de avaliação dos gatilhos), `opening_delay_s` (de `hunt_started` até a dica de abertura),
`opening_duration_s` / `hint_duration_s` (quanto cada dica fica na tela), `hint_gap_s` (intervalo sem dica entre
duas), `queue_max` (int; dicas esperando), `medkit_health_below_pct` (0–100, vida em % da máxima),
`boar_sighted_range_m` e `boar_sighted_half_angle_deg` (critério de "avistado", meio-ângulo do cone em graus),
`drone_no_sighting_s` (tempo sem avistamento para sugerir o drone). Jogo 0.8.2: `objective_kills` (int; alvo da linha
"Abata N javalis" do `ObjectivesPanel`, limitado ao total de javalis da caçada) e `objective_crop_min_pct` (0–100; piso
da linha "Mantenha a lavoura acima de P%"). Validação do `Data`: todos presentes, números > 0, `max_hunts`, `queue_max`
e `objective_kills` inteiros ≥ 1, `boar_sighted_half_angle_deg` ≤ 90, `medkit_health_below_pct` ≤ 100,
`objective_crop_min_pct` ≤ 100. O painel lê os dois com fallback 3 e 50.0 se faltarem.

`minimap.*` (1.4, jogo 0.8.3). Bloco novo no `data/game.json`, exatamente:
```json
"minimap": {
  "image_px": 256,
  "grid_stride": 1,
  "hillshade": {"azimuth_deg": 315.0, "altitude_deg": 40.0, "strength": 0.8, "min": 0.65, "max": 1.25},
  "height_tint": {"low": 0.92, "high": 1.06},
  "crop_row_px": 3,
  "colors": {
    "grass": "#BDA85C", "crop_soil": "#543D26", "road": "#9E4529", "wet": "#5C4D33",
    "water": "#33708C", "water_edge": "#24546B",
    "soy": "#5E9A3A", "corn": "#9DB04A", "crop_row": "#3F6E2A",
    "prop_default": "#9A9A9A"
  },
  "prop_colors": {
    "farmhouse": "#C9533D", "barn": "#8C5A3C", "water_tank": "#9AA0A6",
    "feed_trough": "#7A6248", "fence_segment": "#6E5238", "gate": "#6E5238"
  },
  "canopy": {
    "cerrado_tree": {"radius_m": 2.5, "color": "#3E5F2A"},
    "buriti": {"radius_m": 2.0, "color": "#4D7A34"},
    "ipe": {"radius_m": 2.5, "color": "#C9B42A"}
  }
}
```
Semântica em §8.4 ("Imagem do mapa"). As cores de base (`grass`, `crop_soil`, `road`, `wet`) são as do albedo de
fallback do `Terrain`; o art-director pode afiná-las editando só esses valores. Validação do `Data` (erros em
`get_load_errors()`): bloco presente; `image_px` inteiro em 64–512; `grid_stride` inteiro 1 ou 2; `hillshade.azimuth_deg`
em 0–360, `altitude_deg` em (0, 90], `strength` em 0–2, `0 < min ≤ max`; `height_tint.low` e `.high` > 0; `crop_row_px`
inteiro ≥ 0 (0 = sem linhas); toda chave de `colors` listada acima presente; todo valor de `colors`, `prop_colors` e
`canopy.*.color` String com `Color.html_is_valid`; `canopy.*.radius_m` > 0. Que os ids de `canopy` não são
de densidade variável é checado pelo `minimap_selftest` (B), não pelo `Data`.

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
| `short_name` | string | 1.3: nome curto (≤ 9 caracteres) sob o botão de item do toque e no fallback sem ícone; obrigatório em todo item |
| `kind` | `"passive"` \| `"active"` \| `"consumable"` | passivo/ativo: compra única; consumível: acumula |
| `price`, `currency` | int, string | preço unitário |
| `max_per_hunt` | int | consumíveis levados por caçada |
| `effect` | objeto | parâmetros específicos (unidades no nome do campo) |
```json
{
  "version": 1,
  "items": [
    {"id": "binoculars", "name": "Binóculo", "short_name": "Binóculo", "description": "Zoom de 6x para achar o bando sem espantá-lo.",
     "kind": "active", "price": 600, "currency": "money", "max_per_hunt": 1, "effect": {"zoom": 6.0}},
    {"id": "leather_vest", "name": "Colete de couro", "short_name": "Colete", "description": "Reduz o dano das presas em 35%.",
     "kind": "passive", "price": 2500, "currency": "money", "max_per_hunt": 1, "effect": {"damage_reduction": 0.35}},
    {"id": "medkit", "name": "Kit de primeiros socorros", "short_name": "Kit", "description": "Recupera 50 de vida. Consumível.",
     "kind": "consumable", "price": 300, "currency": "money", "max_per_hunt": 3, "effect": {"heal": 50.0, "use_time_s": 1.5}},
    {"id": "corn_bait", "name": "Ceva de milho", "short_name": "Ceva", "description": "Atrai javalis próximos por 45 s, longe da lavoura. Consumível.",
     "kind": "consumable", "price": 400, "currency": "money", "max_per_hunt": 2,
     "effect": {"duration_s": 45.0, "attract_radius_m": 80.0, "max_boars": 4}},
    {"id": "extra_ammo", "name": "Munição extra", "short_name": "Munição", "description": "Dobra a munição de reserva de todas as armas.",
     "kind": "passive", "price": 800, "currency": "money", "max_per_hunt": 1, "effect": {"reserve_mult": 2.0}},
    {"id": "thermal_scope", "name": "Mira térmica", "short_name": "Térmica", "description": "Ao mirar, destaca javalis até 150 m.",
     "kind": "passive", "price": 150, "currency": "gold", "max_per_hunt": 1, "effect": {"highlight_range_m": 150.0}},
    {"id": "scout_drone", "name": "Drone batedor", "short_name": "Drone", "description": "Revela todos os javalis no minimapa por 10 s. Consumível.",
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
  "native_origin": "https://italocassio.github.io",
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
  "load_timeout_s": 45.0,
  "host_stall_warn_s": 2.5,
  "host_timeout_s": 20.0,
  "peer_absent_s": 3.0,
  "peer_timeout_s": 30.0,
  "hit_claim_tolerance_m": 12.0,
  "name_max_chars": 12
}
```
`server_url` é a produção (`wss://javali-salas.acpw01.workers.dev/ws`, já no lugar do marcador `SUBDOMINIO`);
`dev_server_url` vale no binário do editor (testes e desenvolvimento) e em página servida de `localhost`;
build nativo exportado (APK, desktop) usa `server_url`. `native_origin` é o `Origin` que o cliente nativo envia
no handshake, só para `server_url` (o navegador envia o seu; sem `Origin` a produção responde 403). `relay_hz` é a taxa de envio de um enlace
enquanto está em relay (uma mensagem por tick por direção). Só em página servida de `localhost`/`127.0.0.1`
valem as sobreposições por URL para teste: `?server=ws://127.0.0.1:PORT/ws`, `?relay_only=1` (não tenta
WebRTC), `?drop_ice=1` (não envia candidatos: força o estouro de `ice_timeout_s`). Em nativo: `-- --server=…`.
Dono: game-systems; leitor: `Net` (e `HuntHostSync`/`HuntReplica` para `hit_claim_tolerance_m` e as demoras
de interpolação). Protocolo e limites do servidor: `docs/multiplayer.md` §4 e §5.

### 9.10 `data/horde.json` (0.5.0)
Modo Horda Javali: mapa e prop do objetivo, intervalos, dreno do estoque (`barn_drain_mult`, no lugar de
`contract.crop_drain_mult`), anel de comer, velocidade da corrida ao celeiro, teto de carcaças, multiplicador de
javalis por jogador, prêmio de abate (`kill_reward_mult`), bônus de vitória e as `waves` (cada uma com `groups`
no formato de grupo da §9.6). Esquema, regras de validação (inclusive o teto de 255 javalis por partida) e
seed: `docs/horda.md` §3. Dono: game-systems; leitores: B (`HuntController`, `HordeDirector`, `Boar`), systems
(`Profile.horde_*`, lobby, resultado), `Net` (`map_id`).

### 9.11 `data/upgrades.json` e acréscimos de 1.7 (F1 em 0.9.5; F2–F4 pendentes)
Melhorias compradas com dinheiro, um nível por vez: `backpack` (F1; `bonus_item_slots` por nível) e `knife` (F4; `damage`
por nível e `stats` do golpe). Arquivo novo em `Data.FILES` (`"upgrades"`), coberto pelo `include_filter="data/*.json"`.
Mesmo ciclo: `data/game.json` ganha o bloco `stamina` (F2) e `loadout.item_slots` passa a ser o número de espaços da
mochila nível 1; `data/equipment.json` ganha `energy_drink` depois de `medkit` (F3). Esquema, seed e validação:
`docs/plano_faca_mochila_folego.md` §2.2. Dono: game-systems; leitores: `Profile`, loja, Preparação, A (`Player`), B (rede da faca).

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
  "onboarding": {"learned": []},
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
    "battery_saver": "auto",
```
`best_crop_pct[i] = -1` = nunca vencido; `is_contract_completed` = `>= 0`. `items` guarda quantidade de
consumíveis e `1` para passivos/ativos possuídos. Settings: `mouse_sensitivity`/`touch_sensitivity` 0,1–3,0
(multiplicam `player.mouse_deg_per_px`/`touch_deg_per_px`); volumes 0–1; `quality` ∈ `auto|low|medium|high`;
`touch_controls` ∈ `auto|on|off`; `battery_saver` ∈ `auto|on|off` (`auto` = ligado em modo toque; ligado fixa
`Engine.max_fps = game.json power.battery_saver_fps`, desligado = 0). Quem aplica é `Profile` via `PowerManager`
(`src/systems/power_manager.gd`): no boot, em `settings_changed` e em `touch_mode_changed`. Só na Web, os menus
limitam `devicePixelRatio` a `power.menu_max_pixel_ratio` pelo mesmo `window.__huntMaxDpr` da caçada (que lê o valor
anterior e o restaura ao sair); `player_name` String (até `net.name_max_chars`, sem caracteres de controle;
vazio aparece como "Caçador N", N = slot + 1). A versão do save continua 2: save antigo ganha
`player_name = ""` pelo `sanitize`. Nada de sala, código ou resultado pendente é gravado.

`onboarding.learned` (1.3): lista de ids de dica já aprendidos (`Profile.mark_hint_learned`, §6.3), sem
repetição. Migração **pelo `sanitize`, sem subir a versão** (mesma regra do `player_name`): bloco ausente ou com
tipo errado → `{"learned": []}`; na lista, só ficam Strings que são id de equipamento `active`/`consumable` ou
`"dog_command"`, sem duplicatas, na ordem em que estavam. Não há o que inferir de um save antigo (quem já tem 3
caçadas não vê dicas de qualquer forma), por isso não há passo `2 → 3`. Escrita: junto com qualquer `save()`;
`mark_hint_learned` sozinho não grava (§6.3).

`upgrades` (1.7, F1, jogo 0.9.5): bloco de topo `{"backpack": 1, "knife": 1}` (nível de cada melhoria de
`Data.get_upgrade_ids()`). Migração **pelo `sanitize`, sem subir a versão**: ausente ou inválido → nível 1; valor preso em
1..máximo; ids fora dos dados descartados; o limite de `loadout.items` passa a ser `loadout.item_slots` + bônus da mochila
sanitizada. Save de hoje abre com mochila nível 1 (3 espaços, como antes). Detalhe: `docs/plano_faca_mochila_folego.md` §2.4.

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
| `PREPARATION` | `src/ui/preparation/preparation.tscn` | systems | `Contract_<index>` (0-based; trancado = desabilitado), `%WeaponSlot0`, `%WeaponSlot1`, `%DogOption` (OptionButton), `Item_<id>` (CheckButton; sem etiqueta de tecla desde 1.4, abaixo), `%StartHuntButton` → `Router.start_hunt(Profile.build_hunt_request(...))`; `%ShopButton`; `%BackButton` → `MAP_SELECT` |
| `HUNT` | `src/hunt/hunt.tscn` | B | — |
| `RESULT` | `src/ui/result/result.tscn` | systems | lê `Router.last_result`: resultado, lista de abates (tipo, kg, R$), bônus, total, lavoura %. `%ContinueButton` → `SHOP` (em sala: `LOBBY`); `%RetryButton` → `PREPARATION`; `%MenuButton` → `MAIN_MENU` |
| `SHOP` | `src/ui/shop/shop.tscn` | systems | abas Armas/Equipamentos/Cães; `Buy_<id>`; `%NextHuntButton` → `PREPARATION`; `%BackButton` → `MAIN_MENU` |
| `DONATE` | `src/ui/donate/donate.tscn` | systems | `Package_<id>`, `%PixCodeText` (LineEdit só leitura), `%CopyButton` (`DisplayServer.clipboard_set`), `%RedeemCodeEdit`, `%RedeemButton`, `%RedeemStatusLabel`, `%BackButton` → `MAIN_MENU` |
| `SETTINGS` | `src/ui/settings/settings.tscn` | systems | contém `settings_panel.tscn`; `%BackButton` → `MAIN_MENU` |
| `SETTINGS_PANEL` | `src/ui/settings/settings_panel.tscn` | systems | raiz `Control` com `signal closed`; `%CloseButton` emite `closed`; reutilizado na pausa |
| `LOBBY` | `src/ui/lobby/lobby.tscn` | systems | estados Entrada / Conectando / Sala (abaixo); sai por `%BackButton` → `MAIN_MENU` e `%LeaveButton` (ambos chamam `Net.leave_room()`) |

Música: `music_menu` toca em todas as telas de menu (`MAIN_MENU`, `MAP_SELECT`, `PREPARATION`, `SHOP`,
`DONATE`, `SETTINGS`, `LOBBY`), continua sem reiniciar ao ir de uma para outra e para com fade-out em `HUNT`.
`BOOT` ainda não toca nada e `RESULT` fica sem música para a vinheta de vitória/derrota ser ouvida. A regra
vive no `Router.goto` (§6.6) e na configuração `game.music` (§9.1); as telas não tocam música.

`LOBBY` (nós; `%` = nome único):

| Estado do lobby | Nós |
|---|---|
| Entrada | `%NameEdit` (grava `player_name`), `%CreateRoomButton`, `%CodeEdit` (5 caracteres, maiúsculas), `%JoinButton`, `%BackButton` → `MAIN_MENU`; `%StatusLabel` mostra o erro |
| Conectando | `%StatusLabel`, `%CancelButton` (sempre habilitado) |
| Sala | `%MessageLabel`, `%RoomCodeLabel`, `%RoomLinkLabel`, `%CopyLinkButton` (Web: copia `Net.get_room_link()` e mostra "Link copiado!" por `Lobby.COPIED_FEEDBACK_S`; fora do Web copia o código), `Slot_N/{Swatch, Info/Name, Info/Detail, Role}` (Detail = arma e "direto"/"via servidor"), `%MapOption` e `Contract_<index>` (só anfitrião; só contratos desbloqueados dele), `%ContractLabel`, `%HintLabel`, `LoadoutPanel` (`%WeaponSlot0`, `%WeaponSlot1`, `%DogOption`, `Item_<id>`), `%ReadyButton` (cliente), `%StartButton` (anfitrião; habilita só com todos os clientes prontos), `%ShopButton`, `%LeaveButton` |

Horda (0.5.0): `%ModeLabel`, `%ModeContractButton`, `%ModeHordeButton`, `%HordeInfoLabel` e, no `LoadoutPanel`,
`%WeaponsLockedLabel` + `set_weapons_locked(text)`; resultado de horda com títulos e linhas próprios. Nós,
regras e textos: `docs/horda.md` §10.2 e §10.3.

`%BackButton` só na tela de entrada. `Lobby` tem `class_name`. O `Net` escolhe o contrato padrão; o lobby só
chama `Net.host_select_contract` quando o anfitrião escolhe, e `_begin_hunt` usa `Net.get_hunt_seed()`. O
cliente aperta `%ReadyButton` (o pronto automático da F2 acabou). Cão liberado desde a F7: o detalhe de cada
jogador mostra "Cão: <nome>" (`Lobby.dog_label(id)`) e `request.dog_id = Profile.get_loadout_dog()` vale também
em rede. `LoadoutPanel` (`src/ui/common/loadout_panel.gd`, `class_name LoadoutPanel`,
`VBoxContainer`): `setup(root: Control, dog_locked_text: String = "")`, sinal `changed`; usado pela Preparação
(mesmos nós `%`) e pelo lobby.

Teclas na tela de equipamento: **saem em 1.4** (decisão do dono do jogo; reverte a parte de tela da HF1-S2). O
`LoadoutPanel` (Preparação e lobby) não mostra tecla de atalho nenhuma: somem os nós `ItemKey_<id>` e
`%DogKeyLabel`, os membros `_key_labels` e `_dog_key_label`, `_make_key_label`, `_update_key_labels`,
`_on_touch_mode_changed` e a conexão a `GameEvents.touch_mode_changed`. Cada `Item_<id>` volta a ser filho direto da
caixa de itens (sem a `HBoxContainer`), com `size_flags_horizontal` como os passivos; `%DogOption` fica onde estava
(a `HBoxContainer` do cão pode ficar com ele só, ou sair). As teclas continuam no jogo: barra de itens, legenda e
dicas (§8.4). A frase de ajuda do cão (`_dog_hint`) também perde a tecla (implementado em 0.8.3, decisão do dono do
jogo: a Preparação não informa tecla de atalho nenhuma nos equipamentos): era "Use E ou o botão Cão: Pega! / Volta!"
e passa a "Na caçada, mande o cão: Pega! / Volta!" (só com cão escolhido; a frase sem cão comprado e o `dog_locked_text` do `setup` não
mudam). O `LoadoutPanel` deixa de chamar `InputSetup.get_item_action` e
`get_key_label` (a API do `InputSetup` não muda). Os nomes `Item_<id>` e `%DogOption` não mudam (o `flow_test` os usa).

Cada peer troca para `HUNT` ao receber `Net.room_state_changed(LOADING)`. Na tela de resultado em sala,
"Voltar à sala" → `LOBBY` e `%MenuButton` chama `Net.leave_room()`.

Link com `?sala=CODIGO`: o Boot (`boot.gd`), depois do toque inicial, lê `Net.take_url_room_code()`; se não
vazio, vai ao `LOBBY` com o código como meta do `Router` (`Lobby.INVITE_META`; a API do `Router` não muda), e o
lobby entra na sala sozinho com o nome salvo.

Espectador (F6): `SpectatorCamera` (`src/player/spectator_camera.gd`, extends `Camera3D`; `begin`,
`get_target_slot`, `get_candidates`, `switch_target`, `is_active`), criada pelo `Player` ao morrer se houver
aliado vivo; ela emite `spectate_changed`. `Player.get_spectator()`, `Player.is_spectating()`. Troca de alvo
por `fire`, `spectate_next` (F; era `item_next` até 1.2) ou `weapon_swap` (`SpectatorCamera.SWITCH_ACTIONS`);
respeita só o terreno. Minimapa: `ally_yaws`, `ally_down`,
`center_color`, `is_in_view()` (arrays paralelos a `allies`/`ally_colors`); aliado vivo = seta na cor do slot,
caído = X, fora do alcance = seta na borda. Bússola: losango na cor do slot (oco se caído). Jogador caído em
rede pode abrir a pausa (P) para sair; no solo continua recusando. Loja aberta a partir da sala volta para o
`LOBBY`. Na sala, dica fixa: "Quem cria a sala deve ter o melhor aparelho e conexão. Se o anfitrião sair do
jogo, a partida termina para todos." Conexão ao servidor tem prazo `net.connect_timeout_s`; nenhuma tela
bloqueia esperando rede. O cão de cada peer trafega no resumo de loadout (`L_READY`, `L_LOBBY`, `L_START`;
255 = sem cão); a constante `DOGS_IN_COOP` foi removida. Textos de erro: `Net.room_error` (§6.11). Resultado em rede: "Seus abates: 7 · Equipe: 21 de
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

Cobertura da frente HUD/onboarding (1.3): `check_scripts` usa a lista nova de ações (§4; falha se `use_item` ou
`item_next` existirem), `tests/lib/contract_sigs.gd` ganha `Quickbar`, `HintDirector`, `HintBanner` (pacote A),
os 3 métodos de onboarding do `Profile` e `get_item_action`/`get_key_label` do `InputSetup`; `unit_tests` ganha
`tests/unit/test_onboarding.gd` (`is_onboarding_active` com `hunts_played` 2 e 3; `mark_hint_learned`
idempotente, id inválido ignorado, não grava sozinho e entra no `save()` seguinte; `reset_progress` zera;
`sanitize` com bloco ausente, tipo errado, ids desconhecidos e duplicados; save v2 antigo sem o bloco abre com
`learned = []` e versão 2; validação de `game.onboarding` e de `short_name`); `net_unit` ganha o sandbox
`hud_hints` (`src/hud/debug/hud_hints_test.tscn`, do A, com `--fixed-fps 60`); `mobile_probe.py` ganha um grupo
de itens e passa a abrir a build com `?probe=1&hints=0` (lê `touch_buttons`/`items` do probe: tocar o drone baixa
`items.scout_drone` em 1; tocar o kit com vida cheia não gasta; nenhum botão de item a menos de 60 px CSS de
`LOOK_A`; os testes de Tiro, Mira e Recarregar continuam passando).

Cobertura da Fase 4 (jogo 0.8.2): `check_scripts` ganha `help` no fim da lista de ações de `InputSetup.ACTIONS` (§4);
`tests/lib/contract_sigs.gd` ganha `ObjectivesPanel`, `ControlsLegend` e `TouchControls.set_action_labels` /
`has_action_labels`; `unit_tests` ganha um teste dos painéis (linhas por presença de cão/drone, textos de teclado e de
toque, progresso de abates e piso `min(objective_kills, total)`, lavoura em `OK`/`FAIL` com borda em `P`, "Volta!" não
conta, abertura e recolhimento da legenda, rótulos de tecla vindos de `get_key_label`) e do `Hud` no sandbox com
`--onboarding` (painéis visíveis nas primeiras caçadas e escondidos com `hunts_played = 3`, legenda escondida no toque e
nomes nos botões, escondidos no espectador, na queda e na horda salvo a legenda). O `mobile_probe.py` não muda (abre com
`hints=0`).

Cobertura da Fase 5 (contrato 1.4, jogo 0.8.3): `tests/lib/contract_sigs.gd` ganha `MapMarkers` (`draw` estático e as
constantes `KIND_*`/`DRAW_ORDER`), `Compass.heading_deg_of`/`label_for`/`get_heading_deg`/`get_heading_text`,
`Minimap.get_map_src_rect`/`get_map_dst_rect`, `MinimapBaker.bake`/`world_to_pixel`, `MapRoot.build_minimap`/
`get_minimap_texture`/`get_minimap_image`, `HuntWorld.get_minimap_texture` e `HuntController.get_minimap_texture`,
`Heightmap.get_grid_data`, `Terrain.get_grid_mask`; o `LoadoutPanel` não tem método novo. `unit_tests` ganha
`tests/unit/test_compass_minimap.gd`: `label_for` (0 "N", 45 "NE", 90 "L", 135 "SE", 180 "S", 225 "SO", 270 "O",
315 "NO", 15 "15", 105 "105", 7 ""), `heading_deg_of` (yaw 0 → 0; yaw `-PI/2` → 90; yaw `PI/2` → 270; yaw `-2·PI` → 0;
nunca 360), `get_heading_text` com o grau, `DRAW_ORDER` exata e cores distintas entre `crop`, `bait`, `revealed`,
`boar` e `dog`; `Minimap` com uma `ImageTexture` 256² e `map_rect` 256 m: os dois exemplos exatos de §8.4, origem fora
do mapa → `Rect2()`, `map_texture = null` → `Rect2()`; `MinimapBaker.world_to_pixel` nos quatro cantos e no centro;
o `Hud` ligado a um mundo falso (subclasse de `HuntWorld` dentro do próprio teste, com talhão, cão em `seek` com
alvo, javali marcado e javalis vivos; ceva por `GameEvents.bait_placed`, drone por `GameEvents.item_used`): depois de
um polling, `Compass._marks` tem os tipos `crop`, `bait`, `revealed`, `boar`, `dog_target`, `dog` nessa ordem, o
talhão some com o caçador dentro dele, na horda não há `crop`, e `Minimap.map_texture` é a textura do mundo; e `Data` (`get_load_errors()` vazio com o bloco
`minimap`; erro com `image_px` 1000, com `grid_stride` 3 e com uma cor `"verde"`). `net_unit` ganha o sandbox
`minimap_bake` (`src/world/debug/minimap_selftest.tscn`, do B, `limit_s` 60) e passa a exigir o check
`minimap_same_on_both` do `net_sync`. Teste de UI do `LoadoutPanel`: `Item_<id>` existe e nenhum `ItemKey_<id>` /
`DogKeyLabel` existe, em modo teclado e toque. `flow_test`, `playthrough` e `mobile_probe.py` não mudam.
Implementado em 0.8.3: o `minimap_selftest` tem 8 checks (`texture_size`, `orientation`,
`world_to_pixel_clamped_and_northwest_origin`, `deterministic`, `quality_independent`, `canopy_not_density_scaled`,
`budget`, `png_written`; `map_loaded` só aparece, como FAIL, se a cena do mapa não carregar) e o `net_sync_test` ganhou
`minimap_same_on_both`. `tests/unit/test_compass_minimap.gd` e `tests/unit/test_loadout_panel_keys.gd` são da HF5-QA
(concluídos: 63 e 10 testes); o de `LoadoutPanel` confere também que `_dog_hint` não cita tecla.

Cobertura da Fase 6 (contrato 1.5, jogo 0.8.4): `tests/lib/contract_sigs.gd` ganha `WeaponPanel` (os 5 métodos de
entrada e os 8 de teste de §6.8), `HealthStrip` (`HEIGHT_PX`, `set_health`, `set_vest`, `set_touch` e os 4 de teste) e
`Player.get_weapon_ids`/`debug_set_health`. `unit_tests` ganha `tests/unit/test_weapon_health_hud.gd`
(concluído na HF6-QA: 45 testes; `tests/unit_tests.gd` não mudou, o runner descobre sozinho todo `tests/unit/test_*.gd`;
o `contract_sigs` cobre os métodos das duas vistas e os dois do `Player`; a constante `HealthStrip.HEIGHT_PX` é
conferida pelo teste unitário, não pelo `contract_sigs`, como registra o comentário dele):
- `WeaponPanel` solto (sem `Hud`): `set_weapons([carbine_22, shotgun_12])` → chips `Chip_1`, `Chip_2`, fileira visível,
  teclas "1" e "2" (iguais a `InputSetup.get_key_label(&"weapon_1"/&"weapon_2")`); com uma arma a fileira some; com as 5
  há `Chip_1`…`Chip_5` e nenhum `Chip_6`; `set_active(1)` → `get_active_index() == 1`, nome "Espingarda calibre 12",
  `get_portrait_path() == ScenePaths.weapon_art(&"shotgun_12")`; `set_active(9)` não muda nada; id sem PNG nem SVG
  (lista com um id falso) → `get_portrait_path() == ""` sem erro fatal; `set_ammo(5, 30, false, 10)` → "5" e "| 30", não
  baixa; `set_ammo(2, 30, false, 10)` → baixa (2 ≤ 2,5); `set_ammo(0, 0, false, 5)` → baixa; `set_ammo(3, 0, true, 5)` →
  "| ∞"; `set_reload(true, 0.4)` → `ReloadBar` visível com valor 40, `set_reload(false, 0)` → invisível;
  `set_touch(true)` → `get_chip_key_text(0) == ""`, `set_touch(false)` volta a "1".
- `HealthStrip` solto: `set_health(100, 100)` → "100", 100%, verde; `(50, 100)` → âmbar (50 não é > 50); `(31, 100)` →
  âmbar; `(30, 100)` → vermelha; `(0.4, 100)` → "1"; `(0, 100)` → "0"; `max_hp` 0 não divide por zero; `set_vest(true)`
  → `has_vest()` e `Vest` visível; altura do controle == `HEIGHT_PX` com e sem colete; `set_touch(true)` → largura 300.
- `Hud` com o `player_sandbox` (ou um `Player` de teste, como os testes de HUD de antes): depois do `bind`,
  `_weapon_panel.get_weapon_ids() == player.get_weapon_ids()`; `bot_select_weapon(1)` → depois de um quadro
  `get_active_index() == 1`; `debug_set_health(37)` → "37" na faixa; colete do loadout padrão → `has_vest()`;
  `spectate_changed(1)` esconde `WeaponFrame` e mantém `HealthStrip`, `spectate_changed(-1)` mostra de novo; com
  `InputSetup.set_touch_override("on")` o `WeaponFrame` fica com `offset_left == 128` e a faixa com 300 px, e com `"off"`
  volta (restaurar o modo no fim); `QUICKBAR_BOTTOM_PX == 50` e a `Quickbar` com `offset_bottom == −50`.
Os sandboxes do A que liam privados do `Hud` passam a ler os novos (HF6-A): `hud_horde_test` (`_weapon_panel`:
`get_reserve_text() == "| ∞"` e `get_mag_text()` = pente na horda; "| <reserva>" no contrato), `hud_net_test` e
`spectator_sandbox` (`_weapon_frame` no lugar de `_bottomright_margin`). `flow_test`, `playthrough` e o
`mobile_probe.py` não mudam (o probe não lê o painel; roda na publicação porque o layout do toque mudou).

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
| Draw calls por frame (visão típica) | ≤ 165 (pior caso ≤ 200); javalis ≤ 40 típico, ≤ 80 pior caso |
| Triângulos visíveis | ≤ 200 k típico, ≤ 250 k pior caso; 26 javalis ≤ 40 k |
| Tempo de quadro do cenário | ≤ +2 ms sobre a linha de base da 0.6.0 (23,5 ms em render scale 1,0, DPR 3, GPU de referência) |
| Terreno | 256 × 256 m; grade 129×129 (2 m); malha em 2×2 blocos de 64×64 quads = 32 768 tris, 4 draw calls; colisão HeightMapShape3D 257×257 |
| Flora | só `MultiMeshInstance3D`, blocos de 128 m (2×2) por id; grama `visibility_range_end` 60 m, arbusto 90 m, árvores = view distance; densidade × `flora_density` |
| Lavoura | patches 2×2 m em `MultiMesh` por blocos de 32×32 m, 2 multimeshes por bloco (saudável/comida; trocar = escalar instância a 0); `visibility_range_end` 110 m; ≈ 30 draw calls |
| Javalis simultâneos | ≤ 26 vivos (+ carcaças); LOD e malhas por javali conforme §7.1 |
| Física | 1 `CharacterBody3D`; ≤ 200 shapes estáticas; 72 `HitZone`; ≤ 100 raios de visão/s; 0 corpos de IA |
| Sombras | 1 `DirectionalLight3D`; desligada em "low"; 30/45 m em medium/high; mapa 2048, filtro hard; flora/lavoura/arma sem sombra |
| Luzes extras | nenhuma |
| Partículas | `CPUParticles3D`, ≤ 24 cada, ≤ 6 ativas |
| Materiais únicos | ≤ 32 no total |
| Texturas | ≤ 512² cada (exceção: arma em 1ª pessoa ≤ 1024², §7.3); preferir ruído no shader; `NoiseTexture2D` ≤ 256² |
| Áudio | ≤ 18 vozes; ≤ 4 MB de amostras |
| Carregar a caçada | ≤ 3 s; nenhuma etapa > 700 ms |
| Memória | alvo ≤ 300 MB no total da aba |
| Alocação | nada de `Array`/`Dictionary` novos por frame em laços de IA; HUD/minimapa a 10 Hz |
| Minimapa (1.4) | imagem gerada 1× por caçada na CPU (`MinimapBaker`), RGB8 `image_px`² (256² = 192 KiB), sem `SubViewport`; etapa `minimap` ≤ 60 ms desktop nativo e ≤ 400 ms Web com CPU ×4 (medido em 0.8.3: 9,8 ms no desktop headless, `HUNT_TIMING minimap_ms=10`); desenho: 1 `draw_texture_rect_region` por redesenho (10 Hz), sem alocação |
| Retratos de arma no HUD (1.5) | exceção à regra de ≤ 512²: os PNG 1024×512 de §7.9 (RGBA8 + mipmaps ≈ 2,7 MB de VRAM cada), só das armas carregadas, carregados uma vez no `Hud.bind` (dentro da montagem, antes de `hunt_started`): caçada normal ≤ 2 (≈ 5,3 MB), horda 5 (≈ 13,3 MB), dentro do alvo de 300 MB. Nenhum carregamento ao trocar de arma. Decodificar 5 WebP na Web soma tempo à etapa que monta o jogador: conferir com `load_ab.py --throttle=4` que nenhuma etapa passa de 700 ms (válvula se passar: o chip usa o SVG `ScenePaths.icon(id)` e só o retrato ativo carrega o PNG, com carga na troca) |
| Aliados (cooperativo) | ≤ 3 `RemoteHunter`, ≤ 5000 tris e ≤ 10 `MeshInstance3D` cada, + 1 `Label3D`; draw calls: pior caso ≤ 230 com 3 aliados |
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

Modo Horda Javali (0.5.0): pacotes, ordem e critérios de aceite em `docs/horda.md` §14.

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
- Todos os ids de som da §7.8 existem (`has_sound`); carga dos sons ≤ 400 ms em desktop (35 ms medidos com os 47 MP3; 233 ms só na síntese de fallback).
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
| F7 — cães em rede (concluída em 2026-11-14) | cada jogador leva o seu cão e manda "Pega!"/"Volta!" | B, qa (Sonnet) | N6: comando do cliente muda o estado só do cão dele; sinais de cão só no HUD do dono; marcação aparece para os dois; solo sem mudança |
| F8 — robustez móvel (contrato em `docs/multiplayer.md` §4.7; implementação pendente) | cair e voltar na mesma página sem perder a caçada | coordenação (servidor, `src/core`) e systems (`data/net.json`) primeiro; N e B (Fable) e A (Sonnet) em paralelo; qa (Sonnet) | `Net.debug_cut(5.0)` no cliente: ele volta no mesmo slot com os mesmos javalis vivos, os mesmos canteiros e o mesmo placar parcial, e a caçada termina `VICTORY` nos dois; token errado e carência estourada terminam `DISCONNECTED`; `bun test` com a reentrada; relatório de fps e banda em celular intermediário como anfitrião de 4 (lista completa em §4.7.10 de lá) |

### Frente HUD/onboarding — fases 1 a 4 (contrato 1.3)
Nada muda em `src/core/`, `project.godot`, `export_presets.cfg` nem no Pacote B ou N. Todos em Sonnet. Toda tarefa
termina com `check_scripts`, `unit_tests`, `flow_test` e `playthrough` sem mudança de resultado (exceto o que a
própria tarefa atualiza nos testes).

| Tarefa | Dono | Arquivos | Depende de |
|---|---|---|---|
| HF1-A — teclas fixas, barra, botões de toque | game-developer (A) | `src/input/input_setup.gd`; `src/player/item_belt.gd`, `player.gd`, `spectator_camera.gd`, `src/player/debug/spectator_sandbox.gd` (`item_next` → `spectate_next`); `src/hud/hud.gd`, `src/hud/quickbar.gd` (novo); `src/hud/touch/touch_controls.gd` (+ `.tscn` se precisar) | — |
| HF1-S — dados, save e Profile | game-systems | `data/game.json` (`onboarding`), `data/equipment.json` (`short_name` no arquivo real, sem mexer em outros valores); `src/systems/data_registry.gd` (validação), `save_service.gd` (`sanitize` do bloco), `profile.gd` (3 métodos, `reset_progress`) | — (paralela à HF1-A; sem arquivo em comum) |
| HF1-AR — ícones legíveis no HUD | art-director | `assets/ui/icons/{medkit,corn_bait,scout_drone,binoculars,btn_dog}.svg` (ajuste no lugar, mesmos ids); `assets/preview/hud_icons_preview.tscn|.gd` | — (paralela) |
| HF1-S2 — teclas na tela de equipamento | game-systems | `src/ui/common/loadout_panel.gd` | HF1-A (`InputSetup.get_item_action`/`get_key_label`) |
| HF1-QA | qa-tester | `tests/check_scripts.gd`, `tests/lib/contract_sigs.gd`, `tests/unit/test_onboarding.gd` (novo; parte de dados/save/Profile), `tests/unit_tests.gd` (registrar), `tests/web/mobile_probe.py` | HF1-A, HF1-S, HF1-S2 |
| HF2-A — dicas | game-developer (A) | `src/hud/hint_director.gd`, `hint_banner.gd` (novos), `src/hud/hud.gd` (criação, ligações, `?hints=0`, campo `hint` do probe), `src/hud/debug/hud_hints_test.tscn|.gd` (novos; mundo falso estendendo `HuntWorld` só no `debug/`) | HF1-A, HF1-S |
| HF3-A — cartão do cão e alvo do cão (1.3, jogo 0.8.1) | game-developer (A) | `src/hud/dog_card.gd` (novo), `src/hud/hud.gd` (`_dog_panel`, polling), `src/hud/compass.gd` (marca `dog_target`), `src/hud/minimap.gd` (`dog_target`); `src/core/hunt_world.gd` (só `get_dog_target_position`, e a cópia do Apêndice A); `src/dogs/dog.gd` (só `get_target_position`); `src/hunt/hunt_controller.gd` (só `get_dog_target_position`); `src/player/debug/sandbox_world.gd` (cão falso: `dog_position`, `dog_target_position`, `dog_health_pct`, args `--dog_state`, `--dog_hp`, `--dog_breed`) | HF2-A |
| HF3-QA | qa-tester | `tests/lib/contract_sigs.gd` (`DogCard`; `Dog.get_target_position`; `HuntWorld.get_dog_target_position`; `HuntController.get_dog_target_position`), teste de unidade/sandbox do cartão (texto, cor e ação por estado, toque, sem cão, alvo na bússola/minimapa) | HF3-A |
| HF2-QA | qa-tester | `tests/net_unit.gd` (sandbox `hud_hints`, `limit_s` 60), `tests/lib/contract_sigs.gd` (`HintDirector`, `HintBanner`) | HF2-A |
| HF4-A — objetivos, legenda e nomes nos botões (jogo 0.8.2) | game-developer (A) | `src/hud/objectives_panel.gd`, `src/hud/controls_legend.gd` (novos), `src/hud/hud.gd` (criação, ligações, `_unhandled_input` do `help`, `_setup_onboarding_ui`/`_refresh_onboarding_ui`), `src/hud/touch/touch_controls.gd` (`set_action_labels`), `src/input/input_setup.gd` (ação `help`, tecla H), `src/player/debug/sandbox_world.gd` (`--onboarding`, `--hunts=N`, `--help_key`) | HF2-A, HF3-A, HF4-S |
| HF4-S — dados e validação | game-systems | `data/game.json` (`onboarding.objective_kills` = 3, `onboarding.objective_crop_min_pct` = 50.0), `src/systems/data_registry.gd` (`ONBOARDING_FIELDS` ganha os dois; `objective_kills` inteiro; `objective_crop_min_pct` ≤ 100) | — (paralela à HF4-A: o painel tem fallback) |
| HF4-QA | qa-tester | `tests/check_scripts.gd` (`help` no fim de `expected` das ações), `tests/lib/contract_sigs.gd` (`ObjectivesPanel`, `ControlsLegend`, `TouchControls.set_action_labels`/`has_action_labels`), teste de unidade dos painéis e do `Hud` com `--onboarding` (§12), teste de dados (`Data.get_load_errors()` vazio com as chaves; erro com `objective_kills` 2.5 e com `objective_crop_min_pct` 120) | HF4-A, HF4-S |

O A lê `short_name` com fallback para `name` (`def.get("short_name", def.get("name", ""))`), então HF1-A não
espera HF1-S. Ordem: {HF1-A, HF1-S, HF1-AR} em paralelo → HF1-S2 → HF1-QA → HF2-A → HF2-QA → coordenação
exporta a Web, roda `mobile_probe.py`, sobe `config/version` e publica.

Critérios de aceite:
- **HF1-A:** `ACTIONS` e `ITEM_ACTIONS` exatamente como §4; nenhuma ocorrência das ações `"use_item"`/`"item_next"`
  (o método `ItemBelt.use_item` fica) nem de `selection_changed`/`get_selected_id`/`use_selected`/`_item_label`
  em `src/`. No `player_sandbox` (relato
  manual): Q, G, V e B usam cada item direto; E manda o cão; F parado não faz nada; no `spectator_sandbox`
  (`net_unit --only=spectator`) F troca de alvo. Com loadout `[medkit, scout_drone]` + `caramelo`, a barra
  mostra `Slot_medkit` ("Q", "x1"), `Slot_scout_drone` ("V", "x3"), `Slot_dog_command` ("E") nessa ordem; V →
  "x2"; drone esgotado → espaço apagado; kit com vida 60 → setor cresce por 1,5 s e o espaço fica "x0" apagado; B
  com binóculo → borda âmbar, B de novo → normal. Sem item usável e sem cão: barra invisível e nenhum botão de
  item/cão no toque. Toque: `get_button_center(&"use_medkit") == (w − 380, h − 250)`,
  `get_button_center(&"use_scout_drone") == (w − 476, h − 250)`, `use_item` e `item_next` sem botão. Campos
  `items`, `busy_item`, `binoculars`, `touch_buttons` no probe. Screenshots com janela: desktop 1280×720 e toque
  1558×720 e 960×720 (com 3 itens e cão), sem sobreposição com Tiro, Mira, Recarregar, Trocar, Agachar e joystick.
- **HF1-S:** `Data.get_load_errors()` vazio; `short_name` em todos os 7 itens; save sem `onboarding` abre com
  `learned = []` e versão 2; `is_onboarding_active()` true com `hunts_played` 2, false com 3;
  `mark_hint_learned(&"medkit")` não grava sozinho e aparece no arquivo depois de `save()`.
- **HF1-AR:** os 5 ícones legíveis a 40 px no screenshot de `hud_icons_preview` (sobre `HudPanel` e sobre o
  círculo translúcido do toque); a loja continua bonita (screenshot do cartão).
- **HF1-S2 (revertida em 1.4 pela HF5-S):** Preparação e lobby mostravam "Q"/"G"/"V"/"B" ao lado dos itens usáveis
  possuídos e "E" ao lado do cão escolhido; nada em modo toque; `flow_test` sem mudança.
- **HF2-A:** sandbox `hud_hints` imprime `RESULT:` e cobre: abertura aparece `opening_delay_s` depois de
  `hunt_started`; cada gatilho da tabela de §8.4 dispara com a condição e não dispara sem ela; uma dica por vez,
  `medkit` fura a fila, `queue_max` respeitado; cada id no máximo uma vez por caçada; usar o item esconde a dica
  na hora e chama `mark_hint_learned`; id aprendido nunca aparece; `hunts_played = 3` → `is_active() == false`
  e nenhum sinal; texto de toque com `set_touch_override("on")`; morte e `hunt_ended` limpam tudo; em horda a
  dica da ceva fala em celeiro. Screenshot com janela da dica do kit com o espaço piscando.
- **HF3-A:** `check_scripts`, `unit_tests`, `flow_test` e `playthrough` verdes. No sandbox (`player_sandbox.tscn --dog`,
  `--dog_state=<estado>`): em `follow` o cartão mostra retrato, nome da raça, "Seguindo", barra e "E: Pega!"; nos
  demais estados (menos `retreat`) "E: Volta!"; em `retreat` "Ferido" em `#D9452B` e "Ferido: voltando" apagado; com
  `--touch=on` "Botão Cão: ..." no lugar de "E: ..." e o cartão não encobre o botão Cão. Sem cão o cartão fica
  invisível. Com alvo finito e estado diferente de `follow` aparece o anel na bússola (marca `dog_target`) e no
  minimapa (`dog_target`, preso à borda fora da vista); em `follow` nenhum dos dois. `Dog.get_target_position()`
  é finito de `point`/`bay`/`hold` e `INF` depois de `Volta!`; `HuntWorld.get_dog_target_position()` é `INF` por
  padrão. Screenshots com janela do cartão no teclado e no toque.
- **HF4-A:** `--import` e depois `check_scripts` (única falha esperada até a HF4-QA: a lista de ações em
  `tests/check_scripts.gd`), `unit_tests`, `flow_test` e `playthrough` verdes. No sandbox
  (`player_sandbox.tscn --items=medkit,scout_drone --dog --onboarding`, `--frames=600`): à esquerda quatro linhas
  ("Mande o cão atacar (E)", "Use o drone (V)", "Abata 3 javalis (0/3)", "Mantenha a lavoura acima de 50%"); à direita,
  abaixo do cartão do cão, a legenda com as teclas de §8.4, ao fim da coluna acima do painel da arma; com `--help_key` a
  legenda vira só "H: Ajuda"; com `--touch=on` (1558×720 e 960×720) a legenda some, os objetivos ficam à direita do
  slider e os botões Tiro, Mira, Recarga, Troca e Agachar mostram o nome sem encostar um no outro. Abater 3 alvos marca
  "Abata 3 javalis (3/3)" como feito; lavoura abaixo de 50% deixa a linha vermelha; `Ids.CMD_ATTACK` marca a linha do cão
  e `Ids.CMD_RECALL` não; a morte, o espectador e `hunts_played = 3` escondem tudo. Screenshots com janela do teclado
  (aberta e recolhida) e do toque.
- **HF4-S:** `Data.get_load_errors()` vazio com as duas chaves; sem elas, ou com `objective_kills` não inteiro ou
  `objective_crop_min_pct` > 100, o `Data` aponta o erro.
- **HF1-QA / HF2-QA / HF4-QA:** §12 (cobertura 1.3 e Fase 4); `mobile_probe.py` verde com a build nova.

### Frente HUD/gameplay — fase 5 (contrato 1.4, jogo 0.8.3; implementada e testada em 2026-11-20)
Bússola estilo PUBG, marcadores comuns, minimapa sobre a imagem do mapa, Preparação sem teclas. Contrato em §8.4
("Bússola, marcadores e minimapa"), §9.1 (`minimap.*`), §11 (teclas que saem) e §13.1. Nada muda em
`project.godot`, `export_presets.cfg`, `src/net`, `GameEvents` ou no protocolo de rede; em `src/core/` só o método
`HuntWorld.get_minimap_texture` (Apêndice A). Nenhuma imagem raster nova em `assets/`; o art-director não tem tarefa
(as cores do minimapa ficam em `data/game.json` e podem ser afinadas depois, só nos dados). Todos em Sonnet. Toda
tarefa termina com `check_scripts`, `unit_tests`, `flow_test` e `playthrough` sem mudança de resultado (exceto o que a
própria tarefa atualiza nos testes).

| Tarefa | Dono | Arquivos | Depende de |
|---|---|---|---|
| HF5-0 — núcleo (concluída) | coordenação | `src/core/hunt_world.gd`: só `get_minimap_texture()`, verbatim do Apêndice A (3 linhas) | — |
| HF5-B — imagem do mapa (concluída) | game-developer (B) | `src/world/minimap_baker.gd` (novo); `src/world/map_root.gd` (`build_minimap`, `get_minimap_texture`, `get_minimap_image`); `src/world/heightmap.gd` (só `get_grid_data`); `src/world/terrain.gd` (só `get_grid_mask` e o preenchimento de `_grid_mask` em `_build_meshes`); `src/hunt/hunt_controller.gd` (etapa `minimap` em §8.1 e `get_minimap_texture`); `src/world/debug/minimap_selftest.tscn|.gd` (novos); `src/hunt/debug/net_sync_test.gd` (só o check `minimap_same_on_both`) | HF5-0 |
| HF5-A — bússola, marcadores, minimapa (concluída) | game-developer (A) | `src/hud/map_markers.gd` (novo); `src/hud/compass.gd`; `src/hud/minimap.gd`; `src/hud/hud.gd` (`bind`: `map_texture`, `_crop_rects`, `_crop_centers`; `_poll_world`: tipos novos e `DRAW_ORDER`; na entrega, também `CONTEXT_TOP_FRAC`/`CONTEXT_HEIGHT_FRAC`); `src/player/debug/sandbox_world.gd` (`--minimap_tex`, `--marked`, `--bait`, `--reveal`, `--heading=`; na entrega, também `--crop_alert`) | HF5-0 (paralela à HF5-B: sem textura o minimapa usa o fundo liso) |
| HF5-S — Preparação sem teclas e dados (concluída) | game-systems | `src/ui/common/loadout_panel.gd`; `data/game.json` (bloco `minimap` exato de §9.1 e `"minimap": 1` em `loading.step_weights` entre `"flora"` e `"crop"`, sem mexer em outros valores); `src/systems/data_registry.gd` (validação de `minimap.*`) | — (paralela; o `MinimapBaker` tem fallbacks iguais aos dados) |
| HF5-QA (concluída) | qa-tester | `tests/lib/contract_sigs.gd`; `tests/unit/test_compass_minimap.gd` (novo); `tests/unit/test_loadout_panel_keys.gd` (novo); `tests/unit_tests.gd` (registrar os dois); `tests/net_unit.gd` (sandbox `minimap_bake`, `limit_s` 60, e o comentário da lista) | HF5-A, HF5-B, HF5-S |

Ordem: HF5-0 → {HF5-A, HF5-B, HF5-S} em paralelo (nenhum arquivo em comum) → HF5-QA → coordenação: screenshots de
integração (abaixo), exporta a Web, mede com `load_ab.py --throttle=4`, roda `mobile_probe.py`, sobe `config/version`
para 0.8.3 e publica.

Divergências da entrega aceitas pelo coordenador (já refletidas nas seções citadas; valem como contrato):
- **Preparação (HF5-S, §11, §6.10):** a frase do cão `_dog_hint` perdeu a tecla: "Na caçada, mande o cão: Pega! /
  Volta!". O painel não ouve mais `GameEvents.touch_mode_changed` (sai `_on_touch_mode_changed`).
- **`MapMarkers` (HF5-A, §6.8, §8.4):** helper público `static func color_of(kind: StringName) -> Color`; anel
  `dog_target` com largura 0,25 × `half_px` e contorno largura − 0,5.
- **`Compass` (HF5-A, §8.4):** rótulo que não cabe inteiro na faixa é pulado (o traço fica); entalhe com base no topo
  da caixa (y 36) e vértice em y 30.
- **`Hud` (HF5-A, §8.4):** mensagem de contexto em `CONTEXT_TOP_FRAC = 0.25` (era 0,22), `CONTEXT_HEIGHT_FRAC = 0.08`.
  Resíduo aceito: dica de abertura + aviso + contexto juntos, em 16:9, o texto do contexto encosta ~6 px no topo do
  painel da dica.
- **`Minimap` (HF5-A, §8.4):** o quadrado `crop` preso à moldura só existe com textura.
- **Sandbox (HF5-A, §8.4):** `--crop_alert` novo; `--reveal` pode marcar a dica do drone como aprendida no perfil
  real, usar `--hunts=N`.
- **`MinimapBaker` (HF5-B, §8.4, §13.1):** cores dos dados com meio degrau de byte (pixel exato no hex); linhas de
  cultivo a partir de 1 px dentro do talhão (`CROP_ROW_FIRST_OFFSET_PX`); medido 9,8 ms (desktop headless),
  `HUNT_TIMING minimap_ms=10`.
- **Testes (HF5-B, §12):** `minimap_selftest` com 8 checks; `net_sync_test` com `minimap_same_on_both`.

Critérios de aceite:
- **HF5-0:** `check_scripts` sem erro; `HuntWorld.new().get_minimap_texture() == null`.
- **HF5-B:** `minimap_selftest` roda headless (`tools/godot.sh --headless --path . res://src/world/debug/minimap_selftest.tscn
  -- --out=<caminho absoluto>.png`), termina sozinho com `RESULT:` e código 0, e cobre: monta Mato Grosso
  (`build_heightmap`, `build_terrain`, `build_props_and_water`, `build_flora(1.0, true)`, `build_minimap(cfg)`) e imprime
  `MINIMAP_BAKE_MS=<ms>`; `texture_size` (textura e imagem `image_px`², `FORMAT_RGB8`); `orientation` (o pixel de
  `world_to_pixel` no centro do açude (−70, −55) tem exatamente `colors.water` e o pixel espelhado (70, 55) não tem;
  o centro da soja (−35, 15) é `colors.soy` ou `colors.crop_row`; o centro da sede (10, −85) é `prop_colors.farmhouse`);
  `deterministic` (segundo `MinimapBaker.bake` no mesmo mapa → `get_data()` igual); `quality_independent` (outra
  instância do mapa com `build_flora(0.5, true)` → mesmos bytes); `canopy_not_density_scaled`; `budget`
  (`MINIMAP_BAKE_MS` ≤ 150 é PASS; o relatório traz o valor medido e a meta é ≤ 60 ms). O PNG gravado mostra, sem
  espelhar: soja e milho no centro-sul, açude a noroeste, sede ao norte, mata de galeria ao sul, estrada da porteira à
  lavoura (anexar o caminho no relatório). `hunt.tscn -- --hunt-timing` em desktop imprime `HUNT_TIMING minimap_ms` ≤ 60
  e o total de carga continua ≤ 3 s. `net_unit --only=net_sync` com `minimap_same_on_both` PASS (compara
  `(_host._map as MapRoot).get_minimap_image().get_data()` com a do cliente; não usar `ImageTexture.get_image()`, que
  depende do renderer); os demais sandboxes do `net_unit` sem mudança.
- **HF5-A:** `check_scripts`, `unit_tests`, `flow_test`, `playthrough` e `net_unit --only=hud_net,hud_hints,spectator`
  verdes (o formato de `Compass._marks` e as marcas `ally` não mudam). Screenshots com janela, 1280×720,
  `--frames=600` (`tools/godot.sh --path . --windowed --resolution 1280x720 -s res://tools/screenshot.gd --
  --scene=res://src/player/debug/player_sandbox.tscn --out=<png> --frames=600 <args>`):
  1. `--minimap_tex --dog --dog_state=seek --marked --bait --reveal --heading=135`: a caixa mostra "135°" e "SE" fica
     sob o entalhe; à vista "L", "S", "120", "150" e os traços de 5°; N em vermelho quando à vista (rodar também com
     `--heading=0`); cada marcador com a forma e a cor da tabela de §8.4; o minimapa mostra a imagem de teste com o
     talhão no quadrante de cima à direita (norte para cima, leste à direita) e o contorno verde sobre ele; ceva
     hexágono turquesa, revelados círculos salmão, marcado triângulo vermelho, cão e anel âmbar.
  2. O mesmo com `--touch=on` a 1558×720 e 960×720: bússola, faixa da lavoura e minimapa sem tocar botões nem
     joystick.
  3. Sem `--minimap_tex`: minimapa com o fundo liso de antes e talhão preenchido (fallback).
  Nenhum texto "E", "W" ou "SW" na bússola. O aviso "Javalis na lavoura!" (forçado) não encobre a mensagem de contexto
  a mais do que já encobria em 0.8.2 (comparar com um screenshot de antes). Conferir com `--crop_alert`;
  com o contexto em 0,25 o aviso deixa de cobri-lo (resíduo com a dica, acima).
- **HF5-S:** Preparação e lobby, em teclado e em toque, sem nenhuma etiqueta de tecla nem tecla citada em texto (a
  frase do cão é "Na caçada, mande o cão: Pega! / Volta!"); `find_child("ItemKey_*")` e
  `%DogKeyLabel` não existem; marcar/desmarcar `Item_<id>` e escolher o cão em `%DogOption` funcionam como antes;
  `flow_test` sem mudança; screenshot da Preparação a 1280×720 com 3 itens e cão. `Data.get_load_errors()` vazio com o
  bloco `minimap`; erro com `image_px` 1000, `grid_stride` 3, `hillshade.min` > `max`, uma cor `"verde"` e
  `canopy.ipe.radius_m` 0. Em `loading.step_weights` a chave `minimap` fica entre `flora` e `crop`.
- **HF5-QA:** §12 (cobertura da Fase 5); as 4 suítes e o `net_unit` verdes com tudo entregue.
- **Coordenação (integração):** screenshot com janela de `src/hunt/hunt.tscn` a 1280×720 (`--frames=900`): o
  minimapa mostra o mapa real alinhado com o mundo (andar até o açude: ele passa pelo centro do minimapa) e a bússola
  aponta os dois talhões; `load_ab.py --throttle=4` com `minimap_ms` ≤ 400 (senão `grid_stride = 2` nos dados e
  medir de novo); `mobile_probe.py` verde.

### Frente HUD/gameplay — fase 6 (contrato 1.5, jogo 0.8.4; implementada e testada em 2026-11-20)
Painel da arma com retrato, munição grande e fileira de armas; vida em barra larga embaixo no centro. Contrato em §4
("Fileira de armas"), §6.8 (`WeaponPanel`, `HealthStrip`, `Player.get_weapon_ids`/`debug_set_health`), §7.9
(retratos também no HUD), §8.4 ("Painel
da arma e barra de vida"), §12 (cobertura da Fase 6) e §13.1 (retratos no HUD). Nada muda em `project.godot`,
`export_presets.cfg`, `src/core/`, `src/net`, `GameEvents`, `data/`, `src/ui/`, no `TouchControls` nem no protocolo
de rede. Nenhum asset novo (os 5 retratos e os SVG já existem): o art-director e o game-systems não têm tarefa. Todos
em Sonnet. Toda tarefa termina com `check_scripts`, `unit_tests`, `flow_test` e `playthrough` sem mudança de resultado
(exceto o que a própria tarefa atualiza nos testes).

| Tarefa | Dono | Arquivos | Depende de |
|---|---|---|---|
| HF6-A — painel da arma, barra de vida, layout (concluída) | game-developer (A) | `src/hud/weapon_panel.gd`, `src/hud/health_strip.gd` (novos); `src/hud/hud.gd` (`_build_top_left` só com FPS, `_build_weapon_panel`, `_build_health`, `_build_quickbar` com `QUICKBAR_BOTTOM_PX`, `bind`, `_update_weapon`, `_update_health`, `_apply_touch_layout`/`_place_weapon_frame`, `_on_spectate_changed`; sai o que §8.4 lista); `src/player/player.gd` (só `get_weapon_ids` e `debug_set_health`); `src/player/debug/sandbox_world.gd` (`--hp=`, `--mag=`, `--slot=`); `src/hud/debug/hud_horde_test.gd`, `src/hud/debug/hud_net_test.gd`, `src/player/debug/spectator_sandbox.gd` (só trocar `_ammo_label`/`_bottomright_margin` pelos privados novos, mesmos checks) | — |
| HF6-QA (concluída) | qa-tester | `tests/lib/contract_sigs.gd` (`WeaponPanel`, `HealthStrip`, `Player.get_weapon_ids`, `Player.debug_set_health`); `tests/unit/test_weapon_health_hud.gd` (novo, §12, 45 testes); `tests/unit_tests.gd` (não precisou mudar: o runner descobre `tests/unit/test_*.gd`) | HF6-A |

Ordem: HF6-A → `--import` (classes novas) → HF6-QA → coordenação: screenshots de integração (abaixo), exporta a Web,
mede com `load_ab.py --throttle=4`, roda `mobile_probe.py`, sobe `config/version` para 0.8.4 e publica.

Divergências da entrega aceitas pelo coordenador (já refletidas nas seções citadas; valem como contrato):
- **Sandbox (HF6-A, §8.4):** a ordem real é `--hp`, `--slot`, `--mag`; `--mag` vale para a arma na mão (depois do
  `--slot`), não só para a inicial.
- **`WeaponPanel` (HF6-A, §6.8, §8.4):** `set_weapons` com lista não vazia ativa o índice 0 sozinho. O `WeaponFrame`
  tem 248 px de largura (x 1008–1256 a 1280×720 no teclado, x 128–376 no toque), por causa da margem 12/8 do stylebox
  `HudPanel` do tema, não ≈ 240. Helper público `static func style_portrait(rect: TextureRect) -> void` (filtro,
  `expand_mode` e `stretch_mode` comuns ao retrato grande e aos chips; uso interno, fora do `contract_sigs`).
- **`HealthStrip` (HF6-A, §6.8):** recém-criada mostra "1" até o primeiro `set_health` (`_init` chama
  `set_health(1.0, 1.0)`); comportamento, não bug, porque o `Hud.bind` atualiza antes do primeiro quadro.
- **Geometria do toque (coordenação, §8.4):** com stretch `canvas_items` + aspect `expand`, uma janela 960×720 tem
  canvas virtual 1280×960 (escala 0,75), não 960×720. As "Folgas conferidas" foram reescritas em coordenadas virtuais
  relativas às âncoras (`L`, `A`), sem mudar o layout aprovado; só 1558×720 batia com a geometria antiga. A correção
  vale também para a frase da fileira de itens em "Botões de item (toque)". Um resíduo novo apareceu na conta (mensagem
  do cão na altura do painel em 4:3) e o da mensagem de fim mudou de proporção (agora 16:9 e mais largo).
- **Testes (HF6-QA, §12):** 45 testes em `tests/unit/test_weapon_health_hud.gd`; `tests/unit_tests.gd` sem mudança;
  `HealthStrip.HEIGHT_PX` conferido pelo teste unitário.
- **Resíduo anterior à fase (sem tarefa, §8.4):** na horda a 1280×720, a faixa "Defenda o celeiro! A horda chega em
  N s" (`HORDE_BANNER_TOP_FRAC`) se sobrepõe ao painel do celeiro no topo.

Critérios de aceite:
- **HF6-A:** `--import` e depois `check_scripts`, `unit_tests`, `flow_test`, `playthrough` e
  `net_unit --only=hud_net,hud_hints,spectator` verdes, e `res://src/hud/debug/hud_horde_test.tscn` rodado direto
  (`tools/godot.sh --headless --fixed-fps 60 --path . res://src/hud/debug/hud_horde_test.tscn`, não está no `net_unit`)
  com `RESULT:` sem FAIL (os checks dos três sandboxes mudam só o nó lido).
  Nenhuma ocorrência de `_bottomright_margin`, `_ammo_label`, `_health_bar`, `_vest_label`, `TOUCH_BOTTOM_RIGHT_MARGIN_PX`
  ou `HORDE_AMMO_TEXT` em `src/`. Screenshots com janela, `--frames=600` (`tools/godot.sh --path . --windowed
  --resolution 1280x720 -s res://tools/screenshot.gd -- --scene=res://src/player/debug/player_sandbox.tscn --out=<png>
  --frames=600 <args>`):
  1. Padrão (carabina + espingarda, colete, kit, ceva, binóculo) com `--dog`: embaixo à direita o retrato da carabina,
     "Carabina .22", "10 | 50" em branco, fileira com "1" realçado e "2" apagado; embaixo no centro a faixa de vida de
     400 px com ícone do colete, "Colete", barra verde e "100", e a `Quickbar` logo acima sem encostar; nada no topo à
     esquerda além do FPS (se ligado).
  2. `--slot=2 --mag=1 --hp=25`: retrato e nome da espingarda, chip "2" realçado, pente "1" em vermelho, barra vermelha
     e "25".
  3. `--horde --weapons=carbine_22,shotgun_12,rifle_308,rifle_3006,rifle_338 --slot=5`: cinco chips de "1" a "5" na
     largura do painel, "5" realçado, retrato do .338, reserva "| ∞".
  4. `--weapons=rifle_308 --items=medkit`: sem fileira (uma arma), sem colete (barra mais larga), retrato do .308.
  5. Os itens 1 e 3 com `--touch=on` a 1558×720 e 960×720: painel da arma na coluna da esquerda (x ≈ 128–376 no
     canvas virtual, base em `A − 320`: y 400 a 1558×720, y 640 na janela 960×720, cujo canvas é 1280×960) sem tocar slider, joystick, fileira de botões de item nem faixa da dica; chips sem número; faixa de vida de
     300 px no centro-baixo sem tocar joystick, Agachar, Mira (e o nome dela com `--onboarding`) nem Tiro; FPS ao lado do
     Pausa. Repetir o 960×720 com `--onboarding --dog --items=medkit,scout_drone`: objetivos acima do painel da arma.
  6. Recarga: no sandbox com janela, atirar e apertar R: a barra âmbar aparece sob a munição e some no fim.
- **HF6-QA:** §12 (cobertura da Fase 6); as 4 suítes e o `net_unit` verdes com tudo entregue.
- **Coordenação (integração):** screenshot com janela de `src/hunt/hunt.tscn` a 1280×720 (`--frames=900`) com o
  loadout real: painel da arma, faixa de vida e `Quickbar` como no item 1; `load_ab.py --throttle=4` sem etapa acima de
  700 ms (comparar a etapa do jogador com a 0.8.3; se subir demais, aplicar a válvula de §13.1); `mobile_probe.py`
  verde (o layout do toque mudou, embora o probe não leia o painel).

### Frente HUD/gameplay — HF7: layout de toque estilo PUBG Mobile (contrato 1.6)
Só o modo toque muda (`InputSetup.is_touch_mode()`); o desktop fica idêntico. Contrato em §6.8 (`TouchControls`, `WeaponPanel`,
`HealthStrip`) e §8.4 ("Layout de toque estilo PUBG"). Nada muda em `project.godot`, `export_presets.cfg`, `data/`, `assets/`,
`Quickbar`, mecânica de jogo nem no protocolo de rede. Em Sonnet.

| Tarefa | Dono | Arquivos | Depende de |
|---|---|---|---|
| HF7-A — layout de toque (concluída) | game-developer (A) | `src/hud/touch/touch_controls.gd`, `src/hud/hud.gd`, `src/hud/weapon_panel.gd`, `src/hud/health_strip.gd` | — |
| HF7-QA (concluída) | game-developer (A) | `tests/lib/contract_sigs.gd`, `tests/unit/test_item_hud.gd`, `tests/unit/test_weapon_health_hud.gd`, `tests/web/mobile_probe.py` | HF7-A |

Critérios de aceite:
- **HF7-A:** `check_scripts`, `unit_tests`, `flow_test`, `playthrough` e `net_unit --only=hud_net,hud_hints,spectator` verdes;
  `hud_horde_test` e `hud_horde2_test` sem FAIL. Screenshots com janela (`player_sandbox`, `--touch=on --dog
  --items=medkit,corn_bait,scout_drone,binoculars,leather_vest --weapons=carbine_22,shotgun_12 --frames=600`) a 1532×720,
  1280×720 e 1280×960, cada um com a lista de acessórios aberta e com `--onboarding` (nomes); nada se sobrepõe. `--touch=off`: o
  desktop igual ao de antes (diferença de pixels só na animação da arma).
- **HF7-QA:** testes unitários dos dois Tiros (contagem de dedos), do bloco de baixo (números da foto a 1532), dos botões e da
  lista de acessórios (padrão, troca sozinha, escolher sem usar, seta só com 2+, piscar), dos cartões (toque, prioridade de botão),
  da ausência de sobreposição nas três telas, do chip do colete e dos cartões do `WeaponPanel`; `mobile_probe.py` com o fluxo
  novo (g7: Cura, Acessórios, cartões, dois Tiros; a lista e a troca de arma só rodam com loadout maior que o padrão).
- **Resíduos / divergências (HF7):** (1) com mais de duas armas (horda) os cartões mostram a arma na mão e a próxima do ciclo,
  porque o botão Troca saiu; (2) o texto das dicas de toque ("Toque no drone", "Toque na ceva") e do objetivo "(botão Drone)" não
  mudou: com a lista fechada o item pode estar atrás da seta, e a seta pisca nesse caso; (3) o slider de zoom foi para a coluna da
  esquerda acima do Tiro esquerdo, não à direita dele, para não cruzar o painel de objetivos; (4) o cão passou de br (235, 350)
  para (235, 346).

### Frente faca, mochila e fôlego — F1 a F4 (contrato 1.7, jogo 0.9.5–0.9.8; F1 publicada, F2–F4 pendentes)
Plano, contrato, pacotes por fase (arquivos, donos, modelos, fora de escopo, aceite), prompts de sessão e riscos em
`docs/plano_faca_mochila_folego.md`. Ordem: F1 Mochila → F2 Fôlego → F3 Energético (depende de F2) → F4 Faca (depende de
F1); uma fase por vez. Acréscimos a `src/core/` por fase na §2.1 de lá (F1 `Ids.BACKPACK`/`Ids.KNIFE`; F3
`Ids.I_ENERGY_DRINK`; F4 `HuntRequest.knife_level`, `WeaponViewBase.play_melee`, `NetCodec.KNIFE_WEAPON_INDEX`,
`PlayerBase.bot_knife`). `project.godot` muda só em `config/version`; `GameEvents` não muda.

---

## Apêndice A — `src/core/` (verbatim; coordenador copia, ninguém edita)

### Acréscimos 0.5.0 (Horda Javali) — já aplicados em `src/core/`

Os blocos de arquivo abaixo são a base 1.1; os acréscimos da F8 (`docs/multiplayer.md` §4.7.9) e estes da
horda já estão nos arquivos reais, que são a referência. Todos aditivos, com padrão seguro para o modo contrato.

```gdscript
# game_events.gd (depois de hunter_away_changed)
# Horde mode (docs/horda.md section 4). Only emitted when HuntWorld.is_horde().
signal horde_wave_changed(wave: int, wave_count: int, phase: StringName, countdown_s: float)   # B HuntController -> A Hud
signal horde_wave_progress(remaining: int, wave_total: int)                                   # B HuntController -> A Hud

# ids.gd (fim)
const MODE_CONTRACT: StringName = &"contract"
const MODE_HORDE: StringName = &"horde"
const HP_INTERMISSION: StringName = &"intermission"
const HP_WAVE: StringName = &"wave"

# scene_paths.gd (depois de HUNTER_VISUAL)
const BARN_CORN: String = "res://assets/models/props/barn_corn.tscn"   # horde corn stock (CornStockVisualBase)

# hunt_request.gd
var mode: StringName = &"contract"                    # Ids.MODE_CONTRACT | Ids.MODE_HORDE (docs/horda.md)
static func make_debug(p_map_id: StringName = &"mato_grosso", p_contract_index: int = 0, p_mode: StringName = &"contract") -> HuntRequest   # + r.mode = p_mode
func is_horde() -> bool:
	return mode == Ids.MODE_HORDE

# hunt_result.gd (crop_health_pct = estoque e contract_bonus = bônus de defesa na horda)
var mode: StringName = &"contract"
var horde_wave_count: int = 0
var horde_waves_cleared: int = 0
func is_horde() -> bool:
	return mode == Ids.MODE_HORDE
# to_dict() ganha "mode": String(mode), "horde_wave_count", "horde_waves_cleared"

# player_base.gd (depois de is_reloading)
func get_weapon_count() -> int:           # weapons carried (horde: every weapon of data/weapons.json)
	return 0
func has_infinite_reserve() -> bool:      # horde: reloading never spends the reserve (docs/horda.md section 7)
	return false

# hunt_world.gd (depois de get_result; padrões = modo contrato)
func get_mode() -> StringName:                 # Ids.MODE_CONTRACT | Ids.MODE_HORDE
	return &"contract"
func is_horde() -> bool:
	return get_mode() == Ids.MODE_HORDE
func get_objective_position() -> Vector3:      # horde: barn origin on the ground; Vector3.INF = no objective
	return Vector3.INF
func get_horde_wave() -> int:                  # 1-based wave being fought or announced; 0 = not horde
	return 0
func get_horde_wave_count() -> int:
	return 0
func get_horde_phase() -> StringName:          # Ids.HP_INTERMISSION | Ids.HP_WAVE; &"" = not horde
	return &""
func get_horde_countdown_s() -> float:
	return 0.0
func get_horde_wave_total() -> int:
	return 0
func get_horde_wave_remaining() -> int:
	return 0
func get_horde_waves_cleared() -> int:
	return 0
# (debug, depois de debug_force_end)
func debug_horde_start_next_wave() -> void:    # horde: ends the current intermission now; no-op otherwise / on a client
	pass

# net_codec.gd
const EV_HORDE_WAVE: int = 0x2C        # horde wave state (docs/horda.md section 9)
const MODES: Array[StringName] = [&"contract", &"horde"]              # mode u8 of L_LOBBY and L_START
const HORDE_PHASES: Array[StringName] = [&"intermission", &"wave"]    # phase u8 of EV_HORDE_WAVE
const MAX_BOARS_PER_HUNT: int = 255    # boar ids are u8 on the wire (1..255): total of a whole hunt
```

### Acréscimos 0.9.0 (Horda nível 2) — já aplicados em `src/core/`

Fonte: `docs/plano_horda_nivel2.md` §4.1. Todos aditivos, com padrão seguro para o modo contrato e o nível 1.
Única mudança de valor existente: `MASK_PLAYER_BODY` passa a incluir `FENCE`. Os arquivos reais são a referência.

```gdscript
# layers.gd
const FENCE: int = 16
const MASK_PLAYER_BODY: int = TERRAIN | STATIC | FENCE   # 19; MASK_WEAPON_RAY e MASK_LINE_OF_SIGHT não mudam

# game_events.gd (player_downed/player_revived/ammo_picked_up depois de dog_command_requested;
# hunter_downed/hunter_revived depois de hunter_away_changed)
signal player_downed(bleed_out_s: float)   # A Player -> A Hud; local
signal player_revived(health: float)       # A Player -> A Hud; local
signal ammo_picked_up(rounds: int)         # A Player -> A Hud; local
signal hunter_downed(slot: int)            # B HuntController -> A Hud/Spectator
signal hunter_revived(slot: int, by_slot: int)   # B HuntController -> A Hud

# hunt_request.gd
var horde_level: int = 1                   # só em horda
static func make_debug(p_map_id: StringName = &"mato_grosso", p_contract_index: int = 0, p_mode: StringName = &"contract", p_horde_level: int = 1) -> HuntRequest   # + r.horde_level = p_horde_level

# hunt_result.gd
var horde_level: int = 0                   # 0 no contrato
# to_dict() ganha "horde_level": horde_level

# player_base.gd (depois de is_reloading/get_weapon_count/has_infinite_reserve; bot_set_interact entre os hooks de bot)
func is_downed() -> bool:
	return false
func revive(_health: float) -> void:
	pass
func get_bleed_out_left_s() -> float:
	return 0.0
func needs_ammo() -> bool:
	return false
func add_ammo_mags(_mags: int) -> int:
	return 0
func get_revive_target_slot() -> int:
	return -1
func get_revive_progress() -> float:
	return 0.0
func bot_set_interact(_held: bool) -> void:
	pass

# hunt_world.gd (depois de get_horde_waves_cleared)
func get_horde_level() -> int:
	return 0
func get_player_bounds() -> Rect2:         # Rect2() = sem limite
	return Rect2()
func request_revive(_target_slot: int) -> void:
	pass
func get_ammo_crate_positions() -> PackedVector3Array:
	return PackedVector3Array()

# net_codec.gd
const EV_HUNTER_REVIVED: int = 0x2D        # target_slot u8, by_slot u8
const EV_AMMO_CRATE: int = 0x2E            # crate u8, available u8, taker_slot u8 (255 = ninguém)
const C_REVIVE: int = 0x45                 # target_slot u8
const C_AMMO_CRATE: int = 0x46             # crate u8
const HF_DOWNED: int = 128                 # flags de HUNTER_STATE, bit 7

# scene_paths.gd (depois de BARN_CORN)
const AMMO_CRATE: String = "res://assets/models/props/ammo_crate.tscn"
```

`src/core/corn_stock_visual_base.gd` (novo, `class_name CornStockVisualBase extends Node3D`): constantes
`STAGE_COUNT = 5`, `static func stage_for(pct: float) -> int` (0 se `pct <= 0`, senão `clampi(ceili(pct / 25), 1, 4)`),
`setup(ring_radius_m: float)`, `set_stock_pct(pct: float)`, `set_under_attack(on: bool)` e
`static func create_fallback() -> CornStockVisualBase` (6 cones amarelos no anel que encolhem por estágio). O
arquivo é a referência verbatim.

### Acréscimos 1.7 (faca, mochila e fôlego) — aplicados por fase em `src/core/`

Fonte: `docs/plano_faca_mochila_folego.md` §2.1. Todos aditivos. Os arquivos reais são a referência. F3 e F4 entram aqui no
fecho de cada uma.

```gdscript
# ids.gd (fim) — F1, jogo 0.9.5
# Upgrades bought with money (docs/plano_faca_mochila_folego.md). KNIFE is also HitInfo.weapon_id of a knife hit.
const BACKPACK: StringName = &"backpack"
const KNIFE: StringName = &"knife"
```

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
const LOADING_BOAR: String = "res://assets/ui/loading_boar.tscn"


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


func get_minimap_texture() -> Texture2D:      # 1.4: top-down image of the whole map rect (north up); null = none
	return null


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


func get_dog_target_position() -> Vector3:    # the living boar the local dog is after; INF = none (also on a network client)
	return Vector3.INF


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
