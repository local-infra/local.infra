## Build and run

Build local image from repo root:

```bash
./infra/install/scripts/build-images.sh openclaw --repo-root "$PWD"
```

Then in this folder:

```bash
cp .env.example .env
podman network create ollama_net 2>/dev/null || true
podman compose up -d
```

If you changed the image tag, set `OPENCLAW_IMAGE` in `.env` before `up -d`.

After containers are built and running, the OpenClaw container now starts smartly on its own:

- If `~/.openclaw/openclaw.json` does not exist yet, port `18789` serves an interactive web terminal (`ttyd`) for onboarding.
- If config exists, it starts `openclaw gateway --port 18789 --verbose` automatically.

First-time setup in browser:

1. Open `http://127.0.0.1:18789`
2. Complete onboarding prompts in the web terminal (it runs `onboard_script.sh` automatically)
3. After onboarding finishes, the container automatically switches from web terminal mode to `openclaw gateway`

Optional: set basic auth for this web terminal in `.env`:

```bash
OPENCLAW_WEBTTY_AUTH=admin:change-me
```

Optional: override default web terminal startup command (default is `onboard_script.sh`):

```bash
OPENCLAW_WEBTTY_INIT_CMD=onboard_script.sh
```

First-time setup from host shell (alternative):

```bash
podman compose exec openclaw onboard_script.sh
```

`onboard_script.sh` does all of this:

- runs onboarding (`openclaw onboard --install-daemon` by default)
- forces `gateway.bind` to `lan` in `openclaw.json`
- runs `killall openclaw-gateway` in a loop until no process remains, then starts
  `openclaw gateway --port <configured-port> --verbose` in background

Optional: pass your own onboarding flags through to `openclaw onboard`:

```bash
podman compose exec openclaw onboard_script.sh --non-interactive --accept-risk --mode local
```

If gateway is still managed elsewhere in your environment, restart the container once:

```bash
podman compose restart openclaw
```

If it says start is blocked by mode, set local mode first:

```bash
podman compose exec openclaw openclaw config set gateway.mode local
podman compose restart openclaw
```

Then check from another shell:

```bash
podman compose exec openclaw openclaw gateway status
```

## Troubleshooting

ISSUE:

```plain
origin=http://localhost:18789 host=localhost:18789 ua=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 code=1008 reason=pairing required
```

SOLUTION:

```bash
podman compose exec openclaw openclaw config get gateway.auth.token
podman compose exec openclaw openclaw devices list --url ws://127.0.0.1:18789 --token <PASTE_TOKEN>
podman compose exec openclaw openclaw devices approve --latest --url ws://127.0.0.1:18789 --token <PASTE_TOKEN>
```

## FFmpeg GPU backend switch

`ffmpeg` is wrapped in this image. Any software that runs `ffmpeg` by name will automatically use env-based backend selection.

`ffmpeg-gpu` is also available and behaves the same way.

Default environment values are set in `Dockerfile` and `docker-compose.yaml`:

```bash
FFMPEG_GPU_BACKEND=cpu     # cpu | nvidia | amd | intel
FFMPEG_GPU_DEVICE=/dev/dri/renderD128
FFMPEG_GPU_ENCODE=0        # set to 1 to auto-add vendor encoder flags
FFMPEG_INTEL_MODE=vaapi    # vaapi | qsv (intel backend only)
OPENCLAW_GPU_DEVICE_MAP=nvidia.com/gpu=all
OLLAMA_GPU_DEVICE_MAP=nvidia.com/gpu=all
```

Examples:

```bash
# CPU
FFMPEG_GPU_BACKEND=cpu ffmpeg -i in.mp4 out.mp4

# NVIDIA decode + encode
FFMPEG_GPU_BACKEND=nvidia FFMPEG_GPU_ENCODE=1 ffmpeg -i in.mp4 out.mp4

# AMD VAAPI decode + encode
FFMPEG_GPU_BACKEND=amd FFMPEG_GPU_ENCODE=1 ffmpeg -i in.mp4 out.mp4

# Intel QSV decode + encode
FFMPEG_GPU_BACKEND=intel FFMPEG_INTEL_MODE=qsv FFMPEG_GPU_ENCODE=1 ffmpeg -i in.mp4 out.mp4
```

Runtime device requirements:

- NVIDIA: keep `OPENCLAW_GPU_DEVICE_MAP=nvidia.com/gpu=all`
- AMD/Intel: set `OPENCLAW_GPU_DEVICE_MAP=/dev/dri:/dev/dri` and `FFMPEG_GPU_DEVICE=/dev/dri/renderD128`
