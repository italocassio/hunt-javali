# Plano: HUD e onboarding de gameplay (estilo PUBG)

Retomada em sessão nova. Leia isto, `CLAUDE.md` e o contrato (`docs/arquitetura.md`, versão 1.3). Não rederive
o que está aqui.

## Por quê
Nos testes com usuários, ninguém soube usar o cão, o kit e o drone. A referência é o HUD do PUBG:
bússola com graus e marcadores, minimapa real, legenda de teclas, lista de objetivos e painel da arma com
retrato.

## Decisões do usuário (fixas)
- Teclas fixas: Q kit, G ceva, V drone, B binóculo, E cão, F troca de caçador no espectador.
- O minimapa fica no alto à direita, no desktop e no toque.
- Dicas, legenda e objetivos só nas **3 primeiras caçadas** (`onboarding.max_hunts` em `game.json`).
- Cada fase vira uma versão (0.8.x). A barra nova já foi aprovada; o usuário não precisa aprovar screenshots,
  mas o coordenador revisa antes de integrar.
- Não há mais Fable: o caminho crítico roda em **Opus** e a rotina em **Sonnet**.

## Feito: 0.8.0 (publicada em 20/11/2026, main 71ced48, gh-pages dd2335e)
- Fase 1: `Quickbar` (`src/hud/quickbar.gd`) com um espaço por item mais o cão; botões de item no toque
  (`touch_controls.gd`); `ItemBelt.use_item(id)` no lugar da seleção; teclas na Preparação (`loadout_panel.gd`).
- Fase 2: `HintDirector` + `HintBanner` (`src/hud/hint_*.gd`); `Profile.is_onboarding_active/is_hint_learned/
  mark_hint_learned`; `onboarding.learned` no save; `?hints=0` na Web; sandbox `src/hud/debug/hud_hints_test.tscn`
  (registrado em `tests/net_unit.gd`).
- Contrato 1.3: §4, §6.8, §8.4, §8.11, §9.1, §10 e tarefas HF* em §14.

## Feito: 0.8.1 (publicada em 20/11/2026, main e6c79bd, gh-pages f480b1b, index.pck 7 195 676 B)
- Fase 3: `DogCard` (`src/hud/dog_card.gd`) com retrato SVG da raça, estado, vida e ação ("E: Pega!"/"E: Volta!",
  "Botão Cão:" no toque); `Dog.get_target_position`, `HuntWorld/HuntController.get_dog_target_position` (INF no
  cliente de rede); anel do alvo na bússola e no minimapa. Contrato: o game-developer atualizou junto (sem
  rodada do architect), HF3 em §14. O probe não tem cão no loadout padrão, então não cobre o cartão.

## Feito: 0.8.2 (publicada em 20/11/2026, main ae63573, gh-pages 244f73e, index.pck 7 212 104 B)
- Fase 4: `ObjectivesPanel` (`src/hud/objectives_panel.gd`, à esquerda: cão, drone, abates k/N, lavoura > P%) e
  `ControlsLegend` (`src/hud/controls_legend.gd`, à direita, H recolhe em "H: Ajuda"); ação `help` (H);
  `TouchControls.set_action_labels`; `onboarding.objective_kills`/`objective_crop_min_pct` em `game.json`.
  Na horda só a legenda; tudo some no espectador/queda; `?hints=0` desliga também. Sandbox: `--onboarding`,
  `--hunts=N`, `--help_key`, use `--frames=600`. Contrato: o game-developer atualizou junto (HF4 em §14).

## Feito: 0.8.3 (publicada em 20/11/2026, main fdd3bff, gh-pages 46f5aca, index.pck 7 239 980 B)
- Fase 5: bússola 480×54 com graus, N/NE/L/SE/S/SO/O/NO e rumo no centro; `MapMarkers` (`src/hud/map_markers.gd`)
  é a fonte única de forma/cor (ceva hexágono turquesa, revelados salmão, marcado triângulo); `MinimapBaker`
  (`src/world/minimap_baker.gd`) gera a imagem do mapa uma vez na etapa `minimap` (desktop ~10 ms, Web throttle 4:
  107 ms); bloco `minimap` em `game.json`. Preparação sem teclas de atalho (nem na frase do cão).
  Contrato 1.4 pelo game-architect (Opus) antes e depois; implementação em Sonnet. Sandbox: `--minimap_tex`,
  `--marked`, `--bait`, `--reveal`, `--heading=`, `--crop_alert`. Resíduo aceito: dica + aviso da lavoura +
  contexto juntos encostam ~6 px em 16:9.

