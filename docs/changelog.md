# Histórico de versões

O número da versão fica em `config/version` no `project.godot` e aparece na tela inicial e no menu.
A entrada mais nova fica no topo.

## 0.9.10 — 23/11/2026

**Agora dá para ver o que a sua mão está fazendo.** Curar, beber, soltar o drone e jogar a ceva deixaram de ser
instantâneos e viraram gestos na tela, como já acontecia com a arma e a faca.
- **Kit de primeiros socorros:** o caçador abaixa a arma, atravessa o braço na frente do rosto e **enrola o
  curativo** antes de a vida subir.
- **Energético:** a lata sobe até a boca e o caçador **bebe em dois goles**; o fôlego só enche no último gole.
- **Drone batedor:** sai **das duas mãos** e vai embora voando — sobe, dá uma volta larga pela área e some no fim
  dos 10 segundos. Os seus companheiros de caçada também o veem no céu.
- **Ceva de milho:** a mão recua e **joga a espiga**; o monte cai onde você estava olhando na hora do arremesso.
- Enquanto o gesto acontece você **não atira, não mira, não recarrega e não troca de arma** — mas continua andando
  e olhando à vontade. São gestos curtos: a ceva leva menos de um segundo, o drone pouco mais, o kit e o
  energético um segundo e meio.
- Se você morrer, cair ou cancelar antes da hora, **o item não é gasto**.
- Se a faca estiver na mão, ela volta sozinha para a cintura antes do gesto, e no fim quem volta é a arma.
- Nada mudou no que cada item faz: cura, fôlego, tempo de revelação do drone, duração da ceva e preços são os
  mesmos.

## 0.9.9 — 23/11/2026

**A faca agora fica na mão.** A pedido do dono do jogo, a faca deixou de ser um golpe avulso e virou uma arma de verdade.
- **X** passa a *pegar* a faca, e ela fica na mão até você guardá-la. Para golpear, use o **clique do mouse**, igual
  a atirar. No celular é o mesmo: o botão **Faca** pega a faca, e o botão **Tiro** golpeia.
- Para voltar à arma, use o atalho de sempre (**1**, **2** ou a troca de arma). Apertar **X** de novo também guarda
  a faca. No celular, basta tocar num cartão de arma.
- É um golpe por clique: segurar o botão não sai golpeando sem parar.
- O painel do canto mostra **"Faca"**, sem munição, enquanto ela está na mão, e volta para a arma quando você a guarda.
  No celular o botão Faca fica aceso enquanto a faca está na mão.
- Com a faca na mão não dá para mirar, recarregar nem usar o binóculo. Ao morrer, cair ou ser levantado, o caçador
  volta com a arma na mão.
- Alcance, cadência, dano por nível e o silêncio do golpe continuam os mesmos da 0.9.8.

## 0.9.8 — 23/11/2026

**Faca de caça.** Todo caçador já entra na mata com uma, sempre na cintura.
- Um golpe rápido de perto, sem trocar de arma: a espingarda some, a faca corta e a arma volta à mão. No teclado
  é a tecla **X**; no celular, o botão **Faca**, à direita da tela.
- Não ocupa espaço da mochila nem um dos seus slots de arma. É silenciosa: o javali só reage se for atingido.
- Alcance de 2,2 m, pouco menos de dois golpes por segundo. Acerto na cabeça ou nos vitais corta muito mais fundo,
  como no tiro.
- Na Loja, no topo da aba Armas, dá para afiar a faca em 4 níveis: dano 30, 45, 65 e 90 por golpe, por
  R$ 1.500, R$ 4.000 e R$ 8.000. No nível 1 ela já resolve quase todo leitão; no nível 4, fêmeas e machos
  de até 128 kg. Cachaço continua pedindo três golpes ou mais.
- Serve bem no javali que o cão acuou ou agarrou, e quando a arma está recarregando — o golpe cancela a recarga.
- Vale no contrato, na horda e no cooperativo.

## 0.9.7 — 23/11/2026

**Energético.** Um consumível novo na Loja, para quem ficou sem fôlego.
- Custa R$ 150 e enche o fôlego na hora: o caçador sai do cansaço e volta a correr na mesma hora.
- Dá para levar até 3 por caçada. Ocupa um espaço da mochila, como o kit de primeiros socorros.
- No teclado é a tecla **T**, com espaço próprio na barra de itens. No celular ele entra na lista do botão
  Acessórios.
- Quando o fôlego acaba e você tem um energético, ele pisca sozinho: no celular o botão Acessórios já troca para
  ele, e um toque basta para beber. Ao recuperar o fôlego, o botão volta ao acessório de antes.
- Com o fôlego cheio ele não é gasto à toa: o jogo avisa e guarda a lata.

## 0.9.6 — 23/11/2026

**Fôlego.** Correr agora cansa.
- Dá para correr cerca de 10 segundos seguidos. Uma faixa azul fina, logo abaixo da barra de vida, mostra o fôlego e
  some quando ele está cheio.
