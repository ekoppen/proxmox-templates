#!/bin/bash

# ============================================
# CREATE-TEMPLATE.SH
# Automatisch Debian cloud-init template aanmaken
#
# Download het officiële Debian cloud image en maakt
# er een Proxmox VM template van met cloud-init support.
#
# Gebruik:
#   ./create-template.sh
#   ./create-template.sh --id 9000 --storage local-lvm
#   ./create-template.sh --id 9001 --bridge vmbr1 --name debian-12-cloud
#
# Opties:
#   --id ID          Template VM ID (standaard: 9000)
#   --storage NAAM   Storage backend (standaard: local-lvm)
#   --bridge NAAM    Netwerk bridge (standaard: vmbr0)
#   --name NAAM      Template naam (standaard: debian-12-cloud)
#   --vlan N         VLAN tag (standaard: geen)
#   --auto           Non-interactief (geen prompts, voor gebruik vanuit menu)
#   --help           Toon deze hulptekst
# ============================================

set -e

# ── Configuratie ──────────────────────────────
TEMPLATE_ID=9000
STORAGE="local-lvm"
BRIDGE="vmbr0"
VLAN_TAG=""
TEMPLATE_NAME="debian-12-cloud"

# Debian 12 Bookworm cloud image
IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
CHECKSUM_URL="https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS"
IMAGE_FILE="/tmp/debian-12-genericcloud-amd64.qcow2"

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
    echo -e "${BLUE}Proxmox Template Creator${NC}"
    echo ""
    echo "Gebruik: $0 [opties]"
    echo ""
    echo "Download het officiële Debian 12 cloud image en maakt"
    echo "er een Proxmox VM template van met cloud-init support."
    echo ""
    echo "Opties:"
    echo "  --id ID          Template VM ID (standaard: $TEMPLATE_ID)"
    echo "  --storage NAAM   Storage backend (standaard: $STORAGE)"
    echo "  --bridge NAAM    Netwerk bridge (standaard: $BRIDGE)"
    echo "  --vlan N         VLAN tag (standaard: geen)"
    echo "  --name NAAM      Template naam (standaard: $TEMPLATE_NAME)"
    echo "  --auto           Non-interactief (geen prompts)"
    echo "  --help           Toon deze hulptekst"
    echo ""
    echo "Voorbeelden:"
    echo "  $0"
    echo "  $0 --id 9001 --storage local-lvm"
    echo "  $0 --id 9000 --bridge vmbr1 --name debian-12-test"
    echo "  $0 --id 9000 --vlan 100"
    exit 0
}

# ── Argumenten verwerken ──────────────────────
AUTO_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --id)      TEMPLATE_ID=$2; shift 2 ;;
        --storage) STORAGE=$2;     shift 2 ;;
        --bridge)  BRIDGE=$2;      shift 2 ;;
        --vlan)    VLAN_TAG=$2;   shift 2 ;;
        --name)    TEMPLATE_NAME=$2; shift 2 ;;
        --auto)    AUTO_MODE=true;  shift ;;
        --help)    usage ;;
        *)         log_error "Onbekende optie: $1 (gebruik --help voor opties)" ;;
    esac
done

# ── Header ────────────────────────────────────
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Debian Cloud Template Aanmaken${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""
log_info "Template ID:  $TEMPLATE_ID"
log_info "Storage:      $STORAGE"
log_info "Bridge:       $BRIDGE"
[[ -n "$VLAN_TAG" ]] && log_info "VLAN:         $VLAN_TAG"
log_info "Naam:         $TEMPLATE_NAME"
echo ""

# ── Stap 1: Vereisten check ──────────────────
log_info "[1/9] Vereisten controleren..."

command -v qm &>/dev/null || log_error "qm niet gevonden - dit script moet op een Proxmox host draaien"
command -v wget &>/dev/null || log_error "wget niet gevonden - installeer met: apt-get install -y wget"

log_success "Alle vereisten aanwezig"

# ── Stap 2: Template check ───────────────────
log_info "[2/9] Bestaande template controleren..."

if qm status "$TEMPLATE_ID" &>/dev/null 2>&1; then
    if [[ "$AUTO_MODE" == true ]]; then
        log_info "Template $TEMPLATE_ID bestaat al - overgeslagen"
        exit 0
    fi
    log_warn "VM/template $TEMPLATE_ID bestaat al"
    echo ""
    echo -e "  ${YELLOW}[O]${NC} Overschrijven (verwijder bestaande VM eerst)"
    echo -e "  ${YELLOW}[A]${NC} Afbreken"
    echo ""
    read -p "  Keuze [A]: " OVERWRITE_CHOICE
    OVERWRITE_CHOICE=${OVERWRITE_CHOICE:-A}

    case $OVERWRITE_CHOICE in
        [Oo])
            log_info "Bestaande VM $TEMPLATE_ID verwijderen..."
            qm stop "$TEMPLATE_ID" 2>/dev/null || true
            qm destroy "$TEMPLATE_ID" --purge 2>/dev/null || true
            log_success "Bestaande VM verwijderd"
            ;;
        *)
            log_info "Afgebroken door gebruiker"
            exit 0
            ;;
    esac
else
    log_success "Template ID $TEMPLATE_ID is beschikbaar"
fi

# ── Stap 3: Image check ──────────────────────
log_info "[3/9] Cloud image controleren..."

