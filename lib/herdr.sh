#!/usr/bin/env bash
# lib/herdr.sh — Herdr TUI: binario fijado y configuración reproducible.
#
# Herdr no está en los repos de Debian: se instala el binario oficial en
# ~/.local/bin (usuario, sin sudo). El config se renderiza desde
# templates/herdr/config.toml.in con el tema activo; theme-mode sigue
# actualizando el tema en caliente.

INSTALL_HERDR="${INSTALL_HERDR:-yes}"

# Política: última estable de GitHub; si falla, fallback fijo verificado.
HERDR_REPO="herdrdev/herdr"
HERDR_FALLBACK_VERSION="v0.9.5"
HERDR_FALLBACK_SHA256_X86_64="14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d"
HERDR_FALLBACK_SHA256_AARCH64="17d7536f2da50859523680ef279dffcac8e4a235f4e46fe8da6c2ec44141897c"
HERDR_VERSION="$HERDR_FALLBACK_VERSION"

herdr_asset() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'herdr-linux-x86_64' ;;
    aarch64|arm64) printf 'herdr-linux-aarch64' ;;
    *) return 1 ;;
  esac
}

herdr_fallback_sha256() {
  case "$(uname -m)" in
    x86_64|amd64) printf '%s' "$HERDR_FALLBACK_SHA256_X86_64" ;;
    aarch64|arm64) printf '%s' "$HERDR_FALLBACK_SHA256_AARCH64" ;;
    *) return 1 ;;
  esac
}

herdr_download_url() {
  local version="${1:-$HERDR_VERSION}"
  printf 'https://github.com/%s/releases/download/%s/%s' \
    "$HERDR_REPO" "$version" "$(herdr_asset)"
}

install_herdr() {
  if [[ "$INSTALL_HERDR" != "yes" ]]; then
    section "Omitiendo Herdr (--no-herdr)"
    return 0
  fi

  if dry_run; then
    section "Configurando Herdr (TUI de terminal)"
    log "[dry-run] resolver última estable de $HERDR_REPO; fallback $HERDR_FALLBACK_VERSION (SHA-256)"
    log "[dry-run] descargar $(herdr_download_url) si es la última"
    log "[dry-run] instalar ~/.local/bin/herdr 0755 (usuario, sin sudo)"
    log "[dry-run] renderizar ~/.config/herdr/config.toml desde templates/herdr"
    log "[dry-run] instalar ~/.local/lib/luc-workspace/preview_tag.py (etiqueta de previews)"
    return 0
  fi

  section "Configurando Herdr (TUI de terminal)"
  install_herdr_binary
  install_herdr_config
  install_herdr_preview_tag
  ok "Herdr listo: escribe 'herdr' en una kitty"
}

# Versión del binario en ~/.local/bin (vacía si no está).
herdr_installed_version() {
  local bin="$TARGET_HOME/.local/bin/herdr"
  [[ -x "$bin" ]] || return 0
  "$bin" --version 2>/dev/null | head -1 | awk '{print $NF}'
}

