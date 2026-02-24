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
set -euo pipefail;
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

- `http://gitea.local:3000` (web)
- `ssh://git@gitea.local:2222` (git over SSH)

Add host mapping on the host OS:

```bash
echo "127.0.0.1 gitea.local" | sudo tee -a /etc/hosts
```

If you use devcontainers, also add host mapping in devcontainer config:

```json
"runArgs": ["--add-host=gitea.local:host-gateway"]
```

## 3) Complete initial Gitea setup

1. Open `http://gitea.local:3000`
2. Complete first-run setup
3. Create an admin user
4. Ensure Actions remain enabled (already set via env in `gitea.container`)

Recommended installer values for this Quadlet setup:

- Database Type: `SQLite3`
- Database Path: `/var/lib/gitea/data/gitea.db`
- Repository Root Path: `/var/lib/gitea/git/repositories`
- Git LFS Root Path: `/var/lib/gitea/git/lfs`
- Log Path: `/var/lib/gitea/data/log`
- SSH Server Port: `2222`
- Gitea HTTP Listen Port: `3000`
- Server Domain: `gitea.local`
- Gitea Base URL: `http://gitea.local:3000/`

If you see `http://127.0.0.1:4000/` in the installer, change it to `http://gitea.local:3000/` unless you also changed the Quadlet published port.

## 4) Prepare runner config

Generate default runner config as `localinfra`:

```bash
sudo -iu localinfra bash -lc '
set -euo pipefail;
podman run --rm --entrypoint act_runner docker.io/gitea/act_runner:latest generate-config > ~/.config/gitea/act_runner/config.yaml
'
```

You can keep the generated defaults for the first run.

## 5) Register build runner

Create a runner token in Gitea (repo/org settings -> Actions -> Runners), then register:

```bash
read -r -s -p "Runner token: " RUNNER_TOKEN; echo
export RUNNER_TOKEN
sudo --preserve-env=RUNNER_TOKEN -iu localinfra bash -lc '
set -euo pipefail;
export XDG_RUNTIME_DIR=/run/user/$(id -u);
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus;
[ -n "${RUNNER_TOKEN:-}" ] || { echo "token is empty"; exit 1; }
podman run --rm \
  --entrypoint act_runner \
  --network gitea_net \
  -v gitea_build_runner_data:/data:Z \
  -v "${HOME}/.config/gitea/act_runner/config.yaml:/config.yaml:ro,Z" \
  docker.io/gitea/act_runner:latest \
  register \
    --config /config.yaml \
    --no-interactive \
    --instance http://gitea:3000 \
    --token "${RUNNER_TOKEN}" \
    --name localinfra-build-runner
systemctl --user start gitea-build-runner.service
'
unset RUNNER_TOKEN
```

Set runner labels in `~/.config/gitea/act_runner/config.yaml` (this `act_runner` version ignores labels passed to `register` when `--config` is used):

```yaml
runner:
  labels:
    - "build:docker://docker.io/docker:27-cli"
```

## 6) Verify

```bash
sudo -iu localinfra bash -lc '
set -euo pipefail;
export XDG_RUNTIME_DIR=/run/user/$(id -u);
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus;
systemctl --user status gitea.service --no-pager;
systemctl --user status gitea-build-runner.service --no-pager;
podman ps --filter name=gitea;
podman ps --filter name=gitea-build-runner;
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
- `gitea.local` + `/etc/hosts` only solves name resolution. For devcontainers to reach Gitea, either use host networking for the devcontainer or bind Gitea on a non-loopback address.
- Quadlet-generated units are transient, so `systemctl --user enable gitea.service` (or runner service) fails by design. Use `systemctl --user start ...` after `daemon-reload`; autostart is handled from `[Install]` in the `.container` files.
- If `podman run ... generate-config` appears to hang, force one-shot mode with `--entrypoint act_runner ... generate-config` as shown above.
- On Fedora with SELinux enforcing, use `:Z`/`:z` for host bind mounts (example uses `:ro,Z` for `config.yaml`).
