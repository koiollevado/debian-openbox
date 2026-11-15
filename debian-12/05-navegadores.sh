#!/bin/bash
# 05-navegadores.sh — menu interativo; atualiza ~/.config/openbox/menu.xml após instalar
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

require_root
: >> "$LOGFILE"
log "Início: $(date '+%F %T')"

# Usuário-alvo para atualizar o menu e abrir navegador
TARGET_USER="${SUDO_USER:-}"
[[ -n "$TARGET_USER" ]] || TARGET_USER=$(awk -F: '$3>=1000 && $3<65534 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)
TARGET_HOME=""
[[ -n "$TARGET_USER" ]] && TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
MENU_XML="$TARGET_HOME/.config/openbox/menu.xml"

# Adiciona um item ao submenu "Internet" de ~/.config/openbox/menu.xml
menu_add_item() {
    local label="$1" cmd="$2"
    [[ -f "$MENU_XML" ]] || { warn "menu.xml não encontrado; pulando atualização."; return 0; }
    if grep -qF "<command>$cmd</command>" "$MENU_XML"; then
        log "  menu já contém '$label'"
        return 0
    fi
    # Insere antes do </menu> do submenu Internet (heurística)
    python3 - "$MENU_XML" "$label" "$cmd" <<'PY'
import sys, re
path, label, cmd = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as f: xml = f.read()
item = f'      <item label="{label}"><action name="Execute"><command>{cmd}</command></action></item>\n'
pattern = r'(<menu id="Internet"[^>]*>)(.*?)(\n\s*</menu>)'
def repl(m):
    if f'<command>{cmd}</command>' in m.group(2):
        return m.group(0)
    return m.group(1) + m.group(2) + "\n" + item + m.group(3)
new = re.sub(pattern, repl, xml, count=1, flags=re.S)
if new == xml:
    sys.exit(2)
with open(path, "w", encoding="utf-8") as f: f.write(new)
PY
    [[ $? -eq 0 ]] && log "  menu atualizado: $label" || warn "  falha ao atualizar menu."
    # Recarrega para o usuário atual, se houver sessão
    sudo -u "$TARGET_USER" DISPLAY="${DISPLAY:-:0}" openbox --reconfigure 2>/dev/null || true
}

open_urls_as_user() {
    local browser="$1"; shift
    [[ -n "$TARGET_USER" && -n "${DISPLAY:-}" ]] || { warn "Sem DISPLAY; URLs não abertas."; return 0; }
    sudo -u "$TARGET_USER" env DISPLAY="$DISPLAY" "$browser" "$@" &>/dev/null &
}

apt_install() { ensure_pkg "$1"; }

instalar_Chromium() {
    log "Chromium (Debian repo)..."
    apt-get update -qq || die "apt update falhou."
    apt_install chromium || die "chromium indisponível."
    menu_add_item "Chromium" "chromium"
    open_urls_as_user chromium \
        "https://chrome.google.com/webstore/detail/adblock-plus-free-ad-bloc/cfhdojbkjhnklbpkdaibdccddilifddb" \
        "https://chrome.google.com/webstore/detail/downthemall/nljkibfhlpcnanjgbnlnbjecgicbjkge"
}

instalar_Firefox_Repo() {
    log "Firefox ESR (Debian repo)..."
    apt-get update -qq || die "apt update falhou."
    apt_install firefox-esr || die "firefox-esr indisponível."
    apt_install firefox-esr-l10n-pt-br || warn "l10n pt-BR falhou."
    menu_add_item "Firefox ESR" "firefox-esr"
    open_urls_as_user firefox-esr \
        "https://addons.mozilla.org/pt-BR/firefox/addon/adblock-plus/" \
        "https://addons.mozilla.org/pt-BR/firefox/addon/downthemall/"
}

instalar_Firefox_ESR() { instalar_Firefox_Repo; }

instalar_Firefox_Latest() {
    log "Firefox Latest (tarball Mozilla)..."
    local arch tarball tmpdir
    case "$(uname -m)" in
        x86_64)  arch="linux64" ;;
        aarch64) arch="linux-aarch64" ;;
        *) die "Arquitetura não suportada." ;;
    esac
    tmpdir=$(mktemp -d); trap 'rm -rf "$tmpdir"' RETURN
    tarball="$tmpdir/firefox.tar"
    wget -q --show-progress \
        "https://download.mozilla.org/?product=firefox-latest&os=${arch}&lang=pt-BR" \
        -O "$tarball" || die "Download falhou."
    file "$tarball" | grep -qE 'XZ compressed|bzip2 compressed|gzip compressed' \
        || die "Tarball inválido."
    rm -rf /opt/firefox
    if   file "$tarball" | grep -q 'XZ compressed'; then tar -xJf "$tarball" -C /opt/
    elif file "$tarball" | grep -q 'bzip2 compressed'; then tar -xjf "$tarball" -C /opt/
    else  tar -xzf "$tarball" -C /opt/; fi || die "Extração falhou."
    [[ -x /opt/firefox/firefox ]] || die "Binário ausente."
    ln -sf /opt/firefox/firefox /usr/bin/firefox
    cat > /usr/share/applications/firefox.desktop <<'EOF'
