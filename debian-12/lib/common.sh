#!/bin/bash
# lib/common.sh — funções compartilhadas (Debian 12)
# Não execute diretamente. Use: source "$(dirname "$0")/lib/common.sh"

readonly C_GREEN=$'\e[1;32m'
readonly C_YELLOW=$'\e[1;33m'
readonly C_RED=$'\e[1;31m'
readonly C_RESET=$'\e[0m'

readonly LOGFILE="/var/log/openbox-mini-debian12.log"
readonly STATE_DIR="/var/lib/openbox-mini"
readonly PROJ_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { echo -e "${C_GREEN}[+ ]${C_RESET} $*" | tee -a "$LOGFILE"; }
warn() { echo -e "${C_YELLOW}[! ]${C_RESET} $*" | tee -a "$LOGFILE"; }
die()  { echo -e "${C_RED}[x ]${C_RESET} $*" | tee -a "$LOGFILE" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "Execute como root: sudo bash $0"
}

pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

ensure_pkg() {
    local pkg="$1"
    if pkg_installed "$pkg"; then
        log "  [ok] $pkg"
        return 0
    fi
    log "  [..] Instalando $pkg..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$pkg" \
        || { warn "Falha ao instalar $pkg"; return 1; }
    pkg_installed "$pkg" || { warn "$pkg não foi instalado"; return 1; }
    log "  [ok] $pkg instalado"
}

check_prereqs() {
    local etapa="$1"
    case "$etapa" in
        00-preparacao) ;;
        01-base-openbox)
            command -v apt-get >/dev/null || die "apt-get ausente"
            command -v wget    >/dev/null || die "wget ausente (execute 00 antes)"
            command -v curl    >/dev/null || die "curl ausente (execute 00 antes)"
            ;;
        02-sessao-slim)
            pkg_installed openbox || die "openbox ausente (execute 01 antes)"
            pkg_installed slim    || die "slim ausente (execute 01 antes)"
            ;;
        03-ambiente-openbox)
            pkg_installed openbox || die "openbox ausente"
            ;;
        04-ajustes-finais)
            [[ -f /etc/slim.conf ]] || die "slim não configurado (execute 02 antes)"
            ;;
        05-navegadores)
            command -v curl >/dev/null || die "curl ausente"
            ;;
    esac
    return 0
}

etapa_concluida()  { [[ -f "$STATE_DIR/$1.done" ]]; }
marcar_etapa()     { mkdir -p "$STATE_DIR"; touch "$STATE_DIR/$1.done"; }