- Com o fôlego zerado o caçador fica sem fôlego: só anda, faz barulho de caminhada e respira ofegante. A faixa fica
  vermelha, com uma marca de onde ele volta a correr.
- O fôlego começa a voltar 1 segundo depois de parar de correr. Com 35% o caçador volta a correr sozinho, se você
  continuar segurando Shift ou o analógico.
- Vale no contrato, na horda e no cooperativo. Ao ser levantado na horda, o fôlego volta cheio.

## 0.9.5 — 23/11/2026

**Mochila.** Uma melhoria nova na Loja, no topo da aba Equipamentos.
- A mochila define quantos equipamentos você leva para a caçada: 3 no nível 1 (o de hoje), 4, 5 e 6 no nível máximo.
- Cada nível custa R$ 2.000, R$ 5.000 e R$ 10.000. A compra é permanente.
- Na Preparação, o título mostra o nível da mochila e quantos espaços você tem. Com a mochila cheia, o aviso lembra
  que dá para comprar uma maior.
- Quem já joga começa com a mochila nível 1: nada muda no seu equipamento salvo.

## 0.9.4 — 21/11/2026

**Cães em alto detalhe.** Os três cães foram refeitos no mesmo padrão do javali e do cenário.
- Vira-lata Caramelo esguio de orelhas semi-eretas, Foxhound tricolor de pernas longas e orelhas caídas, Dogo
  Argentino branco e musculoso de cabeça larga.
- Pelagem com sombreamento, olhos, trufa e patas de verdade; correm, apontam, latem, mordem e recuam com mais vida.
- Ficam nítidos de perto e leves de longe, inclusive vistos pela luneta.

## 0.9.3 — 21/11/2026

**Horda: correções e ondas maiores.**
- Os javalis não entram mais dentro dos montes de milho do celeiro: comem pela beira (Níveis 1 e 2).
- O cão não fica mais preso dentro do celeiro: entra e sai pela frente e volta a seguir o caçador.
- Cada onda da horda traz 50% mais javalis (85 para 128 na partida solo). Em grupo o aumento é um pouco menor.
- Celular: o botão de agachar mostra uma pessoa agachada; o de recarregar ganhou os cartuchos na seta.

## 0.9.2 — 21/11/2026

**iPhone: tela cortada e aparelho quente.**
- Jogo salvo na tela inicial do iPhone: ao girar o celular de em pé para deitado, a tela não fica mais com uma faixa
  preta em cima empurrando o jogo para baixo. Apague o ícone e adicione de novo para valer.
- Nova opção nas configurações: "Economia de bateria (30 fps)". Vem ligada no celular e desligada no computador.
  Limita o jogo a 30 quadros por segundo, o que esquenta bem menos o aparelho.
- Os menus usam menos resolução em telas muito densas (como a do iPhone), sem perder nitidez visível.

## 0.9.1 — 20/11/2026

**Celular: botões no lugar do PUBG.** No computador nada muda.
- Dois botões de tiro, um de cada lado da tela. O joystick sobe um pouco para a direita.
- As duas armas viram cartões embaixo, no centro, logo acima da barra de vida. Toque no cartão da outra arma para
  trocar (sai o botão Troca).
- Kit à esquerda das armas; colete com a redução de dano ("35%") ao lado da barra de vida.
- Ceva, drone e binóculo num botão só, à direita das armas. A setinha abre a lista para escolher qual fica no botão.
- Recarregar e agachar no canto de baixo à direita; mira acima do tiro direito, abaixo do cartão do cão.
- O controle de zoom da luneta fica acima do tiro esquerdo.

## 0.9.0 — 20/11/2026

**Horda: correções e Nível 2.**

Correções da Horda (valem nos dois níveis):
- A bala passa entre os arames da cerca, e os javalis enxergam através dela. No modo Contrato nada muda.
- Os javalis contornam o milharal em vez de atravessá-lo, então dá para vê-los chegando.
- Dá para entrar no celeiro. O milho fica numa tulha de madeira no fundo.
- O início de cada onda toca uma sirene.

Nível 2 (o anfitrião escolhe "Nível 1" ou "Nível 2" na sala da horda):
- Munição contada: cada arma começa com o pente e mais 2 pentes. Três caixas de cartuchos no celeiro dão mais
  2 pentes em cada arma e voltam depois de 60 s. Para pegar, aperte F (no celular, o botão "Pegar") ao lado da caixa.
- Ninguém sai do cercado da fazenda.
- Os javalis são mais agressivos: fêmeas investem quando provocadas, o alcance e o dano sobem e o aviso antes
  da investida é mais curto.
- Quem cai pode ser levantado por um companheiro, que segura F (ou "Levantar") por 4 s ao lado; volta com 50 de
  vida. Sem ajuda, morre de vez em 60 s. Sozinho na sala, cair é derrota.
- Prêmios do Nível 2: abate × 0,5 e bônus de vitória de até R$ 5000.

