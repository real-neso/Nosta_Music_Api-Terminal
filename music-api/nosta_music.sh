#!/bin/bash

# Nosta Music CLI - Installer
# Part of Nosta project
# This tool manages music uploads/playback only

set -e

# Handle --uninstall flag
if [ "$1" = "--uninstall" ] || [ "$1" = "-u" ]; then
    echo -e "\033[0;31mUninstall Nosta Music CLI?\033[0m"
    echo -ne "Type 'uninstall' to confirm: "
    read -r confirm
    if [ "$confirm" = "uninstall" ]; then
        rm -f "$HOME/.local/bin/nosta-music"
        rm -rf "$HOME/.nosta" "$HOME/.nosta_token" "$HOME/.nosta_user" /tmp/nosta_uploads
        sed -i '/\.local\/bin/d' "$HOME/.bashrc"
        echo -e "\033[0;32mUninstalled.\033[0m"
        echo "Removed: binary, config, tokens, PATH entry"
    else
        echo "Cancelled."
    fi
    exit 0
fi

R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
M='\033[0;35m'
C='\033[0;36m'
W='\033[1;37m'
D='\033[2m'
N='\033[0m'

CLEAN_URL="https://raw.githubusercontent.com/YOUR_USER/nosta/main/nosta_clean.sh"
FANCY_URL="https://raw.githubusercontent.com/YOUR_USER/nosta/main/nosta.sh"
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="nosta-music"

detect_pm() {
    if command -v pkg &>/dev/null; then
        echo "pkg"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v apt &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v apk &>/dev/null; then
        echo "apk"
    else
        echo "unknown"
    fi
}

PM=$(detect_pm)

install_pkg() {
    local pkg="$1"
    case "$PM" in
        pkg) pkg install -y "$pkg" ;;
        pacman) sudo pacman -S --noconfirm "$pkg" ;;
        apt) sudo apt-get install -y "$pkg" ;;
        dnf) sudo dnf install -y "$pkg" ;;
        apk) apk add "$pkg" ;;
        *) return 1 ;;
    esac
}

show_logo() {
    if [ "${COLUMNS:-80}" -ge 80 ] 2>/dev/null; then
        echo -e "\033[0;37;40m  \033[0;34;40m▄\033[0;94;40m▄▄▄▄\033[0;37;40m    \033[0;34;40m▄\033[0;94;44m▄▄\033[0;37;40m   \033[0;34;40m▄\033[0;94;40m▄▄▄▄▄\033[0;37;40m        \033[0;34;40m▄\033[0;94;40m▄▄▄▄\033[0;37;40m     \033[0;34;40m▄\033[0;94;40m▄▄▄▄▄▄\033[0;34;40m▄\033[0;37;40m    \033[0;34;40m▄\033[0;94;40m▄▄▄▄▄\033[0;37;40m   \033[0m"
        echo -e "\033[0;34;40m▄\033[0;94;44m▄\033[0;94;40m▀▀\033[0;94;44m▀\033[0;94;40m███\033[0;37;40m  \033[0;94;44m \033[0;94;40m█▀\033[0;37;40m  \033[0;34;40m▄\033[0;94;44m▄\033[0;94;40m█▀\033[0;37;40m  \033[0;34;40m▀\033[0;94;44m▀\033[0;94;40m█▄\033[0;37;40m    \033[0;34;40m▄\033[0;94;44m▄\033[0;94;40m▀\033[0;37;40m \033[0;34;40m▀\033[0;94;44m▀\033[0;94;40m█▀\033[0;37;40m \033[0;34;40m▄\033[0;94;44m▄\033[0;94;40m█▀\033[0;94;44m \033[0;94;40m██\033[0;37;40m  \033[0;94;40m▀█\033[0;94;44m▄\033[0;37;40m \033[0;34;40m▄\033[0;94;44m▄\033[0;94;40m█▀\033[0;37;40m  \033[0;34;40m▀\033[0;94;44m▀\033[0;94;40m█▄\033[0;37;40m \033[0m"
        echo -e "\033[0;94;40m██▄\033[0;37;40m \033[0;94;44m \033[0;94;40m█\033[0;94;44m \033[0;94;40m██\033[0;37;40m \033[0;94;44m \033[0;94;40m█\033[0;37;40m   \033[0;94;44m▐\033[0;94;40m█▌\033[0;37;40m    \033[0;34;40m▐\033[0;94;44m▐\033[0;94;40m█\033[0;94;44m▌\033[0;37;40m  \033[0;94;44m \033[0;94;40m██▄▄\033[0;37;40m     \033[0;94;44m \033[0;94;40m█▀\033[0;37;40m \033[0;34;40m▐\033[0;94;44m▐\033[0;94;40m█▌\033[0;37;40m     \033[0;94;44m▐\033[0;94;40m█\033[0;94;44m▌\033[0;37;40m    \033[0;34;40m▐\033[0;94;44m▐\033[0;94;40m█\033[0;94;44m▌\033[0m"
        echo -e "\033[0;34;40m▀\033[0;94;40m▀\033[0;37;40m  \033[0;32;44m \033[0;94;40m█\033[0;37;40m \033[0;94;44m \033[0;94;40m██\033[0;94;44m \033[0;94;40m█\033[0;37;40m   \033[0;94;44m▐\033[0;94;40m█▌\033[0;37;40m    \033[0;34;40m▐\033[0;94;44m▐\033[0;94;40m█▌\033[0;37;40m   \033[0;34;40m▀\033[0;94;40m▀\033[0;94;44m▀\033[0;94;40m████▄\033[0;37;40m      \033[0;94;44m▐\033[0;94;40m██\033[0;37;40m     \033[0;94;44m▐\033[0;94;40m█\033[0;94;44m▌\033[0;34;40m▀\033[0;94;40m▀▀▀▀██\033[0;94;44m▌\033[0m"
        echo -e "\033[0;37;40m    \033[0;32;44m \033[0;94;40m█\033[0;37;40m  \033[0;94;44m \033[0;94;40m███\033[0;37;40m   \033[0;34;40m█\033[0;94;40m██\033[0;37;40m    \033[0;32;44m \033[0;94;40m██\033[0;37;40m  \033[0;34;40m▄\033[0;94;40m▄\033[0;37;40m     \033[0;34;40m▀\033[0;94;44m▀\033[0;94;40m█\033[0;37;40m      \033[0;34;40m▐\033[0;94;40m██\033[0;37;40m     \033[0;94;44m▐\033[0;94;40m█\033[0;94;44m▌\033[0;37;40m    \033[0;34;40m▐\033[0;94;40m██\033[0;94;44m▌\033[0m"
        echo -e "\033[0;34;40m▀\033[0;94;44m▀\033[0;94;40m██▀\033[0;37;40m    \033[0;94;44m \033[0;94;40m██\033[0;37;40m    \033[0;34;40m▀\033[0;94;44m▀\033[0;94;40m█▄▄\033[0;94;44m▄\033[0;94;40m█▀\033[0;37;40m   \033[0;94;44m▐██\033[0;94;40m▄▄▄▄\033[0;94;44m▄\033[0;94;40m▀\033[0;37;40m       \033[0;34;40m▐\033[0;94;40m██\033[0;37;40m     \033[0;94;44m▐\033[0;94;40m█\033[0;94;44m▌\033[0;37;40m    \033[0;34;40m▐\033[0;94;40m██\033[0;94;44m▌\033[0m"
        echo -e "\033[0;37;40m          \033[0;34;40m▀\033[0;94;40m▀▀\033[0;37;40m               \033[0;34;40m▀\033[0;94;40m▀▀▀\033[0;37;40m                              \033[0m"
        echo ""
    else
        echo -e "${C}  Nosta Music CLI${N}"
        echo -e "${D}  part of Nosta project${N}"
        echo ""
    fi
}

