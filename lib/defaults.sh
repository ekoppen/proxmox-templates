#!/bin/bash

# ============================================
# DEFAULTS.SH
# Type registry voor VM configuraties
#
# Nieuw type toevoegen:
#   1. register_type aanroepen (zie voorbeelden)
#   2. Maak een matching cloud-config YAML snippet
#   Klaar! Het type verschijnt automatisch in het menu.
# ============================================

# ── Registry storage ──────────────────────────
# Bash 4+ associatieve arrays
declare -A TYPE_LABELS
declare -A TYPE_DESCRIPTIONS
declare -A TYPE_CORES
declare -A TYPE_MEMORY
declare -A TYPE_DISK
declare -A TYPE_SNIPPETS
declare -A TYPE_POSTINFO
TYPE_ORDER=()

# ── Registry functie ─────────────────────────
# register_type <key> <label> <beschrijving> <cores> <memory> <disk> <snippet> [post-info]
register_type() {
    local key="$1"
    local label="$2"
    local desc="$3"
    local cores="$4"
    local memory="$5"
    local disk="$6"
    local snippet="$7"
    local postinfo="${8:-}"

    TYPE_LABELS["$key"]="$label"
    TYPE_DESCRIPTIONS["$key"]="$desc"
    TYPE_CORES["$key"]="$cores"
    TYPE_MEMORY["$key"]="$memory"
    TYPE_DISK["$key"]="$disk"
    TYPE_SNIPPETS["$key"]="$snippet"
    TYPE_POSTINFO["$key"]="$postinfo"
    TYPE_ORDER+=("$key")
}

# ── Geregistreerde types ─────────────────────

register_type "base" \
    "Base Server" \
    "Kale Debian server met basis tools" \
    2 2048 "" \
    "base-cloud-config.yaml"

register_type "docker" \
    "Docker Server" \
    "Docker + Compose + Portainer" \
    4 4096 "50G" \
    "docker-cloud-config.yaml" \
    "Portainer: https://<IP>:9443"

register_type "webserver" \
    "Webserver" \
    "Nginx + Certbot + UFW + Fail2ban" \
    2 2048 "20G" \
    "webserver-cloud-config.yaml" \
    "Nginx: http://<IP>"

register_type "homelab" \
    "Homelab Server" \
    "Docker + NFS + Portainer + homelab tools" \
    4 4096 "50G" \
    "homelab-cloud-config.yaml" \
    "Portainer: https://<IP>:9443"

register_type "supabase" \
    "Supabase" \
    "Self-hosted Supabase (PostgreSQL + Auth + API)" \
    4 8192 "50G" \
    "supabase-cloud-config.yaml" \
    "Studio: http://<IP>:3000 | API: http://<IP>:8000"

register_type "coolify" \
    "Coolify" \
    "Self-hosted PaaS (Heroku/Vercel alternatief)" \
    2 2048 "30G" \
    "coolify-cloud-config.yaml" \
    "Dashboard: http://<IP>:8000"

register_type "minio" \
    "MinIO" \
    "S3-compatible object storage" \
    4 4096 "50G" \
    "minio-cloud-config.yaml" \
    "Console: http://<IP>:9001 | API: http://<IP>:9000"

# ── Lookup functies ──────────────────────────

# Retourneert snippet pad voor Proxmox
get_snippet_for_type() {
    local type="$1"
    local storage="${2:-local}"
    local path="${3:-snippets}"
    local snippet="${TYPE_SNIPPETS[$type]}"
    [[ -z "$snippet" ]] && return 1
    echo "${storage}:${path}/${snippet}"
}

# Past defaults toe op CORES/MEMORY/DISK_SIZE variabelen
apply_defaults_for_type() {
    local type="$1"
    [[ -z "${TYPE_CORES[$type]}" ]] && return 1
    CORES="${CORES:-${TYPE_CORES[$type]}}"
    MEMORY="${MEMORY:-${TYPE_MEMORY[$type]}}"
    DISK_SIZE="${DISK_SIZE:-${TYPE_DISK[$type]}}"
}

# Geeft post-installatie info voor een type
get_postinfo() {
    local type="$1"
    echo "${TYPE_POSTINFO[$type]}"
}

# Check of een type geregistreerd is
type_exists() {
    [[ -n "${TYPE_LABELS[$1]}" ]]
}

# Lijst alle geregistreerde types
list_types() {
    for key in "${TYPE_ORDER[@]}"; do
        printf "%-12s %s\n" "$key" "${TYPE_LABELS[$key]}"
    done
}
