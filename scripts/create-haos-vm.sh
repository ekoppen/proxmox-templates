#!/bin/bash

# ============================================
# CREATE-HAOS-VM.SH
# Home Assistant OS VM aanmaken op Proxmox
#
# Download het officiële HAOS QCOW2 image en maakt
# een UEFI VM aan (geen cloud-init, eigen OS).
#
# Gebruik:
#   ./create-haos-vm.sh <naam> <vmid> [opties]
#
# Voorbeelden:
#   ./create-haos-vm.sh haos 300 --start
#   ./create-haos-vm.sh haos 300 --version 13.2 --start
#
# Opties:
#   --version VER    HAOS versie (standaard: nieuwste)
#   --storage NAAM   Storage backend (standaard: local-lvm)
#   --bridge NAAM    Netwerk bridge (standaard: vmbr0)
#   --cores N        CPU cores (standaard: 2)
#   --memory N       RAM in MB (standaard: 2048)
#   --disk SIZE      Disk grootte (standaard: 32G)
#   --vlan N         VLAN tag (standaard: geen)
#   --start          VM direct starten
#   --help           Toon deze hulptekst
# ============================================

set -e

# ── Configuratie ──────────────────────────────
STORAGE="local-lvm"
BRIDGE="vmbr0"
VLAN_TAG=""
DEFAULT_CORES=2
DEFAULT_MEMORY=2048
DEFAULT_DISK="32G"
HAOS_VERSION=""

# GitHub release URL
GITHUB_REPO="home-assistant/operating-system"
GITHUB_LATEST="https://github.com/${GITHUB_REPO}/releases/latest"

# ── Libraries laden (optioneel) ───────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USE_LIB=false

for lib_path in "$SCRIPT_DIR/../lib" "/root/lib"; do
    if [[ -f "$lib_path/common.sh" ]]; then
        source "$lib_path/common.sh"
        USE_LIB=true
        break
    fi
done

# Fallback kleuren en functies als lib niet beschikbaar
if [[ "$USE_LIB" != true ]]; then
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
    echo -e "${BLUE}Proxmox Home Assistant OS VM Creator${NC}"
    echo ""
    echo "Gebruik: $0 <naam> <vmid> [opties]"
    echo ""
    echo "Maakt een Home Assistant OS VM aan met UEFI boot."
    echo "Dit is een appliance image (geen cloud-init, eigen OS)."
    echo ""
    echo "Opties:"
    echo "  --version VER    HAOS versie (standaard: nieuwste)"
    echo "  --storage NAAM   Storage backend (standaard: $STORAGE)"
    echo "  --bridge NAAM    Netwerk bridge (standaard: $BRIDGE)"
    echo "  --cores N        CPU cores (standaard: $DEFAULT_CORES)"
    echo "  --memory N       RAM in MB (standaard: $DEFAULT_MEMORY)"
    echo "  --disk SIZE      Disk grootte (standaard: $DEFAULT_DISK)"
    echo "  --vlan N         VLAN tag (standaard: geen)"
    echo "  --start          VM direct starten"
    echo "  --help           Toon deze hulptekst"
    echo ""
    echo "Voorbeelden:"
    echo "  $0 haos 300 --start"
    echo "  $0 haos 300 --version 13.2 --start"
    echo "  $0 haos 300 --cores 4 --memory 4096 --disk 64G"
    echo "  $0 haos 300 --vlan 200 --start"
    exit 0
}

detect_latest_version() {
    local redirect_url=""

    # Methode 1: wget (volg redirect, pak versie uit URL)
    if command -v wget &>/dev/null; then
        redirect_url=$(wget -q --max-redirect=0 "$GITHUB_LATEST" 2>&1 | grep -i "Location:" | awk '{print $2}' | tr -d '\r')
    fi

    # Methode 2: fallback naar curl
    if [[ -z "$redirect_url" ]] && command -v curl &>/dev/null; then
        redirect_url=$(curl -sI "$GITHUB_LATEST" 2>/dev/null | grep -i "^location:" | awk '{print $2}' | tr -d '\r')
    fi

    if [[ -z "$redirect_url" ]]; then
        log_error "Kan nieuwste HAOS versie niet detecteren. Geef een versie op met --version"
    fi

    # Versie uit URL halen: .../releases/tag/13.2 → 13.2
    echo "$redirect_url" | grep -oP '/tag/\K[0-9]+\.[0-9]+.*$' | tr -d '\r\n'
}

