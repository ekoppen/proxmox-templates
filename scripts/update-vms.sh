#!/bin/bash

# ============================================
# UPDATE-VMS.SH
# Bulk apt update/upgrade via QEMU Guest Agent
#
# Gebruik:
#   ./update-vms.sh --vmid 110
#   ./update-vms.sh --all
#   ./update-vms.sh --all --dry-run
#
# Opties:
#   --vmid N       Update specifieke VM
#   --all          Update alle draaiende VMs
#   --dry-run      Toon wat er zou gebeuren
#   --help         Toon hulptekst
# ============================================

set -e

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
    echo -e "${BLUE}Proxmox VM Updater${NC}"
    echo ""
    echo "Gebruik: $0 [opties]"
    echo ""
    echo "Voert apt update + upgrade uit op VMs via QEMU Guest Agent."
    echo ""
    echo "Opties:"
    echo "  --vmid N       Update specifieke VM"
    echo "  --all          Update alle draaiende VMs"
    echo "  --dry-run      Toon wat er zou gebeuren"
    echo "  --help         Toon deze hulptekst"
    echo ""
    echo "Voorbeelden:"
    echo "  $0 --vmid 110"
    echo "  $0 --all"
    echo "  $0 --all --dry-run"
    exit 0
}

# Update een enkele VM via guest agent
update_vm() {
    local vmid=$1
    local name
    name=$(qm config "$vmid" 2>/dev/null | grep "^name:" | awk '{print $2}')

    # Check of VM draait
    local status
    status=$(qm status "$vmid" 2>/dev/null | awk '{print $2}')
    if [[ "$status" != "running" ]]; then
        log_warn "[$vmid] $name - overgeslagen (niet actief)"
        return 2
    fi

    # Check of guest agent beschikbaar is
    if ! qm guest cmd "$vmid" ping &>/dev/null; then
        log_warn "[$vmid] $name - guest agent niet beschikbaar"
        return 1
    fi

    log_info "[$vmid] $name - apt update + upgrade..."
    if qm guest exec "$vmid" -- bash -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq" 2>/dev/null; then
        log_success "[$vmid] $name - bijgewerkt"
        return 0
    else
        log_warn "[$vmid] $name - update mislukt"
        return 1
    fi
}

# Alle draaiende VMs ophalen (exclusief templates)
get_running_vms() {
    qm list 2>/dev/null | tail -n +2 | while read -r line; do
        local vmid status
        vmid=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $3}')
        if [[ "$status" == "running" ]]; then
            local is_tpl
            is_tpl=$(qm config "$vmid" 2>/dev/null | grep "^template:" | awk '{print $2}')
            [[ "$is_tpl" != "1" ]] && echo "$vmid"
        fi
    done
}

# ── Argumenten verwerken ──────────────────────
[[ $# -eq 0 ]] && usage

VM_ID=""
ALL_VMS=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --vmid)    VM_ID=$2;       shift 2 ;;
        --all)     ALL_VMS=true;   shift ;;
        --dry-run) DRY_RUN=true;   shift ;;
        --help)    usage ;;
        *)         log_error "Onbekende optie: $1 (gebruik --help)" ;;
    esac
done

# Validatie
if [[ "$ALL_VMS" != true && -z "$VM_ID" ]]; then
    log_error "Geef --vmid N of --all op"
fi

# ── Update uitvoeren ────────────────────────
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  VM Updates${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

TOTAL=0
SUCCESS=0
FAILED=0
SKIPPED=0

if [[ "$ALL_VMS" == true ]]; then
    VMIDS=$(get_running_vms)
    if [[ -z "$VMIDS" ]]; then
        log_warn "Geen draaiende VMs gevonden"
        exit 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "Dry-run modus - geen wijzigingen"
        echo ""
        echo "$VMIDS" | while read -r vmid; do
            [[ -z "$vmid" ]] && continue
            local_name=$(qm config "$vmid" 2>/dev/null | grep "^name:" | awk '{print $2}')
            echo -e "  [$vmid] $local_name - ${YELLOW}zou bijgewerkt worden${NC}"
        done
        echo ""
        exit 0
    fi

    echo "$VMIDS" | while read -r vmid; do
        [[ -z "$vmid" ]] && continue
        TOTAL=$((TOTAL + 1))
        update_vm "$vmid"
        rc=$?
        if [[ $rc -eq 0 ]]; then
            SUCCESS=$((SUCCESS + 1))
        elif [[ $rc -eq 2 ]]; then
            SKIPPED=$((SKIPPED + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    done
else
    # Check of VM bestaat
    qm status "$VM_ID" &>/dev/null 2>&1 || log_error "VM $VM_ID niet gevonden"

    if [[ "$DRY_RUN" == true ]]; then
        local_name=$(qm config "$VM_ID" 2>/dev/null | grep "^name:" | awk '{print $2}')
        log_info "Dry-run: [$VM_ID] $local_name zou bijgewerkt worden"
        exit 0
    fi

    TOTAL=1
    update_vm "$VM_ID"
    rc=$?
    if [[ $rc -eq 0 ]]; then
        SUCCESS=1
    elif [[ $rc -eq 2 ]]; then
        SKIPPED=1
    else
        FAILED=1
    fi
fi

# ── Samenvatting ──────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Updates voltooid${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "  Totaal:      $TOTAL"
echo -e "  Bijgewerkt:  ${GREEN}$SUCCESS${NC}"
[[ $SKIPPED -gt 0 ]] && echo -e "  Overgeslagen: ${YELLOW}$SKIPPED${NC}"
[[ $FAILED -gt 0 ]] && echo -e "  Mislukt:     ${RED}$FAILED${NC}"
echo ""
