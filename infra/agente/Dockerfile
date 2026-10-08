# Agente self-hosted de Azure Pipelines en un contenedor Linux.
# Usa el Docker de la máquina anfitriona (socket montado) para construir las imágenes del demo.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    AGENT_ALLOW_RUNASROOT=1 \
    AZURE_EXTENSION_DIR=/opt/az-extensions

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git jq libicu70 gnupg lsb-release unzip zip \
 && curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu jammy stable" > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
 && rm -rf /var/lib/apt/lists/*

# Extensión de Container Apps preinstalada: ahorra tiempo en cada run.
RUN az extension add --name containerapp -y --only-show-errors

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh
WORKDIR /azp
ENTRYPOINT ["start.sh"]
