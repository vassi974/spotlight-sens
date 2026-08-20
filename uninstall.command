#!/bin/bash
# =====================================================================
#  Spotlight par le sens — désinstallation
#  Arrête et retire les services. Propose (mais ne force pas) la suppression
#  du venv, des index et de la config.
# =====================================================================
set -uo pipefail
DEST="$HOME/Scripts/spotlight-sens"
LA="$HOME/Library/LaunchAgents"
UID_N="$(id -u)"

echo "▸ Arrêt et retrait des services"
for lab in com.vassili.spotlight-sens-daemon com.vassili.spotlightsens-app \
           com.vassili.spotlight-sens-rate com.vassili.spotlight-sens-reindex; do
  launchctl bootout "gui/$UID_N/$lab" 2>/dev/null && echo "  ✓ arrêté $lab" || true
  rm -f "$LA/$lab.plist"
done
pkill -f "SpotlightSens.app/Contents/MacOS/SpotlightSens" 2>/dev/null || true
echo "  ✓ services retirés"

printf "\nSupprimer aussi le venv, les index et la config (données locales) ? [o/N] "
read -r rep || rep="n"
if [[ "$rep" =~ ^[Oo] ]]; then
  rm -rf "$DEST/venv" "$DEST"/*.sqlite "$DEST"/*.npy "$DEST/config.json" "$DEST/rate.json" "$DEST"/*.log
  echo "  ✓ venv + index + config supprimés"
else
  echo "  ✓ données conservées (venv/index/config intacts)"
fi
echo "▸ Terminé. Le dossier $DEST (code) est conservé — supprime-le à la main si tu veux."
