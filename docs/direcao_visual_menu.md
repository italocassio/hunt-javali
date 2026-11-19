# Direção visual: menu e preparação da caçada

## Objetivo

Atualizar a apresentação das telas de entrada, menu principal e preparação de caçada para uma identidade cinematográfica do Cerrado mato-grossense. As imagens anexas são fundos atmosféricos; textos, botões, indicadores e painéis devem continuar sendo controles reais do Godot.

Use a linguagem visual de pôster de jogo de ação contemporâneo como referência de impacto, contraste e hierarquia. **Não reproduza logos, personagens, marcas, fontes proprietárias ou elementos específicos de GTA VI.** O jogo mantém identidade própria: Brasil, fazendas, lavouras, caminhonetes, torres de observação, cães e javalis.

## Contexto do projeto

- Engine: Godot 4.7.2, GDScript 2.0 tipado, renderer Compatibility; alvo Web, desktop e celular.
- Textos visíveis ao jogador em PT-BR; identificadores, arquivos e comentários de código em inglês.
- O visual atual é majoritariamente procedural. Estas duas imagens são assets novos e devem ser carregadas sem quebrar os fallbacks existentes.
- Telas e pontos de entrada atuais: `src/ui/boot/boot.tscn`, `src/ui/main_menu/main_menu.gd`, `src/ui/preparation/preparation.gd`; seleção de mapa em `src/ui/map_select/`.
- `UiKit` centraliza componentes/tema e `AssetLoader` permite carregamento com fallback. Consulte `docs/arquitetura.md` antes de mudar APIs ou responsabilidades.
- Não modificar economia, progressão, fluxo de navegação, contratos, loadout, salvamento, multiplayer nem regras de caçada para atender a esta direção visual.

## Assets fornecidos

- `assets/ui/main_menu_cerrado.png` — arte panorâmica cinematográfica do menu principal, com caçador à esquerda e javali à direita.
- `assets/ui/preparation_cerrado.png` — paisagem de preparação, com caminhonete e equipamentos à esquerda e área central mais escura para os painéis.

Ambas são imagens 16:9, sem texto e sem interface. Usar como fundo (`TextureRect` ou solução equivalente), cobrindo a área disponível sem distorção; centralizar/recortar de modo responsivo. Aplicar uma camada escura translúcida ou gradiente atrás de textos quando necessário para manter contraste. Não editar a imagem para desenhar texto de UI sobre ela.

## Paleta e componentes

- Base: marrom muito escuro/preto quente para painéis translúcidos.
- Ação e foco: laranja, âmbar e dourado; verde apenas para dinheiro, sucesso, saúde e indicadores positivos.
- Texto: marfim/branco quente. Usar sombra/contorno com moderação sobre fundos claros.
- Painéis: transparência suficiente para revelar o cenário sem comprometer legibilidade; bordas finas douradas/âmbar e separadores discretos.
- Botões: estados normal, hover, pressionado, foco por teclado/toque e desabilitado claramente distinguíveis. O botão primário de avançar/iniciar deve ser o elemento de maior contraste.
- Reutilizar o tema e componentes do `UiKit` sempre que possível. Evitar duplicar estilos por tela ou introduzir dependência de fonte externa.

## Direção por tela

### Entrada (`boot`)

- Trocar o fundo chapado por uma composição do Cerrado coerente com os dois fundos fornecidos. Se a cena de entrada aceitar reutilização, usar `main_menu_cerrado.png` com tratamento visual mais limpo.
- Preservar o gesto atual de início (“Toque para começar” ou equivalente), foco e fluxo de áudio/boot.
- Manter a chamada curta, legível e discreta; não embutir título em imagem raster.

### Menu principal

- Usar `main_menu_cerrado.png` como fundo em tela cheia.
- Manter as ações existentes e a navegação: Jogar, Loja, Jogar com amigos (beta), Apoie o jogo (doação Pix), Configurações e Sair, se atualmente suportada.
- Organizar ações em coluna lateral com `Jogar` em destaque. O caçador permanece visualmente à esquerda: não cobrir rosto/corpo com uma coluna opaca; adaptar largura/posição conforme viewport.
- Integrar o perfil do caçador em painel compacto e legível, aproveitando os dados existentes de `Profile.get_stats()` (vitórias/jogadas, javalis abatidos, maior javali e total ganho). Não inserir números fictícios.
- Preservar a exibição de versão e os valores reais da carteira/ouro onde já aparecem via `UiKit`/autoload.
- O logotipo/título atual, se existir, deve ser texto ou arte própria do jogo; nunca recriar o texto por geração de imagem.

### Seleção de mapa

- Manter todos os mapas, estados bloqueados (“Em breve”), contagem de contratos e seleção reais.
- Levar a paleta, painéis e botões para a nova identidade. Não é necessário forçar o fundo de preparação nesta tela se prejudicar a leitura dos cards.

### Preparação

- Usar `preparation_cerrado.png` em tela cheia, com painéis escuros translúcidos por cima.
- Cabeçalho identifica “Preparação: Mato Grosso”; conservar carteira/ouro e controles de perfil/configurações se presentes no layout base.
- Coluna esquerda: contratos, estado bloqueado/concluído, detalhe do contrato, composição dos alvos, recompensa e bônus. Preservar seleção, scroll e dados atuais.
- Coluna direita: armas, atributos, equipamentos e cão, usando os dados/loadout atuais. Cards selecionáveis devem ter foco e estado selecionado evidentes.
- Rodapé: `Voltar`, `Loja` e `Iniciar caçada`. O botão de início é primário e mantém exatamente o fluxo de `_on_start()`.
- Em largura pequena, empilhar as colunas e permitir rolagem vertical; não cortar controles, esconder informação essencial ou tornar áreas de toque pequenas.

## Requisitos de implementação

1. Antes de editar, leia `CLAUDE.md`, `docs/arquitetura.md` e as cenas/scripts das telas afetadas. Respeite os donos de pasta e contratos existentes.
2. Faça a menor alteração visual coerente. Preserve caminhos de navegação, sinais, nomes de nós usados por testes, foco, scroll e estados acessíveis.
3. Carregue as imagens de forma resiliente (preferencialmente via `AssetLoader` conforme o padrão do projeto) e mantenha aparência aceitável se um asset faltar.
4. Garanta `mouse_filter` adequado para que fundos e painéis decorativos não bloqueiem cliques; controles devem continuar navegáveis por mouse, teclado e toque.
5. Verifique layout em proporções largas e estreitas. Não fixar coordenadas de uma única resolução; usar âncoras, containers, flags e limites de tamanho do Godot.
6. Preserve custo de renderização baixo para WebGL2 e celulares intermediários. Evite blur pesado, partículas decorativas permanentes ou múltiplas cópias grandes da textura.
7. Não transforme screenshot em tela estática: menus e valores permanecem elementos interativos e dinâmicos.

## Critérios de aceite

- As telas de entrada/menu/preparação têm fundos e tratamento visual consistentes com a paleta descrita.
- Os assets são encontrados nos caminhos listados e não geram erro fatal quando ausentes.
- Menu, perfil, carteira, seleção de mapa, contratos, loadout, loja e início de caçada continuam usando seus dados e fluxos reais.
- Textos têm contraste suficiente e controles permanecem acessíveis em viewport largo e estreito, mouse/teclado/toque.
- Não há referências visuais ou textuais a GTA VI dentro do jogo; a referência é apenas de clima, contraste e acabamento.
- Ao concluir, relatar arquivos alterados, decisões de layout e validações executadas. Rode as verificações indicadas em `CLAUDE.md` que forem relevantes às telas/scripts alterados.
