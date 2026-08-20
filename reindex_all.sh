#!/bin/bash
# Ré-indexe mails + documents, puis recharge le moteur résident (sinon il garde
# les anciens index en mémoire). Lancé chaque nuit par le LaunchAgent.
PY="$HOME/Scripts/semsearch/venv/bin/python"
D="$HOME/Scripts/spotlight-sens"
"$PY" "$D/mail_index.py"
"$PY" "$D/docs_index.py"
launchctl kickstart -k "gui/$(id -u)/com.vassili.spotlight-sens-daemon"
"$HOME/Scripts/alerte.py" --battement com.vassili.spotlight-sens-reindex 2>/dev/null
echo "réindex mails+docs + moteur rechargé : $(date)"
