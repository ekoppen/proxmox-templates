#!/usr/bin/env bash
# Post-install hook for catalogic. Args: <app-key> <ctid> <ip>
# Prints the Traefik file-provider snippet (Traefik runs on a separate host,
# so we print rather than auto-apply). See catalogic/deploy/LXC_BOOTSTRAP.md §4.
set -euo pipefail
IP="${3:-<IP>}"

cat <<EOF

────────────────────────────────────────────────────────────
 Traefik routing for catalogic (add on the Traefik host)
────────────────────────────────────────────────────────────
Drop this at /opt/traefik/data/dynamic/catalogic.yml (or add via traefixie):

http:
  routers:
    catalogic:
      rule: "Host(\`catalogic.doorkoppen.nl\`)"
      entryPoints: [websecure]
      service: catalogic-lb
      tls:
        certResolver: le
  services:
    catalogic-lb:
      loadBalancer:
        healthCheck:
          path: /ready
          interval: 10s
          timeout: 3s
        servers:
          - url: "http://${IP}:3000"
────────────────────────────────────────────────────────────
EOF