Detalhes técnicos: contrato horda 2.0 em `docs/plano_horda_nivel2.md`; camada de colisão 5 `fence`;
`data/horde.json` versão 2 com `levels`; classes novas `HordeRoute` e `HordeAmmoCrates`; `horde_level` no
`HuntRequest`, `HuntResult`, `L_LOBBY` e `L_START`; `HF_DOWNED`, `C_REVIVE`, `C_AMMO_CRATE`, `EV_HUNTER_REVIVED`,
`EV_AMMO_CRATE`; ação de entrada `interact` (F); sirene gravada com ElevenLabs em `assets/audio/sfx/horde_wave_start.mp3`.

## 0.8.4 — 20/11/2026

**Painel da arma com retrato e barra de vida embaixo.**

- No canto inferior direito, o painel da arma mostra o retrato e o nome da arma na mão e a munição em números
  grandes (pente | reserva). Pente baixo fica vermelho; na horda a reserva aparece como ∞.
- Com duas armas ou mais, uma fileira mostra todas com a tecla de cada uma (1 a 5) e realça a que está na mão.
- A vida saiu do canto superior esquerdo e virou uma barra larga embaixo, no centro, com o número e o colete
  quando equipado. A barra muda para âmbar e depois vermelho conforme a vida cai. A barra de itens subiu e fica
  logo acima dela.
- No celular, o painel da arma fica na coluna da esquerda, acima do joystick, e a fileira não mostra números.
- No espectador, o painel da arma some; a vida continua visível.

Detalhes técnicos: contrato 1.5 em `docs/arquitetura.md` §2, §4, §6.8, §7.9, §8.4, §12, §13.1 e §14 (HF6);
classes novas `WeaponPanel` e `HealthStrip` (`src/hud/`); `Player.get_weapon_ids()`; flags `--hp=`, `--slot=` e
`--mag=` no sandbox.

## 0.8.3 — 20/11/2026

**Bússola com graus e marcadores; minimapa com o mapa de verdade.**

- A bússola mostra os graus a cada 15°, os pontos cardeais e colaterais (N, NE, L, SE, S, SO, O, NO, com o N em
  vermelho) e o rumo atual em graus no centro.
- Na bússola e no minimapa, cada coisa tem forma e cor próprias: lavoura (quadrado verde), cão (círculo âmbar),
  o javali que o cão persegue (anel âmbar), aliados (losango), ceva (hexágono turquesa), javali marcado
  (triângulo vermelho) e javalis revelados pelo drone (círculo salmão).
- O minimapa agora mostra uma imagem de cima do mapa real, com relevo, açude, estrada, sede, talhões com as
  linhas de plantio e as árvores. A imagem é gerada uma vez ao carregar a caçada, sem custo durante o jogo.
- Na Preparação, os equipamentos não mostram mais a tecla de atalho.
- A mensagem de contexto desceu um pouco para não cobrir o aviso "Javalis na lavoura!".

Detalhes técnicos: contrato 1.4 em `docs/arquitetura.md` §6.8, §6.9, §8.1, §8.4, §9.1 e §14 (HF5); classes novas
`MapMarkers` (`src/hud/`) e `MinimapBaker` (`src/world/`); etapa `minimap` no carregamento; bloco `minimap` em
`data/game.json`.

## 0.8.2 — 20/11/2026

**Objetivos e legenda de teclas nas primeiras caçadas.**

- À esquerda, uma lista de objetivos: mandar o cão atacar, usar o drone (só quando você tem cão ou drone),
  abater 3 javalis com o progresso e manter a lavoura acima de 50%. Cada objetivo cumprido fica marcado.
- À direita, abaixo do cartão do cão, a legenda das teclas (mover, atirar, recarregar, correr, agachar, armas,
  os seus itens e o cão). A tecla H recolhe a legenda em "H: Ajuda" e abre de novo.
- No celular não há legenda de teclas: todo botão de ação mostra o nome embaixo.
- Tudo isso aparece só nas 3 primeiras caçadas e some quando você cai ou vira espectador. Na horda, só a
  legenda aparece.

Detalhes técnicos: contrato em `docs/arquitetura.md` §4, §6.8, §8.4, §9.1 e §14 (HF4); classes novas
`ObjectivesPanel` e `ControlsLegend` (`src/hud/`); ação `help` (H); `onboarding.objective_kills` e
`objective_crop_min_pct` em `data/game.json`.

## 0.8.1 — 20/11/2026

**Cartão do cão: quem é, o que está fazendo e o que a tecla faz agora.**

- O painel do cão virou um cartão com o retrato da raça, o nome, o estado em cores (seguindo, procurando,
  apontando, acuando, segurando, ferido, voltando) e a vida.
- Uma linha mostra a próxima ação: "E: Pega!" quando o cão está do seu lado, "E: Volta!" quando está atrás de
  um javali, e "Ferido: voltando" quando ele não obedece. No celular aparece "Botão Cão:".
- O javali que o cão está perseguindo ganha um anel na bússola e no minimapa.
- Limitação: em rede, só o anfitrião vê o anel do alvo do cão.

