#!/bin/bash

# ============================================
# QUICK CREATE SHORTCUTS
# Snelle one-liners voor veelgebruikte setups
#
# Gebruik:
#   ./quick-docker.sh <naam> <vmid> [--start]
#   ./quick-webserver.sh <naam> <vmid> [--start]
#   ./quick-homelab.sh <naam> <vmid> [--start]
#   ./quick-supabase.sh <naam> <vmid> [--start]
#   ./quick-coolify.sh <naam> <vmid> [--start]
#   ./quick-minio.sh <naam> <vmid> [--start]
#   ./quick-appwrite.sh <naam> <vmid> [--start]
# ============================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load lang file for error message
for _lp in "$SCRIPT_DIR/../lib" "/root/lib"; do
    if [[ -f "$_lp/config.sh" ]]; then source "$_lp/config.sh" 2>/dev/null || true; fi
    LANG_CHOICE="${LANG_CHOICE:-en}"
    if [[ -f "$_lp/lang/${LANG_CHOICE}.sh" ]]; then
        source "$_lp/lang/${LANG_CHOICE}.sh"
        break
    fi
done

case "$(basename "$0")" in
    quick-docker.sh)
        exec "$SCRIPT_DIR/create-vm.sh" "$1" "$2" docker --cores 4 --memory 4096 --disk 50G "${@:3}" ;;
    quick-webserver.sh)
        exec "$SCRIPT_DIR/create-vm.sh" "$1" "$2" webserver --cores 2 --memory 2048 --disk 20G "${@:3}" ;;
    quick-homelab.sh)
        exec "$SCRIPT_DIR/create-vm.sh" "$1" "$2" homelab --cores 4 --memory 4096 --disk 50G "${@:3}" ;;
    quick-supabase.sh)
        exec "$SCRIPT_DIR/create-vm.sh" "$1" "$2" supabase --cores 4 --memory 8192 --disk 50G "${@:3}" ;;
    quick-coolify.sh)
        exec "$SCRIPT_DIR/create-vm.sh" "$1" "$2" coolify --cores 2 --memory 2048 --disk 30G "${@:3}" ;;
    quick-minio.sh)
        exec "$SCRIPT_DIR/create-vm.sh" "$1" "$2" minio --cores 4 --memory 4096 --disk 50G "${@:3}" ;;
    quick-appwrite.sh)
        exec "$SCRIPT_DIR/create-vm.sh" "$1" "$2" appwrite --cores 4 --memory 4096 --disk 50G "${@:3}" ;;
    *)
        echo "$MSG_QUICK_UNKNOWN"
        exit 1 ;;
esac
