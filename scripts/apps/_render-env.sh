#!/usr/bin/env bash
# ============================================
# _render-env.sh
# Render an app .env from its .env.example by applying generated secrets and
# prompted values. Runs INSIDE the target LXC (openssl available) and is also
# directly unit-testable on a dev machine.
#
# Usage:
#   _render-env.sh <env-example> <gen-spec> <answers> <out>
#     <env-example> : path to the repo's .env.example
#     <gen-spec>    : file with lines "VAR=secret32|secret64|password"
#     <answers>     : file with lines "VAR=value" (prompted values; value may
#                     contain '=' and '/')
#     <out>         : path to write the rendered .env
# ============================================
set -euo pipefail

[[ $# -eq 4 ]] || { echo "usage: $0 <env-example> <gen-spec> <answers> <out>" >&2; exit 2; }
ENV_EXAMPLE="$1"; GEN_SPEC="$2"; ANSWERS="$3"; OUT="$4"

[[ -f "$ENV_EXAMPLE" ]] || { echo "render-env: missing $ENV_EXAMPLE" >&2; exit 1; }

gen_secret() {
    case "$1" in
        secret32) openssl rand -hex 32 ;;
        secret64) openssl rand -hex 64 ;;
        password) openssl rand -base64 24 | tr -d '/+=\n' | head -c 24 ;;
        *) echo "render-env: unknown generator '$1'" >&2; return 1 ;;
    esac
}

# Set key=value in $OUT: replace the line starting with "KEY=" or append it.
# Uses awk prefix-match so values containing '=' / '/' are written verbatim.
set_kv() {
    local key="$1" val="$2"
    if grep -qE "^${key}=" "$OUT"; then
        awk -v k="$key" -v v="$val" 'index($0, k"=")==1 { print k"="v; next } { print }' \
            "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
    else
        printf '%s=%s\n' "$key" "$val" >> "$OUT"
    fi
}

cp "$ENV_EXAMPLE" "$OUT"

# 1) Generated secrets
if [[ -f "$GEN_SPEC" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        local_key="${line%%=*}"; gen="${line#*=}"
        set_kv "$local_key" "$(gen_secret "$gen")"
    done < "$GEN_SPEC"
fi

# 2) Prompted answers (override anything above; value kept verbatim)
if [[ -f "$ANSWERS" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        local_key="${line%%=*}"; val="${line#*=}"
        set_kv "$local_key" "$val"
    done < "$ANSWERS"
fi

chmod 600 "$OUT" 2>/dev/null || true
echo "render-env: wrote $OUT"
