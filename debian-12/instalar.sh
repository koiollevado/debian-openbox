#!/bin/bash
# instalar.sh — orquestrador (Debian 12)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_root

ETAPAS=(
    "00-preparacao.sh"
    "01-base-openbox.sh"
    "02-sessao-slim.sh"
    "03-ambiente-openbox.sh"
    "04-ajustes-finais.sh"
    "05-navegadores.sh"
)

for etapa in "${ETAPAS[@]}"; do
    nome="${etapa%.sh}"
    if etapa_concluida "$nome"; then
        log "Etapa '$nome' já concluída. Pulando."
        continue
    fi
    check_prereqs "$nome" || die "Pré-requisitos não atendidos para '$nome'."

    log "=========================================="
    log "Executando: $etapa"
    log "=========================================="

    if bash "$(dirname "$0")/$etapa"; then
        marcar_etapa "$nome"
        log "Etapa '$nome' concluída."
    else
        die "Falha em '$etapa'. Corrija e execute novamente."
    fi
done

log "✅ Todas as etapas concluídas."
echo
if [[ -t 0 ]]; then
    read -r -p "Reiniciar agora? (s/N): " -n 1 r; echo
    [[ ${r,,} == "s" ]] && reboot
else
    warn "Reinicie manualmente."
fi