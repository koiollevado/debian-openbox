#!/bin/bash
# 03-ambiente-openbox.sh — menu, rc, conky, Xresources, autostart
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_root
: >> "$LOGFILE"
log "Início: $(date '+%F %T')"

TARGET_USER="${1:-${SUDO_USER:-}}"
if [[ -z "$TARGET_USER" ]]; then
    TARGET_USER=$(awk -F: '$3>=1000 && $3<65534 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)
fi
[[ -n "$TARGET_USER" ]] || die "Não foi possível determinar usuário-alvo."
id "$TARGET_USER" &>/dev/null || die "Usuário '$TARGET_USER' não existe."
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
[[ -d "$TARGET_HOME" ]] || die "HOME inválido: $TARGET_HOME"
log "Usuário-alvo: $TARGET_USER ($TARGET_HOME)"

safe_copy() {
    local src="$1" dst="$2" mode="$3" required="${4:-1}"
    if [[ ! -f "$src" ]]; then
        [[ "$required" == "1" ]] && die "Fonte ausente: $src"
        warn "Fonte opcional ausente: $src"
        return 0
    fi
    if [[ -f "$dst" ]] && ! cmp -s "$src" "$dst"; then
        cp -a "$dst" "${dst}.bak.$(date +%s)"
        warn "Backup: ${dst}.bak.*"
    fi
    install -m "$mode" -o "$TARGET_USER" -g "$TARGET_USER" "$src" "$dst"
    log "  → $(basename "$dst")"
}

# .xinitrc: preserva o do Script 2 (marcado); só sobrescreve com --force-xinitrc
XINITRC_DST="$TARGET_HOME/.xinitrc"
FORCE_XINITRC=0
[[ "${1:-}" == "--force-xinitrc" || "${2:-}" == "--force-xinitrc" ]] && FORCE_XINITRC=1

if [[ -f "$XINITRC_DST" ]] && grep -q 'gerenciado-por-instalacao-openbox' "$XINITRC_DST" && (( ! FORCE_XINITRC )); then
    log ".xinitrc preservado (gerenciado pelo Script 2)."
else
    safe_copy "$PROJ_DIR/config/xinitrc" "$XINITRC_DST" 755 1
fi

safe_copy "$PROJ_DIR/config/conkyrc"    "$TARGET_HOME/.conkyrc"    644 1
safe_copy "$PROJ_DIR/config/Xresources" "$TARGET_HOME/.Xresources" 644 0

# Interface de rede: ajusta enp4s4 hardcoded do conkyrc
CONKYRC="$TARGET_HOME/.conkyrc"
if [[ -f "$CONKYRC" ]] && grep -q 'enp4s4' "$CONKYRC"; then
    IFACE=$(ip -br link 2>/dev/null | awk '$1 != "lo" {print $1; exit}')
    if [[ -n "$IFACE" ]]; then
        sed -i "s/enp4s4/$IFACE/g" "$CONKYRC"
        log "conkyrc: interface ajustada para $IFACE"
    else
        warn "Não foi possível detectar interface; conkyrc mantém enp4s4."
    fi
fi

# Wallpapers
WALLPAPER_DIR="$TARGET_HOME/.wallpapers"
mkdir -p "$WALLPAPER_DIR"
if [[ -d "$PROJ_DIR/wallpapers" ]]; then
    shopt -s nullglob
    ws=( "$PROJ_DIR"/wallpapers/* )
    shopt -u nullglob
    if (( ${#ws[@]} > 0 )); then
        cp -n "${ws[@]}" "$WALLPAPER_DIR/"
        chown -R "$TARGET_USER:$TARGET_USER" "$WALLPAPER_DIR"
        log "Wallpapers: ${#ws[@]} arquivo(s)."
    else
        warn "wallpapers/ vazio."
    fi
fi

# Openbox config
OB_DIR="$TARGET_HOME/.config/openbox"
mkdir -p "$OB_DIR"
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config"

safe_copy "$PROJ_DIR/config/rc.xml"   "$OB_DIR/rc.xml"   644 1
safe_copy "$PROJ_DIR/config/menu.xml" "$OB_DIR/menu.xml" 644 1

# Autostart idempotente
AUTOSTART="$OB_DIR/autostart"
MARK="# gerenciado-por-instalacao-openbox"
if [[ -f "$AUTOSTART" ]] && ! grep -qF "$MARK" "$AUTOSTART"; then
    cp -a "$AUTOSTART" "$AUTOSTART.bak.$(date +%s)"
    warn "Backup do autostart anterior."
fi

BODY=""
command -v plank >/dev/null && BODY+="plank &"$'\n' || warn "plank ausente (omitido)"
command -v conky >/dev/null && [[ -f "$TARGET_HOME/.conkyrc" ]] \
    && BODY+="conky -c $TARGET_HOME/.conkyrc &"$'\n' || warn "conky/.conkyrc ausente"
command -v feh >/dev/null && compgen -G "$WALLPAPER_DIR/*" >/dev/null \
    && BODY+="feh --randomize --bg-fill $WALLPAPER_DIR/*"$'\n' || warn "feh/sem wallpapers"

cat > "$AUTOSTART" <<EOF
$MARK — gerado em $(date '+%F %T')
# Remova a linha acima para o script não sobrescrever nas próximas execuções.

$BODY
EOF
chmod 644 "$AUTOSTART"
chown "$TARGET_USER:$TARGET_USER" "$AUTOSTART"
log "Autostart escrito."

marcar_etapa "03-ambiente-openbox"
log "✅ Ambiente Openbox configurado."