# Caçada ao Javali — Diretrizes do Projeto

Jogo de caça em primeira pessoa. O caçador entra em um mapa do Brasil (primeiro: Mato Grosso),
precisa abater todos os javalis e salvar a lavoura e a fauna. Perde se a lavoura for destruída
ou se morrer.

## Engine e alvo
- Godot 4.7.2, GDScript 2.0 tipado.
- Alvo principal: Web (WebAssembly), jogável em navegador desktop, Android e iOS.
- Renderer Compatibility (WebGL2). Exportação Web sem threads, para rodar no Safari do iOS e em qualquer hospedagem estática.
- Meta de desempenho: 30+ fps em celular intermediário.
- Todo controle funciona em teclado/mouse e em toque.

## Contrato
- `docs/arquitetura.md` é a fonte da verdade: pastas, donos, autoloads, sinais, APIs, dados, camadas de colisão.
- Siga caminhos, nomes de nós, sinais e assinaturas exatamente como estão lá.
- Contrato errado ou incompleto: faça o mínimo necessário e relate. Não invente API em silêncio.

## Arquitetura
- Cenas como componentes reutilizáveis. Composição em vez de herança profunda.
- Sinais para comunicação entre sistemas independentes (barramento `GameEvents`).
- Autoloads só para sistemas realmente globais.
- Lógica de gameplay separada da UI.
- Resources/dados para tudo que é configuração e balanceamento. Nenhum número mágico no código.
- Máquinas de estado para comportamento complexo (javali, cão).
- Movimento sempre multiplicado por delta.

## Arte e áudio
- 100% procedural: nenhum asset baixado, nenhum binário externo.
- Visual low-poly estilizado, paleta do cerrado mato-grossense.

## Idioma
- Identificadores, nomes de arquivo e comentários de código em inglês.
- Todo texto que o jogador lê em português do Brasil.

## Rodando o Godot
- Use sempre o wrapper, nunca o caminho do binário: `tools/godot.sh` (Bash) ou `tools\godot.ps1` (PowerShell).
- Todo comando precisa encerrar sozinho: cena de teste que chama `get_tree().quit()`, ou `--quit` / `--quit-after N`.
  Nunca deixe um processo do Godot aberto.
- Validação, a partir da raiz do projeto, nesta ordem:
  ```bash
  tools/godot.sh --headless --path . --import          # só quando arquivos novos precisam ser importados
  tools/godot.sh --headless --path . res://tests/check_scripts.tscn
  tools/godot.sh --headless --path . res://tests/unit_tests.tscn
  tools/godot.sh --headless --fixed-fps 60 --path . res://tests/flow_test.tscn
  tools/godot.sh --headless --fixed-fps 60 --path . res://tests/playthrough.tscn
  ```
- Rode só os passos que a mudança pode afetar, e sempre `check_scripts` depois de editar scripts.
- `--headless` não renderiza nem toca som. Para ver o jogo, rode com janela e salve um screenshot (ver `tools/`).
- Exportação Web: `tools/godot.sh --headless --path . --export-release "Web" build/web/index.html`.
- Publicação: o código vai para a `main` e o conteúdo de `build/web` vai para o ramo `gh-pages` (GitHub Pages).
  Antes de cada publicação, aumente `config/version` em `project.godot`: a tela inicial e o menu mostram esse
  número, e é por ele que o dono do jogo confere se a versão nova está no ar.
- Controles de toque: rode `python tests/web/mobile_probe.py` (build Web no Chrome emulando celular) antes de publicar mudança neles.

## Arquivos compartilhados
- `project.godot`, `export_presets.cfg` e `CLAUDE.md` pertencem à sessão principal. Agentes não editam: relatam o que precisa mudar.
- Cada agente escreve só nas pastas do seu pacote (ver `docs/arquitetura.md`).

## Workflow
- Analise antes de implementar.
- Mudanças pequenas e incrementais. Preserve o que já funciona.
- Nunca presuma que algo funciona sem validar.

## Agentes
- A sessão principal decide, planeja, integra e revisa. Não implementa.
- Delegue implementação a `game-developer` (gameplay) ou `game-systems` (dados, economia, menus) sem perguntar antes.
  Esta instrução permanente conta como o usuário pedindo esses agentes.
- `art-director` produz tudo que se vê e se ouve, dentro de `assets/`.
- `game-architect` e `qa-tester` são para decisões reais e validação. Não mande edições de rotina nem exploração.
- Modelos: a sessão principal (Fable) coordena e decide. Agentes rodam em Sonnet, passando `model: sonnet` ao lançar.
  Exceção: trabalho difícil ou de caminho crítico (IA dos javalis e fluxo da caçada, bug que o Sonnet não resolveu,
  decisão de arquitetura) roda em Fable. O limite de uso de 5 horas é o gargalo: gaste Fable onde julgamento pesa.
- Dê a cada agente uma tarefa estreita: arquivos envolvidos, o que fica fora do escopo e critérios de aceite.
  Passe as decisões já tomadas, para ele não as rederivar.
- Edite direto só quando a mudança for de poucas linhas em um arquivo já em contexto.
