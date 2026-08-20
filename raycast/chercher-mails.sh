#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Chercher dans mes mails (par le sens)
# @raycast.mode fullOutput
# @raycast.packageName Spotlight par le sens
# @raycast.icon 🔎
# @raycast.argument1 { "type": "text", "placeholder": "mot, nom (même mal orthographié), ou idée" }
# @raycast.description Recherche 3 couches (mot exact + fautes + sens) dans Apple Mail.

FORMAT=texte K=8 ~/Scripts/semsearch/venv/bin/python ~/Scripts/spotlight-sens/cherche.py "$1"
