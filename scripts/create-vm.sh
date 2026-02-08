#!/bin/bash

# ============================================
# CREATE-VM.SH
# Snel VMs aanmaken vanuit Proxmox templates
#
# Gebruik:
#   ./create-vm.sh <naam> <vmid> <type> [opties]
#
# Types:
#   base       - Kale Debian server
#   docker     - Docker + Portainer
#   webserver  - Nginx + Certbot + UFW
#   homelab    - Docker + NFS + homelab tools
#   supabase   - Self-hosted Supabase
#   coolify    - Self-hosted PaaS (Coolify)
#
# Voorbeelden:
#   ./create-vm.sh web-01 110 webserver
#   ./create-vm.sh docker-prod 120 docker --cores 4 --memory 8192
#   ./create-vm.sh test-vm 130 base --full
# ============================================

set -e

# ── Configuratie ──────────────────────────────
TEMPLATE_ID=9000                          # ID van je Debian template
STORAGE="local-lvm"                       # Storage voor VM disks
SNIPPET_STORAGE="local"                   # Storage waar snippets staan
SNIPPET_PATH="snippets"                   # Pad binnen storage
DEFAULT_CORES=2
DEFAULT_MEMORY=2048                       # MB
DEFAULT_DISK_SIZE=""                      # Leeg = niet resizen
CLONE_TYPE="linked"                       # linked of full

# ── Libraries laden (optioneel) ───────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USE_REGISTRY=false

for lib_path in "$SCRIPT_DIR/../lib" "/root/lib"; do
    if [[ -f "$lib_path/defaults.sh" ]]; then
        source "$lib_path/common.sh" 2>/dev/null || true
        source "$lib_path/defaults.sh"
        USE_REGISTRY=true
        break
    fi
done

# Fallback kleuren en functies als lib niet beschikbaar
if [[ "$USE_REGISTRY" != true ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
    log_success() { echo -e "${GREEN}[OK]${NC}   $1"; }
    log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_error()   { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }
fi

# ── Functies ──────────────────────────────────
usage() {
    echo -e "${BLUE}Proxmox VM Creator${NC}"
    echo ""
    echo "Gebruik: $0 <naam> <vmid> <type> [opties]"
    echo ""
    echo "Types:"
    if [[ "$USE_REGISTRY" == true ]]; then
        for key in "${TYPE_ORDER[@]}"; do
            printf "  %-12s %s\n" "$key" "${TYPE_DESCRIPTIONS[$key]}"
        done
    else
        echo "  base       Kale Debian server"
        echo "  docker     Docker + Docker Compose + Portainer"
        echo "  webserver  Nginx + Certbot + UFW firewall"
        echo "  homelab    Docker + NFS client + homelab tools"
    fi
    echo ""
    echo "Opties:"
    echo "  --cores N      Aantal CPU cores (standaard: $DEFAULT_CORES)"
    echo "  --memory N     RAM in MB (standaard: $DEFAULT_MEMORY)"
    echo "  --disk SIZE    Disk resizen, bijv. 32G (standaard: niet resizen)"
    echo "  --full         Full clone i.p.v. linked clone"
    echo "  --start        VM direct starten na aanmaken"
    echo ""
    echo "Voorbeelden:"
    echo "  $0 web-01 110 webserver"
    echo "  $0 docker-prod 120 docker --cores 4 --memory 8192 --disk 50G --start"
    exit 1
}

get_snippet() {
    local type=$1
    if [[ "$USE_REGISTRY" == true ]]; then
        local result
        result=$(get_snippet_for_type "$type" "$SNIPPET_STORAGE" "$SNIPPET_PATH")
        if [[ -n "$result" ]]; then
            echo "$result"
        else
            log_error "Onbekend type: $type (gebruik '$0' zonder argumenten voor beschikbare types)"
        fi
    else
        case $type in
            base)      echo "${SNIPPET_STORAGE}:${SNIPPET_PATH}/base-cloud-config.yaml" ;;
            docker)    echo "${SNIPPET_STORAGE}:${SNIPPET_PATH}/docker-cloud-config.yaml" ;;
            webserver) echo "${SNIPPET_STORAGE}:${SNIPPET_PATH}/webserver-cloud-config.yaml" ;;
            homelab)   echo "${SNIPPET_STORAGE}:${SNIPPET_PATH}/homelab-cloud-config.yaml" ;;
            *)         log_error "Onbekend type: $type (kies uit: base, docker, webserver, homelab)" ;;
        esac
    fi
}

get_defaults_for_type() {
    local type=$1
    if [[ "$USE_REGISTRY" == true ]]; then
        apply_defaults_for_type "$type" || log_error "Onbekend type: $type"
    else
        case $type in
            base)      CORES=${CORES:-$DEFAULT_CORES}; MEMORY=${MEMORY:-$DEFAULT_MEMORY} ;;
            docker)    CORES=${CORES:-4};               MEMORY=${MEMORY:-4096} ;;
            webserver) CORES=${CORES:-2};               MEMORY=${MEMORY:-2048} ;;
            homelab)   CORES=${CORES:-4};               MEMORY=${MEMORY:-4096} ;;
            *)         log_error "Onbekend type: $type" ;;
        esac
    fi
}

