# Ollama Volume Migration (backup + restore)

When Ollama was moved to `infra/services/ai/ollama/docker-compose.yaml`, Compose may create a new volume name for `ollama_data`.

Use this to migrate existing models safely.

If you use Podman, replace `docker` with `podman` in commands below.

## Open WebUI

`./docker-compose.yaml` now includes:

- `ollama` (model runtime)
- `open-webui` (web UI)

Start both:

```bash
docker compose -f ./docker-compose.yaml up -d
```

Open UI:

- `http://127.0.0.1:3000`
- To change the host port: set `OPEN_WEBUI_PORT` (default `3000`)

Model management:

- In Open WebUI, go to **Models** and use the Ollama integration to pull/remove models.

Useful runtime logs:

```bash
docker compose -f ./docker-compose.yaml logs -f ollama
docker compose -f ./docker-compose.yaml logs -f open-webui
```

## Scripted way (recommended)

Two scripts are included in this folder:

- `./backup-volume.sh <volume_name>`
- `./restore-volume.sh <volume_name>`

Both take exactly one argument: the Docker/Podman volume name.

Example:

```bash
./backup-volume.sh workspace_ollama_data
./restore-volume.sh ollama_ollama_data
```

Notes:

- Backup files are written to `./backup/`.
- File names are `<safe_volume_name>__YYYYMMDD_HHMMSS.tar`.
- Backup is intentionally uncompressed for faster create/restore.
- Backups use `tar --numeric-owner` to preserve owner/group IDs and permissions.
- Restore prefers the latest matching backup for the provided volume name.
- If no matching backup exists, restore uses the latest backup archive in `./backup/`.
- Restore supports both `.tar` and legacy `.tar.gz` backups.

## 1) Find old and new volume names

```bash
docker volume ls --format '{{.Name}}' | grep 'ollama_data'
```

Typical names:

- old volume (from root compose): `workspace_ollama_data`
- new volume (from `./docker-compose.yaml`): `ollama_ollama_data`

Set variables:

```bash
OLD_VOL=workspace_ollama_data
NEW_VOL=ollama_ollama_data
```

## 2) Stop Ollama before backup

```bash
docker compose -f ./docker-compose.yaml down || true
docker rm -f ollama 2>/dev/null || true
```

## 3) Backup old volume to tar

```bash
./backup-volume.sh "${OLD_VOL}"
```

## 4) Restore backup into new volume

```bash
./restore-volume.sh "${NEW_VOL}"
```

## 5) Verify data exists in new volume

```bash
docker run --rm -v "${NEW_VOL}:/data" alpine sh -c "du -sh /data && ls -la /data"
```

You should see `.ollama` data files (including model blobs/manifests).

## 6) Start moved Ollama stack

```bash
docker compose -f ./docker-compose.yaml up -d
```

## Optional: direct copy without backup archive

Use this only if you do not want a tar backup:

```bash
docker volume create "${NEW_VOL}"
docker run --rm \
  -v "${OLD_VOL}:/from:ro" \
  -v "${NEW_VOL}:/to" \
  alpine sh -c "cp -a /from/. /to/"
```
