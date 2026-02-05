# Proxmox VM Templates & Automation

Snel VMs aanmaken vanuit Proxmox cloud-init templates met één commando.

```bash
create-vm.sh docker-01 110 docker --start
```

Dat is alles. Na ~60 seconden heb je een volledig geconfigureerde Docker server met Portainer, log management, en je SSH key.

## Server Types

| Type | Wat je krijgt |
|---|---|
| `base` | Debian server met admin user, SSH, basistools, auto-updates |
| `docker` | Docker + Docker Compose + Portainer + log rotation |
| `webserver` | Nginx + Certbot (Let's Encrypt) + UFW firewall + fail2ban |
| `homelab` | Docker + Portainer + NFS client + Watchtower auto-updates |

## Quick Start

```bash
# 1. Clone de repo op je Proxmox server
git clone https://github.com/JOUW_USERNAME/proxmox-templates.git
cd proxmox-templates

# 2. Configureer met jouw SSH key en template ID
bash setup.sh

# 3. Installeer snippets en scripts
bash install.sh

# 4. Maak je eerste VM
create-vm.sh docker-01 110 docker --start
```

## Gebruik

```bash
# Docker server
create-vm.sh docker-01 110 docker --start

# Webserver met custom resources
create-vm.sh web-01 120 webserver --cores 4 --memory 4096 --start

# Full clone (onafhankelijk van template)
create-vm.sh prod-db 130 docker --full --cores 8 --memory 16384 --disk 100G

# Snelle shortcuts met vooraf ingestelde resources
quick-docker.sh mijn-app 140 --start     # 4 cores, 4GB, 50GB
quick-webserver.sh site-01 150 --start    # 2 cores, 2GB, 20GB
quick-homelab.sh lab-01 160 --start       # 4 cores, 4GB, 50GB

# Overzicht van alle VMs
list-vms.sh

# VM opruimen
delete-vm.sh 140
```

## Structuur

```
proxmox-templates/
├── setup.sh                    # Eerste keer configuratie
├── install.sh                  # Installatie op Proxmox
├── snippets/                   # Cloud-init configs → /var/lib/vz/snippets/
│   ├── base-cloud-config.yaml
│   ├── docker-cloud-config.yaml
│   ├── webserver-cloud-config.yaml
│   └── homelab-cloud-config.yaml
└── scripts/                    # VM management → /root/scripts/
    ├── create-vm.sh
    ├── quick-create.sh
    ├── list-vms.sh
    └── delete-vm.sh
```

## Vereisten

- Proxmox VE 8.x of 9.x
- Een Debian/Ubuntu cloud-init template (zie hieronder)

### Template aanmaken (als je er nog geen hebt)

```bash
# Download Debian cloud image
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2

# Maak VM aan
qm create 9000 --name debian-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0

# Importeer disk
qm importdisk 9000 debian-12-generic-amd64.qcow2 local-lvm

# Configureer
qm set 9000 --scsihw virtio-scsi-pci --virtio0 local-lvm:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot c --bootdisk virtio0
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1

# Maak er een template van
qm template 9000
```

## Aanpassen

**Nieuw server-type toevoegen:**
1. Maak een YAML in `snippets/`, bijv. `database-cloud-config.yaml`
2. Voeg het type toe aan `get_snippet()` en `get_defaults_for_type()` in `create-vm.sh`
3. Klaar — `create-vm.sh db-01 170 database --start`

**Defaults aanpassen:**
Pas de variabelen bovenin `create-vm.sh` aan (template ID, storage, default cores/memory).

## License

MIT