# ── Argumenten verwerken ──────────────────────
[[ $# -lt 3 ]] && usage

VM_NAME=$1
VM_ID=$2
VM_TYPE=$3
shift 3

CORES=""
MEMORY=""
DISK_SIZE="$DEFAULT_DISK_SIZE"
START_AFTER=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --cores)   CORES=$2;      shift 2 ;;
        --memory)  MEMORY=$2;     shift 2 ;;
        --disk)    DISK_SIZE=$2;  shift 2 ;;
        --full)    CLONE_TYPE="full"; shift ;;
        --start)   START_AFTER=true;  shift ;;
        *)         log_error "Onbekende optie: $1" ;;
    esac
done

# Type-specifieke defaults toepassen
get_defaults_for_type "$VM_TYPE"

SNIPPET=$(get_snippet "$VM_TYPE")

# ── Validatie ─────────────────────────────────
# Check of template bestaat
qm status $TEMPLATE_ID &>/dev/null || log_error "Template $TEMPLATE_ID niet gevonden"

# Check of VM ID al bestaat
if qm status $VM_ID &>/dev/null 2>&1; then
    log_error "VM ID $VM_ID bestaat al"
fi

# Check of snippet bestand bestaat
SNIPPET_FILE="/var/lib/vz/${SNIPPET_PATH}/$(basename "$SNIPPET")"
[[ -f "$SNIPPET_FILE" ]] || log_error "Snippet niet gevonden: $SNIPPET_FILE"

# ── VM aanmaken ───────────────────────────────
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  VM aanmaken: ${GREEN}$VM_NAME${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""
log_info "Type:     $VM_TYPE"
log_info "VM ID:    $VM_ID"
log_info "Clone:    $CLONE_TYPE"
log_info "Cores:    $CORES"
log_info "Memory:   ${MEMORY}MB"
log_info "Snippet:  $SNIPPET"
[[ -n "$DISK_SIZE" ]] && log_info "Disk:     $DISK_SIZE"
echo ""

# Clone
log_info "Template $TEMPLATE_ID klonen..."
if [[ "$CLONE_TYPE" == "full" ]]; then
    qm clone $TEMPLATE_ID $VM_ID --name "$VM_NAME" --full 1
else
    qm clone $TEMPLATE_ID $VM_ID --name "$VM_NAME" --full 0
fi
log_success "VM gekloond"

# Resources instellen
log_info "Resources configureren..."
qm set $VM_ID --cores "$CORES" --memory "$MEMORY"
log_success "CPU: ${CORES} cores, RAM: ${MEMORY}MB"

# Cloud-init snippet koppelen
log_info "Cloud-init configureren..."
qm set $VM_ID --cicustom "user=${SNIPPET}"
qm set $VM_ID --ipconfig0 ip=dhcp
log_success "Snippet gekoppeld: $SNIPPET"

# Disk resizen indien gewenst
if [[ -n "$DISK_SIZE" ]]; then
    log_info "Disk resizen naar $DISK_SIZE..."
    qm disk resize $VM_ID virtio0 "$DISK_SIZE"
    log_success "Disk geresized naar $DISK_SIZE"
fi

# Starten indien gewenst
if [[ "$START_AFTER" == true ]]; then
    log_info "VM starten..."
    qm start $VM_ID
    log_success "VM gestart"

    # Wacht op QEMU Guest Agent voor IP adres
    log_info "Wachten op IP adres (max 60s)..."
    for i in $(seq 1 12); do
        sleep 5
        IP=$(qm guest cmd $VM_ID network-get-interfaces 2>/dev/null | \
             grep -oP '"ip-address"\s*:\s*"\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
             grep -v '^127\.' | head -1)
        if [[ -n "$IP" ]]; then
            break
        fi
    done
fi

# ── Samenvatting ──────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  VM succesvol aangemaakt!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "  Naam:     ${GREEN}$VM_NAME${NC}"
echo -e "  ID:       $VM_ID"
echo -e "  Type:     $VM_TYPE"
echo -e "  Cores:    $CORES"
echo -e "  RAM:      ${MEMORY}MB"
if [[ -n "$IP" ]]; then
    echo -e "  IP:       ${GREEN}$IP${NC}"
    echo ""
    echo -e "  SSH:      ${YELLOW}ssh admin@$IP${NC}"

    # Type-specifieke toegangsinformatie
    if [[ "$USE_REGISTRY" == true ]]; then
        POSTINFO=$(get_postinfo "$VM_TYPE")
        if [[ -n "$POSTINFO" ]]; then
            echo -e "  Toegang:  ${YELLOW}${POSTINFO//<IP>/$IP}${NC}"
        fi
    else
        [[ "$VM_TYPE" == "docker" || "$VM_TYPE" == "homelab" ]] && \
            echo -e "  Portainer: ${YELLOW}https://$IP:9443${NC}"
    fi
fi
echo ""
