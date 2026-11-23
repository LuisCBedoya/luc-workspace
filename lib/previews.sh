#!/usr/bin/env bash
# lib/previews.sh — miniaturas de ranger y ytwatch (ueberzugpp).
#
# ueberzugpp es el backend de previews de las dos aplicaciones. Se instala
# aparte del bloque ytwatch para que `--no-ytwatch` no deje ranger sin
# miniaturas.
#
# Política: última estable del build OBS; si falla, se usa el .deb
# vendorizado en el repo como fallback verificado con SHA-256. No se añade
# ningún repositorio APT.

UEBERZUGPP_OBS_BASE="https://download.opensuse.org/repositories/home:/justkidding/Debian_13/amd64"
UEBERZUGPP_FALLBACK_VERSION="2.9.11"
UEBERZUGPP_FALLBACK_SHA256="7f351202756f5027ddf752da9d90bc67f0be41d8338f5b851b828d4386a5e815"
UEBERZUGPP_VERSION="$UEBERZUGPP_FALLBACK_VERSION"
UEBERZUGPP_ARCH="amd64"

# 1 si las miniaturas no quedaron instaladas; el resumen lo muestra aunque
# la instalación siga (son opcionales).
PREVIEWS_UNAVAILABLE=0

ueberzugpp_vendor_deb() {
  printf '%s/vendor/ueberzugpp_%s_%s.deb' \
    "$PROJECT_ROOT" "$UEBERZUGPP_FALLBACK_VERSION" "$UEBERZUGPP_ARCH"
}

ueberzugpp_deb_url() {
  local version="${1:-$UEBERZUGPP_VERSION}"
  printf '%s/ueberzugpp_%s_%s.deb' \
    "$UEBERZUGPP_OBS_BASE" "$version" "$UEBERZUGPP_ARCH"
}

ueberzugpp_latest_obs_version() {
  local listing
  cmd_exists curl || return 1
  listing=$(curl -fsSL --max-time 30 "$UEBERZUGPP_OBS_BASE/" 2>/dev/null) || return 1
  printf '%s\n' "$listing" |
    grep -oE "ueberzugpp_[0-9][0-9.]*_${UEBERZUGPP_ARCH}\.deb" |
    sed -E "s/^ueberzugpp_([0-9][0-9.]*)_${UEBERZUGPP_ARCH}\.deb$/\1/" |
    sort -V | tail -1
}

# Versión del paquete ueberzugpp instalado (vacía si no está).
ueberzugpp_installed_version() {
  dpkg-query -W -f='${Version}' ueberzugpp 2>/dev/null || true
}

# Estado real del paquete: no basta con que existan los binarios, porque un
# dpkg interrumpido deja el paquete desempaquetado pero sin configurar.
ueberzugpp_dpkg_ok() {
  dpkg-query -W -f='${Status}' ueberzugpp 2>/dev/null |
    grep -q 'install ok installed'
}

# Comprueba que el paquete está configurado y dejó los dos comandos que usan
# ranger/ytwatch.
ueberzugpp_binaries_ok() {
  ueberzugpp_dpkg_ok &&
    [[ -x /usr/bin/ueberzugpp && -x /usr/bin/ueberzug ]]
}

