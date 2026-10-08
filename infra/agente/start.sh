#!/bin/bash
# Registra el agente la primera vez (necesita AZP_URL y AZP_TOKEN) y luego lo ejecuta.
# La configuración queda en el volumen /azp, así que los reinicios ya no necesitan el token.
set -euo pipefail

AZP_POOL="${AZP_POOL:-Default}"
AZP_AGENT_NAME="${AZP_AGENT_NAME:-$(hostname)}"
cd /azp

if [ ! -f .agent ]; then
  : "${AZP_URL:?Define AZP_URL, por ejemplo https://dev.azure.com/mi-org}"
  : "${AZP_TOKEN:?Define AZP_TOKEN (PAT con Agent Pools: Read & manage)}"

  if [ ! -f ./config.sh ]; then
    echo ">> Descargando el agente de Azure Pipelines"
    PACKAGE_URL=$(curl -LsS -u ":$AZP_TOKEN" -H 'Accept:application/json' \
      "$AZP_URL/_apis/distributedtask/packages/agent?platform=linux-x64&top=1" | jq -r '.value[0].downloadUrl')
    curl -LsS "$PACKAGE_URL" | tar -xz
  fi

  echo ">> Registrando el agente $AZP_AGENT_NAME en el pool $AZP_POOL"
  ./config.sh --unattended --agent "$AZP_AGENT_NAME" --url "$AZP_URL" --auth PAT --token "$AZP_TOKEN" \
    --pool "$AZP_POOL" --work _work --replace --acceptTeeEula
fi

unset AZP_TOKEN
exec ./run.sh
