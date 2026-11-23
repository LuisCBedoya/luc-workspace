#!/usr/bin/env bash
# lib/ytwatch.sh — buscador TUI de YouTube.
#
# yt-dlp sigue siendo el motor de búsqueda y mpv el reproductor: ytwatch es
# una capa TUI sobre ellos, así que depende del binario oficial de yt-dlp
# que instala lib/music.sh en ~/.local/bin.
#
# Las miniaturas (ueberzugpp) se instalan aparte en lib/previews.sh: así
# `--no-ytwatch` no deja ranger sin previews.

# Se puede omitir el bloque con --no-ytwatch.
INSTALL_YTWATCH="${INSTALL_YTWATCH:-yes}"

# Política: última estable de GitHub + checksums.txt; fallback fijo
# verificado si el release falla o no se puede comprobar.
YTWATCH_REPO="geovannewashington/ytwatch"
YTWATCH_FALLBACK_VERSION="v0.3.0"
YTWATCH_FALLBACK_SHA256="8634951408637c63cf623fd7f6c53b2588b2e9baed687f64565bcc9e2d624560"
YTWATCH_VERSION="$YTWATCH_FALLBACK_VERSION"

YTARCH="amd64"

ytwatch_download_tarball_url() {
  local version="${1:-$YTWATCH_VERSION}"
  printf 'https://github.com/%s/releases/download/%s/ytwatch_%s_linux_%s.tar.gz' \
    "$YTWATCH_REPO" "$version" "${version#v}" "$YTARCH"
}

install_ytwatch() {
  if [[ "$INSTALL_YTWATCH" != "yes" ]]; then
    section "Omitiendo ytwatch (--no-ytwatch)"
    return 0
  fi

  if dry_run; then
    section "Configurando ytwatch (buscador TUI de YouTube)"
    log "[dry-run] resolver última estable de $YTWATCH_REPO; checksums.txt; fallback $YTWATCH_FALLBACK_VERSION (SHA-256)"
    log "[dry-run] descargar $(ytwatch_download_tarball_url) si es la última"
    log "[dry-run] instalar ~/.local/bin/ytwatch 0755 (usuario)"
    log "[dry-run] instalar ~/.local/bin/ytwatch-{check,update} 0755 (usuario)"
    log "[dry-run] render ~/.config/ytwatch/config.toml desde templates/ytwatch"
    log "[dry-run] instalar ~/.local/bin/ueberzugpp (wrapper de offset para Herdr)"
    log "[dry-run] las miniaturas (ueberzugpp) se instalan en lib/previews.sh"
    return 0
  fi

  section "Configurando ytwatch (buscador TUI de YouTube)"
  install_ytwatch_tools
  install_ytwatch_binary
  install_ytwatch_config
  install_ytwatch_overlay
  ok "ytwatch listo: escribe ytwatch en una kitty (audio por defecto)"
  info "Estado y actualizaciones: ytwatch-check · ytwatch-update"
}

# Helpers de estado/actualización en ~/.local/bin (usuario, sin sudo).
# Sin ellos, el timer de avisos nunca revisa ytwatch (`find_bin` los salta).
install_ytwatch_tools() {
  local dir="$TARGET_HOME/.local/bin"
  local name src dst

  make_user_dir "$dir"
  for name in ytwatch-check ytwatch-update; do
    src="$PROJECT_ROOT/bin/$name"
    dst="$dir/$name"
    if [[ ! -f "$src" ]]; then
      warn "Falta $src; se omite $name"
      continue
    fi
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
      continue
    fi
    if [[ -f "$dst" ]]; then
      backup_user_path "$dst"
    fi
    run_user install -m 0755 -- "$src" "$dst"
  done
  ok "ytwatch: ytwatch-check y ytwatch-update en $dir"
}

# Wrapper de ueberzugpp: ytwatch calcula x/y respecto a su pane, pero
# ueberzugpp coloca la ventana X11 respecto a kitty. El wrapper suma el
# sidebar y la barra de pestañas de Herdr; fuera de Herdr no toca nada.
install_ytwatch_overlay() {
  local dir="$TARGET_HOME/.local/bin"
  local src="$PROJECT_ROOT/templates/ytwatch/ueberzugpp.in"
  local dst="$dir/ueberzugpp"

  [[ -f "$src" ]] || { warn "Falta $src; se omite el wrapper de ueberzugpp"; return 0; }
  make_user_dir "$dir"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    return 0
  fi
  if [[ -f "$dst" ]]; then
    backup_user_path "$dst"
  fi
  run_user install -m 0755 -- "$src" "$dst"
  ok "ytwatch: wrapper ueberzugpp en $dir (offset de Herdr)"
}

# Versión del binario ytwatch en ~/.local/bin (vacía si no está).
ytwatch_installed_version() {
  local bin="$TARGET_HOME/.local/bin/ytwatch"
  [[ -x "$bin" ]] || return 0
  "$bin" --version 2>/dev/null | head -1 | awk '{print $NF}'
}