## Feito: 0.8.4 (publicada em 20/11/2026, main ffc559d, gh-pages 7874fa5, index.pck 7 255 292 B)
- Fase 6: `WeaponPanel` (`src/hud/weapon_panel.gd`: retrato, nome, munição grande, fileira 1–5 só com 2+ armas,
  sem números no toque) e `HealthStrip` (`src/hud/health_strip.gd`: vida larga embaixo no centro, colete como
  ícone); `Quickbar` sobe para logo acima da vida; no toque o painel da arma vai para a coluna da esquerda.
  `Player.get_weapon_ids/debug_set_health`; sandbox `--hp=`, `--slot=`, `--mag=`. Contrato 1.5 pelo game-architect
  (Opus) antes e depois. Toque 4:3 usa canvas virtual 1280×960. mobile_probe 76 ok; load_ab throttle 4:
  player_ms 3340. Resíduos: faixa da horda sobre o painel do celeiro (anterior à fase); mensagem longa do cão
  em 4:3 pode encostar no painel da arma.

**Plano concluído: as 6 fases estão publicadas.**

## Falta (em ordem)
| Fase | O quê | Arquivos prováveis | Modelo |
|---|---|---|---|
| ~~4~~ | (feita em 0.8.2) Objetivos à esquerda (mandar o cão, usar o drone, abater 3, lavoura > 50%) + legenda de teclas à direita, recolhível em "H: Ajuda"; no toque, legendas nos botões. Só nas 3 primeiras caçadas | `src/hud/` novo, `input_setup.gd` (ação `help`), `game.json` | Sonnet |
| ~~5~~ | (feita em 0.8.3) Bússola com graus, NE/NO/SE/SO e marcadores (lavoura, cão, aliados, ceva, javalis revelados); minimapa com imagem de cima do mapa real, gerada uma vez ao carregar | `compass.gd`, `minimap.gd`, `src/world/` | **Opus** (pesa no celular) |
| ~~6~~ | (feita em 0.8.4) Painel da arma com retrato (`assets/ui/weapons/<id>.png`) e munição grande, fileira de armas 1–5; vida em barra larga embaixo, no centro | `hud.gd` | Sonnet |

## Como rodar cada fase (o que funcionou na 0.8.0)
1. **game-architect (Opus)** atualiza `docs/arquitetura.md` com as decisões já passadas no prompt e devolve
   a divisão em tarefas por agente, com arquivos e dependências. Ele só edita a doc.
2. Em paralelo, cada agente na sua pasta: game-developer (`src/hud`, `src/player`, `src/input`), game-systems
   (`data/`, `src/systems`, `src/ui`), art-director (`assets/`).
3. qa-tester (Sonnet): `check_scripts` e `contract_sigs` com as classes novas, testes unitários e sandbox no
   `net_unit`.
4. O coordenador revisa os screenshots (`tools/screenshot.gd`, `player_sandbox.tscn --items=... --dog
   [--touch=on]`), sobe `config/version`, escreve em `docs/changelog.md` e faz o commit **por caminho**.
5. Publicação (qa-tester, Sonnet): worktree limpo, 4 suítes + `net_unit`, export e `mobile_probe.py`
   (o build fica no worktree, via `JAVALI_BUILD_DIR`), push na main, gh-pages, conferência do Content-Length.
   Siga a memória `publish-from-clean-worktree`.

## Cuidados
- A árvore tem trabalho de outras sessões (`README.md`, `export_presets.cfg`, `.vscode/`): nunca use
  `git add -A`.
- O `mobile_probe.py` navega os menus por coordenadas fixas (`enter_hunt`). Redesenho de menu quebra o probe.
- A dica cruza a área do diff de pixel da mira: o probe usa `?hints=0`.
- Depois de criar um `class_name` novo, rode `--import` antes do `check_scripts`.
- Prompts curtos, com a tarefa §14 do contrato, os arquivos permitidos, o que fica fora e o aceite. Não mande
  o agente explorar.
