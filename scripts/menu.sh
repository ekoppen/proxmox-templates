#!/bin/bash

# ============================================
# MENU.SH
# Interactief whiptail menu voor Proxmox VMs
# Inspired by tteck/community-scripts
#
# Gebruik:
#   ./menu.sh          (interactief menu)
#   pve-menu           (via symlink na installatie)
# ============================================

set -e

# ── Pad detectie ──────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Zoek lib directory (naast scripts/ of in /root/lib/)
if [[ -f "$SCRIPT_DIR/../lib/common.sh" ]]; then
    LIB_DIR="$SCRIPT_DIR/../lib"
elif [[ -f "/root/lib/common.sh" ]]; then
    LIB_DIR="/root/lib"
else
    echo "FOUT: lib/ directory niet gevonden"
    echo "Verwacht in: $SCRIPT_DIR/../lib/ of /root/lib/"
    exit 1
fi

# ── Libraries laden ───────────────────────────
source "$LIB_DIR/common.sh"
source "$LIB_DIR/defaults.sh"

# ── Whiptail check ────────────────────────────
check_whiptail

# ── Welkomscherm ──────────────────────────────
show_welcome() {
    whiptail --backtitle "$BACKTITLE" --title "Welkom" --msgbox \
"Proxmox VM Manager

Maak snel nieuwe VMs aan vanuit cloud-init templates.
Selecteer een servertype, pas eventueel de instellingen
aan en de VM wordt automatisch aangemaakt.

Beschikbare types:
$(for key in "${TYPE_ORDER[@]}"; do
    printf "  %-12s %s\n" "$key" "${TYPE_DESCRIPTIONS[$key]}"
done)" 20 65
}

# ── Server type selectie ──────────────────────
select_type() {
    local menu_items=()
    for key in "${TYPE_ORDER[@]}"; do
        menu_items+=("$key" "${TYPE_LABELS[$key]} - ${TYPE_DESCRIPTIONS[$key]}")
    done

    SELECTED_TYPE=$(menu_select "Server Type" "Kies een server type:" 20 "${menu_items[@]}") || return 1
}

# ── Modus selectie ────────────────────────────
select_mode() {
    MODE=$(menu_select "Installatie Modus" "Kies een modus:" 12 \
        "standaard" "Standaard (aanbevolen) - automatische instellingen" \
        "geavanceerd" "Geavanceerd - alle opties handmatig instellen") || return 1
}

# ── VM naam en ID invoer ──────────────────────
input_vm_basics() {
    # VM Naam
    VM_NAME=$(input_box "VM Naam" "Geef een naam voor de VM:" "${SELECTED_TYPE}-01") || return 1
    [[ -z "$VM_NAME" ]] && { msg_info "Fout" "VM naam mag niet leeg zijn."; return 1; }

    # VM ID - suggereer volgende beschikbare
    local suggested_id
    suggested_id=$(next_vmid 100)
    VM_ID=$(input_box "VM ID" "Geef een VM ID (nummer):" "$suggested_id") || return 1
    [[ -z "$VM_ID" ]] && { msg_info "Fout" "VM ID mag niet leeg zijn."; return 1; }

    # Valideer dat ID een nummer is
    if ! [[ "$VM_ID" =~ ^[0-9]+$ ]]; then
        msg_info "Fout" "VM ID moet een nummer zijn."
        return 1
    fi

    # Check of ID al in gebruik is
    if qm status "$VM_ID" &>/dev/null 2>&1; then
        msg_info "Fout" "VM ID $VM_ID is al in gebruik.\nKies een ander ID."
        return 1
    fi
}

# ── Geavanceerde opties ──────────────────────
input_advanced() {
    # CPU cores
    local default_cores="${TYPE_CORES[$SELECTED_TYPE]}"
    CORES=$(input_box "CPU Cores" "Aantal CPU cores:" "$default_cores") || return 1

    # Memory
    local default_memory="${TYPE_MEMORY[$SELECTED_TYPE]}"
    MEMORY=$(input_box "RAM (MB)" "RAM in megabytes:" "$default_memory") || return 1

    # Disk size
    local default_disk="${TYPE_DISK[$SELECTED_TYPE]}"
    if [[ -n "$default_disk" ]]; then
        DISK_SIZE=$(input_box "Disk Grootte" "Disk grootte (bijv. 50G, leeg = niet resizen):" "$default_disk") || return 1
    else
        DISK_SIZE=$(input_box "Disk Grootte" "Disk grootte (bijv. 32G, leeg = niet resizen):" "") || return 1
    fi

    # Clone type
    CLONE_TYPE=$(menu_select "Clone Type" "Kies clone type:" 12 \
        "linked" "Linked clone (snel, deelt base disk)" \
        "full" "Full clone (onafhankelijk, meer ruimte)") || return 1

    # Auto-start
    if confirm "Auto-start" "VM direct starten na aanmaken?"; then
        START_AFTER="--start"
    else
        START_AFTER=""
    fi
}