# ── Argumenten verwerken ──────────────────────
[[ $# -lt 2 ]] && usage

# Eerste argument check op --help
[[ "$1" == "--help" ]] && usage

VM_NAME=$1
VM_ID=$2
shift 2

CORES=$DEFAULT_CORES
MEMORY=$DEFAULT_MEMORY
DISK_SIZE=$DEFAULT_DISK
START_AFTER=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --version) HAOS_VERSION=$2;  shift 2 ;;
        --storage) STORAGE=$2;       shift 2 ;;
        --bridge)  BRIDGE=$2;        shift 2 ;;
        --vlan)    VLAN_TAG=$2;      shift 2 ;;
        --cores)   CORES=$2;         shift 2 ;;
        --memory)  MEMORY=$2;        shift 2 ;;
        --disk)    DISK_SIZE=$2;     shift 2 ;;
        --start)   START_AFTER=true; shift ;;
        --help)    usage ;;
        *)         log_error "Onbekende optie: $1 (gebruik --help voor opties)" ;;
    esac
done

# ── Header ────────────────────────────────────
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Home Assistant OS VM Aanmaken${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

# ── Stap 1: Vereisten check ──────────────────
log_info "[1/8] Vereisten controleren..."

command -v qm &>/dev/null || log_error "qm niet gevonden - dit script moet op een Proxmox host draaien"

# wget of curl moet beschikbaar zijn
if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
    log_error "wget of curl niet gevonden - installeer met: apt-get install -y wget"
fi

command -v xz &>/dev/null || log_error "xz niet gevonden - installeer met: apt-get install -y xz-utils"

log_success "Alle vereisten aanwezig"

# ── Stap 2: VM ID check ──────────────────────
log_info "[2/8] VM ID controleren..."

if qm status "$VM_ID" &>/dev/null 2>&1; then
    log_error "VM ID $VM_ID bestaat al"
fi

log_success "VM ID $VM_ID is beschikbaar"

# ── Stap 3: Versie detectie ──────────────────
log_info "[3/8] HAOS versie bepalen..."

if [[ -z "$HAOS_VERSION" ]]; then
    log_info "Nieuwste versie detecteren via GitHub..."
    HAOS_VERSION=$(detect_latest_version)
    if [[ -z "$HAOS_VERSION" ]]; then
        log_error "Kan versie niet detecteren. Geef een versie op met --version"
    fi
fi

log_success "Versie: $HAOS_VERSION"

# ── Stap 4: Image downloaden ─────────────────
IMAGE_URL="https://github.com/${GITHUB_REPO}/releases/download/${HAOS_VERSION}/haos_ova-${HAOS_VERSION}.qcow2.xz"
IMAGE_XZ="/tmp/haos_ova-${HAOS_VERSION}.qcow2.xz"
IMAGE_FILE="/tmp/haos_ova-${HAOS_VERSION}.qcow2"

log_info "[4/8] HAOS image downloaden..."

if [[ -f "$IMAGE_XZ" ]]; then
    log_success "Image al aanwezig: $IMAGE_XZ (hergebruik)"
else
    log_info "URL: $IMAGE_URL"
    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$IMAGE_XZ" "$IMAGE_URL" || log_error "Download mislukt. Controleer de versie ($HAOS_VERSION)"
    else
        curl -L -o "$IMAGE_XZ" "$IMAGE_URL" || log_error "Download mislukt. Controleer de versie ($HAOS_VERSION)"
    fi
    log_success "Image gedownload"
fi

# ── Stap 5: Image uitpakken ──────────────────
log_info "[5/8] Image uitpakken..."

if [[ -f "$IMAGE_FILE" ]]; then
    log_success "Uitgepakt image al aanwezig (hergebruik)"
else
    xz -d -k "$IMAGE_XZ"
    log_success "Image uitgepakt: $IMAGE_FILE"
fi

# ── Stap 6: VM aanmaken ──────────────────────
log_info "[6/8] VM aanmaken (q35 + UEFI)..."

log_info "Naam:     $VM_NAME"
log_info "VM ID:    $VM_ID"
log_info "Versie:   $HAOS_VERSION"
log_info "Cores:    $CORES"
log_info "Memory:   ${MEMORY}MB"
log_info "Disk:     $DISK_SIZE"
log_info "Storage:  $STORAGE"
log_info "Bridge:   $BRIDGE"
[[ -n "$VLAN_TAG" ]] && log_info "VLAN:     $VLAN_TAG"
echo ""

NET0="virtio,bridge=${BRIDGE}"
[[ -n "$VLAN_TAG" ]] && NET0="${NET0},tag=${VLAN_TAG}"

qm create "$VM_ID" \
    --name "$VM_NAME" \
    --machine q35 \
    --bios ovmf \
    --efidisk0 "${STORAGE}:1,pre-enrolled-keys=0" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --net0 "$NET0" \
    --ostype l26

log_success "VM aangemaakt (q35 + OVMF UEFI)"

# ── Stap 7: Disk importeren ──────────────────
log_info "[7/8] QCOW2 image importeren..."

qm importdisk "$VM_ID" "$IMAGE_FILE" "$STORAGE" 2>&1 | tail -1

# Detecteer geïmporteerde disk via unused0
UNUSED_DISK=$(qm config "$VM_ID" | grep "^unused0:" | cut -d' ' -f2)

if [[ -z "$UNUSED_DISK" ]]; then
    log_error "Geïmporteerde disk niet gevonden als unused0. Controleer storage configuratie."
fi

log_success "Disk geïmporteerd: $UNUSED_DISK"

# ── Stap 8: VM configureren ──────────────────
log_info "[8/8] VM configureren..."

# Disk koppelen als scsi0 met virtio-scsi-single controller
qm set "$VM_ID" --scsihw virtio-scsi-single --scsi0 "$UNUSED_DISK"
log_success "SCSI disk gekoppeld"

# Boot order instellen
qm set "$VM_ID" --boot "order=scsi0"
log_success "Boot order ingesteld"

# Disk resizen naar gewenste grootte
qm disk resize "$VM_ID" scsi0 "$DISK_SIZE"
log_success "Disk geresized naar $DISK_SIZE"

# QEMU Guest Agent inschakelen
qm set "$VM_ID" --agent enabled=1
log_success "QEMU Guest Agent ingeschakeld"

# Serial console
qm set "$VM_ID" --serial0 socket
log_success "Serial console geconfigureerd"

# ── Cleanup ──────────────────────────────────
log_info "Tijdelijke bestanden opruimen..."
rm -f "$IMAGE_XZ" "$IMAGE_FILE"
log_success "Opgeruimd"

# ── Optioneel starten ────────────────────────
IP=""
if [[ "$START_AFTER" == true ]]; then
    log_info "VM starten..."
    qm start "$VM_ID"
    log_success "VM gestart"

    # Wacht op IP adres via QEMU Guest Agent
    log_info "Wachten op IP adres (max 120s)..."
    for i in $(seq 1 24); do
        sleep 5
        IP=$(qm guest cmd "$VM_ID" network-get-interfaces 2>/dev/null | \
             grep -oP '"ip-address"\s*:\s*"\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
             grep -v '^127\.' | head -1) || true
        if [[ -n "$IP" ]]; then
            break
        fi
    done

    if [[ -z "$IP" ]]; then
        log_warn "Geen IP gedetecteerd. HAOS kan even nodig hebben om op te starten."
        log_warn "Controleer de Proxmox console voor het IP adres."
    fi
fi

# ── VM beschrijving instellen ────────────────
VM_NOTES="Type: Home Assistant OS ${HAOS_VERSION} (UEFI appliance)"
if [[ -n "$IP" ]]; then
    VM_NOTES="${VM_NOTES}\nHome Assistant: http://${IP}:8123"
fi
qm set "$VM_ID" --description "$(echo -e "$VM_NOTES")" 2>/dev/null || true

# ── Samenvatting ──────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Home Assistant OS VM aangemaakt!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "  Naam:     ${GREEN}$VM_NAME${NC}"
echo -e "  ID:       $VM_ID"
echo -e "  Versie:   HAOS $HAOS_VERSION"
echo -e "  Cores:    $CORES"
echo -e "  RAM:      ${MEMORY}MB"
echo -e "  Disk:     $DISK_SIZE"
[[ -n "$VLAN_TAG" ]] && echo -e "  VLAN:     $VLAN_TAG"
echo -e "  BIOS:     UEFI (OVMF)"
if [[ -n "$IP" ]]; then
    echo -e "  IP:       ${GREEN}$IP${NC}"
    echo ""
    echo -e "  Toegang:  ${YELLOW}http://$IP:8123${NC}"
else
    echo ""
    echo -e "  ${YELLOW}Start de VM en ga naar http://<IP>:8123${NC}"
fi
echo ""
