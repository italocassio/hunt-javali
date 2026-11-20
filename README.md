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

# Android (APK arm64, assinado com a chave de debug; instala por cabo ou copiando o arquivo)
mkdir -p build/android
tools/godot.sh --headless --path . --export-debug "Android" build/android/CacadaAoJavali.apk
```

Android exige, além dos export templates: JDK 17, Android SDK (`platform-tools` e `build-tools;35.0.1`),
e a keystore de debug do Godot em `%APPDATA%\Godot\keystores\debug.keystore`. Em Editor → Configurações do Editor →
Exportar → Android, aponte o caminho do JDK e do SDK. Para instalar com o celular plugado (Depuração USB ligada):

```bash
adb install -r build/android/CacadaAoJavali.apk
```

No PowerShell (o Windows não executa `.sh`), a mesma exportação é:

```powershell
New-Item -ItemType Directory -Force build\android
tools\godot.ps1 --headless --path . --export-debug "Android" build\android\CacadaAoJavali.apk
```

As predefinições de exportação estão em `export_presets.cfg`. A pasta `build/` não é versionada.

Para gerar os arquivos de distribuição:

```bash
cd build
powershell -NoProfile -Command "Compress-Archive -Force -Path windows/CacadaAoJavali.exe -DestinationPath CacadaAoJavali-windows-x86_64.zip"   # no Windows
(cd linux && tar --mode=755 -czf ../CacadaAoJavali-linux-x86_64.tar.gz CacadaAoJavali.x86_64)
```

O `--mode=755` mantém o bit de execução do binário Linux quando o empacotamento é feito no Windows.

## Rodar a versão Web localmente

Gere o build Web (acima) e sirva a pasta `build/web` com qualquer servidor estático. Abrir o `index.html`
direto (`file://`) não funciona: o navegador bloqueia o carregamento do jogo.

```bash
python -m http.server 8000 --directory build/web
```

Abra http://localhost:8000. `Ctrl+C` encerra o servidor.

### No celular (mesma rede Wi-Fi)

```bash
python -m http.server 8000 --bind 0.0.0.0 --directory build/web
```

Descubra o IP do computador (`ipconfig` no Windows, `ip addr` no Linux) e abra `http://<IP>:8000` no celular,
por exemplo `http://192.168.0.10:8000`. Se não abrir, libere a porta 8000 (ou o Python) no firewall.

### Jogar com amigos (servidor de salas)

O modo multiplayer precisa do servidor de salas (detalhes em [server/README.md](server/README.md)):

- Em `localhost`, o jogo usa o servidor local (`dev_server_url` em `data/net.json`, `ws://localhost:8787/ws`).
  Suba-o em outro terminal, com [Bun](https://bun.sh) instalado:
  ```bash
  cd server && bun server.js --port 8787
  ```
  Para apontar para outro servidor, use `?server=<url>` no endereço (só vale em `localhost`).
- Por qualquer outro endereço (ex.: o IP da rede no celular), o jogo usa o servidor de produção
  (`server_url`), que recusa (403) páginas fora da lista de origens permitidas, como um IP da rede local. Para testar salas no celular,
  publique a versão e teste pela página do GitHub Pages.

## Testes

```bash
tools/godot.sh --headless --path . res://tests/check_scripts.tscn
tools/godot.sh --headless --path . res://tests/unit_tests.tscn
tools/godot.sh --headless --fixed-fps 60 --path . res://tests/flow_test.tscn
tools/godot.sh --headless --fixed-fps 60 --path . res://tests/playthrough.tscn
```

## Documentação

A arquitetura (pastas, autoloads, sinais, APIs, dados) está em [docs/arquitetura.md](docs/arquitetura.md).
