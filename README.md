# Proxmox VM Templates & Automation

Quickly create VMs from Proxmox cloud-init templates with a single command or an interactive menu.

```bash
create-vm.sh docker-01 110 docker --start
```

In ~60 seconds you'll have a fully configured server with your SSH key, auto-updates, and all required software.

## Server Types

| Type | What you get | Access |
|---|---|---|
| `base` | Debian server with admin user, SSH, basic tools, auto-updates | SSH |
| `docker` | Docker + Docker Compose + Portainer + log rotation | Portainer: `https://<IP>:9443` |
| `webserver` | Nginx + Certbot (Let's Encrypt) + UFW firewall + Fail2ban | `http://<IP>` |
| `homelab` | Docker + Portainer + NFS client + Watchtower auto-updates | Portainer: `https://<IP>:9443` |
| `supabase` | Self-hosted Supabase (PostgreSQL + Auth + API + Studio) | Studio: `http://<IP>:3000` |
| `coolify` | Self-hosted PaaS (Heroku/Vercel alternative) | Dashboard: `http://<IP>:8000` |
| `minio` | S3-compatible object storage | Console: `http://<IP>:9001` |
| `appwrite` | Multi-project BaaS platform (Firebase/Supabase alternative) | Console: `http://<IP>` |

## Quick Start

```bash
# 1. Clone the repo on your Proxmox server
git clone https://github.com/ekoppen/proxmox-templates.git
cd proxmox-templates

# 2. Configure with your SSH key and template ID
bash setup.sh

# 3. Install snippets and scripts
bash install.sh

# 4. Create your first VM
create-vm.sh docker-01 110 docker --start
```

> **No template yet?** `setup.sh` detects this automatically and offers to create one. You can also run `create-template.sh` manually.

## Usage

### Interactive menu

```bash
pve-menu
```

Whiptail menu where you choose a server type, enter a name/ID, and optionally adjust resources. If no template exists, it offers to create one automatically.

### CLI

```bash
# Docker server
create-vm.sh docker-01 110 docker --start

# Webserver with custom resources
create-vm.sh web-01 120 webserver --cores 4 --memory 4096 --start

# Supabase
create-vm.sh supa-01 130 supabase --start

# Coolify
create-vm.sh cool-01 140 coolify --start

# MinIO
create-vm.sh minio-01 150 minio --start

# Appwrite
create-vm.sh appwrite-01 160 appwrite --start

# Full clone (independent of template)
create-vm.sh prod-db 170 docker --full --cores 8 --memory 16384 --disk 100G

# Quick shortcuts
quick-docker.sh my-app 180 --start
quick-webserver.sh site-01 190 --start
quick-homelab.sh lab-01 200 --start
quick-supabase.sh supa-01 210 --start
quick-coolify.sh cool-01 220 --start
quick-minio.sh minio-01 230 --start
quick-appwrite.sh appwrite-01 240 --start

# List all VMs
list-vms.sh

# Delete a VM
delete-vm.sh 180
```

### Create a template

```bash
# Default (ID 9000, local-lvm, vmbr0)
create-template.sh

# With options
create-template.sh --id 9001 --storage local-lvm --bridge vmbr1
```

Downloads the official Debian 12 cloud image, verifies the checksum, and creates a Proxmox template. Also works non-interactively with `--auto` (used by the menu).

## Structure

```
proxmox-templates/
├── setup.sh                        # First-time configuration (SSH key, template, storage)
├── install.sh                      # Installation on Proxmox
├── lib/                            # Shared libraries
│   ├── common.sh                   #   Colors, logging, whiptail helpers
│   ├── defaults.sh                 #   Type registry (all server types)
│   └── secrets.sh                  #   Secret generation helpers
├── snippets/                       # Cloud-init configs → /var/lib/vz/snippets/
│   ├── base-cloud-config.yaml
│   ├── docker-cloud-config.yaml
│   ├── webserver-cloud-config.yaml
│   ├── homelab-cloud-config.yaml
│   ├── supabase-cloud-config.yaml
│   ├── coolify-cloud-config.yaml
│   ├── minio-cloud-config.yaml
│   └── appwrite-cloud-config.yaml
└── scripts/                        # VM management → /root/scripts/
    ├── create-template.sh          #   Automatic Debian template creation
    ├── create-vm.sh                #   Create VM from template
    ├── menu.sh                     #   Interactive whiptail menu (pve-menu)
    ├── quick-create.sh             #   Shortcuts via symlinks
    ├── list-vms.sh                 #   VM overview
    └── delete-vm.sh                #   Delete VM
```

## Adding a new server type

1. Create a YAML snippet in `snippets/`, e.g. `database-cloud-config.yaml`
2. Add one `register_type()` call in `lib/defaults.sh`:
   ```bash
   register_type "database" \
       "Database Server" \
       "PostgreSQL + pgAdmin" \
       4 8192 "100G" \
       "database-cloud-config.yaml" \
       "pgAdmin: http://<IP>:5050"
   ```
3. Done — the type automatically appears in the menu and CLI.

## VM Notes

After creation, VM notes are set in Proxmox with the server type, SSH command, and access URLs. Visible in the Proxmox web UI under the Notes tab.

## Production Setup

A few tips for production use:

- **Coolify** works great as an orchestrator — it manages services, SSL certificates, and deployments across your VMs.
- **MinIO** provides S3-compatible object storage for backups, media, or any file storage needs.
- **Appwrite** supports multiple projects on a single instance, making it ideal as a shared BaaS backend (unlike Supabase which is single-project per instance).
- Use `--full` for production VMs so they're independent of the template.
- Consider adding `--cpu host` to `qm set` for better performance with newer Docker images that benefit from modern CPU instructions.
- Linked clones share the template's base disk. This saves storage but means the template cannot be deleted. For memory, Proxmox supports overcommit — you can allocate more total RAM across VMs than physically available, as long as they don't all use their maximum simultaneously.

## Requirements

- Proxmox VE 8.x or 9.x
- A Debian cloud-init template (automatically created by `create-template.sh`)

## License

MIT