# ── Bevestigingsscherm ────────────────────────
show_confirmation() {
    local disk_info="niet resizen"
    [[ -n "$DISK_SIZE" ]] && disk_info="$DISK_SIZE"

    local start_info="Nee"
    [[ -n "$START_AFTER" ]] && start_info="Ja"

    local postinfo="${TYPE_POSTINFO[$SELECTED_TYPE]}"
    local postinfo_line=""
    [[ -n "$postinfo" ]] && postinfo_line="\nToegang:    $postinfo"

    whiptail --backtitle "$BACKTITLE" --title "Bevestiging" --yesno \
"De volgende VM wordt aangemaakt:

  Naam:       $VM_NAME
  ID:         $VM_ID
  Type:       ${TYPE_LABELS[$SELECTED_TYPE]}
  Cores:      $CORES
  RAM:        ${MEMORY}MB
  Disk:       $disk_info
  Clone:      $CLONE_TYPE
  Auto-start: $start_info
$postinfo_line

Doorgaan?" 22 60
}

# ── VM aanmaken ───────────────────────────────
create_vm() {
    local cmd_args=("$VM_NAME" "$VM_ID" "$SELECTED_TYPE")
    cmd_args+=("--cores" "$CORES")
    cmd_args+=("--memory" "$MEMORY")
    [[ -n "$DISK_SIZE" ]] && cmd_args+=("--disk" "$DISK_SIZE")
    [[ "$CLONE_TYPE" == "full" ]] && cmd_args+=("--full")
    [[ -n "$START_AFTER" ]] && cmd_args+=("--start")

    # Zoek create-vm.sh
    local create_script
    if [[ -f "$SCRIPT_DIR/create-vm.sh" ]]; then
        create_script="$SCRIPT_DIR/create-vm.sh"
    elif [[ -f "/root/scripts/create-vm.sh" ]]; then
        create_script="/root/scripts/create-vm.sh"
    else
        log_error "create-vm.sh niet gevonden"
    fi

    clear
    show_banner
    echo -e "${BLUE}VM aanmaken met de volgende instellingen:${NC}"
    echo ""

    # Voer create-vm.sh uit
    bash "$create_script" "${cmd_args[@]}"
    local exit_code=$?

    echo ""
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}Druk op Enter om terug te gaan naar het menu...${NC}"
    else
        echo -e "${RED}Er is een fout opgetreden. Druk op Enter om terug te gaan...${NC}"
    fi
    read -r
}

# ── VM overzicht ──────────────────────────────
show_vm_list() {
    local list_script
    if [[ -f "$SCRIPT_DIR/list-vms.sh" ]]; then
        list_script="$SCRIPT_DIR/list-vms.sh"
    elif [[ -f "/root/scripts/list-vms.sh" ]]; then
        list_script="/root/scripts/list-vms.sh"
    else
        msg_info "Fout" "list-vms.sh niet gevonden"
        return
    fi

    clear
    bash "$list_script"
    echo ""
    echo -e "${GREEN}Druk op Enter om terug te gaan naar het menu...${NC}"
    read -r
}

# ── VM verwijderen ────────────────────────────
delete_vm_menu() {
    local vmid
    vmid=$(input_box "VM Verwijderen" "Geef het VM ID om te verwijderen:" "") || return
    [[ -z "$vmid" ]] && return

    if ! qm status "$vmid" &>/dev/null 2>&1; then
        msg_info "Fout" "VM $vmid niet gevonden."
        return
    fi

    local name
    name=$(qm config "$vmid" 2>/dev/null | grep "^name:" | awk '{print $2}')

    if confirm "Bevestiging" "VM $vmid ($name) verwijderen?\n\nDit kan niet ongedaan gemaakt worden!"; then
        clear
        local delete_script
        if [[ -f "$SCRIPT_DIR/delete-vm.sh" ]]; then
            delete_script="$SCRIPT_DIR/delete-vm.sh"
        elif [[ -f "/root/scripts/delete-vm.sh" ]]; then
            delete_script="/root/scripts/delete-vm.sh"
        else
            log_error "delete-vm.sh niet gevonden"
        fi
        bash "$delete_script" "$vmid" --force
        echo ""
        echo -e "${GREEN}Druk op Enter om terug te gaan naar het menu...${NC}"
        read -r
    fi
}