clear
show_logo

echo -e "${D}  This tool manages music uploads, playback, and metadata.${N}"
echo -e "${D}  Connects to: nosta-server.onrender.com${N}"
echo ""

echo -e "${W}Checking dependencies...${N}"

MISSING=()
for cmd in curl jq mpv; do
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${G}✓${N} $cmd"
    else
        echo -e "  ${R}✗${N} $cmd (missing)"
        MISSING+=("$cmd")
    fi
done

if command -v ffmpeg &>/dev/null; then
    echo -e "  ${G}✓${N} ffmpeg (optional)"
else
    echo -e "  ${Y}~${N} ffmpeg (optional, for metadata)"
    MISSING+=("ffmpeg")
fi

echo ""

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -ne "${Y}Install missing packages? (y/n): ${N}"
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        for pkg in "${MISSING[@]}"; do
            echo -e "${B}Installing $pkg...${N}"
            if ! install_pkg "$pkg"; then
                echo -e "${R}Failed to install $pkg. Install manually and re-run.${N}"
                exit 1
            fi
        done
        echo -e "${G}All dependencies installed.${N}"
    else
        echo -e "${R}Cannot continue without required dependencies.${N}"
        exit 1
    fi
else
    echo -e "${G}All dependencies satisfied.${N}"
fi

echo ""

echo -e "${W}Choose interface style:${N}"
echo ""
echo -e "  ${C}[1]${N} ${W}Fancy${N} - Emoji icons, decorative borders, colorful tables"
echo -e "      ${D}Best for modern terminals (Kitty, Alacritty, GNOME Terminal)${N}"
echo ""
echo -e "  ${C}[2]${N} ${W}Basic${N} - Clean, minimal, no emoji. Fast and universal"
echo -e "      ${D}Best for Termux, old terminals, or simplicity lovers${N}"
echo ""
echo -ne "${W}Enter choice (1 or 2): ${N}"
read -r choice

mkdir -p "$INSTALL_DIR"

if [ "$choice" = "1" ]; then
    echo -e "${B}Downloading Fancy UI...${N}"
    curl -sL "$FANCY_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"
    echo -e "${G}Fancy UI installed.${N}"
else
    echo -e "${B}Downloading Basic UI...${N}"
    curl -sL "$CLEAN_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"
    echo -e "${G}Basic UI installed.${N}"
fi

chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo -ne "${Y}Add to PATH (~/.bashrc)? (y/n): ${N}"
    read -r add_path
    if [[ "$add_path" =~ ^[Yy]$ ]]; then
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$HOME/.bashrc"
        echo -e "${G}Added to PATH.${N}"
        echo -e "${Y}Run 'source ~/.bashrc' or restart terminal to apply.${N}"
    else
        echo -e "${D}Skipped. Run with: $INSTALL_DIR/$SCRIPT_NAME${N}"
    fi
fi

echo ""
echo -e "${G}═══════════════════════════════════════${N}"
echo -e "${G}  Nosta Music CLI Installed!${N}"
echo -e "${G}═══════════════════════════════════════${N}"
echo ""
echo -e "  ${W}Run:${N}       ${C}nosta-music${N}"
echo -e "  ${W}Direct:${N}    ${C}$INSTALL_DIR/$SCRIPT_NAME${N}"
echo -e "  ${W}Uninstall:${N} ${C}bash install_nosta_music.sh --uninstall${N}"
echo ""
echo -ne "${W}Launch now? (y/n): ${N}"
read -r launch
if [[ "$launch" =~ ^[Yy]$ ]]; then
    "$INSTALL_DIR/$SCRIPT_NAME"
fi