Detalhes técnicos: contrato 1.3 (jogo 0.8.1) em `docs/arquitetura.md` §6.8, §8.4, §8.10 e §14 (HF3); classe
nova `DogCard` (`src/hud/dog_card.gd`); `Dog.get_target_position()` e `HuntWorld.get_dog_target_position()`.

## 0.8.0 — 20/11/2026

**Barra de equipamento e dicas para quem está começando.**

- Barra de equipamento embaixo, no centro: cada item tem o seu espaço, com ícone, quantidade e tecla própria
  (Q kit, G ceva, V drone, B binóculo, E cão). Acabou o "trocar item com F".
- No celular, cada item ganhou o seu botão, com nome e contador; o botão do cão agora diz "Cão".
- Dicas na hora certa nas 3 primeiras caçadas: vida baixa ("Q: Curar"), javali à vista com o cão do lado,
  muito tempo sem achar javali (drone) e javalis na lavoura (ceva). Depois que o jogador usa a ação, a dica não
  volta mais.
- A tela de preparação mostra a tecla de cada item e a do cão.
- Ícones dos itens redesenhados para ler bem em tamanho pequeno.
- No modo espectador, F continua trocando de caçador.

Detalhes técnicos: contrato 1.3 (`docs/arquitetura.md` §4, §6.8, §8.4, §8.11, §9.1, §10); classes novas
`Quickbar`, `HintDirector` e `HintBanner`; `ItemBelt.use_item(id)` substitui a seleção; save ganha
`onboarding.learned` (sem mudar a versão do save); `?hints=0` desliga as dicas na Web.

## 0.7.4 — 19/11/2026

**Todos os menus no estilo cinematográfico, e retratos das armas.**

- Loja, escolha de mapa, preparação, sala de amigos, resultado, doação e configurações com fundo pintado do
  cerrado, título grande com filete âmbar, carteira em pílula e botões inclinados com ícones.
- Resultado com título dourado na vitória e vermelho na derrota, total em destaque e estatísticas com ícones.
- Retratos das cinco armas na loja e na escolha de armas da preparação.
- Configurações: as linhas de liga/desliga usam o mesmo cartão das outras.

Detalhes técnicos: retratos em `assets/ui/weapons/<id>.png` (1024×512, fundo transparente), renderizados dos
modelos HD procedurais por `tools/render_weapon_art.gd`, importados como WebP com perda e mipmaps (~300 KB no
total); fallback para o ícone SVG. Tema global refeito (botões, cartões, controles base) e ícones novos de rodapé.

## 0.7.3 — 19/11/2026

**Menu novo, estilo pôster, com fundos pintados do cerrado.**

- Menu principal refeito: logo "Caçada ao Javali" com sol e cabeça de javali, botões inclinados com ícones
  (Jogar em destaque), barra de dinheiro/ouro com atalhos de perfil e configurações, e cartão de perfil do
  caçador com as estatísticas reais.
- Fundos pintados do cerrado na tela inicial, no menu, na escolha de mapa e na preparação da caçada.
- Botões e painéis com a nova paleta: preto quente translúcido, bordas âmbar, ação principal em laranja.
- Botão "Sair" no menu fora do navegador (desktop e Android).

Detalhes técnicos: os dois fundos (`assets/ui/*_cerrado.png`) são a única arte raster do projeto, fornecida pelo
dono do jogo, importados como WebP com perda (~690 KB no total, antes 5,4 MB). Logo, ícones e fonte de destaque
(`FontVariation` da fonte padrão) continuam procedurais. `UiKit.add_background` / `build_page(..., background_path)`
com fallback para o fundo chapado.

## 0.7.2 — 19/11/2026

**Tela de carregamento nova: javali correndo e porcentagem.**

- Um javali galopa sobre a barra de progresso e a porcentagem mostra quanto falta.
- A tela de carregamento só some com a cena pronta: acabou o congelamento de vários segundos logo
  depois que a caçada aparecia. O navegador prepara terreno, água, construções, árvores, javalis e cão
  aos poucos, atrás da tela de carregamento.
- O jogador só se move e atira depois que a tela some.
- Caçada em grupo: o anfitrião espera até 45 s (antes 25 s) por um celular que ainda está carregando.

Detalhes técnicos: `ShaderWarmup` revela o mundo por partes, mostra cada tipo de javali e cão diante da câmera e
gira a câmera antes de liberar o overlay; `LoadingProgress` usa `loading.step_weights` de `data/game.json`;
`prop_builder.gd` carrega os props HD sob demanda (−35 ms). Medição (Chrome emulando celular, CPU 4x, cache frio):
nenhum quadro > 150 ms depois do overlay sumir (antes, trava de ~6 s); maior quadro preso no overlay ~10 s
(antes ~33 s). O tempo total da primeira carga não mudou: é compilação de shader, que agora acontece atrás da tela.

## 0.7.1 — 19/11/2026

**Javalis com olhos.**

- Os olhos dos javalis estavam enterrados na cabeça e não apareciam. Agora têm brilho e pálpebra mais clara,
  visíveis de perto e na luneta; de média distância o olho vem pintado.

