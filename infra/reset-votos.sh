#!/usr/bin/env bash
# Reinicia la votación en producción antes de cada misión.
# Uso:  PROD_URL=https://hero-agency-luis.azurewebsites.net ADMIN_TOKEN=xxxx ./infra/reset-votos.sh
set -euo pipefail
curl -fsS -X POST "${PROD_URL:?Define PROD_URL}/api/votes/reset?token=${ADMIN_TOKEN:?Define ADMIN_TOKEN}"
echo ""
