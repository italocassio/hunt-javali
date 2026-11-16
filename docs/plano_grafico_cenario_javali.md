# Plano: cenário e javalis em alto detalhe procedural

Continuação da frente gráfica que gerou a versão 0.6.0 (armas, braços e caçadores aliados HD).
Este arquivo é para a sessão principal que vai coordenar a próxima frente. Ele traz o que já foi decidido,
o que funcionou, o que custou caro e as etapas propostas. Não rederive o que está aqui.

## 1. O que já existe (0.6.0, commit 67096d7, no ar)

- **Armas em 1ª pessoa HD**, 100% procedurais: `assets/models/weapons/showcase/<id>_hd.gd` (5 armas),
  montadas em `assets/models/weapons/weapon_view.gd`. Entre 5 400 e 11 900 triângulos com braços, 4 malhas, até 4 materiais.
- **Ferramentas reaproveitáveis** em `assets/models/weapons/showcase/`:
  - `hd_mesh.gd`: lofts, bisel, normais suaves por ponto soldado, `section_ring`, `curve`, `bake_ao` (AO assado
    por raycast, **só em vértices côncavos**: foi isso que derrubou a montagem de 1,1 s para 136 ms).
  - Shaders: `hd_wood.gdshader` (veio com warp de domínio, quadriculado com fade e uniforms `warp_amount`,
    `ring_freq`, `ring_amount`, `smoke_amount`, `tone_amount`), `hd_hard.gdshader` (metal/plástico),
    `hd_lens.gdshader`, `hd_arms.gdshader` (tecido/luva/pele num material só, com id de feature em UV2.y).
  - Textura de ruído 512² compartilhada (`FastNoiseLite.get_seamless_image`, 114 ms, gerada uma vez).
  - `hd_view.gd`: base para renders de estúdio.
  - `arms_hd.gd`: braços com luva e IK simples (`reach`, `bolt_pose`, `pump_pose`, `mag_reach`).
- **FOV próprio da arma**: o nó `Gun` é escalado em (1, 1, k), k = 0,55, em torno do olho, o que equivale a
  ~46° só para a arma. Sem shader e sem SubViewport (§7.3).
- **Caçador aliado HD**: `assets/models/hunter/` (`hunter_rig.gd`, `hunter_body.gd`, `hunter_held.gd`,
  `hunter_visual.gd`).
  - Até 4 698 triângulos e 10 malhas, montagem em 47 ms.
  - Cor do slot por cor de vértice, com malha recolorida em cache por slot e nenhum material por jogador.
  - Partes rígidas, sem esqueleto.
- **Previews** em `assets/preview/`: `preview_weapons`, `preview_rifle_showcase` (`--gun=<id>`),
  `preview_arms_showcase`, `preview_hunters`. Já existem `preview_boars`, `preview_props`, `preview_map`,
  `preview_dogs` e `preview_water`, que servem de base para esta frente.
- **Medição de FPS**: `tests/web/perf_ab.py` compara duas builds Web no Chrome headless emulando celular, com
  GPU real, quadril e ADS, com e sem CPU 4x.

## 2. Decisões que continuam valendo

- 100% procedural: nada de Tripo3D, GLB, textura baixada ou malha pré-assada em binário no repositório.
- Visual: realista-estilizado de jogo mobile de caça, paleta do cerrado mato-grossense, tarde dourada.
- Modelos (o usuário é Pro; o limite de 5 h é o gargalo):
  - **Opus** onde a forma orgânica exige julgamento visual: javali, árvores, cães.
  - **Sonnet** para hard-surface (props), otimização, testes e publicação.
  - **Fable** não é usado nesta frente: decisão do usuário, que prefere Opus.
- Regras de custo para todo agente:
  - screenshots em no máximo 960×540;
  - abrir só as imagens necessárias;
  - no máximo 3 rodadas de ajuste visual por modelo;
  - preferir diferença de pixels (script) a abrir imagens quando o objetivo for "não mudou".
- A sessão principal revisa as imagens antes de aprovar cada etapa. Ninguém diz que ficou bom sem ter visto.
- O art-director escreve só em `assets/`. Mudança em `src/`, `tests/` ou `project.godot` é relatada, não feita.
  A sessão principal edita a doc (poucas linhas); mudança em teste vai para o qa-tester.
- Toda arte começa como **protótipo isolado** em preview. Só depois de aprovada entra no caminho do jogo.

