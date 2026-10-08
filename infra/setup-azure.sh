#!/usr/bin/env bash
# Crea la infraestructura del demo en Azure.
# Uso:  APP=hero-agency-luis ./infra/setup-azure.sh
# Requiere Azure CLI con sesión iniciada (az login).
set -euo pipefail

APP="${APP:?Define APP con un nombre único, por ejemplo: APP=hero-agency-luis}"
RG="${RG:-rg-hero-agency}"
LOCATION="${LOCATION:-eastus2}"
PLAN="${PLAN:-plan-hero-agency}"
ADMIN_TOKEN="${ADMIN_TOKEN:-$(openssl rand -hex 8)}"

echo ">> Grupo de recursos"
az group create -n "$RG" -l "$LOCATION" -o none

echo ">> App Service Plan S1 (Standard: necesario para deployment slots)"
az appservice plan create -g "$RG" -n "$PLAN" --is-linux --sku S1 -o none

echo ">> Web App de producción"
az webapp create -g "$RG" -p "$PLAN" -n "$APP" --runtime "NODE:22-lts" -o none

echo ">> Slot staging"
az webapp deployment slot create -g "$RG" -n "$APP" --slot staging -o none

for SLOT_ARGS in "" "--slot staging"; do
  # Always On evita el arranque en frío durante la charla.
  az webapp config set -g "$RG" -n "$APP" $SLOT_ARGS --always-on true -o none
  # El artefacto ya trae node_modules: no hace falta compilar en el servidor.
  az webapp config appsettings set -g "$RG" -n "$APP" $SLOT_ARGS -o none \
    --settings SCM_DO_BUILD_DURING_DEPLOYMENT=false ADMIN_TOKEN="$ADMIN_TOKEN"
done

# APP_ENV es "slot setting": se queda pegado al slot cuando se hace swap.
az webapp config appsettings set -g "$RG" -n "$APP" -o none --slot-settings APP_ENV=production
az webapp config appsettings set -g "$RG" -n "$APP" --slot staging -o none --slot-settings APP_ENV=staging

PROD_HOST=$(az webapp show -g "$RG" -n "$APP" --query defaultHostName -o tsv)
STAGING_HOST=$(az webapp show -g "$RG" -n "$APP" --slot staging --query defaultHostName -o tsv)

echo ""
echo "Listo. Copia estos valores en las variables de azure-pipelines.yml:"
echo "  webAppName:    $APP"
echo "  resourceGroup: $RG"
echo "  prodUrl:       https://$PROD_HOST"
echo "  stagingUrl:    https://$STAGING_HOST"
echo ""
echo "Token para reiniciar votaciones (guárdalo): $ADMIN_TOKEN"
echo "  curl -X POST \"https://$PROD_HOST/api/votes/reset?token=$ADMIN_TOKEN\""
echo ""
echo "Para borrar todo después de la charla:  az group delete -n $RG --yes"
