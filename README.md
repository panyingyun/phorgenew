# Phorge Docker image (unofficial)

This repository provides an unofficial Docker image for Phorge. The image runs multiple services inside a single container (PHP-FPM, Nginx, SSH hooks, etc.) using `supervisord` to manage processes.

Important: This is an unofficial image and is not affiliated with the upstream Phorge project.

**Automatic builds**
- The repository contains a GitHub Actions workflow at `.github/workflows/dockerimage.yml` that builds the Docker image nightly (schedule) and on demand (`workflow_dispatch`).
- Built images are pushed to Docker Hub under `rrvenn/phorge`.
- Tags published by CI: a short commit SHA tag (7 characters) and `latest` (so `rrvenn/phorge:latest` will point to the newest image).

Getting started
----------------
You can run the image directly with `docker run` or orchestrate the stack with `docker-compose` (a `docker-compose.yml` is included in the repo).

Docker Compose
--------------
The included `docker-compose.yml` defines these services:
- `ph-web` — the Phorge web container (image `rrvenn/phorge`).
- `ph-database` — MariaDB (`mariadb:10.11`).
- `ph-storage` — MinIO object storage (`minio/minio`) configured as an S3-compatible storage server.

The compose file references an `.env` file via `env_file: .env`. Update the `.env` file and then start the stack:

```bash
docker-compose up -d
```

.env template
-------------
Create a file named `.env` next to `docker-compose.yml`. The image reads environment variables at container start and the startup script applies them to Phorge's configuration. Below is a recommended template with defaults (where provided):

```env
# Phorge runtime
PROTOCOL=http            # http or https (default: http)
BASE_URI=example.com     # required: the public base URI (no trailing slash)

# SSH / git user
GIT_USER=root            # default in the Dockerfile is 'root'
SSH_PORT=8022            # default SSH port inside the container

# Database (MariaDB/MySQL)
MYSQL_HOST=mysql         # host or service name (no default)
MYSQL_PORT=3306          # default 3306
MYSQL_USER=root          # database user
MYSQL_PASSWORD=changeme  # database password

# MinIO / S3 (optional)
MINIO_SERVER=minio       # hostname or bucket name used by the startup script
MINIO_PORT=9000          # port for MinIO (compose maps 9000)
MINIO_SERVER_ACCESS_KEY=access_key
MINIO_SERVER_SECRET_KEY=secret_key

# SMTP (optional — all required for SMTP to be configured)
SMTP_SERVER=smtp.example.com
SMTP_PORT=587
SMTP_USER=smtp-user
SMTP_PASSWORD=smtp-password
SMTP_PROTOCOL=tls       # smtp protocol (e.g. tls)

# Volumes: the compose file creates named volumes; you may mount host paths instead
```

Notes on variables
- `PROTOCOL`: when set to `https` the startup script writes a small preamble to force HTTPS in PHP runtime.
- `GIT_USER`: the image creates this user (if missing) and configures Phorge to use it for SSH/Git access.
- `MINIO_SERVER` and related keys are used to configure Phorge's S3 storage settings — if you don't provide them, built-in file storage will be used.

Chinese (zh_CN) localization
-----------------------------
This image bundles a Simplified Chinese language pack (see `extensions/`), covering the most
frequently used UI strings (navigation, buttons, menus, settings, common actions). To use it:

1. Log in to Phorge.
2. Go to **Settings → Translation** and select **中文 (简体中文)**.
3. The UI switches to Chinese; untranslated strings fall back to English.

The pack is deployed automatically into Phorge's `src/extensions/` directory during the image
build, so it survives container restarts and image rebuilds.

Example: quick run with `docker run`
----------------------------------
You can also run the image directly (example):

```bash
docker run --rm -p 80:80 -p 8022:8022 \
  -e MYSQL_HOST=mysqlhost.com -e MYSQL_USER=root -e MYSQL_PASSWORD=changeme \
  -e BASE_URI=example.com -v /your/repo/folder:/var/repo \
  rrvenn/phorge:latest
```

Docker image tags
- `rrvenn/phorge:latest` — newest image built by CI.
- `rrvenn/phorge:<short-sha>` — images built by CI are also published with a short SHA tag for reproducibility.

Links
- Docker Hub: https://hub.docker.com/r/rrvenn/phorge

See also
- `Dockerfile`, `scripts/startup.sh`, and `docker-compose.yml` for details on how the container is configured and what environment variables are supported.
