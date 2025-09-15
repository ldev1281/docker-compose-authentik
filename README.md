# Authentik Docker Compose Deployment (with Caddy Reverse Proxy)

This repository provides a production-ready Docker Compose configuration for deploying Authentik — an open-source identity and access management solution — with PostgreSQL as the database backend and Caddy as a reverse proxy. The setup includes automatic initialization, secure environment variable handling, and support for running behind a SOCKS5h-aware SMTP relay container.

## Setup Instructions

### 1. Clone the Repository

Clone the project to your server in the `/docker/authentik/` directory:

```
mkdir -p /docker/authentik
cd /docker/authentik

# Clone the main Authentik project
git clone https://github.com/ldev1281/docker-compose-authentik.git .
```


### 2. Create Docker Network and Set Up Reverse Proxy

This project is designed to work with the reverse proxy configuration provided by [`docker-compose-proxy-client`](https://github.com/ldev1281/docker-compose-proxy-client). To enable this integration, follow these steps:

1. **Create the shared Docker network** (if it doesn't already exist):

   ```bash
   docker network create --driver bridge proxy-client-authentik
   ```

2. **Set up the Caddy reverse proxy** by following the instructions in the [`docker-compose-proxy-client`](https://github.com/ldev1281/docker-compose-proxy-client).  

Once Caddy is installed, it will automatically detect the Authentik container via the `caddy-authentik` network and route traffic accordingly.


### 3. Configure and Start the Application

Configuration Variables:

| Variable Name               | Description                                          | Default Value            |
|-----------------------------|------------------------------------------------------|--------------------------|
| `AUTHENTIK_POSTGRES_VERSION` | Version of the PostgreSQL image                      | `16-alpine`              |
| `AUTHENTIK_IMAGE`            | Docker image for Authentik                           | `ghcr.io/goauthentik/server` |
| `AUTHENTIK_TAG`              | Tag of the Authentik Docker image                    | `2025.6.4`               |
| `AUTHENTIK_POSTGRES_USER`    | PostgreSQL username for Authentik                    | `authentik`              |
| `AUTHENTIK_POSTGRES_PASSWORD`| PostgreSQL password for Authentik                    | *(auto-generated)*       |
| `AUTHENTIK_POSTGRES_DB`      | Name of the PostgreSQL database for Authentik        | `authentik`              |
| `AUTHENTIK_SECRET_KEY`       | Secret key for Authentik                             | *(auto-generated)*       |
| `AUTHENTIK_EMAIL__HOST`      | SMTP server host                                     | `localhost`             |
| `AUTHENTIK_EMAIL__PORT`      | SMTP server port                                     | `25`                     |
| `AUTHENTIK_EMAIL__USERNAME`  | SMTP username                                        | *(empty)*                |
| `AUTHENTIK_EMAIL__PASSWORD`  | SMTP password                                        | *(empty)*                |
| `AUTHENTIK_EMAIL__USE_TLS`   | Enable TLS for SMTP                                  | `false`                  |
| `AUTHENTIK_EMAIL__USE_SSL`   | Enable SSL for SMTP                                  | `false`                  |
| `AUTHENTIK_EMAIL__TIMEOUT`   | Timeout for SMTP connections                         | `10`                     |
| `AUTHENTIK_EMAIL__FROM`      | "From" email address for Authentik                   | `authentik@localhost`    |

To configure and launch all required services, run the provided script:

```bash
./tools/init.bash
```

The script will:

- Prompt you to enter configuration values (press `Enter` to accept defaults).
- Generate secure random secrets automatically.
- Save all settings to the `.env` file located at the project root.

**Important:**  
Make sure to securely store your `.env` file locally for future reference or redeployment.

### 4. Start the Authentik Service

```
docker compose up -d
```

This will start Authentik and make your configured domains available.

### 5. Verify Running Containers


```bash
docker ps
```

You should see the authentik-app container running.
To start the initial setup, navigate to https://<your server's IP or hostname>/if/flow/initial-setup/

### 6. Persistent Data Storage

Authentik and PostgreSQL use the following bind-mounted volumes for data persistence:

- `./vol/authentik-postgres/var/lib/postgresql/data` – PostgreSQL database volume
- `./vol/authentik-app/media` – Authentik runtime data and attachments
- `./vol/authentik-app/templates` – Authentik templates
- `./vol/authentik-redis/data` – Redis data


---

### Example Directory Structure

```
/docker/authentik/
├── docker-compose.yml
├── tools/
│   └── init.bash
├── vol/
│   ├── authentik-app/
│   │   ├── media/
│   │   └── templates/
│   ├── authentik-postgres/
│   │   └── var/lib/postgresql/data/
│   └── authentik-redis/
│       └── data/
├── .env
```

Creating a Backup Task for Authentik

To create a backup task for your Authentik deployment using [`backup-tool`](https://github.com/ldev1281/backup-tool), add a new task file to `/etc/limbo-backup/rsync.conf.d/`:

```bash
sudo nano /etc/limbo-backup/rsync.conf.d/20-authentik.conf.bash
```

Paste the following contents:

```bash
CMD_BEFORE_BACKUP="docker compose --project-directory /docker/authentik down"
CMD_AFTER_BACKUP="docker compose --project-directory /docker/authentik up -d"

CMD_AFTER_RESTORE=(
"docker network create --driver bridge proxy-client-authentik || true"
"docker compose --project-directory /docker/authentik up -d"
)

INCLUDE_PATHS=(
  "/docker/authentik"
)
```


## License

Licensed under the Prostokvashino License. See [LICENSE](LICENSE) for details
