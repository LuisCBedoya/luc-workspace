#!/usr/bin/env bash
# lib/versions.sh — resolución de "última estable" y checksums de releases.
#
# Política: las herramientas externas se instalan en su última estable. Si
# el release falla, desaparece o no se puede verificar, cada lib usa su
# versión fija/vendorizada como fallback. No se busca reproducibilidad de
# versiones idénticas, sino de configuración y funcionamiento.

# Último tag estable de GitHub (excluye pre-releases). Vacío si no hay red.
latest_github_tag() {
  local repo="$1" tag
  [[ -n "$repo" ]] || return 1
  cmd_exists curl || return 1
  tag=$(curl -fsSL --max-time 20 \
    "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null |
    sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  [[ -n "$tag" ]] || return 1
  printf '%s\n' "$tag"
}

github_release_url() {
  printf 'https://github.com/%s/releases/download/%s/%s' "$1" "$2" "$3"
}

# SHA-256 de un asset según un checksums.txt/SHA-256.txt de la release.
# Acepta formato "sha  archivo" y "sha *archivo".
github_release_checksum() {
  local repo="$1" tag="$2" checksum_asset="$3" asset="$4"
  local tmp sha
  tmp=$(mktemp "${TMPDIR:-/tmp}/luc-checksums.XXXXXX") || return 1
  if ! curl -fsSL --max-time 60 -o "$tmp" \
       "$(github_release_url "$repo" "$tag" "$checksum_asset")"; then
    rm -f -- "$tmp"
    return 1
  fi
  sha=$(awk -v f="$asset" '$2 == f || $2 == "*" f { print $1; exit }' "$tmp")
  rm -f -- "$tmp"
  [[ -n "$sha" ]] || return 1
  printf '%s\n' "$sha"
}

sha256_file() {
  sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

# version_ge A B -> 0 si A >= B (sort -V).
version_ge() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}
