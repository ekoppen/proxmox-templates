#!/bin/bash

# ============================================
# APPS.SH
# Registry of installable apps (Docker Compose stacks) for install-app.sh.
#
# New app toevoegen:
#   1. register_app aanroepen
#   2. APP_GEN / APP_PROMPT vullen (optioneel)
#   3. Optioneel: scripts/apps/<key>.hook.sh voor post-install info
#   Klaar! De app verschijnt automatisch in het "Install App" menu.
# ============================================

declare -A APP_LABELS
declare -A APP_DESC
declare -A APP_REPO
declare -A APP_COMPOSE
declare -A APP_PORT
declare -A APP_CORES
declare -A APP_MEMORY
declare -A APP_DISK
declare -A APP_FUSE
declare -A APP_HEALTHCHECK
declare -A APP_POSTINFO
declare -A APP_GEN      # newline-separated "VAR=secret32|secret64|password"
declare -A APP_PROMPT   # newline-separated "VAR|label|default|required"
APP_ORDER=()

# register_app <key> <label> <desc> <repo> <compose> <port> <cores> <memory> <disk> <fuse> <healthcheck> <postinfo>
register_app() {
    local key="$1"
    APP_LABELS["$key"]="$2"
    # shellcheck disable=SC2034
    APP_DESC["$key"]="$3"
    APP_REPO["$key"]="$4"
    APP_COMPOSE["$key"]="$5"
    APP_PORT["$key"]="$6"
    APP_CORES["$key"]="$7"
    APP_MEMORY["$key"]="$8"
    APP_DISK["$key"]="$9"
    APP_FUSE["$key"]="${10}"
    APP_HEALTHCHECK["$key"]="${11}"
    APP_POSTINFO["$key"]="${12}"
    APP_ORDER+=("$key")
}

# ── catalogic ────────────────────────────────
register_app "catalogic" \
    "catalogic" \
    "${MSG_APP_CATALOGIC_DESC:-Central music metadata service (Postgres + MinIO)}" \
    "git@github.com:ekoppen/catalogic.git" \
    "docker-compose.prod.yml" \
    "3000" \
    "4" "4096" "32G" \
    "true" \
    "/ready" \
    "API: http://<IP>:3000/v1 | Docs: http://<IP>:3000/docs"
APP_GEN["catalogic"]=$'POSTGRES_PASSWORD=password\nMINIO_ROOT_PASSWORD=password\nJWT_SECRET=secret32\nAPI_TOKEN_PEPPER=secret32'
APP_PROMPT["catalogic"]=$'LISTENER_DATABASE_URL|Listener Postgres URL (read-only)|postgres://readonly_user:readonly_pass@<listener-ip>:5432/listener|false'

# ── listener ─────────────────────────────────
register_app "listener" \
    "listener" \
    "${MSG_APP_LISTENER_DESC:-Music listener app (frontend + api + db, nginx)}" \
    "git@github.com:ekoppen/music-listener.git" \
    "docker-compose.production.yml" \
    "80" \
    "4" "4096" "20G" \
    "false" \
    "/" \
    "App: http://<IP>"
APP_GEN["listener"]=$'DB_PASSWORD=password\nREDIS_PASSWORD=password\nJWT_SECRET=secret32\nSESSION_SECRET=secret32\nINTEGRATION_API_KEY=secret32'
APP_PROMPT["listener"]=$'YOUTUBE_API_KEY|YouTube API key|.|true\nSPOTIFY_CLIENT_ID|Spotify client ID|.|true\nSPOTIFY_CLIENT_SECRET|Spotify client secret|.|true'

# ── retrohead ────────────────────────────────
register_app "retrohead" \
    "retrohead" \
    "${MSG_APP_RETROHEAD_DESC:-Retro videoclip player (frontend + backend + nginx)}" \
    "git@github.com:ekoppen/retrohead.git" \
    "docker-compose.yml" \
    "5173" \
    "2" "2048" "20G" \
    "false" \
    "/" \
    "Frontend: http://<IP>:5173 | HLS: http://<IP>:8080"
APP_GEN["retrohead"]=$'ADMIN_PASSWORD=password\nJWT_SECRET=secret64\nADMIN_API_TOKEN=secret32'
APP_PROMPT["retrohead"]=$'HOST_LIBRARY_ROOT|Host path to the videoclip library (NFS mount)|/mnt/videoclips|true'

# ── Helpers ──────────────────────────────────
app_exists() { [[ -n "${APP_LABELS[$1]:-}" ]]; }

list_apps() {
    for key in "${APP_ORDER[@]}"; do
        printf "%-12s %s\n" "$key" "${APP_LABELS[$key]}"
    done
}
