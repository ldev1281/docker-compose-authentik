#!/bin/bash
set -euo pipefail

# -------------------------------------
# AUTHENTIK setup script
# -------------------------------------

# Get absolute path of script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
VOL_DIR="${SCRIPT_DIR}/../vol/"

AUTHENTIK_POSTGRES_VERSION=16-alpine
AUTHENTIK_IMAGE=ghcr.io/goauthentik/server
AUTHENTIK_TAG=2025.6.4

# Generate secure random defaults
generate_defaults() {
    PG_PASS=$(openssl rand -base64 36 | tr -d '\n')
    AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')
}

# Load existing configuration from .env file
load_existing_env() {
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
}

# Prompt user to confirm or update configuration
prompt_for_configuration() {
    echo "Please enter configuration values (press Enter to keep current/default value):"
    echo ""

    echo "postgres:"

    read -p "AUTHENTIK_POSTGRES_USER [${AUTHENTIK_POSTGRES_USER:-authentik}]: " input
    AUTHENTIK_POSTGRES_USER=${input:-${AUTHENTIK_POSTGRES_USER:-authentik}}

    read -p "AUTHENTIK_POSTGRES_PASSWORD [${AUTHENTIK_POSTGRES_PASSWORD:-$PG_PASS}]: " input
    AUTHENTIK_POSTGRES_PASSWORD=${input:-${AUTHENTIK_POSTGRES_PASSWORD:-$PG_PASS}}

    read -p "AUTHENTIK_POSTGRES_DB [${AUTHENTIK_POSTGRES_DB:-authentik}]: " input
    AUTHENTIK_POSTGRES_DB=${input:-${AUTHENTIK_POSTGRES_DB:-authentik}}

    echo ""
    echo "app:"

    read -p "AUTHENTIK_SECRET_KEY [auto-generated hidden]: " input
    if [[ -n "$input" ]]; then
        AUTHENTIK_SECRET_KEY="$input"
    fi

    echo ""
    echo "smtp:"

    read -p "AUTHENTIK_EMAIL__HOST [${AUTHENTIK_EMAIL__HOST:-localhost}]: " input
    AUTHENTIK_EMAIL__HOST=${input:-${AUTHENTIK_EMAIL__HOST:-localhost}}

    read -p "AUTHENTIK_EMAIL__PORT [${AUTHENTIK_EMAIL__PORT:-25}]: " input
    AUTHENTIK_EMAIL__PORT=${input:-${AUTHENTIK_EMAIL__PORT:-25}}

    read -p "AUTHENTIK_EMAIL__USERNAME [${AUTHENTIK_EMAIL__USERNAME:-}]: " input
    AUTHENTIK_EMAIL__USERNAME=${input:-${AUTHENTIK_EMAIL__USERNAME:-}}

    read -p "AUTHENTIK_EMAIL__PASSWORD [${AUTHENTIK_EMAIL__PASSWORD:-example}]: " input
    AUTHENTIK_EMAIL__PASSWORD=${input:-${AUTHENTIK_EMAIL__PASSWORD:-example}}

    read -p "AUTHENTIK_EMAIL__USE_TLS [${AUTHENTIK_EMAIL__USE_TLS:-true}]: " input
    AUTHENTIK_EMAIL__USE_TLS=${input:-${AUTHENTIK_EMAIL__USE_TLS:-true}}

    read -p "AUTHENTIK_EMAIL__USE_SSL [${AUTHENTIK_EMAIL__USE_SSL:-true}]: " input
    AUTHENTIK_EMAIL__USE_SSL=${input:-${AUTHENTIK_EMAIL__USE_SSL:-true}}

    read -p "AUTHENTIK_EMAIL__TIMEOUT [${AUTHENTIK_EMAIL__TIMEOUT:-10}]: " input
    AUTHENTIK_EMAIL__TIMEOUT=${input:-${AUTHENTIK_EMAIL__TIMEOUT:-10}}

    read -p "AUTHENTIK_EMAIL__FROM [${AUTHENTIK_EMAIL__FROM:-authentik@localhost}]: " input
    AUTHENTIK_EMAIL__FROM=${input:-${AUTHENTIK_EMAIL__FROM:-authentik@localhost}}
}

# Display and confirm configuration
confirm_and_save_configuration() {
    CONFIG_LINES=(
        "# PostgreSQL"
        "AUTHENTIK_POSTGRES_VERSION=${AUTHENTIK_POSTGRES_VERSION}"
        "AUTHENTIK_POSTGRES_USER=${AUTHENTIK_POSTGRES_USER}"
        "AUTHENTIK_POSTGRES_PASSWORD=${AUTHENTIK_POSTGRES_PASSWORD}"
        "AUTHENTIK_POSTGRES_DB=${AUTHENTIK_POSTGRES_DB}"
        ""
        "# Authentik"
        "AUTHENTIK_IMAGE=${AUTHENTIK_IMAGE}"
        "AUTHENTIK_TAG=${AUTHENTIK_TAG}"
        "AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}"
        ""
        "# SMTP"
        "AUTHENTIK_EMAIL__HOST=${AUTHENTIK_EMAIL__HOST}"
        "AUTHENTIK_EMAIL__PORT=${AUTHENTIK_EMAIL__PORT}"
        "AUTHENTIK_EMAIL__USERNAME=${AUTHENTIK_EMAIL__USERNAME}"
        "AUTHENTIK_EMAIL__PASSWORD='${AUTHENTIK_EMAIL__PASSWORD}'"
        "AUTHENTIK_EMAIL__USE_TLS=${AUTHENTIK_EMAIL__USE_TLS}"
        "AUTHENTIK_EMAIL__USE_SSL=${AUTHENTIK_EMAIL__USE_SSL}"
        "AUTHENTIK_EMAIL__TIMEOUT=${AUTHENTIK_EMAIL__TIMEOUT}"
        "AUTHENTIK_EMAIL__FROM=${AUTHENTIK_EMAIL__FROM}"
    )

    echo ""
    echo "The following environment configuration will be saved:"
    echo "-----------------------------------------------------"
    for line in "${CONFIG_LINES[@]}"; do echo "$line"; done
    echo "-----------------------------------------------------"
    echo ""

    read -p "Proceed with this configuration? (y/n): " CONFIRM
    echo ""
    if [[ "$CONFIRM" != "y" ]]; then
        echo "Configuration aborted by user."
        exit 1
    fi

    printf "%s\n" "${CONFIG_LINES[@]}" > "$ENV_FILE"
    echo ".env file saved to $ENV_FILE"
    echo ""
}

# Prepare volumes and run docker-compose
setup_containers() {
    echo "Stopping all containers and removing volumes..."
    docker compose down -v

    echo "Clearing volume data..."
    [ -d "$VOL_DIR" ] && rm -rf "$VOL_DIR"/*
    mkdir -p "${VOL_DIR}/authentik-app/media" && chown 1000 "${VOL_DIR}/authentik-app/media"

    echo "Starting containers..."
    docker compose up -d

    echo "Waiting 60 seconds for services to initialize..."
    sleep 60

    echo "Done!"
    echo ""
}

# -----------------------------------
# Main logic
# -----------------------------------

if [[ -f "$ENV_FILE" ]]; then
    echo ".env file found. Loading existing configuration."
    load_existing_env
else
    echo ".env file not found. Generating defaults."
    generate_defaults
fi

prompt_for_configuration
confirm_and_save_configuration
setup_containers