Detalhes técnicos: `head_x_at` invertia errado a seção da cabeça; o contrato §7.1 registra que o LOD do javali
acompanha o zoom. Medição de carga 0.6.1 × 0.7.0 (`tests/web/load_ab.py`): a caçada da 0.7.0 demora mais na
primeira abertura sobretudo por compilação de shaders novos (~80%) e montagem procedural (~20%); com o cache de
shader do navegador, a diferença cai para ~1,5 s em CPU 4x.

## 0.7.0 — 18/11/2026

**Cenário e javalis em alto detalhe, 100% gerados por código.**

O que mudou para o jogador:

- Javalis refeitos: corpo em cunha com corcunda e crina de cerdas, cabeça longa, presas, pelagem áspera.
  Leitão listrado, fêmea marrom-acinzentada, macho escuro e alfa quase preto, com mais detalhe de perto
  e versões leves de longe.
- Sede da fazenda, galpão, caixa d'água, cerca, porteira, ceva, cocho e estoque de milho refeitos:
  reboco caiado, telha, madeira envelhecida, zinco com ferrugem.
- Árvores novas: pequizeiro retorcido com casca de cortiça, ipê-amarelo florido e buriti com folhas em leque,
  com vento e brilho no contraluz do fim de tarde. Moitas, cupinzeiros, capim, soja e milho também refeitos.
- Chão com capim seco e verde, estrada de terra vermelha, sulcos na lavoura e açude que reflete o céu e o sol.
- Desempenho igual ou melhor que a 0.6.1 (teste com celular emulado).

Detalhes técnicos: orçamentos por LOD no contrato (§7.1, §7.4, §7.5, §7.6, §13.1); 1 material para todos os
props; terreno com 3 leituras de textura no lugar de ruído procedural; javalis aquecidos na carga da caçada;
o LOD do javali acompanha o zoom da luneta. Medição (Chrome emulando celular, preset low): quadro igual em
x1 (~13–15 ms), igual ou melhor em CPU 4x; 140–147 draw calls, ~181 k triângulos.

## 0.6.1 — 16/11/2026

**Caçada muito mais leve no celular.**

O que mudou para o jogador:

- A caçada roda bem mais fluida: no teste com celular emulado, de ~26 para ~69 quadros por segundo.
- A imagem da caçada usa no máximo 1,5x a densidade de pixels da tela na qualidade baixa (2x na média e alta),
  em vez de renderizar o 3D menor e esticar. Menus continuam na nitidez total.
- A tarde dourada foi reequilibrada na luz, no céu e na névoa, sem o filtro de cor de tela cheia.

Detalhes técnicos: `render_scale` 1,0 em todos os presets e `max_pixel_ratio` novo por preset (`data/game.json`, limitado só durante a caçada);
`adjustment` do ambiente removido (−4,6 ms em DPR 3); orçamentos da frente "cenário e javalis HD" no contrato
(§7.1, §7.4, §7.5, §7.6, §7.12, §13.1), a partir da linha de base medida na Etapa 0.

## 0.6.0 — 16/11/2026

**Armas, braços e caçadores aliados em alto detalhe, 100% gerados por código.**

O que mudou para o jogador:

- As 5 armas foram refeitas em alto detalhe: madeira com veio, metal, luneta com lente, serrilhado no punho.
  Cada uma tem silhueta própria (.22 leve de mira aberta, 12 de bomba, .308 de ferrolho, .30-06 semiautomático,
  .338 com luneta grande e freio de boca).
- Braços novos em 1ª pessoa: manga cáqui e luvas, segurando cada arma, com animação de ferrolho, bomba e recarga.
- A arma aparece maior e mais perto na tela (campo de visão próprio da arma), sem mudar a mira.
- Os caçadores aliados da caçada com amigos foram refeitos: colete e boné na cor do jogador, roupa de campo,
  versões das armas novas na mão, poses de andar, agachar, mirar, recarregar e cair.

Detalhes técnicos: orçamento da arma em 1ª pessoa ≤ 12 000 triângulos com braços (§7.3) e do caçador aliado
≤ 5 000 (§7.11). Cada arma é montada em 60–136 ms no desktop na entrada da caçada (cache depois).

## 0.5.0 — 15/11/2026

**Novo modo na caçada com amigos: Horda Javali.**

O que mudou para o jogador:

- Na sala, o anfitrião escolhe o modo: "Contrato" (como antes) ou "Horda Javali". Vale com 1 a 4 caçadores.
- Na horda, os caçadores defendem o celeiro da sede em Mato Grosso. Javalis chegam em 8 ondas, cada vez
  maiores, a última com o cachaço alfa, e correm direto para o milho. Ninguém foge: machos e alfa investem
  contra quem chega perto.
- Vitória: abater todas as ondas. Derrota: o estoque de milho do celeiro chega a 0% ou todos os caçadores morrem.
- Todas as armas ficam disponíveis (teclas 1 a 5; no celular, o botão Trocar passa por todas) e a munição de
  reserva é infinita.
