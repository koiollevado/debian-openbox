#!/bin/bash
# 02-sessao-slim.sh — slim como DM + .xinitrc base (marcado)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_root
: >> "$LOGFILE"
log "Início: $(date '+%F %T')"

pkg_installed slim || die "slim ausente. Execute 01-base-openbox.sh antes."

SLIM_CONF="/etc/slim.conf"
DM_FILE="/etc/X11/default-display-manager"

log "Preseed do debconf para slim..."
echo "slim shared/default-x-display-manager select slim" | debconf-set-selections
echo "slim shared/default-x-display-manager seen true"  | debconf-set-selections
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive slim \
    || warn "dpkg-reconfigure retornou erro (continuando)."

if [[ "$(cat "$DM_FILE" 2>/dev/null)" != "/usr/bin/slim" ]]; then
    echo "/usr/bin/slim" > "$DM_FILE"
    log "default-display-manager → /usr/bin/slim"
fi

systemctl list-unit-files 2>/dev/null | grep -q '^slim\.service' \
    && systemctl enable slim.service 2>/dev/null \
    && log "slim.service habilitado" \
    || warn "Não foi possível habilitar slim.service."

for dm in gdm3 gdm lightdm sddm lxdm xdm wdm; do
    systemctl is-enabled "$dm" &>/dev/null && {
        warn "Desabilitando outro DM: $dm"
        systemctl disable "$dm" 2>/dev/null || true
    }
done

# Usuário-alvo: argumento → SUDO_USER → primeiro UID>=1000
TARGET_USER="${1:-${SUDO_USER:-}}"
if [[ -z "$TARGET_USER" ]]; then
    TARGET_USER=$(awk -F: '$3>=1000 && $3<65534 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)
fi

if [[ -n "$TARGET_USER" ]] && id "$TARGET_USER" &>/dev/null; then
    USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    XINITRC="$USER_HOME/.xinitrc"

    if [[ -f "$XINITRC" ]] && ! grep -q 'gerenciado-por-instalacao-openbox' "$XINITRC"; then
        cp -a "$XINITRC" "${XINITRC}.bak.$(date +%s)"
        warn "Backup do .xinitrc anterior criado."
    fi

    # Fonte: config/xinitrc do projeto (se existir); senão, gera mínimo.
    if [[ -f "$PROJ_DIR/config/xinitrc" ]]; then
        install -m 755 -o "$TARGET_USER" -g "$TARGET_USER" \
            "$PROJ_DIR/config/xinitrc" "$XINITRC"
        # Garante a marca de gerenciamento (idempotência do 03)
        grep -q 'gerenciado-por-instalacao-openbox' "$XINITRC" \
            || sed -i '1i # gerenciado-por-instalacao-openbox' "$XINITRC"
        log ".xinitrc copiado de config/xinitrc."
    else
        cat > "$XINITRC" <<'EOF'
#!/bin/sh
# gerenciado-por-instalacao-openbox
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"
exec openbox-session
EOF
        chmod 755 "$XINITRC"
        chown "$TARGET_USER:$TARGET_USER" "$XINITRC"
        log ".xinitrc mínimo criado."
    fi
else
    warn "Nenhum usuário humano detectado. Crie um e rode: $0 <usuario>"
fi

if [[ -f "$SLIM_CONF" ]]; then
    grep -qE '^auto_login' "$SLIM_CONF" && \
        sed -i 's/^auto_login.*/# auto_login desabilitado pela instalacao/' "$SLIM_CONF"
fi

DM_ATUAL=$(cat "$DM_FILE" 2>/dev/null || echo "<vazio>")
log "Verificação: DM=$DM_ATUAL  slim.service=$(systemctl is-enabled slim.service 2>/dev/null || echo não)"
[[ "$DM_ATUAL" == "/usr/bin/slim" ]] || die "slim não é o DM padrão."

marcar_etapa "02-sessao-slim"
log "✅ Sessão slim configurada."