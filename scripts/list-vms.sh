#!/bin/bash

# ============================================
# LIST-VMS.SH
# Overzicht van alle VMs met status en IP
# ============================================

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Proxmox VM Overzicht${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

printf "%-8s %-25s %-10s %-6s %-8s %-16s\n" "VMID" "NAAM" "STATUS" "CORES" "RAM" "IP"
printf "%-8s %-25s %-10s %-6s %-8s %-16s\n" "────" "────" "──────" "─────" "───" "──"

for vmid in $(qm list 2>/dev/null | tail -n +2 | awk '{print $1}'); do
    NAME=$(qm config $vmid 2>/dev/null | grep "^name:" | awk '{print $2}')
    STATUS=$(qm status $vmid 2>/dev/null | awk '{print $2}')
    CORES=$(qm config $vmid 2>/dev/null | grep "^cores:" | awk '{print $2}')
    MEMORY=$(qm config $vmid 2>/dev/null | grep "^memory:" | awk '{print $2}')
    IP="-"

    # Probeer IP op te halen als VM draait
    if [[ "$STATUS" == "running" ]]; then
        IP=$(qm guest cmd $vmid network-get-interfaces 2>/dev/null | \
             grep -oP '"ip-address"\s*:\s*"\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
             grep -v '^127\.' | head -1)
        [[ -z "$IP" ]] && IP="wachten..."
        STATUS_COLOR=$GREEN
    else
        STATUS_COLOR=$RED
    fi

    # Template markering
    IS_TEMPLATE=$(qm config $vmid 2>/dev/null | grep "^template:" | awk '{print $2}')
    [[ "$IS_TEMPLATE" == "1" ]] && NAME="${NAME} ${YELLOW}[T]${NC}"

    printf "%-8s %-25b %-10b %-6s %-8s %-16s\n" \
        "$vmid" "$NAME" "${STATUS_COLOR}${STATUS}${NC}" "${CORES:-?}" "${MEMORY:-?}MB" "${IP:-—}"
done

echo ""
