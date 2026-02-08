#!/bin/bash

# ============================================
# COMMON.SH
# Gedeelde functies voor Proxmox VM scripts
# Kleuren, logging, whiptail helpers
# ============================================

# ── Kleuren ───────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Logging ───────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }

# ── Whiptail ──────────────────────────────────
BACKTITLE="Proxmox VM Manager"

check_whiptail() {
    if ! command -v whiptail &>/dev/null; then
        echo -e "${RED}whiptail is niet geinstalleerd.${NC}"
        echo "Installeer met: apt-get install -y whiptail"
        exit 1
    fi
}

# Informatie dialoog
msg_info() {
    whiptail --backtitle "$BACKTITLE" --title "$1" --msgbox "$2" 12 60
}

# Bevestiging dialoog (retourneert 0=ja, 1=nee)
confirm() {
    whiptail --backtitle "$BACKTITLE" --title "$1" --yesno "$2" 10 60 3>&1 1>&2 2>&3
}

# Tekst invoer
input_box() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    whiptail --backtitle "$BACKTITLE" --title "$title" --inputbox "$prompt" 10 60 "$default" 3>&1 1>&2 2>&3
}

# Menu selectie (key-value paren als argumenten)
menu_select() {
    local title="$1"
    local prompt="$2"
    local height="$3"
    shift 3
    whiptail --backtitle "$BACKTITLE" --title "$title" --menu "$prompt" "$height" 70 $((height - 8)) "$@" 3>&1 1>&2 2>&3
}

# Radio selectie (key-value-status triples als argumenten)
radio_select() {
    local title="$1"
    local prompt="$2"
    local height="$3"
    shift 3
    whiptail --backtitle "$BACKTITLE" --title "$title" --radiolist "$prompt" "$height" 70 $((height - 8)) "$@" 3>&1 1>&2 2>&3
}

# ── Hulpfuncties ──────────────────────────────

# Volgende beschikbare VM ID
next_vmid() {
    local start=${1:-100}
    local vmid=$start
    while qm status "$vmid" &>/dev/null 2>&1; do
        vmid=$((vmid + 1))
    done
    echo "$vmid"
}

# ASCII banner
show_banner() {
    echo -e "${CYAN}"
    echo '  ____  __     __ _____   __  __                                '
    echo ' |  _ \ \ \   / /| ____| |  \/  |  __ _  _ __    __ _   __ _  ___ _ __ '
    echo ' | |_) | \ \ / / |  _|   | |\/| | / _` || `_ \  / _` | / _` |/ _ \ `__|'
    echo ' |  __/   \ V /  | |___  | |  | || (_| || | | || (_| || (_| ||  __/ |   '
    echo ' |_|       \_/   |_____| |_|  |_| \__,_||_| |_| \__,_| \__, |\___|_|   '
    echo '                                                        |___/           '
    echo -e "${NC}"
}
