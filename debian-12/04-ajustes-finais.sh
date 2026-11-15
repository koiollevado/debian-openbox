#!/bin/bash
# 04-ajustes-finais.sh — wallpapers extra, sudoers, auto-login opcional, autofs, temas
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_root
: >> "$LOGFILE"
log "Início: $(date '+%F %T')"

TARGET_USER=""
DO_AUTO_LOGIN=0
DO_AUTOFS="ask"

for arg in "$@"; do
    case "$arg" in
        --auto-login) DO_AUTO_LOGIN=1 ;;
        --no-autofs)  DO_AUTOFS=no ;;
        --autofs)     DO_AUTOFS=yes ;;
        --*)          die "Opção desconhecida: $arg" ;;
        *)
            [[ -z "$TARGET_USER" ]] || die "Usuário já especificado."
            TARGET_USER="$arg" ;;
    esac
done

[[ -n "$TARGET_USER" ]] || TARGET_USER="${SUDO_USER:-}"
[[ -n "$TARGET_USER" ]] || TARGET_USER=$(awk -F: '$3>=1000 && $3<65534 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)
[[ -n "$TARGET_USER" ]] || die "Sem usuário-alvo."
id "$TARGET_USER" &>/dev/null || die "Usuário inválido: $TARGET_USER"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
[[ -d "$TARGET_HOME" ]] || die "HOME inválido: $TARGET_HOME"
log "Usuário-alvo: $TARGET_USER ($TARGET_HOME)"

# Wallpapers (respeita locale Pictures/Imagens)
if [[ -d "$TARGET_HOME/Imagens" ]]; then
    PICTURES_DIR="$TARGET_HOME/Imagens"
elif [[ -d "$TARGET_HOME/Pictures" ]]; then
    PICTURES_DIR="$TARGET_HOME/Pictures"
else
    PICTURES_DIR="$TARGET_HOME/Imagens"
    mkdir -p "$PICTURES_DIR"
fi
mkdir -p "$TARGET_HOME/.wallpapers" "$PICTURES_DIR/wallpapers"

glob_copy() {
    local pattern="$1" dst="$2"
    shopt -s nullglob
    local files=( "$PROJ_DIR"/$pattern )
    shopt -u nullglob
    (( ${#files[@]} == 0 )) && { warn "Nada casou com '$pattern'"; return 0; }
    for f in "${files[@]}"; do
        cp -f "$f" "$dst/"
        log "  → $(basename "$f")"
    done
    chown "$TARGET_USER:$TARGET_USER" "$dst"/* 2>/dev/null || true
}
glob_copy "wallpapers*"  "$TARGET_HOME/.wallpapers"
glob_copy "wall0*.*"     "$PICTURES_DIR/wallpapers"

# Sudoers NOPASSWD (validação obrigatória)
SUDOERS_FILE="/etc/sudoers.d/${TARGET_USER}-reboot"
if [[ ! -f "$SUDOERS_FILE" ]]; then
    cat > "$SUDOERS_FILE" <<EOF
# Permite $TARGET_USER reiniciar/desligar sem senha.
$TARGET_USER ALL=(root) NOPASSWD: /sbin/reboot, /sbin/shutdown, /sbin/poweroff, /usr/sbin/reboot, /usr/sbin/shutdown, /usr/sbin/poweroff, /usr/bin/systemctl reboot, /usr/bin/systemctl poweroff
EOF
    chmod 0440 "$SUDOERS_FILE"
    chown root:root "$SUDOERS_FILE"
    if ! visudo -c -f "$SUDOERS_FILE" >/dev/null 2>&1; then
        rm -f "$SUDOERS_FILE"
        die "sudoers inválido — arquivo removido."
    fi
    log "Regra sudoers criada e validada."
else
    log "Sudoers já existe."
fi

# Auto-login opt-in
if (( DO_AUTO_LOGIN )); then
    [[ -f /etc/slim.conf ]] || die "slim.conf ausente."
    warn "Auto-login: qualquer pessoa com acesso físico entra como $TARGET_USER."
    SLIM_BAK="/etc/slim.conf.bak.$(date +%s)"
    cp -a /etc/slim.conf "$SLIM_BAK"
    sed -i -E '/^[[:space:]]*default_user[[:space:]]/d; /^[[:space:]]*auto_login[[:space:]]/d' /etc/slim.conf
    {
        echo ""
        echo "# Configurado por 04-ajustes-finais.sh em $(date '+%F %T')"
        echo "default_user        $TARGET_USER"
        echo "auto_login          yes"
    } >> /etc/slim.conf
    if ! grep -qE "^default_user[[:space:]]+$TARGET_USER\$" /etc/slim.conf \
       || ! grep -qE "^auto_login[[:space:]]+yes\$" /etc/slim.conf; then
        cp -a "$SLIM_BAK" /etc/slim.conf
        die "Falha ao configurar auto-login — backup restaurado."
    fi
    log "Auto-login configurado."
else
    log "Auto-login não configurado (padrão)."
fi

# AutoFS
case "$DO_AUTOFS" in
    yes) ensure_pkg autofs || warn "autofs falhou." ;;
    ask)
        if [[ -t 0 ]]; then
            read -r -p "Instalar autofs (CD/DVD)? (s/N): " -n 1 r; echo
            [[ ${r,,} == "s" ]] && ensure_pkg autofs || log "AutoFS ignorado."
        else
            warn "Não-interativo: autofs não instalado."
        fi ;;
    no) log "AutoFS ignorado." ;;
esac

# Temas/ícones
mkdir -p "$TARGET_HOME/.local/share/icons" "$TARGET_HOME/.local/share/themes"
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/share"

shopt -s nullglob
zips=( "$PROJ_DIR"/temas-icones/*.zip "$PROJ_DIR"/*.zip )
tars=( "$PROJ_DIR"/temas-icones/*.tar.gz "$PROJ_DIR"/*.tar.gz )
shopt -u nullglob

(( ${#zips[@]} )) && ! command -v unzip >/dev/null && ensure_pkg unzip || true

for f in "${tars[@]}"; do
    log "Extraindo $(basename "$f") → icons/"
    tar -xzf "$f" -C "$TARGET_HOME/.local/share/icons/" 2>>"$LOGFILE" \
        && log "  ok" || warn "  falha"
done
for f in "${zips[@]}"; do
    log "Extraindo $(basename "$f") → themes/"
    unzip -q -o "$f" -d "$TARGET_HOME/.local/share/themes/" 2>>"$LOGFILE" \
        && log "  ok" || warn "  falha"
done

chown -R "$TARGET_USER:$TARGET_USER" \
    "$TARGET_HOME/.local/share/icons" \
    "$TARGET_HOME/.local/share/themes"

marcar_etapa "04-ajustes-finais"
log "✅ Ajustes finais concluídos."