#!/bin/bash

# ============================================
# INSTALL.SH
# Installeert snippets en scripts op Proxmox
#
# Gebruik:
#   scp -r proxmox-templates/ root@pve2:/tmp/
#   ssh root@pve2 "bash /tmp/proxmox-templates/install.sh"
# ============================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/root/scripts"
LIB_DIR="/root/lib"
SNIPPET_DIR="/var/lib/vz/snippets"

echo -e "${BLUE}Proxmox VM Templates - Installatie${NC}"
echo ""

# 1. Snippets content-type inschakelen op local storage
echo -e "${BLUE}[1/7]${NC} Snippets inschakelen op local storage..."
CURRENT_CONTENT=$(pvesm status --storage local 2>/dev/null | tail -1 | awk '{print $5}')
if ! echo "$CURRENT_CONTENT" | grep -q "snippets"; then
    # Voeg snippets toe aan bestaande content types
    pvesm set local --content iso,vztmpl,backup,snippets
    echo -e "${GREEN}  ✓ Snippets ingeschakeld${NC}"
else
    echo -e "${GREEN}  ✓ Snippets was al ingeschakeld${NC}"
fi

# 2. Snippets directory aanmaken
echo -e "${BLUE}[2/7]${NC} Snippets directory controleren..."
mkdir -p "$SNIPPET_DIR"
echo -e "${GREEN}  ✓ $SNIPPET_DIR bestaat${NC}"

# 3. Cloud-init YAMLs kopiëren
echo -e "${BLUE}[3/7]${NC} Cloud-init configuraties installeren..."
cp "$SCRIPT_DIR/snippets/"*.yaml "$SNIPPET_DIR/"
echo -e "${GREEN}  ✓ Snippets gekopieerd naar $SNIPPET_DIR${NC}"

# 4. Libraries installeren
echo -e "${BLUE}[4/7]${NC} Libraries installeren..."
mkdir -p "$LIB_DIR"
cp "$SCRIPT_DIR/lib/"*.sh "$LIB_DIR/"
chmod +x "$LIB_DIR/"*.sh
echo -e "${GREEN}  ✓ Libraries geïnstalleerd in $LIB_DIR${NC}"

# 5. Scripts installeren
echo -e "${BLUE}[5/7]${NC} Scripts installeren..."
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/scripts/"*.sh "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/"*.sh

# Quick-create symlinks aanmaken
ln -sf "$INSTALL_DIR/quick-create.sh" "$INSTALL_DIR/quick-docker.sh"
ln -sf "$INSTALL_DIR/quick-create.sh" "$INSTALL_DIR/quick-webserver.sh"
ln -sf "$INSTALL_DIR/quick-create.sh" "$INSTALL_DIR/quick-homelab.sh"
ln -sf "$INSTALL_DIR/quick-create.sh" "$INSTALL_DIR/quick-supabase.sh"
ln -sf "$INSTALL_DIR/quick-create.sh" "$INSTALL_DIR/quick-coolify.sh"
echo -e "${GREEN}  ✓ Scripts geïnstalleerd in $INSTALL_DIR${NC}"

# 6. Menu shortcut aanmaken
echo -e "${BLUE}[6/7]${NC} Menu shortcut installeren..."
ln -sf "$INSTALL_DIR/menu.sh" /usr/local/bin/pve-menu
echo -e "${GREEN}  ✓ pve-menu commando beschikbaar${NC}"

# 7. PATH toevoegen als dat nog niet is gedaan
echo -e "${BLUE}[7/7]${NC} PATH configureren..."
if ! grep -q "$INSTALL_DIR" /root/.bashrc 2>/dev/null; then
    echo "" >> /root/.bashrc
    echo "# Proxmox VM scripts" >> /root/.bashrc
    echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> /root/.bashrc
    echo -e "${GREEN}  ✓ $INSTALL_DIR toegevoegd aan PATH${NC}"
else
    echo -e "${GREEN}  ✓ PATH was al geconfigureerd${NC}"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installatie voltooid!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "Geïnstalleerde snippets:"
ls -1 "$SNIPPET_DIR/"*.yaml 2>/dev/null | while read f; do echo "  $(basename "$f")"; done
echo ""
echo "Geïnstalleerde scripts:"
ls -1 "$INSTALL_DIR/"*.sh 2>/dev/null | while read f; do echo "  $(basename "$f")"; done
echo ""
echo "Gebruik (na 'source ~/.bashrc' of opnieuw inloggen):"
echo ""
echo "  pve-menu                                    # Interactief menu"
echo "  create-vm.sh docker-01 110 docker --start   # CLI"
echo "  create-vm.sh supa 200 supabase --start      # Supabase"
echo "  quick-docker.sh mijn-app 130 --start        # Quick shortcut"
echo "  quick-supabase.sh supa-01 140 --start       # Supabase shortcut"
echo "  quick-coolify.sh coolify-01 150 --start     # Coolify shortcut"
echo "  list-vms.sh                                 # VM overzicht"
echo "  delete-vm.sh 130                            # VM verwijderen"
echo ""
echo -e "${BLUE}Let op:${NC} pas TEMPLATE_ID in create-vm.sh aan naar het"
echo "ID van je Debian cloud-init template."
echo ""
