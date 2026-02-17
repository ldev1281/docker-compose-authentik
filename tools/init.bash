#!/bin/bash
set -euo pipefail

# -------------------------------------
# AUTHENTIK setup script
# -------------------------------------

# Get absolute path of script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
VOL_DIR="${SCRIPT_DIR}/../vol"
BACKUP_TASKS_SRC_DIR="${SCRIPT_DIR}/../etc/limbo-backup/rsync.conf.d"
BACKUP_TASKS_DST_DIR="/etc/limbo-backup/rsync.conf.d"

REQUIRED_TOOLS="docker limbo-backup.bash"
REQUIRED_NETS="proxy-client-authentik"
BACKUP_TASKS="10-authentik.conf.bash"

AUTHENTIK_POSTGRES_VERSION="16-alpine"
AUTHENTIK_IMAGE="ghcr.io/goauthentik/server"
CURRENT_AUTHENTIK_VERSION="2025.10.3"

check_requirements() {
    missed_tools=()
    for cmd in $REQUIRED_TOOLS; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missed_tools+=("$cmd")
        fi
    done

    if ((${#missed_tools[@]})); then
        echo "Required tools not found:" >&2
        for cmd in "${missed_tools[@]}"; do
            echo "  - $cmd" >&2
        done
        echo "Hint: run dev-prod-init.recipe from debian-setup-factory" >&2
        echo "Abort"
        exit 127
    fi
}

create_networks() {
    for net in $REQUIRED_NETS; do
        if docker network inspect "$net" >/dev/null 2>&1; then
            echo "Required network already exists: $net"
        else
            echo "Creating required docker network: $net (driver=bridge)"
            docker network create --driver bridge --internal "$net" >/dev/null
        fi
    done
}

create_backup_tasks() {
    for task in $BACKUP_TASKS; do
        src_file="${BACKUP_TASKS_SRC_DIR}/${task}"
        dst_file="${BACKUP_TASKS_DST_DIR}/${task}"

        if [[ ! -f "$src_file" ]]; then
            echo "Warning: backup task not found: $src_file" >&2
            continue
        fi

        cp "$src_file" "$dst_file"
        echo "Created backup task: $dst_file"
    done
}

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
    AUTHENTIK_VERSION=${CURRENT_AUTHENTIK_VERSION}
    echo ""
    echo "smtp:"

    read -p "AUTHENTIK_EMAIL__HOST [${AUTHENTIK_EMAIL__HOST:-smtp.mailgun.org}]: " input
    AUTHENTIK_EMAIL__HOST=${input:-${AUTHENTIK_EMAIL__HOST:-smtp.mailgun.org}}

    read -p "AUTHENTIK_EMAIL__PORT [${AUTHENTIK_EMAIL__PORT:-587}]: " input
    AUTHENTIK_EMAIL__PORT=${input:-${AUTHENTIK_EMAIL__PORT:-587}}

    read -p "AUTHENTIK_EMAIL__USERNAME [${AUTHENTIK_EMAIL__USERNAME:-postmaster@sandbox123.mailgun.org}]: " input
    AUTHENTIK_EMAIL__USERNAME=${input:-${AUTHENTIK_EMAIL__USERNAME:-postmaster@sandbox123.mailgun.org}}

    read -p "AUTHENTIK_EMAIL__FROM [${AUTHENTIK_EMAIL__FROM:-authentik@sandbox123.mailgun.org}]: " input
    AUTHENTIK_EMAIL__FROM=${input:-${AUTHENTIK_EMAIL__FROM:-authentik@sandbox123.mailgun.org}}    

    read -p "AUTHENTIK_EMAIL__PASSWORD [${AUTHENTIK_EMAIL__PASSWORD:-example}]: " input
    AUTHENTIK_EMAIL__PASSWORD=${input:-${AUTHENTIK_EMAIL__PASSWORD:-example}}

    read -p "AUTHENTIK_EMAIL__USE_TLS [${AUTHENTIK_EMAIL__USE_TLS:-true}]: " input
    AUTHENTIK_EMAIL__USE_TLS=${input:-${AUTHENTIK_EMAIL__USE_TLS:-true}}

    read -p "AUTHENTIK_EMAIL__USE_SSL [${AUTHENTIK_EMAIL__USE_SSL:-false}]: " input
    AUTHENTIK_EMAIL__USE_SSL=${input:-${AUTHENTIK_EMAIL__USE_SSL:-false}}

    read -p "AUTHENTIK_EMAIL__TIMEOUT [${AUTHENTIK_EMAIL__TIMEOUT:-10}]: " input
    AUTHENTIK_EMAIL__TIMEOUT=${input:-${AUTHENTIK_EMAIL__TIMEOUT:-10}}

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
        "AUTHENTIK_VERSION=${AUTHENTIK_VERSION}"
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
    while :; do
        read -p "Proceed with this configuration? (y/n): " CONFIRM
        [[ "$CONFIRM" == "y" ]] && break
        [[ "$CONFIRM" == "n" ]] && { echo "Configuration aborted by user."; exit 1; }
    done

    printf "%s\n" "${CONFIG_LINES[@]}" > "$ENV_FILE"
    echo ".env file saved to $ENV_FILE"
    echo ""
}

# Prepare volumes and run docker-compose
setup_containers() {
    echo "Stopping all containers and removing volumes..."
    docker compose down -v

    if [ -d "$VOL_DIR" ]; then
        echo "The 'vol' directory exists:"
        echo " - In case of a new install type 'y' to clear its contents. WARNING! This will remove all previous configuration files and stored data."
        echo " - In case of an upgrade/installing a new application type 'n' (or press Enter)."
        read -p "Clear it now? (y/N): " CONFIRM
        echo ""
        if [[ "$CONFIRM" == "y" ]]; then
            echo "Clearing 'vol' directory..."
            rm -rf "${VOL_DIR:?}"/*
        fi
    fi

    mkdir -p "${VOL_DIR}/authentik-app/media" && chown 1000 "${VOL_DIR}/authentik-app/media"

    echo "Starting containers..."
    docker compose up -d

    echo "Waiting 20 seconds for services to initialize..."
    sleep 20

    echo "Done!"
    echo ""
}

# -----------------------------------
# Main logic
# -----------------------------------
check_requirements

if [[ -f "$ENV_FILE" ]]; then
    echo ".env file found. Loading existing configuration."
    load_existing_env
else
    echo ".env file not found. Generating defaults."
    generate_defaults
fi

prompt_for_configuration
confirm_and_save_configuration
create_networks
create_backup_tasks
setup_containers