## 3. Lições (o que custou caro ou deu errado)

1. **A medição de FPS levou 79 min** na primeira vez, por causa de rodadas de atribuição e ruído da máquina.
   Meça uma vez no início (linha de base) e uma no fim, com `perf_ab.py`, 1 rodada e limite de 20 min.
2. **O tempo de montagem procedural é custo real.** A primeira versão do .308 levava 1,1 s, contra o limite
   de 700 ms por etapa de carga (§13.1). Peça a cada agente o tempo de montagem a frio (`Time.get_ticks_usec`),
   com meta explícita. Para objetos que aparecem no meio da caçada (javalis), a meta é ainda menor.
3. **Confira os orçamentos do contrato antes de delegar.** O .308 ocupou quase todo o orçamento e os braços
   não cabiam; foi preciso enxugar a arma depois. Divida o orçamento entre as partes já no brief.
4. **O enquadramento importa mais que o modelo.** Os braços só ficaram bons depois do FOV próprio da arma.
   Se algo não ficar bom em 3 rodadas, pergunte se a causa é câmera, luz ou escala antes de pedir mais detalhe.
5. **A luz de fim de tarde distorce cores**: o amarelo vira laranja e o jeans fica escuro. Confira as cores
   na luz do jogo, não só no estúdio.
6. **Perigos com agentes:**
   - nunca `git stash` nem `git add -A`, porque há trabalho não commitado de outras sessões;
   - nunca matar processo por nome; um agente matou um Godot de outra sessão;
   - o modo automático bloqueia matar processos; peça ao usuário quando sobrar processo travado.
7. Pontos fracos já registrados (não bloqueiam):
   - o gatilho da 12 fica longe da mão;
   - na mira da .22, a coronha ocupa a parte de baixo da tela;
   - a mão direita não puxa a alavanca da .30-06;
   - a madeira mostra um pontilhado fino quando vista de longe;
   - falta aquecer armas e caçadores no menu (`src/`).

## 4. Problema de partida: o jogo já está abaixo de 30 fps

Na build Web, no Chrome emulando celular (DPR 3, canvas 2532×1170, qualidade "low" com render scale 0,75)
e com a GPU integrada Intel UHD deste PC, a caçada roda a **~27 fps (36 ms/quadro) com qualquer arma**,
já na 0.5.0. A cena está presa à GPU. O cenário HD não pode piorar isso; o ideal é melhorar.
Por isso a etapa 0 mede e descobre para onde vai o tempo de quadro antes de qualquer arte.

## 5. Etapas (uma por vez, validando cada uma antes da próxima)

### Etapa 0: linha de base e contrato (qa-tester, Sonnet; a doc é da sessão principal)
- Medir na build Web atual: tempo de quadro, draw calls, triângulos visíveis e o peso de cada sistema
  (terreno, flora por id, lavoura, javalis, props, água, céu/névoa, sombras), ligando e desligando cada um
  numa build de diagnóstico ou pelo hook `window.huntProbe`. Medir também o efeito do render scale e do DPR
  (suspeita: taxa de preenchimento/fill rate).
- Resultado: tabela "sistema → ms" e uma recomendação de onde há folga e onde não há.
- Com esses números, a sessão principal propõe ao usuário os novos orçamentos de §7.1, §7.4, §7.5, §7.6 e §13.1
  e atualiza a doc depois de confirmar. Pontos de partida, a ajustar pela medição:
  - **Javali**: LOD por distância com `visibility_range`.
    - Perto (≤ 25 m): ≤ 3 000 triângulos.
    - Médio: ≤ 900 triângulos.
    - Longe: ≤ 300 triângulos.
    - Malhas compartilhadas entre instâncias do mesmo tipo e 1 material por tipo.
    - Pior caso de 26 javalis visíveis dentro de ~40 mil triângulos.
  - **Props**: 3 a 4 vezes os limites atuais, porque são poucos e estáticos.
  - **Flora**: continua em `MultiMesh`. O ganho visual vem de shader (cor, vento, translucidez falsa,
    variação por instância) e de silhueta melhor, não de multiplicar triângulos de instâncias numerosas
    (grama e lavoura).
  - Texturas procedurais: mantenha a regra de 512², com exceção explícita quando houver.
- Conferir quais números estão em `tests/unit/test_assets.gd`. O que mudar nesse teste é do qa-tester.

