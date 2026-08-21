#!/bin/bash
# Active le MODE DÉMO : le moteur sert la fausse base (demo_*) au lieu des vrais
# index. Les vrais index sont mis de côté (renommés .real), rien n'est détruit.
set -e
D="$HOME/Scripts/spotlight-sens"; cd "$D"
[ -f demo_mail.sqlite ] || { echo "Fausse base absente. Lance d'abord : venv/bin/python demo_build.py"; exit 1; }
if [ ! -f .demo_active ]; then
  for f in mail.sqlite mail_vecs.npy docs.sqlite docs_vecs.npy; do
    [ -f "$f" ] && mv "$f" "$f.real"
  done
  touch .demo_active
fi
cp -f demo_mail.sqlite mail.sqlite
cp -f demo_mail_vecs.npy mail_vecs.npy
cp -f demo_docs.sqlite docs.sqlite
cp -f demo_docs_vecs.npy docs_vecs.npy
launchctl kickstart -k "gui/$(id -u)/com.vassili.spotlight-sens-daemon"
echo "✅ MODE DÉMO ACTIF (fausse base). Filme, puis lance ./demo_off.sh pour revenir au réel."