# Descarga e instala una release concreta. La fallback lleva SHA-256
# fijado; la última estable se registra con su SHA (Herdr no publica
# checksums.txt en sus releases).
install_herdr_candidate() {
  local version="$1"
  local home="$TARGET_HOME"
  local dir="$home/.local/bin"
  local bin="$dir/herdr"
  local tmp got expected installed

  if ! herdr_asset >/dev/null; then
    warn "Arquitectura no soportada para Herdr ($(uname -m))"
    return 1
  fi

  tmp=$(run_user mktemp -d "${TMPDIR:-/tmp}/herdr.XXXXXX") || {
    warn "No se pudo crear el directorio temporal de Herdr"
    return 1
  }

  if ! run_user curl -fsSL --max-time 300 -o "$tmp/herdr" \
       "$(herdr_download_url "$version")"; then
    rm -rf -- "$tmp"
    warn "Fallo descargando Herdr $version"
    return 1
  fi

  got=$(sha256_file "$tmp/herdr")
  if [[ "$version" == "$HERDR_FALLBACK_VERSION" ]]; then
    expected=$(herdr_fallback_sha256)
    if [[ "$got" != "$expected" ]]; then
      rm -rf -- "$tmp"
      warn "Checksum de Herdr $version no coincide (esperado $expected, obtenido ${got:-ninguno}); se descarta"
      return 1
    fi
  else
    info "Herdr $version: SHA-256 $got (release sin checksums.txt; se registra)"
  fi

  run_user chmod 0755 "$tmp/herdr" 2>/dev/null || true
  if ! run_user "$tmp/herdr" --version >/dev/null 2>&1; then
    rm -rf -- "$tmp"
    warn "El binario de Herdr $version no arranca; no se instala"
    return 1
  fi

  if [[ -f "$bin" ]]; then
    backup_user_path "$bin"
  fi
  run_user install -m 0755 -- "$tmp/herdr" "$bin"
  rm -rf -- "$tmp"
  HERDR_VERSION="$version"
  installed=$(herdr_installed_version 2>/dev/null || true)
  ok "Herdr: ${installed:-desconocida} ($bin)"
  return 0
}

# Resuelve la última estable y cae al fallback fijo si falla. Nunca
# retrocede si la versión instalada ya es igual o más nueva.
install_herdr_binary() {
  local home="$TARGET_HOME"
  local dir="$home/.local/bin"
  local installed latest want fallback

  make_user_dir "$dir"
  installed=$(herdr_installed_version 2>/dev/null || true)

  if ! cmd_exists curl; then
    warn "curl no está instalado; Herdr no se puede descargar"
    return 0
  fi

  latest=$(latest_github_tag "$HERDR_REPO" 2>/dev/null || true)
  fallback="$HERDR_FALLBACK_VERSION"
  want="${latest:-$fallback}"

  if [[ -n "$installed" ]] && version_ge "$installed" "${want#v}"; then
    if [[ "$installed" == "${want#v}" ]]; then
      info "Herdr ya instalado: $installed (última estable: $want)"
    else
      info "Herdr instalado ($installed) es más nuevo que la última ($want); no se toca"
    fi
    return 0
  fi

  info "Herdr: última estable ${want}; instalada ${installed:-ninguna}"
  if [[ -n "$latest" ]] && install_herdr_candidate "$latest"; then
    return 0
  fi
  if [[ "$fallback" != "$latest" ]]; then
    warn "Herdr $want no se pudo instalar; se usa el fallback $fallback"
    if install_herdr_candidate "$fallback"; then
      return 0
    fi
  fi
  warn "Herdr no se pudo instalar; queda ${installed:-ninguno}"
}

# Config de Herdr con los atajos actuales y el tema de la paleta activa.
install_herdr_config() {
  local dir="$TARGET_HOME/.config/herdr"

  make_user_dir "$dir"
  render_theme_template "$PROJECT_ROOT/templates/herdr/config.toml.in" \
    "$dir/config.toml" 0644
  ok "Herdr: config en $dir/config.toml"
}

# Módulo compartido por los wrappers de ueberzug: aprende la base X11 de su
# hijo y etiqueta cada ventana con la pestaña real de Herdr (HERDR_TAB_ID).
install_herdr_preview_tag() {
  local dir="$TARGET_HOME/.local/lib/luc-workspace"
  local src="$PROJECT_ROOT/templates/herdr/preview_tag.py"
  local dst="$dir/preview_tag.py"

  [[ -f "$src" ]] || { warn "Falta $src; se omite el etiquetado de previews"; return 0; }
  make_user_dir "$dir"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    return 0
  fi
  if [[ -f "$dst" ]]; then
    backup_user_path "$dst"
  fi
  run_user install -m 0644 -- "$src" "$dst"
  ok "Herdr: etiquetado de previews en $dst"
}