DOWNLOAD_IMAGE=true
if [[ -f "$IMAGE_FILE" ]]; then
    if [[ "$AUTO_MODE" == true ]]; then
        DOWNLOAD_IMAGE=false
        log_success "Bestaand image hergebruikt"
    else
        log_warn "Image bestaat al: $IMAGE_FILE"
        echo ""
        echo -e "  ${YELLOW}[H]${NC} Hergebruiken (sla download over)"
        echo -e "  ${YELLOW}[O]${NC} Opnieuw downloaden"
        echo ""
        read -p "  Keuze [H]: " IMAGE_CHOICE
        IMAGE_CHOICE=${IMAGE_CHOICE:-H}

        case $IMAGE_CHOICE in
            [Oo])
                DOWNLOAD_IMAGE=true
                ;;
            *)
                DOWNLOAD_IMAGE=false
                log_success "Bestaand image hergebruikt"
                ;;
        esac
    fi
fi

# ── Stap 4: Download ─────────────────────────
if [[ "$DOWNLOAD_IMAGE" == true ]]; then
    log_info "[4/9] Debian 12 cloud image downloaden..."
    log_info "URL: $IMAGE_URL"
    wget -q --show-progress -O "$IMAGE_FILE" "$IMAGE_URL"
    log_success "Image gedownload naar $IMAGE_FILE"
else
    log_info "[4/9] Download overgeslagen (hergebruik)"
fi

# ── Stap 5: Checksum ─────────────────────────
log_info "[5/9] SHA512 checksum verifiëren..."

CHECKSUM_FILE="/tmp/debian-cloud-SHA512SUMS"
wget -q -O "$CHECKSUM_FILE" "$CHECKSUM_URL"

IMAGE_BASENAME=$(basename "$IMAGE_FILE")
EXPECTED_SUM=$(grep "$IMAGE_BASENAME" "$CHECKSUM_FILE" | awk '{print $1}')

if [[ -z "$EXPECTED_SUM" ]]; then
    log_warn "Checksum niet gevonden voor $IMAGE_BASENAME - verificatie overgeslagen"
else
    ACTUAL_SUM=$(sha512sum "$IMAGE_FILE" | awk '{print $1}')
    if [[ "$EXPECTED_SUM" == "$ACTUAL_SUM" ]]; then
        log_success "Checksum OK"
    else
        log_error "Checksum komt niet overeen! Image is mogelijk corrupt. Verwijder $IMAGE_FILE en probeer opnieuw."
    fi
fi

rm -f "$CHECKSUM_FILE"

# ── Stap 6: VM aanmaken ──────────────────────
log_info "[6/9] VM aanmaken (ID: $TEMPLATE_ID)..."

NET0="virtio,bridge=${BRIDGE}"
[[ -n "$VLAN_TAG" ]] && NET0="${NET0},tag=${VLAN_TAG}"

qm create "$TEMPLATE_ID" \
    --name "$TEMPLATE_NAME" \
    --memory 2048 \
    --cores 2 \
    --net0 "$NET0"

log_success "VM $TEMPLATE_ID aangemaakt"

# ── Stap 7: Disk importeren ──────────────────
log_info "[7/9] Cloud image importeren naar $STORAGE..."

qm importdisk "$TEMPLATE_ID" "$IMAGE_FILE" "$STORAGE" 2>&1 | tail -1

# Detecteer de geïmporteerde disk via unused0 (werkt met LVM-thin én directory storage)
UNUSED_DISK=$(qm config "$TEMPLATE_ID" | grep "^unused0:" | cut -d' ' -f2)

if [[ -z "$UNUSED_DISK" ]]; then
    log_error "Geïmporteerde disk niet gevonden als unused0. Controleer storage configuratie."
fi

log_success "Disk geïmporteerd: $UNUSED_DISK"

# ── Stap 8: VM configureren ──────────────────
log_info "[8/9] Template configureren..."

# Disk koppelen als virtio0
qm set "$TEMPLATE_ID" --virtio0 "$UNUSED_DISK"
log_success "Virtio disk gekoppeld"

# Cloud-init drive toevoegen
qm set "$TEMPLATE_ID" --ide2 "${STORAGE}:cloudinit"
log_success "Cloud-init drive toegevoegd"

# Boot order instellen
qm set "$TEMPLATE_ID" --boot "order=virtio0"
log_success "Boot order ingesteld"

# Serial console voor cloud-init output
qm set "$TEMPLATE_ID" --serial0 socket --vga serial0
log_success "Serial console geconfigureerd"

# QEMU Guest Agent inschakelen
qm set "$TEMPLATE_ID" --agent enabled=1
log_success "QEMU Guest Agent ingeschakeld"

# ── Stap 9: Template converteren ─────────────
log_info "[9/9] VM converteren naar template..."

qm template "$TEMPLATE_ID"
log_success "VM geconverteerd naar template"

# Opruimen
rm -f "$IMAGE_FILE"
log_success "Tijdelijk image opgeruimd"

# ── Samenvatting ──────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Template succesvol aangemaakt!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "  ID:       ${GREEN}$TEMPLATE_ID${NC}"
echo -e "  Naam:     $TEMPLATE_NAME"
echo -e "  Storage:  $STORAGE"
echo -e "  Bridge:   $BRIDGE"
[[ -n "$VLAN_TAG" ]] && echo -e "  VLAN:     $VLAN_TAG"
echo ""
echo "  Je kunt nu VMs aanmaken met:"
echo ""
echo -e "  ${YELLOW}create-vm.sh mijn-vm 110 docker --start${NC}"
echo -e "  ${YELLOW}pve-menu${NC}"
echo ""