# Descarga el binario de la release con checksum verificado y lo deja en
# ~/.local/bin/ytwatch (usuario; sin sudo). Sin red queda el binario previo.
install_ytwatch_binary() {
  local home="$TARGET_HOME"
  local dir="$home/.local/bin"
  local bin="$dir/ytwatch"
  local installed latest want fallback

  make_user_dir "$dir"
  installed=$(ytwatch_installed_version 2>/dev/null || true)

  if ! cmd_exists curl; then
    warn "curl no está instalado; ytwatch no se puede descargar"
    return 0
  fi

  latest=$(latest_github_tag "$YTWATCH_REPO" 2>/dev/null || true)
  fallback="$YTWATCH_FALLBACK_VERSION"
  want="${latest:-$fallback}"

  if [[ -n "$installed" ]] && version_ge "$installed" "${want#v}"; then
    if [[ "$installed" == "${want#v}" ]]; then
      info "ytwatch ya instalado: $installed (última estable: $want)"
    else
      info "ytwatch instalado ($installed) es más nuevo que la última ($want); no se toca"
    fi
    return 0
  fi

  info "ytwatch: última estable ${want}; instalada ${installed:-ninguna}"
  if [[ -n "$latest" ]] && fetch_ytwatch_tarball "$latest"; then
    YTWATCH_VERSION="$latest"
  elif [[ "$fallback" != "$latest" ]] && fetch_ytwatch_tarball "$fallback"; then
    warn "ytwatch $want no se pudo verificar/descargar; se usa el fallback $fallback"
    YTWATCH_VERSION="$fallback"
  else
    warn "Sin binario nuevo de ytwatch; queda ${installed:-ninguno}"
    return 0
  fi

  installed=$(ytwatch_installed_version 2>/dev/null || true)
  if ! run_user "$YT_TMP_DIR/ytwatch" --version >/dev/null 2>&1; then
    warn "El binario de ytwatch $YTWATCH_VERSION no arranca; no se instaló nada"
    rm -rf -- "$YT_TMP_DIR"
    return 0
  fi

  if [[ -n "$installed" ]]; then
    backup_user_path "$bin"
  fi
  run_user install -m 0755 -- "$YT_TMP_DIR/ytwatch" "$bin"
  installed=$(ytwatch_installed_version 2>/dev/null || true)

  ok "ytwatch: ${installed:-desconocida} ($bin)"
  info "Para comprobar si hay versión nueva: ytwatch-check"
  rm -rf -- "$YT_TMP_DIR"
}

# Descarga el tarball de una versión concreta y verifica su SHA-256.
# La fallback usa el SHA fijado; la última estable usa checksums.txt.
fetch_ytwatch_tarball() {
  local version="$1" tmpdir asset expected got
  # Como el usuario: si lo crea root (0700), curl no puede escribir.
  tmpdir=$(run_user mktemp -d "${TMPDIR:-/tmp}/ytwatch.XXXXXX")
  YT_TMP_DIR="$tmpdir"
  asset="ytwatch_${version#v}_linux_${YTARCH}.tar.gz"

  if ! run_user curl -fsSL --max-time 300 -o "$tmpdir/tarball.tar.gz" \
       "$(ytwatch_download_tarball_url "$version")"; then
    rm -rf -- "$tmpdir"
    warn "Fallo descargando ytwatch $version"
    return 1
  fi

  if [[ "$version" == "$YTWATCH_FALLBACK_VERSION" ]]; then
    expected="$YTWATCH_FALLBACK_SHA256"
  else
    expected=$(github_release_checksum "$YTWATCH_REPO" "$version" "checksums.txt" "$asset" || true)
    if [[ -z "$expected" ]]; then
      warn "ytwatch $version no publica checksum para $asset; se descarta"
      rm -rf -- "$tmpdir"
      return 1
    fi
  fi

  got=$(sha256_file "$tmpdir/tarball.tar.gz")
  if [[ "$got" != "$expected" ]]; then
    warn "Checksum de ytwatch $version no coincide (esperado $expected, obtenido ${got:-ninguno}); se descarta"
    rm -rf -- "$tmpdir"
    return 1
  fi

  if ! tar xzf "$tmpdir/tarball.tar.gz" -C "$tmpdir"; then
    warn "El tarball de ytwatch $version no se pudo extraer"
    rm -rf -- "$tmpdir"
    return 1
  fi
  return 0
}

# Config del usuario: plantilla copiada tal cual (sin placeholders de color:
# el tema "terminal" sigue la paleta viva de kitty que recolorea theme-mode).
install_ytwatch_config() {
  local home="$TARGET_HOME"
  local dst="$home/.config/ytwatch/config.toml"
  backup_user_path "$dst"
  install_template_user 0644 "$PROJECT_ROOT/templates/ytwatch/config.toml.in" "$dst"
  ok "Config: $dst"
}