- HUD de horda: "Celeiro 87%", "Javalis no celeiro!", "Onda 3/8", anúncio de cada onda e marcador do celeiro
  no minimapa e na bússola. O milho do celeiro diminui à vista conforme é comido.
- O abate paga menos que na campanha, a vitória paga um bônus de defesa e a horda não libera contratos.
- O modo contrato, no solo e com amigos, não mudou.

O que mudou no projeto:

- Contrato do modo em `docs/horda.md`; dados em `data/horde.json`.
- `HordeDirector` (novo) planeja e libera as ondas; o `CropManager` vira o estoque do celeiro em modo horda;
  a IA dos javalis ganhou 7 desvios só para a horda.
- Rede: byte de modo no fim de `L_LOBBY`/`L_START`; evento novo `EV_HORDE_WAVE`; o protocolo continua 1.
- Assets procedurais: `barn_corn` (5 estágios), sons `horde_wave_start`/`horde_wave_clear`, ícone `barn`.

## 0.4.10 — 15/11/2026

**Rolagem por arraste nos menus no celular.**

O que mudou para o jogador:

- No celular, as listas dos menus (lobby, Mapas, Preparação, Loja, Resultado, Doação, Configurações) rolam
  arrastando o dedo em qualquer ponto, inclusive em cima de botões e cartões. Antes só rolava pela barra.
- Um toque simples continua acionando o botão; um arraste não aciona nada. Arrasto rápido desliza um pouco
  depois de soltar.
- Nos controles de volume, arrastar para o lado muda o volume e arrastar para cima ou para baixo rola a lista.
- No computador nada mudou.

O que mudou no projeto:

- `src/ui/common/touch_scroll_container.gd` (novo): ScrollContainer com arraste por toque; `UiKit.scroll_list()`
  passa a usá-lo, sem mudar a assinatura.
- `README.md`: como rodar a versão Web localmente, no celular pela rede e com o servidor de salas local.

## 0.4.9 — 15/11/2026

**Reconexão na caçada com amigos.**

O que mudou para o jogador:

- Se a internet de um jogador cair no meio da caçada, ele não sai mais da partida: aparece "Reconectando…",
  o caçador fica parado e o jogo tenta voltar sozinho por até 30 segundos. Ao voltar, aparece
  "Conexão restabelecida." e ele continua com os mesmos javalis, a mesma lavoura e o mesmo placar.
- Os outros veem "<Nome> está reconectando…" e "<Nome> voltou.". Enquanto está fora, o caçador do aliado
  fica parado e os javalis o ignoram. O anfitrião guarda o lugar por 45 segundos.
- Se não der para voltar a tempo, a partida termina para ele como antes, com os abates pagos.
- Com "Mostrar quadros por segundo" ligado, a caçada com amigos mostra também o tráfego de rede
  (envio e recebimento em kB/s e quantos aliados estão em conexão direta ou via servidor).
- Só funciona sem recarregar a página. O modo solo não mudou.

O que mudou no projeto:

- Servidor de salas (`server/rooms.js`, publicado): entrada de volta com `tok` e `ep` na sala trancada,
  erros `bad_token` (4401) e `replaced` (4411), `lock` com os tokens, `clean` no `peer_left`.
- `src/net/`: reconexão com sonda, tentativas e época do enlace; `Net.is_reconnecting()`, `get_traffic()`.
- `src/hunt/`: carência do slot no anfitrião, `EV_FULL_SYNC` (diário de eventos repetido na volta).
- `data/net.json`: `peer_timeout_s` 45, `rejoin_timeout_s` 30, `rejoin_backoff_s`, `rejoin_probe_s`.
- Contrato em `docs/multiplayer.md` §4.7. Testes novos: `relay_rejoin` e `rejoin` no `tests/net_test.tscn`,
  sandbox `net_sync` no `tests/net_unit.tscn`, cenário `rejoin` no `tests/web/coop_probe.py`.

## 0.4.8 — 14/11/2026

**Cães na caçada com amigos.**

O que mudou para o jogador:

- No modo "Jogar com amigos", cada jogador pode levar o próprio cão. A lista da sala mostra a arma e o cão de
  cada um.
- "Pega!" e "Volta!" comandam só o seu cão, e só você vê os avisos dele. Quando qualquer cão marca um javali,
  a marca aparece para todos.
- O abate feito pelo cão paga o dono do cão.
- Se o dono cai, o cão fica parado esperando; se o dono sai da partida, o cão sai junto.
- O modo solo não mudou.

O que mudou no projeto:

- `src/dogs/dog.gd` com dono (`owner_slot`) e `command()` público; réplica nova `src/dogs/dog_puppet.gd`.
- `hunt_controller.gd`, `hunt_host_sync.gd`, `hunt_replica.gd`: um cão por jogador no anfitrião, seção `DOG`
  do snapshot, comandos e marcações pela rede.
- `src/net/net_session.gd`: o cão de cada jogador trafega no resumo de equipamento.
- Teste novo: cenário `dogs` no `tests/net_test.tscn` e sandbox `net_dogs` no `tests/net_unit.tscn`.

