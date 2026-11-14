# Caçada ao Javali

Jogo de caça em primeira pessoa. Você é o caçador, entra em um mapa do Brasil (primeiro: Mato Grosso),
abate todos os javalis e salva a lavoura e a fauna. Perde se a lavoura for destruída ou se morrer.

- Engine: Godot 4.7.2 (GDScript tipado), renderer Compatibility.
- Plataformas: Web (navegador desktop, Android e iOS), Windows e Linux.
- Controles: teclado e mouse, ou toque.
- Arte e áudio 100% procedurais, sem assets externos.

## Jogar

| Plataforma | Como obter |
|---|---|
| Web | Abra a página do jogo no GitHub Pages (ramo `gh-pages`). |
| Windows (x86_64) | Baixe `CacadaAoJavali-windows-x86_64.zip`, extraia e execute `CacadaAoJavali.exe`. |
| Linux (x86_64) | Baixe `CacadaAoJavali-linux-x86_64.tar.gz`, extraia, e execute `./CacadaAoJavali.x86_64`. |

Os executáveis de Windows e Linux são de arquivo único (o `.pck` vem embutido) e não precisam de instalação.
No Linux, se o arquivo perder a permissão de execução: `chmod +x CacadaAoJavali.x86_64`.
O Windows pode mostrar o aviso do SmartScreen, porque o executável não é assinado: "Mais informações" → "Executar assim mesmo".

## Compilar

Requisitos: Godot 4.7.2 com os export templates 4.7.2 instalados (Editor → Gerenciar Modelos de Exportação).
Os scripts `tools/godot.sh` (Bash) e `tools\godot.ps1` (PowerShell) localizam o editor
(`$GODOT`, `godot` no PATH, ou a pasta ao lado do repositório). Rode sempre a partir da raiz do projeto.

```bash
# Web (sem threads, roda em qualquer hospedagem estática)
tools/godot.sh --headless --path . --export-release "Web" build/web/index.html

# Windows (x86_64)
mkdir -p build/windows
tools/godot.sh --headless --path . --export-release "Windows Desktop" build/windows/CacadaAoJavali.exe

# Linux (x86_64)
mkdir -p build/linux
tools/godot.sh --headless --path . --export-release "Linux" build/linux/CacadaAoJavali.x86_64
```

As predefinições de exportação estão em `export_presets.cfg`. A pasta `build/` não é versionada.

Para gerar os arquivos de distribuição:

```bash
cd build
powershell -NoProfile -Command "Compress-Archive -Force -Path windows/CacadaAoJavali.exe -DestinationPath CacadaAoJavali-windows-x86_64.zip"   # no Windows
(cd linux && tar --mode=755 -czf ../CacadaAoJavali-linux-x86_64.tar.gz CacadaAoJavali.x86_64)
```

O `--mode=755` mantém o bit de execução do binário Linux quando o empacotamento é feito no Windows.

## Testes

```bash
tools/godot.sh --headless --path . res://tests/check_scripts.tscn
tools/godot.sh --headless --path . res://tests/unit_tests.tscn
tools/godot.sh --headless --fixed-fps 60 --path . res://tests/flow_test.tscn
tools/godot.sh --headless --fixed-fps 60 --path . res://tests/playthrough.tscn
```

## Documentação

A arquitetura (pastas, autoloads, sinais, APIs, dados) está em [docs/arquitetura.md](docs/arquitetura.md).
