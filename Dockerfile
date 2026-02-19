# syntax=docker/dockerfile:1
FROM fedora:43

ARG USERNAME=openclaw
ARG UID=1000
ARG GID=1000

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN dnf -y update && \
    dnf -y install \
      git \
      nodejs npm \
      python3 \
      sudo tini \
      ca-certificates curl \
      iproute procps-ng && \
    dnf clean all

# Пользователь + sudo (внутри контейнера)
RUN groupadd -g ${GID} ${USERNAME} && \
    useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# Ставим OpenClaw CLI глобально
# (делаем это под root, чтобы не возиться с правами на global npm prefix)
RUN npm install -g openclaw@latest

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# entrypoint
COPY --chown=${UID}:${GID} entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 18789
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]

# В контейнере не ставим daemon через systemd.
# Просто держим gateway в foreground.
CMD ["openclaw", "gateway", "--port", "18789", "--verbose"]
