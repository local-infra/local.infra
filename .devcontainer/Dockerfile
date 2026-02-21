FROM quay.io/fedora/fedora-toolbox:43

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD bash -lc 'true'

# Установить необходимые пакеты

# trunk-ignore(hadolint/DL3041)
RUN dnf -y install \
      plantuml \
      graphviz \
      java-latest-openjdk-headless \
      libxcrypt-compat \
      uv \
 && dnf -y clean all \
 && rm -rf /var/cache/dnf

# Force Java headless for everything (safe in devcontainer)
ENV JAVA_TOOL_OPTIONS="-Djava.awt.headless=true"

# Make plantuml always headless (avoid X11 in containers)
RUN cat > /usr/local/bin/plantuml <<'EOF' \
 && chmod +x /usr/local/bin/plantuml
#!/usr/bin/env bash
unset DISPLAY
exec /usr/bin/plantuml "$@"
EOF

WORKDIR /workspace
RUN useradd -m vscode
USER vscode