# ── Template check ───────────────────────────
check_template() {
    # Lees TEMPLATE_ID uit create-vm.sh
    local create_script=""
    if [[ -f "$SCRIPT_DIR/create-vm.sh" ]]; then
        create_script="$SCRIPT_DIR/create-vm.sh"
    elif [[ -f "/root/scripts/create-vm.sh" ]]; then
        create_script="/root/scripts/create-vm.sh"
    else
        return 0
    fi

    local tpl_id
    tpl_id=$(grep "^TEMPLATE_ID=" "$create_script" | head -1 | cut -d'=' -f2 | awk '{print $1}')
    [[ -z "$tpl_id" ]] && return 0

    # Check of template bestaat
    if ! qm status "$tpl_id" &>/dev/null 2>&1; then
        if confirm "Template Ontbreekt" \
            "Template $tpl_id niet gevonden.\n\nWil je automatisch een Debian 12 cloud template aanmaken?\n\n(Dit downloadt het officiële cloud image en maakt een template aan)"; then

            # Zoek create-template.sh
            local tpl_script=""
            if [[ -f "$SCRIPT_DIR/create-template.sh" ]]; then
                tpl_script="$SCRIPT_DIR/create-template.sh"
            elif [[ -f "/root/scripts/create-template.sh" ]]; then
                tpl_script="/root/scripts/create-template.sh"
            fi

            if [[ -n "$tpl_script" ]]; then
                clear
                show_banner
                echo -e "${BLUE}Template aanmaken...${NC}"
                echo ""
                bash "$tpl_script" --id "$tpl_id" --auto
                local exit_code=$?
                echo ""
                if [[ $exit_code -eq 0 ]]; then
                    echo -e "${GREEN}Template aangemaakt. Druk op Enter om door te gaan...${NC}"
                else
                    echo -e "${RED}Template aanmaken mislukt. Druk op Enter om terug te gaan...${NC}"
                    read -r
                    return 1
                fi
                read -r
            else
                msg_info "Fout" "create-template.sh niet gevonden.\n\nInstalleer opnieuw met install.sh."
                return 1
            fi
        else
            # Gebruiker kiest "Nee" - terug naar menu
            return 1
        fi
    fi
    return 0
}

# ── VM Aanmaak Flow ──────────────────────────
create_vm_flow() {
    # Template check
    check_template || return

    # Stap 1: Type selecteren
    select_type || return

    # Stap 2: Modus kiezen
    select_mode || return

    # Stap 3: Naam en ID
    input_vm_basics || return

    # Stap 4: Defaults of geavanceerd
    if [[ "$MODE" == "geavanceerd" ]]; then
        input_advanced || return
    else
        # Standaard: defaults uit registry
        CORES="${TYPE_CORES[$SELECTED_TYPE]}"
        MEMORY="${TYPE_MEMORY[$SELECTED_TYPE]}"
        DISK_SIZE="${TYPE_DISK[$SELECTED_TYPE]}"
        CLONE_TYPE="linked"
        START_AFTER="--start"
    fi

    # Stap 5: Bevestigen
    show_confirmation || return

    # Stap 6: Uitvoeren
    create_vm
}

# ── Hoofdmenu ─────────────────────────────────
main_menu() {
    while true; do
        local choice
        choice=$(menu_select "Hoofdmenu" "Wat wil je doen?" 14 \
            "aanmaken"   "VM aanmaken" \
            "overzicht"  "VM overzicht" \
            "verwijderen" "VM verwijderen" \
            "afsluiten"  "Menu sluiten") || break

        case "$choice" in
            aanmaken)    create_vm_flow ;;
            overzicht)   show_vm_list ;;
            verwijderen) delete_vm_menu ;;
            afsluiten)   break ;;
        esac
    done
}

# ── Main ──────────────────────────────────────
show_welcome
main_menu

clear
show_banner
echo -e "${GREEN}Tot ziens!${NC}"
echo ""
