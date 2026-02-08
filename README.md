# Proxmox VM Templates & Automation

Snel VMs aanmaken vanuit Proxmox cloud-init templates met één commando of via een interactief menu.

```bash
create-vm.sh docker-01 110 docker --start
```

Na ~60 seconden heb je een volledig geconfigureerde server met je SSH key, auto-updates, en alle benodigde software.

## Server Types

| Type | Wat je krijgt | Toegang |
|---|---|---|
| `base` | Debian server met admin user, SSH, basistools, auto-updates | SSH |
| `docker` | Docker + Docker Compose + Portainer + log rotation | Portainer: `https://<IP>:9443` |
| `webserver` | Nginx + Certbot (Let's Encrypt) + UFW firewall + Fail2ban | `http://<IP>` |
| `homelab` | Docker + Portainer + NFS client + Watchtower auto-updates | Portainer: `https://<IP>:9443` |
| `supabase` | Self-hosted Supabase (PostgreSQL + Auth + API + Studio) | Studio: `http://<IP>:3000` |
| `coolify` | Self-hosted PaaS (Heroku/Vercel alternatief) | Dashboard: `http://<IP>:8000` |

## Quick Start

```bash
# 1. Clone de repo op je Proxmox server
git clone https://github.com/ekoppen/proxmox-templates.git
cd proxmox-templates

# 2. Configureer met jouw SSH key en template ID
bash setup.sh

# 3. Installeer snippets en scripts
bash install.sh

# 4. Maak je eerste VM
create-vm.sh docker-01 110 docker --start
```

> **Nog geen template?** `setup.sh` detecteert dit automatisch en biedt aan om er een aan te maken. Je kunt ook handmatig `create-template.sh` draaien.

## Gebruik

### Interactief menu

```bash
pve-menu
```

Whiptail-menu waarmee je een server type kiest, naam/ID invult, en optioneel resources aanpast. Als er geen template bestaat, wordt aangeboden om er automatisch een aan te maken.

### CLI

```bash
# Docker server
create-vm.sh docker-01 110 docker --start

# Webserver met custom resources
create-vm.sh web-01 120 webserver --cores 4 --memory 4096 --start

# Supabase
create-vm.sh supa-01 130 supabase --start

# Coolify
create-vm.sh cool-01 140 coolify --start

# Full clone (onafhankelijk van template)
create-vm.sh prod-db 150 docker --full --cores 8 --memory 16384 --disk 100G

# Snelle shortcuts
quick-docker.sh mijn-app 160 --start
quick-webserver.sh site-01 170 --start
quick-homelab.sh lab-01 180 --start
quick-supabase.sh supa-01 190 --start
quick-coolify.sh cool-01 200 --start

# Overzicht van alle VMs
list-vms.sh

# VM opruimen
delete-vm.sh 160
```

### Template aanmaken

```bash
# Standaard (ID 9000, local-lvm, vmbr0)
create-template.sh

# Met opties
create-template.sh --id 9001 --storage local-lvm --bridge vmbr1
```

Downloadt het officiële Debian 12 cloud image, verifieert de checksum, en maakt er een Proxmox template van. Werkt ook non-interactief met `--auto` (gebruikt door het menu).

## Structuur

```
proxmox-templates/
├── setup.sh                        # Eerste keer configuratie (SSH key, template, storage)
├── install.sh                      # Installatie op Proxmox
├── lib/                            # Gedeelde libraries
│   ├── common.sh                   #   Kleuren, logging, whiptail helpers
│   ├── defaults.sh                 #   Type registry (alle server types)
│   └── secrets.sh                  #   Secret generatie helpers
├── snippets/                       # Cloud-init configs → /var/lib/vz/snippets/
│   ├── base-cloud-config.yaml
│   ├── docker-cloud-config.yaml
│   ├── webserver-cloud-config.yaml
│   ├── homelab-cloud-config.yaml
│   ├── supabase-cloud-config.yaml
│   └── coolify-cloud-config.yaml
└── scripts/                        # VM management → /root/scripts/
    ├── create-template.sh          #   Automatisch Debian template aanmaken
    ├── create-vm.sh                #   VM aanmaken vanuit template
    ├── menu.sh                     #   Interactief whiptail menu (pve-menu)
    ├── quick-create.sh             #   Shortcuts via symlinks
    ├── list-vms.sh                 #   VM overzicht
    └── delete-vm.sh                #   VM verwijderen
```

## Nieuw server-type toevoegen

1. Maak een YAML snippet in `snippets/`, bijv. `database-cloud-config.yaml`
2. Voeg één `register_type()` call toe in `lib/defaults.sh`:
   ```bash
   register_type "database" \
       "Database Server" \
       "PostgreSQL + pgAdmin" \
       4 8192 "100G" \
       "database-cloud-config.yaml" \
       "pgAdmin: http://<IP>:5050"
   ```
3. Klaar — het type verschijnt automatisch in het menu en CLI.

## VM Notes

Na het aanmaken worden VM notes ingesteld in Proxmox met het server type, SSH commando en toegangs-URLs. Zichtbaar in de Proxmox web UI onder het Notes-tabblad.

## Vereisten

- Proxmox VE 8.x of 9.x
- Een Debian cloud-init template (wordt automatisch aangemaakt door `create-template.sh`)

## License

MIT
