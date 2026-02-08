#!/bin/bash

# ============================================
# SETUP.SH
# Eerste keer configuratie - personaliseert de
# cloud-init configs met jouw instellingen
#
# Gebruik:
#   bash setup.sh
#   bash setup.sh --ssh-key "ssh-ed25519 AAAA..."
# ============================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Argument parsing ──────────────────────────
SSH_KEY_ARG=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --ssh-key) SSH_KEY_ARG="$2"; shift 2 ;;
        *)         shift ;;
    esac
done

# ── Header ────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Proxmox Templates - Setup Wizard      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo "  Dit script configureert de templates met"
echo "  jouw persoonlijke instellingen."
echo ""

# ── Stap 1: SSH Key ──────────────────────────
echo -e "${BOLD}Stap 1/3: SSH Public Key${NC}"
echo -e "─────────────────────────────────────────"
echo ""

SSH_KEY=""

# Check of er een key via argument is meegegeven
if [[ -n "$SSH_KEY_ARG" ]]; then
    SSH_KEY="$SSH_KEY_ARG"
    echo -e "  SSH key via argument: ${GREEN}✓${NC}"
    echo "  ${SSH_KEY:0:50}..."
    echo ""
else
    # Zoek automatisch naar lokale SSH keys
    FOUND_KEYS=()
    KEY_FILES=()

    for keyfile in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
        if [[ -f "$keyfile" ]]; then
            FOUND_KEYS+=("$(cat "$keyfile")")
            KEY_FILES+=("$keyfile")
        fi
    done

    if [[ ${#FOUND_KEYS[@]} -gt 0 ]]; then
        echo "  Gevonden SSH keys op dit systeem:"
        echo ""
        for i in "${!FOUND_KEYS[@]}"; do
            KEY_TYPE=$(echo "${FOUND_KEYS[$i]}" | awk '{print $1}')
            KEY_COMMENT=$(echo "${FOUND_KEYS[$i]}" | awk '{print $3}')
            echo -e "  ${GREEN}[$((i+1))]${NC} ${KEY_FILES[$i]}"
            echo "      Type: $KEY_TYPE"
            [[ -n "$KEY_COMMENT" ]] && echo "      Comment: $KEY_COMMENT"
            echo ""
        done

        echo -e "  ${GREEN}[P]${NC} Plak een andere key"
        echo -e "  ${YELLOW}[S]${NC} Sla over (later handmatig invullen)"
        echo ""
        read -p "  Keuze [1]: " KEY_CHOICE
        KEY_CHOICE=${KEY_CHOICE:-1}

        case $KEY_CHOICE in
            [0-9])
                IDX=$((KEY_CHOICE - 1))
                if [[ $IDX -ge 0 && $IDX -lt ${#FOUND_KEYS[@]} ]]; then
                    SSH_KEY="${FOUND_KEYS[$IDX]}"
                    echo -e "  ${GREEN}✓${NC} Key geselecteerd: ${KEY_FILES[$IDX]}"
                else
                    echo -e "  ${RED}Ongeldige keuze${NC}"
                fi
                ;;
            [Pp])
                echo ""
                echo "  Plak je volledige SSH public key:"
                echo "  (begint met ssh-ed25519, ssh-rsa, of ecdsa-...)"
                echo ""
                read -r SSH_KEY
                ;;
            [Ss])
                echo -e "  ${YELLOW}Overgeslagen - pas YOUR_SSH_PUBLIC_KEY_HERE later aan${NC}"
                ;;
        esac
    else
        echo "  Geen SSH keys gevonden op dit systeem."
        echo ""
        echo "  Je kunt:"
        echo -e "  ${GREEN}[P]${NC} Een SSH public key plakken"
        echo -e "  ${GREEN}[G]${NC} Een nieuwe key genereren"
        echo -e "  ${YELLOW}[S]${NC} Overslaan"
        echo ""
        read -p "  Keuze [P]: " KEY_CHOICE
        KEY_CHOICE=${KEY_CHOICE:-P}

        case $KEY_CHOICE in
            [Pp])
                echo ""
                echo "  Plak je volledige SSH public key:"
                read -r SSH_KEY
                ;;
            [Gg])
                echo ""
                read -p "  E-mail of comment voor de key [$(whoami)@$(hostname)]: " KEY_COMMENT
                KEY_COMMENT=${KEY_COMMENT:-"$(whoami)@$(hostname)"}
                ssh-keygen -t ed25519 -C "$KEY_COMMENT" -f ~/.ssh/id_ed25519 -N ""
                SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
                echo ""
                echo -e "  ${GREEN}✓${NC} Nieuwe key gegenereerd: ~/.ssh/id_ed25519.pub"
                echo ""
                echo -e "  ${YELLOW}Vergeet niet deze public key toe te voegen aan je"
                echo -e "  Proxmox server (~/.ssh/authorized_keys)${NC}"
                ;;
            [Ss])
                echo -e "  ${YELLOW}Overgeslagen${NC}"
                ;;
        esac
    fi
fi

# Validatie SSH key
if [[ -n "$SSH_KEY" ]]; then
    if [[ "$SSH_KEY" =~ ^ssh-(ed25519|rsa|ecdsa)|^ecdsa-sha2 ]]; then
        # Vervang in alle YAML bestanden
        find "$SCRIPT_DIR/snippets" -name "*.yaml" -exec \
            sed -i "s|YOUR_SSH_PUBLIC_KEY_HERE|$SSH_KEY|g" {} \;
        echo -e "  ${GREEN}✓ SSH key ingesteld in alle cloud-init configs${NC}"
    else
        echo -e "  ${RED}Key lijkt geen geldige SSH public key te zijn${NC}"
        echo -e "  ${YELLOW}De placeholder YOUR_SSH_PUBLIC_KEY_HERE blijft staan${NC}"
    fi
