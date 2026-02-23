# Infra Install Scripts

This folder contains bootstrap scripts for local infra setup.
End-user entrypoint is only:

```bash
./infra/install/install.sh
```

## Full install (recommended)

This command creates required network(s), builds local images, and starts service stacks one by one.

From repo root:

```bash
./infra/install/install.sh
```

With explicit engine:

```bash
./infra/install/install.sh --engine podman
```

Install using user systemd units (enable/start managed services):

```bash
./infra/install/install.sh --with-systemd-user
```

## User systemd install (autostart on boot)

Template units live in:

```text
infra/install/systemd/
```

Install rendered user units and enable/start them:

```bash
./infra/install/scripts/install-systemd-user.sh \
  --repo-root "$PWD" \
  --template-dir "$PWD/infra/install/systemd"
```

Useful options:

```bash
./infra/install/scripts/install-systemd-user.sh \
  --repo-root "$PWD" \
  --template-dir "$PWD/infra/install/systemd" \
  --engine podman
./infra/install/scripts/install-systemd-user.sh \
  --repo-root "$PWD" \
  --template-dir "$PWD/infra/install/systemd" \
  --no-start
./infra/install/scripts/install-systemd-user.sh \
  --repo-root "$PWD" \
  --template-dir "$PWD/infra/install/systemd" \
  --no-enable
```

Control services as that user:

```bash
systemctl --user status ai-ollama.service ai-openclaw.service
systemctl --user restart ai-ollama.service
systemctl --user restart ai-openclaw.service
systemctl --user stop ai-openclaw.service
systemctl --user disable --now ai-openclaw.service
systemctl --user enable --now ai-openclaw.service
```

For boot-time user autostart, enable linger once (as root/admin):

```bash
sudo loginctl enable-linger <username>
```

## Build images

First and only image right now: OpenClaw.

From repo root:

```bash
./infra/install/scripts/build-images.sh openclaw --repo-root "$PWD"
```

Create the shared network once:

```bash
podman network create ollama_net 2>/dev/null || true
```

Default tag:

```text
localhost/openclaw:fedora43
```

Override the tag:

```bash
OPENCLAW_IMAGE=localhost/openclaw:mytag ./infra/install/scripts/build-images.sh openclaw --repo-root "$PWD"
```

Force engine:

```bash
./infra/install/scripts/build-images.sh openclaw --repo-root "$PWD" --engine podman
```

Your runtime compose uses `OPENCLAW_IMAGE` from:

```text
infra/services/ai/assistants/openclaw-local-llm/.env
```
