#!/usr/bin/env bash
# Unit test for lib/apps.sh registry — runs anywhere with bash 4+.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/.."
# shellcheck source=/dev/null
source "$ROOT/lib/apps.sh"

fail=0
check() { if eval "$1"; then echo "  ok: $2"; else echo "  FAIL: $2"; fail=1; fi; }

check "[[ \${#APP_ORDER[@]} -eq 3 ]]"                          "three apps registered"
check "app_exists catalogic"                                  "catalogic exists"
check "app_exists retrohead"                                  "retrohead exists"
check "app_exists listener"                                   "listener exists"
check "! app_exists nope"                                     "unknown app rejected"
check "[[ '${APP_REPO[catalogic]}' == 'git@github.com:ekoppen/catalogic.git' ]]" "catalogic repo url"
check "[[ '${APP_REPO[listener]}' == 'git@github.com:ekoppen/music-listener.git' ]]" "listener repo url"
check "[[ '${APP_COMPOSE[catalogic]}' == 'docker-compose.prod.yml' ]]" "catalogic compose file"
check "[[ '${APP_COMPOSE[listener]}' == 'docker-compose.production.yml' ]]" "listener compose file"
check "[[ '${APP_FUSE[catalogic]}' == 'true' ]]"              "catalogic needs fuse"
check "[[ '${APP_FUSE[retrohead]}' == 'false' ]]"            "retrohead no fuse"
check "grep -q 'JWT_SECRET=secret' <<<\"\${APP_GEN[listener]}\"" "listener generates JWT_SECRET"
check "grep -q 'YOUTUBE_API_KEY|' <<<\"\${APP_PROMPT[listener]}\"" "listener prompts YOUTUBE_API_KEY"
check "grep -q 'LISTENER_DATABASE_URL|' <<<\"\${APP_PROMPT[catalogic]}\"" "catalogic prompts LISTENER_DATABASE_URL"

if [[ $fail -eq 0 ]]; then echo "PASS test-apps-registry"; else echo "FAILED"; exit 1; fi
