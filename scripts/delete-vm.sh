#!/bin/bash

# ============================================
# DELETE-VM.SH
# VM verwijderen met bevestiging
#
# Gebruik:
#   ./delete-vm.sh <vmid>
#   ./delete-vm.sh <vmid> --force   (zonder bevestiging)
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

[[ -z "$1" ]] && { echo "Gebruik: $0 <vmid> [--force]"; exit 1; }

VM_ID=$1
FORCE=false
[[ "$2" == "--force" ]] && FORCE=true

# Check of VM bestaat
qm status $VM_ID &>/dev/null 2>&1 || { echo -e "${RED}VM $VM_ID niet gevonden${NC}"; exit 1; }

# Haal info op
NAME=$(qm config $VM_ID 2>/dev/null | grep "^name:" | awk '{print $2}')
STATUS=$(qm status $VM_ID 2>/dev/null | awk '{print $2}')
IS_TEMPLATE=$(qm config $VM_ID 2>/dev/null | grep "^template:" | awk '{print $2}')

# Bescherming tegen per-ongeluk template verwijderen
if [[ "$IS_TEMPLATE" == "1" ]]; then
    echo -e "${RED}WAARSCHUWING: VM $VM_ID ($NAME) is een TEMPLATE!${NC}"
    echo -e "${RED}Templates kunnen niet verwijderd worden met dit script.${NC}"
    echo -e "${RED}Gebruik 'qm set $VM_ID --template 0' om eerst de template status te verwijderen.${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}VM verwijderen:${NC}"
echo -e "  ID:     $VM_ID"
echo -e "  Naam:   $NAME"
echo -e "  Status: $STATUS"
echo ""

if [[ "$FORCE" != true ]]; then
    read -p "Weet je het zeker? (ja/nee): " CONFIRM
    [[ "$CONFIRM" != "ja" ]] && { echo "Geannuleerd."; exit 0; }
fi

# Stop VM als die draait
if [[ "$STATUS" == "running" ]]; then
    echo -e "${BLUE}[INFO]${NC} VM stoppen..."
    qm stop $VM_ID
    sleep 3
fi

# Verwijder VM
echo -e "${BLUE}[INFO]${NC} VM verwijderen..."
qm destroy $VM_ID --purge
echo -e "${GREEN}[OK]${NC}   VM $VM_ID ($NAME) verwijderd"
echo ""
