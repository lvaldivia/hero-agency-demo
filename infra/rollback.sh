#!/usr/bin/env bash
# Misión 6 (Aizawa): rollback instantáneo.
# Después de un swap, el slot staging guarda la versión anterior de producción.
# Volver a hacer swap la devuelve a producción en segundos.
set -euo pipefail

APP="${APP:-hero-agency-luis}"
RG="${RG:-rg-hero-agency}"

echo ">> Aizawa activa Erasure: swap staging <-> producción"
az webapp deployment slot swap -g "$RG" -n "$APP" --slot staging --target-slot production
echo ">> Rollback completo. Revisa los celulares del público."
