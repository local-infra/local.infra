# Gitea + Build Runner via Quadlet (localinfra user)

This directory contains rootless Quadlet units for:

- `gitea` (Git + package registry + actions server)
- `gitea-build-runner` (Gitea Actions runner intended for build jobs)

Files:

- `gitea.container`
- `gitea.network`
- `gitea-data.volume`
- `gitea-config.volume`
- `gitea-build-runner.container`
- `gitea-build-runner-data.volume`

## 1) Prerequisites

- Podman installed for user `localinfra`
- user systemd manager available (`systemctl --user ...`)
- linger enabled for `localinfra` so services survive logout:

```bash
sudo loginctl enable-linger localinfra
```

## 2) Install Quadlet files for `localinfra`

```bash
sudo -iu localinfra bash -lc '
set -euo pipefail
mkdir -p ~/.config/containers/systemd ~/.config/gitea/act_runner
cp /workspace/infra/services/scm/gitea/*.container ~/.config/containers/systemd/
cp /workspace/infra/services/scm/gitea/*.network ~/.config/containers/systemd/
cp /workspace/infra/services/scm/gitea/*.volume ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user enable --now podman.socket
systemctl --user start gitea.service
'
```

Gitea will be reachable on:

- `http://127.0.0.1:3000` (web)
- `ssh://git@127.0.0.1:2222` (git over SSH)

## 3) Complete initial Gitea setup

1. Open `http://127.0.0.1:3000`
2. Complete first-run setup
3. Create an admin user
4. Ensure Actions remain enabled (already set via env in `gitea.container`)

## 4) Prepare runner config

Generate default runner config as `localinfra`:

```bash
sudo -iu localinfra bash -lc '
set -euo pipefail
podman run --rm docker.io/gitea/act_runner:latest generate-config > ~/.config/gitea/act_runner/config.yaml
'
```

You can keep the generated defaults for the first run.

## 5) Register build runner

Create a runner token in Gitea (repo/org settings -> Actions -> Runners), then register:

```bash
sudo -iu localinfra bash -lc '
set -euo pipefail
RUNNER_TOKEN="<PASTE_RUNNER_TOKEN>"
podman run --rm \
  --network gitea_net \
  -v gitea_build_runner_data:/data \
  -v "${HOME}/.config/gitea/act_runner/config.yaml:/config.yaml:ro" \
  docker.io/gitea/act_runner:latest \
  register \
    --config /config.yaml \
    --no-interactive \
    --instance http://gitea:3000 \
    --token "${RUNNER_TOKEN}" \
    --name localinfra-build-runner \
    --labels "build:docker://docker.io/docker:27-cli"
'
```

Then start the runner service:

```bash
sudo -iu localinfra bash -lc '
set -euo pipefail
systemctl --user start gitea-build-runner.service
'
```

## 6) Verify

```bash
sudo -iu localinfra bash -lc '
set -euo pipefail
systemctl --user status gitea.service --no-pager
systemctl --user status gitea-build-runner.service --no-pager
podman ps --filter name=gitea
podman ps --filter name=gitea-build-runner
'
```

Check logs:

```bash
sudo -iu localinfra bash -lc 'journalctl --user -u gitea.service -f'
sudo -iu localinfra bash -lc 'journalctl --user -u gitea-build-runner.service -f'
```

## Notes

- Runner unit mounts `%t/podman/podman.sock` to `/var/run/docker.sock` so build jobs can use Docker-compatible API via rootless Podman.
- This runner is intended for build/publish workloads. Keep host deployment actions separate (or pull-based on host) to reduce blast radius.
- If you need LAN access, change `PublishPort=127.0.0.1:...` entries in `gitea.container`.
- Quadlet-generated units are transient, so `systemctl --user enable gitea.service` (or runner service) fails by design. Use `systemctl --user start ...` after `daemon-reload`; autostart is handled from `[Install]` in the `.container` files.
