#!/bin/bash
# 01-base-openbox.sh — pacotes base do Openbox
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_root
: >> "$LOGFILE"
log "Início: $(date '+%F %T')"

log "Atualizando índices..."
apt-get update -qq || die "apt update falhou"

log "Upgrade do sistema base..."
DEBIAN_FRONTEND=noninteractive apt-get -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    upgrade || warn "upgrade retornou erro (continuando)."

# Grupos divididos para diagnóstico rápido e instalação incremental.
# bsdmainutils fornece 'ncal' (usado pelo conkyrc). fonts-dejavu/liberation
# fornecem as fontes referenciadas pelo conkyrc e pelo Xresources.
declare -A GRUPOS=(
    [window_manager]="openbox obmenu obconf lxappearance"
    [terminal_editor]="lxterminal geany"
    [sessao_grafica]="xinit slim"
    [desktop_util]="feh pcmanfm conky plank bsdmainutils"
    [audio]="pulseaudio pavucontrol"
    [rede_utils]="wget curl"
    [arquivos]="p7zip-full p7zip-rar xarchiver"
    [captura_midia]="gnome-screenshot vlc"
    [fontes]="fonts-dejavu fonts-liberation"
)

for grupo in window_manager terminal_editor sessao_grafica desktop_util \
             audio rede_utils arquivos captura_midia fontes; do
    log "Grupo: $grupo"
    # shellcheck disable=SC2086
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ${GRUPOS[$grupo]} \
        || die "Falha no grupo '$grupo'. Veja $LOGFILE."
done

log "Limpando cache..."
apt-get -y autoremove --purge || true
apt-get -y clean || true

marcar_etapa "01-base-openbox"
log "✅ Base Openbox instalada."