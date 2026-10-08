#!/usr/bin/env bash
# Borra TODO el grupo de recursos del demo (App Service, plan, slot y ACR).
# Uso:  ./infra/cleanup.sh
# El plan S1 cobra por hora mientras exista: córrelo apenas termine la charla.
set -euo pipefail

RG="${RG:-rg-hero-agency}"

echo ">> Borrando el grupo de recursos $RG (tarda unos minutos)"
az group delete -n "$RG" --yes
echo ">> Listo. Los service connections de Azure DevOps quedan apuntando a un grupo que ya no existe: bórralos si no los vas a reutilizar."
