#!/usr/bin/env bash
# Unit test for scripts/apps/_render-env.sh — runs anywhere with bash + openssl.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
RENDER="$DIR/../scripts/apps/_render-env.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/env.example" <<'EOF'
PORT=3000
JWT_SECRET=replace-me
DATABASE_URL=postgres://u:p@localhost:5432/db
YOUTUBE_API_KEY=
LOG_LEVEL=info
EOF

cat > "$tmp/gen" <<'EOF'
JWT_SECRET=secret32
EOF

cat > "$tmp/answers" <<'EOF'
YOUTUBE_API_KEY=abc123
DATABASE_URL=postgres://x:y@10.0.0.1:5432/listener
EOF

bash "$RENDER" "$tmp/env.example" "$tmp/gen" "$tmp/answers" "$tmp/.env"

fail=0
check() { if eval "$1"; then echo "  ok: $2"; else echo "  FAIL: $2"; fail=1; fi; }

check "grep -qx 'PORT=3000' '$tmp/.env'"               "untouched key preserved"
check "grep -qx 'LOG_LEVEL=info' '$tmp/.env'"          "untouched key preserved (2)"
jwt=$(grep '^JWT_SECRET=' "$tmp/.env" | cut -d= -f2-)
check "[[ \${#jwt} -eq 64 ]]"                          "generated secret32 is 64 hex chars"
check "! grep -q 'replace-me' '$tmp/.env'"             "placeholder secret replaced"
check "grep -qx 'YOUTUBE_API_KEY=abc123' '$tmp/.env'"  "prompted value set"
check "grep -qx 'DATABASE_URL=postgres://x:y@10.0.0.1:5432/listener' '$tmp/.env'" "value with = and / preserved"

if [[ $fail -eq 0 ]]; then echo "PASS test-render-env"; else echo "FAILED"; exit 1; fi
