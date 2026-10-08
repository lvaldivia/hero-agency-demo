#!/usr/bin/env bash
# Crea la infraestructura del demo en Azure: ACR + Azure Container Apps (staging y producción).
# Uso:  APP=hero-agency-luis ACR=acrheroagencyluis ./infra/setup-azure.sh
# Requiere Azure CLI con sesión iniciada (az login) y Docker (para subir la imagen inicial).
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash en Windows: no convertir /subscriptions/... en rutas locales

APP="${APP:?Define APP con un nombre único, por ejemplo: APP=hero-agency-luis}"
ACR="${ACR:?Define ACR con un nombre único (solo letras y números), por ejemplo: ACR=acrheroagencyluis}"
RG="${RG:-rg-hero-agency}"
LOCATION="${LOCATION:-eastus2}"
ENV_NAME="${ENV_NAME:-cae-hero-agency}"
STAGING_APP="${STAGING_APP:-$APP-staging}"
IMAGE_REPO="${IMAGE_REPO:-hero-agency}"
ADMIN_TOKEN="${ADMIN_TOKEN:-$(openssl rand -hex 16)}"

az extension add --name containerapp --upgrade -y -o none
az provider register -n Microsoft.App --wait -o none

echo ">> Grupo de recursos"
az group create -n "$RG" -l "$LOCATION" -o none

echo ">> Azure Container Registry (Basic, sin admin user)"
az acr create -g "$RG" -n "$ACR" --sku Basic --admin-enabled false -o none
ACR_LOGIN=$(az acr show -g "$RG" -n "$ACR" --query loginServer -o tsv)
IMAGE="$ACR_LOGIN/$IMAGE_REPO:inicial"

echo ">> Imagen inicial ($IMAGE) para que ambas apps arranquen sanas"
az acr login -n "$ACR"
docker build -t "$IMAGE" "$(dirname "$0")/.."
docker push "$IMAGE"

echo ">> Container Apps Environment (consumo, sin Log Analytics)"
az containerapp env create -g "$RG" -n "$ENV_NAME" -l "$LOCATION" --logs-destination none -o none

# Dos apps en lugar de slots: APP_ENV queda fijo en cada una, como un "slot setting".
# Una sola réplica en cada una: los votos viven en memoria.
# --registry-identity system: identidad administrada con AcrPull, sin contraseñas.
create_app() {
  local name="$1" app_env="$2" mode="$3"
  echo ">> Container App $name (APP_ENV=$app_env, revisiones: $mode)"
  az containerapp create -g "$RG" -n "$name" --environment "$ENV_NAME" -o none \
    --image "$IMAGE" --registry-server "$ACR_LOGIN" --registry-identity system \
    --ingress external --target-port 8080 \
    --cpu 0.25 --memory 0.5Gi --min-replicas 1 --max-replicas 1 \
    --revisions-mode "$mode" \
    --secrets admin-token="$ADMIN_TOKEN" \
    --env-vars APP_ENV="$app_env" ADMIN_TOKEN=secretref:admin-token
}

create_app "$STAGING_APP" staging single
# Producción en modo "multiple": la revisión anterior queda viva para el rollback (Misión 6).
create_app "$APP" production multiple
az containerapp ingress traffic set -g "$RG" -n "$APP" --revision-weight latest=100 -o none

PROD_HOST=$(az containerapp show -g "$RG" -n "$APP" --query properties.configuration.ingress.fqdn -o tsv)
STAGING_HOST=$(az containerapp show -g "$RG" -n "$STAGING_APP" --query properties.configuration.ingress.fqdn -o tsv)

echo ""
echo "Listo. Valores para las variables de azure-pipelines.yml:"
echo "  containerAppName:  $APP"
echo "  stagingAppName:    $STAGING_APP"
echo "  resourceGroup:     $RG"
echo "  containerRegistry: $ACR_LOGIN"
echo "  prodUrl:           https://$PROD_HOST"
echo "  stagingUrl:        https://$STAGING_HOST"
echo ""
echo "Token para reiniciar votaciones (guárdalo en PREPARACION.md, no en el repo): $ADMIN_TOKEN"
echo "  PROD_URL=https://$PROD_HOST ADMIN_TOKEN=$ADMIN_TOKEN ./infra/reset-votos.sh"
echo ""
echo "Para borrar todo después de la charla:  RG=$RG ./infra/cleanup.sh"
