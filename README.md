After containers are build and runnig make this:

```bash
podman compose exec openclaw openclaw onboard --install-daemon
```

## Manual Gateway startup

```bash
podman compose exec openclaw openclaw gateway --port 18789 --verbose
```

If it says start is blocked by mode, set local mode first:

```bash
podman compose exec openclaw openclaw config set gateway.mode local
openclaw gateway --port 18789 --verbose
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
