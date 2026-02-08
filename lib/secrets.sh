#!/bin/bash

# ============================================
# SECRETS.SH
# Secret generatie voor Supabase en andere services
# Gebruikt openssl - geen externe dependencies
#
# NB: Deze functies zijn bedoeld om ON-VM te draaien
# zodat secrets nooit op de Proxmox host staan.
# De cloud-config snippets embedden deze functies.
# ============================================

# Genereer random secret (standaard 40 chars)
generate_secret() {
    local length="${1:-40}"
    openssl rand -base64 "$length" | tr -d '/+\n' | head -c "$length"
}

# Genereer JWT secret voor Supabase
generate_jwt_secret() {
    generate_secret 40
}

# Base64url encode (zonder padding)
base64url_encode() {
    openssl enc -base64 -A | tr '+/' '-_' | tr -d '='
}

# Genereer een JWT token
# Gebruik: generate_jwt <payload_json> <secret>
generate_jwt() {
    local payload="$1"
    local secret="$2"

    local header='{"alg":"HS256","typ":"JWT"}'
    local header_b64
    header_b64=$(echo -n "$header" | base64url_encode)
    local payload_b64
    payload_b64=$(echo -n "$payload" | base64url_encode)

    local signature
    signature=$(echo -n "${header_b64}.${payload_b64}" | \
        openssl dgst -sha256 -hmac "$secret" -binary | base64url_encode)

    echo "${header_b64}.${payload_b64}.${signature}"
}

# Genereer Supabase anon key
generate_supabase_anon_key() {
    local jwt_secret="$1"
    local iat
    iat=$(date +%s)
    local exp=$((iat + 157680000))  # +5 jaar

    local payload="{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":${iat},\"exp\":${exp}}"
    generate_jwt "$payload" "$jwt_secret"
}

# Genereer Supabase service_role key
generate_supabase_service_key() {
    local jwt_secret="$1"
    local iat
    iat=$(date +%s)
    local exp=$((iat + 157680000))  # +5 jaar

    local payload="{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":${iat},\"exp\":${exp}}"
    generate_jwt "$payload" "$jwt_secret"
}
