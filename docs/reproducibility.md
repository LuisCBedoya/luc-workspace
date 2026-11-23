# Reproducibilidad

Este proyecto busca **reproducibilidad funcional**: desde un Debian 13
limpio, `sudo ./install.sh` deja el mismo escritorio, los mismos ajustes,
temas y comportamiento. **No** busca que todos los binarios tengan la
misma versión exacta para siempre; para eso haría falta congelar Debian,
Brave, opencode, yt-dlp y todo el resto, con el coste de seguridad y
mantenimiento que implica.

## Qué queda fijado en el repo

- Configuraciones, plantillas, paletas, temas, iconos, wallpapers y
  scripts de sesión.
- Tema dark de opencode (`templates/opencode/mocha-black.json`) y
  `~/.config/opencode/cli.json`.
- Policy y helper de Brave.
- Fallbacks vendorizados/fijados con SHA-256:
  - `vendor/ueberzugpp_2.9.11_amd64.deb`
  - Nerd Font 3.5.1
  - Herdr v0.9.5
  - ytwatch v0.3.0
  - zathura-pdf-mupdf 0.4.6

## Qué se instala en su última estable

| Herramienta | Resolución | Verificación |
|---|---|---|
| `ueberzugpp` | Última versión del build Debian 13 en OBS | SHA-256 registrado (OBS no publica checksum) |
| Herdr | Último release estable de GitHub | SHA-256 registrado (no hay checksums.txt) |
| ytwatch | Último release estable de GitHub | `checksums.txt` de la release |
| Nerd Font | Último release estable de GitHub | `SHA-256.txt` de la release |
| yt-dlp | `releases/latest` | Binario se prueba con `--version` |
| Oh My Zsh | `git clone --depth=1` de la rama actual | — |
| Brave | Repo APT oficial (`stable main`) | Firma APT de Brave |
| Paquetes Debian | APT de Debian 13 | Firma APT de Debian |
| opencode | Lo instala el usuario (curl/script oficial) | El repo deja tema y `cli.json` |

Si la última estable falla, desaparece o no se puede verificar, cada
componente usa su fallback fijo con SHA. Nunca se degrada una versión
instalada igual o más nueva.

## Excepciones deliberadas

### `zathura-pdf-mupdf` queda fijado

Se compila desde el tarball 0.4.6, se verifica su SHA y se parchea el
mínimo de MuPDF (26 → 24) porque Debian 13 trae MuPDF 1.25.1. Una versión
nueva puede exigir una API o una versión de MuPDF que Debian 13 no tiene,
y romper el build de ranger/zathura. No es una app de uso diario: se
actualiza a mano, probando el build, y se actualizan versión + SHA + patch.

### `yt-dlp` va a la última

YouTube cambia con frecuencia. Congelar yt-dlp rompe la reproducción. Se
actualiza explícitamente con `ytdlp-update` (con backup y rollback).

### Brave y APT van a la última

Se priorizan las actualizaciones de seguridad. Fijar versiones de Brave o
de paquetes Debian exigiría un snapshot de Debian y asumir que no habrá
parches; no es el objetivo.

### opencode es externo

El repo no instala opencode. `install_user_configs` deja
`~/.config/opencode/cli.json` y `~/.config/opencode/themes/mocha-black.json`
antes de que opencode exista, así que al instalarlo (antes o después) ya
tiene el tema. El script oficial de opencode solo instala el binario y
toca el `PATH`; no toca `~/.config/opencode`.

## Verificación

- `./install.sh --dry-run` no descarga, no escribe y no toca red.
- `sudo ./install.sh` resuelve las versiones al ejecutar.
- `verify.sh` comprueba presencia, configuración, permisos y coherencia;
  no exige versiones exactas.
- `desktop-doctor` comprueba el estado de la sesión y las apps.
- Los fallbacks se verifican con SHA-256; las versiones latest con el
  checksum publicado o, si no existe, se registra el SHA en el log.

## Actualizar un fallback

1. Descargar el asset nuevo.
2. Calcular su SHA-256.
3. Actualizar la constante `*_FALLBACK_VERSION`/`*_FALLBACK_SHA256` en la
   lib correspondiente.
4. Actualizar el `.deb` de `vendor/` si aplica.
5. Ejecutar `bash -n`, `--dry-run` y una instalación controlada.

## Qué no garantiza

- Versiones idénticas de paquetes, Brave, opencode, yt-dlp o extensiones.
- Datos de usuario (perfil de Brave, sesiones de opencode, claves SSH/GPG,
  bookmarks) que no están en el repo.
- Comportamiento idéntico en hardware distinto (NVIDIA, Secure Boot,
  códecs de audio, monitores).
- Una instalación real desde cero sin una VM/prueba manual: el repo
  incluye checks estáticos, pero la validación final es del usuario.