fi

echo ""

# ── Stap 2: Template ID ──────────────────────
echo -e "${BOLD}Stap 2/3: Proxmox Template${NC}"
echo -e "─────────────────────────────────────────"
echo ""

# Probeer beschikbare templates te vinden als we op Proxmox draaien
if command -v qm &>/dev/null; then
    echo "  Beschikbare templates:"
    qm list 2>/dev/null | tail -n +2 | while read -r line; do
        VMID=$(echo "$line" | awk '{print $1}')
        IS_TPL=$(qm config "$VMID" 2>/dev/null | grep "^template:" | awk '{print $2}')
        if [[ "$IS_TPL" == "1" ]]; then
            NAME=$(qm config "$VMID" 2>/dev/null | grep "^name:" | awk '{print $2}')
            echo "    [$VMID] $NAME"
        fi
    done
    echo ""
fi

read -p "  VM ID van je Debian cloud-init template [9000]: " TEMPLATE_ID
TEMPLATE_ID=${TEMPLATE_ID:-9000}
sed -i "s|^TEMPLATE_ID=.*|TEMPLATE_ID=$TEMPLATE_ID|" "$SCRIPT_DIR/scripts/create-vm.sh"
echo -e "  ${GREEN}✓ Template ID: $TEMPLATE_ID${NC}"

# Check of het gekozen template bestaat
if command -v qm &>/dev/null; then
    if qm status "$TEMPLATE_ID" &>/dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Template $TEMPLATE_ID gevonden${NC}"
    else
        echo ""
        echo -e "  ${YELLOW}Template $TEMPLATE_ID niet gevonden op deze host.${NC}"
        echo ""
        echo -e "  ${GREEN}[A]${NC} Automatisch aanmaken (Debian 12 cloud image)"
        echo -e "  ${YELLOW}[D]${NC} Doorgaan zonder template"
        echo ""
        read -p "  Keuze [A]: " TPL_CHOICE
        TPL_CHOICE=${TPL_CHOICE:-A}

        case $TPL_CHOICE in
            [Aa])
                # Zoek create-template.sh
                CREATE_TPL=""
                if [[ -f "$SCRIPT_DIR/scripts/create-template.sh" ]]; then
                    CREATE_TPL="$SCRIPT_DIR/scripts/create-template.sh"
                elif [[ -f "/root/scripts/create-template.sh" ]]; then
                    CREATE_TPL="/root/scripts/create-template.sh"
                fi

                if [[ -n "$CREATE_TPL" ]]; then
                    echo ""
                    bash "$CREATE_TPL" --id "$TEMPLATE_ID" --storage "${STORAGE:-local-lvm}"
                    if [[ $? -eq 0 ]]; then
                        echo -e "  ${GREEN}✓ Template $TEMPLATE_ID succesvol aangemaakt${NC}"
                    else
                        echo -e "  ${RED}Template aanmaken mislukt. Je kunt dit later handmatig doen met:${NC}"
                        echo -e "  ${YELLOW}bash scripts/create-template.sh --id $TEMPLATE_ID${NC}"
                    fi
                else
                    echo -e "  ${RED}create-template.sh niet gevonden${NC}"
                    echo -e "  ${YELLOW}Voer eerst install.sh uit, of maak handmatig een template aan.${NC}"
                fi
                ;;
            *)
                echo -e "  ${YELLOW}Doorgaan zonder template. Maak later een template aan met:${NC}"
                echo -e "  ${YELLOW}bash scripts/create-template.sh --id $TEMPLATE_ID${NC}"
                ;;
        esac
    fi
fi

echo ""

# ── Stap 3: Storage ──────────────────────────
echo -e "${BOLD}Stap 3/3: Storage${NC}"
echo -e "─────────────────────────────────────────"
echo ""

# Probeer beschikbare storage te vinden
if command -v pvesm &>/dev/null; then
    echo "  Beschikbare storage:"
    pvesm status 2>/dev/null | tail -n +2 | awk '{printf "    [%s] type: %s\n", $1, $2}'
    echo ""
fi

read -p "  Storage voor VM disks [local-lvm]: " STORAGE
STORAGE=${STORAGE:-local-lvm}
sed -i "s|^STORAGE=.*|STORAGE=\"$STORAGE\"|" "$SCRIPT_DIR/scripts/create-vm.sh"
echo -e "  ${GREEN}✓ Storage: $STORAGE${NC}"
echo ""

# ── Samenvatting ──────────────────────────────
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Setup voltooid!                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "  Configuratie:"
if [[ -n "$SSH_KEY" ]]; then
    echo -e "    SSH Key:     ${GREEN}ingesteld${NC}"
else
    echo -e "    SSH Key:     ${YELLOW}niet ingesteld (handmatig aanpassen)${NC}"
fi
echo "    Template ID: $TEMPLATE_ID"
echo "    Storage:     $STORAGE"
echo ""
echo "  Volgende stap:"
echo ""
echo -e "    ${BOLD}bash install.sh${NC}"
echo ""
echo "  Dit installeert de snippets en scripts op"
echo "  je Proxmox server."
echo ""