## 0.4.7 — 14/11/2026

**Contador de FPS na caçada.**

O que mudou para o jogador:

- A opção "Mostrar quadros por segundo" das configurações agora funciona: com ela ligada, aparece o número
  de FPS no canto superior esquerdo da tela, abaixo da vida. Dá para ligar e desligar a qualquer momento,
  inclusive com o jogo pausado.

O que mudou no projeto:

- Causa do bug: a configuração `show_fps` era salva, mas nenhum código do HUD a lia.
- Novo `src/hud/fps_counter.gd` (`FpsCounter`, um `Label`): lê `Profile.get_setting("show_fps")`, segue
  `GameEvents.settings_changed`, atualiza a cada 0,5 s e não processa nada enquanto está oculto.
- `src/hud/hud.gd`: cria o contador e o coloca no canto superior esquerdo.
- `src/hud/debug/hud_net_test.gd`: 8 verificações novas para o contador.

## 0.4.6 — 14/11/2026

**Som do cerrado novo, sem cigarras.**

O que mudou para o jogador:

- O som ambiente do cerrado foi refeito: agora é só brisa no capim e pássaros distantes, sem o barulho
  de cigarra que irritava. O volume voltou ao normal (igual ao do vento).

O que mudou no projeto:

- `assets/audio/sfx/amb_cerrado_loop.mp3` regerado (ElevenLabs) com o prompt novo de
  `assets/audio/sfx_prompts.json`.
- `src/hunt/hunt_controller.gd`: removida a constante `AMBIENCE_DB_BY_ID` da 0.4.5; os dois loops
  voltam a tocar em `AMBIENCE_DB` (-6 dB).

## 0.4.5 — 14/11/2026

**Som do cerrado mais baixo na caçada.**

O que mudou para o jogador:

- O som ambiente do cerrado (cigarras, pássaros e brisa) ficou bem mais baixo durante a caçada, para não
  irritar. O som do vento continua como estava.

O que mudou no projeto:

- `src/hunt/hunt_controller.gd`: constante nova `AMBIENCE_DB_BY_ID` com o volume de `amb_cerrado_loop`
  (-15 dB, antes -6 dB como o vento). Para ajustar, basta mudar esse número.

## 0.4.4 — 14/11/2026

**A música continua tocando em todas as telas de menu até a caçada começar.**

O que mudou para o jogador:

- A música orquestral agora toca também no mapa, na preparação, na loja, na doação e nas configurações,
  além do menu e do lobby. Ela não reinicia ao trocar de tela e some com um fade ao começar a caçada.
- A tela de resultado fica sem música, para a vinheta de vitória ou derrota ser ouvida.

O que mudou no projeto:

- Só dados e teste: `music.scenes` em `data/game.json` ganhou as telas de menu; `tests/unit/test_music.gd` e
  a §7.8, §9.1 e a regra de telas de `docs/arquitetura.md` acompanham. Nenhum código mudou.

## 0.4.3 — 14/11/2026

**Música orquestral no menu e no lobby.**

O que mudou para o jogador:

- Uma música orquestral heroica e tensa (cordas graves, caixa de marcha, tambores e metais) toca no menu
  principal e no lobby do "Jogar com amigos". Ela segue sem reiniciar de uma tela para a outra e some com
  um fade ao sair, por exemplo ao escolher o mapa ou entrar na caçada.
- O volume da música acompanha o volume de ambiente nas configurações.

O que mudou no projeto:

- Faixa `assets/audio/music/music_menu.mp3` (90 s, instrumental, gerada com ElevenLabs). `Sfx` ganhou
  `play_music`, `stop_music` e `is_music_playing` (tocador próprio, fora do pool de efeitos, no barramento
  `Ambience`, carga sob demanda, loop).
- O `Router.goto` decide onde toca, a partir do bloco novo `music` de `data/game.json` (faixa, cenas,
  volume e fades). Novo `Router.scene_has_music`. Contrato na §7.8, §6.6 e §9.1 de `docs/arquitetura.md`.
- `check_scripts` isenta também `assets/audio/music/`. Teste novo em `tests/unit/test_music.gd`.

## 0.4.2 — 14/11/2026

**Javali mais realista: guincho, morte e bufada de alerta.**

O que mudou para o jogador:

- Novos sons do javali: o guincho ao ser atingido, o som da morte e a bufada de alerta foram refeitos
  para soar como um javali selvagem de verdade (e não como um porco doméstico). A morte agora é um
  grunhido fraco e uma expiração que some, sem grito dramático.

O que mudou no projeto:

- Só arquivos de som: `boar_squeal`, `boar_death` e `boar_snort_alert` em `assets/audio/sfx/`, com os
  prompts novos em `assets/audio/sfx_prompts.json`. `boar_snort_alert` passou de 0,7 s para 1,0 s.
  Nenhum código nem contrato mudou.

## 0.4.1 — 14/11/2026

