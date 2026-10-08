#!/usr/bin/env bash
# Misión 6 (Aizawa): rollback instantáneo.
# Producción corre en modo "multiple revisions": después de cada deploy, la revisión
# anterior sigue viva. Mover el 100% del tráfico a ella la devuelve en segundos, sin redeploy.
# Correrlo dos veces vuelve a la versión nueva.
set -euo pipefail
export MSYS_NO_PATHCONV=1

APP="${APP:-hero-agency-luis}"
RG="${RG:-rg-hero-agency}"

CURRENT=$(az containerapp ingress traffic show -g "$RG" -n "$APP" \
  --query "[?weight==\`100\`] | [0].revisionName" -o tsv)
if [ -z "$CURRENT" ]; then
  # El tráfico apunta a "latest": resolvemos cuál es la última revisión.
  CURRENT=$(az containerapp show -g "$RG" -n "$APP" --query properties.latestRevisionName -o tsv)
fi
TARGET=$(az containerapp revision list -g "$RG" -n "$APP" \
  --query "sort_by([?properties.active && name!='$CURRENT'], &properties.createdTime)[-1].name" -o tsv)

if [ -z "$TARGET" ]; then
  echo "No hay una revisión anterior activa para hacer rollback." >&2
  exit 1
fi

echo ">> Aizawa activa Erasure: tráfico de $CURRENT -> $TARGET"
az containerapp ingress traffic set -g "$RG" -n "$APP" --revision-weight "$TARGET=100" -o none
echo ">> Rollback completo. Revisa los celulares del público."
