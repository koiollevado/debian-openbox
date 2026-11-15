#!/bin/bash
# 00-preparacao.sh — pré-requisitos, sources.list, otimizações do APT
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_root
mkdir -p "$(dirname "$LOGFILE")"
: > "$LOGFILE"
log "Início: $(date '+%F %T')"

if ! grep -q '^VERSION_CODENAME=bookworm' /etc/os-release 2>/dev/null; then
    warn "Este script é destinado ao Debian 12 (bookworm)."
fi

log "Instalando ferramentas base..."
apt-get update -qq || die "apt update falhou"
for pkg in wget curl gnupg ca-certificates git sudo; do
    ensure_pkg "$pkg" || die "Falha em pré-requisito: $pkg"
done

SOURCES_NOVO="$PROJ_DIR/config/sources.list"
if [[ -f "$SOURCES_NOVO" ]]; then
    log "Aplicando sources.list do projeto..."
    cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.$(date +%s)" 2>/dev/null || true
    cp "$SOURCES_NOVO" /etc/apt/sources.list
    if ! apt-get update -qq; then
        warn "apt update falhou com o novo sources.list; restaurando backup."
        cp -a /etc/apt/sources.list.bak.* /etc/apt/sources.list 2>/dev/null || true
        die "Verifique $SOURCES_NOVO"
    fi
    log "sources.list aplicado."
else
    warn "config/sources.list ausente; mantendo o atual."
fi

if [[ ! -f /etc/apt/apt.conf.d/99openbox-mini ]]; then
    cat > /etc/apt/apt.conf.d/99openbox-mini <<'EOF'
APT::Install-Recommends "0";
APT::Install-Suggests "0";
Acquire::Languages "none";
Acquire::Retries "3";
EOF
    log "Otimizações do APT aplicadas."
fi

marcar_etapa "00-preparacao"
log "✅ Preparação concluída."