**Sons de verdade: tiros, javalis, cães, passos, ambiente e interface.**

O que mudou para o jogador:

- Os 47 efeitos sonoros passam a ser gravações realistas (tiros de cada calibre, recarga, passos, javali,
  cães, vento, cerrado, sons de interface e as vinhetas de vitória e derrota), no lugar dos sons sintéticos.
- O grunhido de ataque e o som de morte do javali foram refeitos para soar mais como um animal de verdade.

O que mudou no projeto:

- Sons gerados com ElevenLabs a partir de `assets/audio/sfx_prompts.json` e guardados em
  `assets/audio/sfx/<id>.mp3`. São a única exceção à regra de arte 100% procedural.
- `Sfx` carrega os MP3 no `_ready` (~35 ms em desktop, 2,2 MB). A síntese procedural continua como
  reserva para qualquer id sem arquivo. API e ids não mudaram.
- `default_bus_layout.tres` declara os barramentos `SFX`, `Ambience` e `UI`, para o som não sumir na Web.
- `check_scripts` isenta `res://assets/audio/sfx/` da proibição de binários. Contrato na §7.8 de
  `docs/arquitetura.md`.

## 0.4.0 — 14/11/2026

**Jogar com amigos (beta): caçada cooperativa de 2 a 4 jogadores.**

O que mudou para o jogador:

- Botão novo no menu, "Jogar com amigos (beta)". Um jogador cria a sala e recebe um código de 5 letras e
  um link de convite; os amigos entram pelo código ou abrindo o link. Cada um escolhe o próprio equipamento
  e aperta "Pronto"; o anfitrião escolhe o mapa e o contrato e inicia.
- Todos caçam os mesmos javalis. Cada abate paga quem deu o tiro; o bônus do contrato é pago cheio a cada
  jogador. O contrato só avança para quem já o tinha liberado.
- Mais jogadores, mais javalis: ×1,5 com dois, ×2 com três, ×2,5 com quatro.
- Derrota se a lavoura acabar ou se todos os caçadores caírem. Quem cai assiste a um aliado até o fim.
- Aliados aparecem no mapa com a cor de cada um (laranja, azul, amarelo, roxo), no minimapa e na bússola.
- Se o anfitrião sair, a caçada termina para todos e os abates de cada um são pagos.
- Cães ainda não vão para a caçada com amigos (em breve). O modo solo não mudou.

O que mudou no projeto:

- Servidor de salas em `server/` (Cloudflare Workers + Durable Objects, plano gratuito), publicado em
  `wss://javali-salas.acpw01.workers.dev/ws`. Os jogadores se conectam direto por WebRTC; quando não dá,
  o tráfego passa pelo servidor.
- Autoload novo `Net` (`src/net/`), configuração em `data/net.json`, bloco `coop` em `data/game.json`.
- Plano e protocolo em `docs/multiplayer.md`; contrato 1.1 em `docs/arquitetura.md`.
- Suítes novas: `tests/net_test.tscn`, `tests/net_unit.tscn`, `tests/web/coop_probe.py`.

## 0.3.4 — 12/11/2026

**Drone batedor vira item básico e todo jogador ganha 3.**

Motivo: jogadores relataram dificuldade para encontrar os javalis. O drone revela todos os javalis no
minimapa por 10 s; os que estão fora do alcance do minimapa aparecem na borda, indicando a direção.

O que mudou para o jogador:

| | Antes | Agora |
|---|---|---|
| Preço do drone | 30 de ouro | 400 de dinheiro |
| Drones por caçada | 2 | 3 |
| Drones no início do jogo | 0 | 3, já equipados |

- Quem já tinha save recebe 3 drones uma única vez, na primeira vez que abrir a versão nova. Eles são
  somados aos que o jogador já tinha, até o limite de 9 por consumível.
- Nesse caso o drone é equipado sozinho se houver slot de item livre. Com os 3 slots ocupados, os drones
  vão para o inventário e o jogador equipa na tela de preparação.
- O uso na caçada não mudou: selecionar o drone no cinto de itens e usar.

O que mudou no projeto:

- `data/equipment.json`: `scout_drone` com `price 400`, `currency money`, `max_per_hunt 3`.
- `data/game.json`: `economy.start_items` passa a `{"medkit": 1, "scout_drone": 3}`.
- Save na versão 2. A migração 1 → 2 (`SaveService._migrate_v1_to_v2`) concede a quantidade definida em
  `economy.start_items.scout_drone`; o save migrado é gravado na hora, então a concessão não se repete.
- Para mudar o preço ou a quantidade inicial, basta editar os dois arquivos de dados acima. Mudar a
  quantidade inicial não dá drones de novo a quem já está na versão 2 do save.
- Contrato atualizado em `docs/arquitetura.md` (resumo do jogo, §6.3, dados de exemplo e §10).

## 0.3.3

Mostra o número da versão na tela inicial e no menu.

## 0.3.2

Controles de toque no padrão de shooter mobile.

## 0.3.1

Corrige os controles de toque no celular.

## 0.3

Jogo mais difícil.