# root sin `die`: los pasos de previews son opcionales y deben poder caer a
# un fallback aunque el instalador se ejecute sin sudo.
previews_run_root() {
  if dry_run; then
    print_cmd "$@"
    return 0
  fi
  if [[ "$EUID" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# Si una instalación anterior dejó dpkg a medias, se repara antes de seguir.
previews_repair_dpkg() {
  local audit
  audit=$(dpkg --audit 2>/dev/null || true)
  if [[ -n "$audit" ]]; then
    info "dpkg tiene paquetes pendientes; ejecutando apt-get -f install"
    previews_run_root env DEBIAN_FRONTEND=noninteractive \
      apt-get -y -f install || warn "No se pudo reparar dpkg; se intenta igualmente"
  fi
}

install_previews() {
  section "Miniaturas de ranger/ytwatch (ueberzugpp)"

  if dry_run; then
    log "[dry-run] resolver última estable en $UEBERZUGPP_OBS_BASE"
    log "[dry-run] fallback vendorizado: $(ueberzugpp_vendor_deb) (SHA-256 verificado)"
    log "[dry-run] la última de OBS se registra con SHA-256; no hay checksum upstream"
    log "[dry-run] 'apt-get install' del .deb local; fallback dpkg -i + apt-get -f"
    log "[dry-run] no degradar una versión de ueberzugpp ya instalada"
    return 0
  fi

  install_ueberzugpp
}

ueberzugpp_version_ge() {
  dpkg --compare-versions "$1" ge "$2"
}

# Instala un .deb concreto. Devuelve 0 solo si el paquete queda configurado,
# con los dos comandos y versión >= la candidata.
ueberzugpp_install_deb() {
  local deb="$1" version="$2" label="$3"
  local installed rc=0

  [[ -f "$deb" ]] || return 1

  # El paquete legado `ueberzug` (Python) es dueño de /usr/bin/ueberzug y
  # choca con el shim que trae ueberzugpp (drop-in). Se retira antes:
  # el shim mantiene el comando para ranger (preview_images_method
  # ueberzug) y en Debian 13 no arrastra dependientes.
  if dpkg-query -W -f='${Status}' ueberzug 2>/dev/null | grep -q 'install ok installed'; then
    info "Retirando ueberzug legado (ueberzugpp instala el shim /usr/bin/ueberzug)"
    previews_run_root env DEBIAN_FRONTEND=noninteractive apt-get -y remove ueberzug ||
      warn "No se pudo retirar ueberzug; dpkg puede fallar por el binario en conflicto"
  fi

  # APT resuelve las dependencias y configura el paquete en una sola
  # transacción. Así dpkg no lo deja a medias ni imprime el error de
  # dependencias. `dpkg -i` + `apt-get -f` queda como fallback.
  info "ueberzugpp: instalando $label con APT (dependencias incluidas; puede tardar)"
  if ! previews_run_root env DEBIAN_FRONTEND=noninteractive \
       apt-get install -y --no-install-recommends --allow-unauthenticated \
       --allow-downgrades "$deb"; then
    warn "APT no pudo instalar $label; se intenta dpkg -i + apt-get -f"
    if ! previews_run_root dpkg -i "$deb"; then
      info "dpkg pidió dependencias; apt-get -f las resuelve"
      previews_run_root env DEBIAN_FRONTEND=noninteractive apt-get -y -f install || rc=1
    fi
  fi

  installed=$(ueberzugpp_installed_version)
  if [[ "$rc" -eq 0 && -n "$installed" ]] &&
     ueberzugpp_version_ge "$installed" "$version" &&
     ueberzugpp_binaries_ok; then
    UEBERZUGPP_VERSION="$installed"
    PREVIEWS_UNAVAILABLE=0
    ok "ueberzugpp: $installed (miniaturas activas; $label)"
    return 0
  fi
  warn "ueberzugpp $label no quedó instalado/configurado"
  return 1
}

install_ueberzugpp() {
  local installed latest fallback want downloaded deb got

  case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
      PREVIEWS_UNAVAILABLE=1
      warn "ueberzugpp solo está disponible para amd64; en $(uname -m) se omiten las miniaturas"
      return 0
      ;;
  esac

  # Una instalación anterior pudo dejar dpkg a medias (por ejemplo, un
  # dpkg -i sin dependencias). Se repara antes de decidir si hay que instalar.
  previews_repair_dpkg

  installed=$(ueberzugpp_installed_version)
  latest=$(ueberzugpp_latest_obs_version 2>/dev/null || true)
  fallback="$UEBERZUGPP_FALLBACK_VERSION"
  want="${latest:-$fallback}"

  if [[ -n "$installed" ]] &&
     ueberzugpp_version_ge "$installed" "$want" &&
     ueberzugpp_binaries_ok; then
    PREVIEWS_UNAVAILABLE=0
    info "ueberzugpp ya instalado: $installed (última disponible: $want)"
    return 0
  fi
  if [[ -n "$installed" ]]; then
    if ueberzugpp_version_ge "$installed" "$want"; then
      warn "ueberzugpp $installed está instalado pero faltan /usr/bin/ueberzugpp o /usr/bin/ueberzug; se repara"
    else
      info "ueberzugpp instalado: $installed; última disponible: $want (fallback $fallback)"
    fi
  fi

  # 1) Última estable de OBS. No publica checksums: se registra el SHA.
  if [[ -n "$latest" ]] && cmd_exists curl; then
    downloaded=$(mktemp "${TMPDIR:-/tmp}/ueberzugpp.XXXXXX.deb") || downloaded=""
    if [[ -n "$downloaded" ]] &&
       curl -fsSL --max-time 300 -o "$downloaded" "$(ueberzugpp_deb_url "$latest")"; then
      got=$(sha256_file "$downloaded")
      info "ueberzugpp $latest: SHA-256 $got (OBS no publica checksums; se registra)"
      if ueberzugpp_install_deb "$downloaded" "$latest" "última $latest"; then
        rm -f -- "$downloaded"
        return 0
      fi
    else
      warn "No se pudo descargar ueberzugpp $latest de OBS"
    fi
    [[ -n "$downloaded" ]] && rm -f -- "$downloaded"
  fi

  # 2) Fallback vendorizado con SHA fijado.
  deb=$(ueberzugpp_vendor_deb)
  if [[ -f "$deb" ]]; then
    got=$(sha256_file "$deb")
    if [[ "$got" != "$UEBERZUGPP_FALLBACK_SHA256" ]]; then
      warn "Checksum del fallback vendorizado no coincide (esperado $UEBERZUGPP_FALLBACK_SHA256, obtenido ${got:-ninguno})"
    elif ueberzugpp_install_deb "$deb" "$fallback" "fallback $fallback vendorizado"; then
      return 0
    fi
  fi

  # 3) Si no hay vendor/ válido, intentar el .deb fijo desde OBS.
  if cmd_exists curl; then
    downloaded=$(mktemp "${TMPDIR:-/tmp}/ueberzugpp.XXXXXX.deb") || downloaded=""
    if [[ -n "$downloaded" ]] &&
       curl -fsSL --max-time 300 -o "$downloaded" "$(ueberzugpp_deb_url "$fallback")"; then
      got=$(sha256_file "$downloaded")
      if [[ "$got" == "$UEBERZUGPP_FALLBACK_SHA256" ]] &&
         ueberzugpp_install_deb "$downloaded" "$fallback" "fallback $fallback de OBS"; then
        rm -f -- "$downloaded"
        return 0
      fi
      warn "El fallback $fallback de OBS no coincide con el SHA fijado"
    else
      warn "No se pudo descargar el fallback $fallback de OBS"
    fi
    [[ -n "$downloaded" ]] && rm -f -- "$downloaded"
  fi

  PREVIEWS_UNAVAILABLE=1
  warn "ueberzugpp no quedó instalado; ranger/ytwatch funcionan sin miniaturas"
  warn "Revisa el log y reintenta con: ytwatch-update --ueberzugpp"
}
