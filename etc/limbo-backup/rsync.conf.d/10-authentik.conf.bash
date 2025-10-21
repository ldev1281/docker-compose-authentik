CMD_BEFORE_BACKUP="docker compose --project-directory /docker/authentik down"
CMD_AFTER_BACKUP="docker compose --project-directory /docker/authentik up -d"

CMD_BEFORE_RESTORE="docker compose --project-directory /docker/authentik down || true"
CMD_AFTER_RESTORE=(
"docker network create --driver bridge --internal proxy-client-authentik || true"
"docker compose --project-directory /docker/authentik up -d"
)

INCLUDE_PATHS=(
  "/docker/authentik"
)
