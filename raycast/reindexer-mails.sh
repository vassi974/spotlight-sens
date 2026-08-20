#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Ré-indexer mes mails (maintenant)
# @raycast.mode compact
# @raycast.packageName Spotlight par le sens
# @raycast.icon ♻️
# @raycast.description Reconstruit l'index des mails (sinon fait chaque nuit).

~/Scripts/semsearch/venv/bin/python ~/Scripts/spotlight-sens/mail_index.py 2>&1 | grep -E "uniques|FINI" | tail -2