### Etapa 1: Javali HD (art-director, Opus)
- Contrato §7.1: `boar_visual.tscn` / `boar_visual.gd`, nó `Head` e todos os métodos da tabela.
  - O modelo deve caber nas caixas de `BoarVisualBase.HIT_ZONES` (±5 cm).
  - Escala 1 = 100 kg.
  - Variações por tipo: leitão, fêmea, macho, alfa.
- Visual: javali-europeu/asselvajado do Brasil.
  - Corpo em cunha, cabeça grande e focinho comprido.
  - Crina dorsal, pelagem áspera (shader de pelo com ruído e direção, não fios) e presas.
  - Orelhas pequenas e eretas, rabo fino com tufo, cascos.
- Animação por partes rígidas: andar, trote, galope acima de 5 m/s, comer, mancar, alerta, raspar (telegrafa
  a investida), ataque, tranco e morte.
- Começar por um protótipo isolado (preview de estúdio e no mapa, ao lado do caçador HD para checar escala).
  Integrar só depois de aprovado.
- Metas de montagem: a frio ≤ 40 ms por tipo no desktop e ≈ 0 em cache. Javalis nascem no meio da caçada,
  então a malha é compartilhada entre instâncias.
- Aceite:
  - previews de cada tipo parado, andando, galopando, raspando, atacando e morto;
  - uma imagem a 10, 30 e 60 m (LOD);
  - `check_scripts`, `unit_tests`, `flow_test` e `playthrough` passam.
- Depois, se o usuário quiser, cães (§7.2) no mesmo padrão, em Opus.

### Etapa 2: Props (art-director, Sonnet)
- Itens: `farmhouse`, `barn`, `water_tank`, `fence_segment`, `gate`, `corn_bait`, `feed_trough` e `barn_corn` (§7.4, §7.12).
- Dimensões são contrato (±10%), porque a colisão vem delas.
- Reusar `hd_mesh.gd` e os shaders.
  - Alvenaria caiada com barra suja, telha cerâmica, madeira envelhecida e zinco.
  - Desgaste e AO assado só nas regiões côncavas.
- Uma ou duas peças por tarefa, começando pela `farmhouse` (a "casa chapada" é o que mais destoa).

### Etapa 3: Flora (art-director, Opus para árvores; Sonnet para grama e lavoura)
- Ids (§7.5): `cerrado_tree`, `ipe`, `buriti`, `shrub` (os "arbustos em bloco"), `termite_mound`, `grass_tuft`,
  `soy_*` e `corn_*`.
- Respeitar `MultiMesh`, `visibility_range` e o shader de vento (`assets/shaders/foliage_wind.gdshader`).
- Cuidado com alpha scissor e transparência em celular (overdraw). Prefira geometria de silhueta com
  normais "infladas" para a copa parecer volumosa.

### Etapa 4: Terreno, água e ambiente (Sonnet; Opus se travar no visual)
- `terrain.gdshader`: capim do cerrado, terra vermelha, lavoura e margem úmida (§7.6), com macro-variação e
  detalhe perto.
- `water.gdshader`.
- `mato_grosso_env` (§7.7): céu, névoa e luz de tarde dourada.
- É barato em triângulos e caro em fragmento. Medir.

### Etapa 5: Medição final e publicação (Sonnet)
- Rodar `perf_ab.py` uma vez, comparando a versão publicada com a nova.
- Subir `config/version` (a 0.6.0 é a atual) e registrar em `docs/changelog.md`.
- Commit por caminho.
- Build e testes em worktree limpo; rodar `mobile_probe.py`.
- Publicar no `gh-pages` e conferir o `Content-Length` de `index.pck` no ar.
- Siga a memória `publish-from-clean-worktree`: ela já tem o passo a passo e as armadilhas.

## 6. Brief padrão para cada agente (copiar e adaptar)
- Arquivos envolvidos, o que fica fora do escopo e critérios de aceite.
- Decisões já tomadas, para o agente não rederivar.
- Orçamento: triângulos, malhas, materiais e tempo de montagem.
- Caminho dos screenshots: `C:\Users\adrie\AppData\Local\Temp\<pasta>\`, em 960×540. O agente informa quais olhou.
- Testes a rodar e resultado de cada um.
- Proibições:
  - `git stash`, `git add -A`, commit (a sessão principal faz);
  - matar processo por nome;
  - editar `project.godot` ou `export_presets.cfg`.
