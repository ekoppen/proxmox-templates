#!/usr/bin/env bash
# Post-install hook for retrohead. Args: <app-key> <ctid> <ip>
# Reminds about the videoclip library mount and DB-managed API keys.
set -euo pipefail
CTID="${2:-<ctid>}"

cat <<EOF

────────────────────────────────────────────────────────────
 retrohead — manual follow-up
────────────────────────────────────────────────────────────
1. Media library: retrohead expects the videoclip library at the host path
   you entered (HOST_LIBRARY_ROOT). Make sure that NFS share is mounted INSIDE
   the LXC, e.g. on the Proxmox host:
       pct set ${CTID} -mp0 /mnt/videoclips,mp=/mnt/videoclips
   (or configure an NFS mount inside the container) and restart the stack.

2. External API keys (e.g. Giphy) are NOT in .env — set them in the encrypted
   DB KV store via the app at  /admin/integrations.
────────────────────────────────────────────────────────────
EOF