[Desktop Entry]
Name=Firefox
Comment=Navegador Web
Exec=/opt/firefox/firefox %u
Icon=/opt/firefox/browser/chrome/icons/default/default128.png
Type=Application
Categories=Network;WebBrowser;
Terminal=false
StartupWMClass=Firefox
EOF
    menu_add_item "Firefox Latest" "firefox"
    open_urls_as_user firefox \
        "https://addons.mozilla.org/pt-BR/firefox/addon/adblock-plus/" \
        "https://addons.mozilla.org/pt-BR/firefox/addon/downthemall/"
}

instalar_Chrome() {
    log "Google Chrome (.deb)..."
    local tmpdir deb
    tmpdir=$(mktemp -d); deb="$tmpdir/chrome.deb"
    wget -q --show-progress \
        "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" \
        -O "$deb" || { rm -rf "$tmpdir"; die "Download falhou."; }
    if ! dpkg -i "$deb" 2>>"$LOGFILE"; then
        DEBIAN_FRONTEND=noninteractive apt-get install -f -y \
            || { rm -rf "$tmpdir"; die "Dependências do Chrome falharam."; }
    fi
    rm -rf "$tmpdir"
    menu_add_item "Google Chrome" "google-chrome-stable"
    open_urls_as_user google-chrome-stable \
        "https://chrome.google.com/webstore/detail/adblock-plus-free-ad-bloc/cfhdojbkjhnklbpkdaibdccddilifddb" \
        "https://chrome.google.com/webstore/detail/downthemall/nljkibfhlpcnanjgbnlnbjecgicbjkge"
}

instalar_Brave() {
    log "Brave Browser (repo oficial)..."
    curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
        https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
        || die "Chave GPG falhou."
    curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources \
        https://brave-browser-apt-release.s3.brave.com/brave-browser.sources \
        || die "Repositório falhou."
    apt-get update -qq || die "apt update falhou."
    ensure_pkg brave-browser || die "brave-browser falhou."
    menu_add_item "Brave Browser" "brave-browser"
    open_urls_as_user brave-browser \
        "https://chrome.google.com/webstore/detail/adblock-plus-free-ad-bloc/cfhdojbkjhnklbpkdaibdccddilifddb" \
        "https://chrome.google.com/webstore/detail/downthemall/nljkibfhlpcnanjgbnlnbjecgicbjkge"
}

if [[ ! -t 0 ]]; then
    die "Este script é interativo. Execute em um terminal (TTY ou X)."
fi

while true; do
    clear
    echo "====================================================="
    echo "           INSTALADOR DE NAVEGADORES"
    echo "====================================================="
    echo "   1. Chromium (Debian)"
    echo "   2. Firefox (Debian — ESR)"
    echo "   3. Firefox ESR (mesmo que 2)"
    echo "   4. Firefox Latest (tarball oficial)"
    echo "   5. Google Chrome (estável, .deb)"
    echo "   6. Brave Browser (repo oficial)"
    echo "   0. Sair"
    echo "====================================================="
    read -r -p "   Opção: " opcao || exit 0
    case "$opcao" in
        1) instalar_Chromium ;;
        2) instalar_Firefox_Repo ;;
        3) instalar_Firefox_ESR ;;
        4) instalar_Firefox_Latest ;;
        5) instalar_Chrome ;;
        6) instalar_Brave ;;
        0) log "Encerrado."; exit 0 ;;
        *) warn "Opção inválida."; sleep 1.5 ;;
    esac
    echo
    read -r -p "Enter para o menu..." || true
done