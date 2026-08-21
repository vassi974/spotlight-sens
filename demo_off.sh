#!/bin/bash
# Désactive le MODE DÉMO : restaure les vrais index mis de côté par demo_on.sh.
set -e
D="$HOME/Scripts/spotlight-sens"; cd "$D"
if [ ! -f .demo_active ]; then echo "Pas en mode démo, rien à faire."; exit 0; fi
for f in mail.sqlite mail_vecs.npy docs.sqlite docs_vecs.npy; do
  [ -f "$f.real" ] && mv -f "$f.real" "$f"
done
rm -f .demo_active
launchctl kickstart -k "gui/$(id -u)/com.vassili.spotlight-sens-daemon"
echo "✅ RETOUR AU RÉEL — tes vrais index sont restaurés."
