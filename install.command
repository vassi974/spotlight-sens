#!/bin/bash
# =====================================================================
#  Spotlight par le sens — installateur une commande (macOS)
#  Double-clic sur ce fichier, ou : bash install.command
#
#  Il fait tout : dépendances Python (venv dédié), compilation de l'app,
#  services (LaunchAgents), premier index, lancement. Idempotent — on peut
#  le relancer sans casse.
# =====================================================================
set -euo pipefail

DEST="$HOME/Scripts/spotlight-sens"          # emplacement standard (le code y est fixé)
SELF="$(cd "$(dirname "$0")" && pwd)"
LA="$HOME/Library/LaunchAgents"
PY="$DEST/venv/bin/python3"
UID_N="$(id -u)"

say(){ printf "\n\033[1;34m▸ %s\033[0m\n" "$1"; }
ok(){  printf "  \033[32m✓\033[0m %s\n" "$1"; }
die(){ printf "\n\033[1;31m✗ %s\033[0m\n" "$1"; exit 1; }

# ---------------------------------------------------------------------
say "Vérifications"
command -v python3 >/dev/null || die "Python 3 introuvable. Installe-le (python.org ou 'brew install python')."
command -v swiftc  >/dev/null || die "swiftc introuvable. Installe les outils Xcode : xcode-select --install"
ok "python3 : $(python3 -V 2>&1)"
ok "swiftc présent"

# ---------------------------------------------------------------------
say "Installation des fichiers dans $DEST"
mkdir -p "$DEST"
if [ "$SELF" != "$DEST" ]; then
  # copie du code, JAMAIS les données ni le venv ni le .app compilé
  rsync -a --delete \
    --exclude 'venv/' --exclude '*.sqlite' --exclude '*.npy' --exclude '*.log' \
    --exclude 'config.json' --exclude 'rate.json' --exclude '__pycache__/' \
    --exclude '.git/' --exclude 'app/SpotlightSens.app/' \
    "$SELF"/ "$DEST"/
  ok "fichiers copiés"
else
  ok "déjà en place"
fi

# ---------------------------------------------------------------------
say "Environnement Python (venv dédié + dépendances)"
if [ ! -x "$PY" ]; then
  python3 -m venv "$DEST/venv"
  ok "venv créé"
fi
"$PY" -m pip install --quiet --upgrade pip
"$PY" -m pip install --quiet fastembed numpy certifi segno
ok "dépendances installées (fastembed, numpy, certifi, segno)"

# ---------------------------------------------------------------------
say "Compilation de l'application"
bash "$DEST/app/build.sh" >/dev/null
[ -d "$DEST/app/SpotlightSens.app" ] || die "la compilation a échoué"
ok "SpotlightSens.app construit"

# ---------------------------------------------------------------------
say "Mise en place des services (LaunchAgents)"
mkdir -p "$LA"

plist_prog(){ # $1=label  $2..=ProgramArguments  puis clés supplémentaires via STDIN
  local label="$1"; shift
  local args="" a
  for a in "$@"; do args="$args    <string>$a</string>\n"; done
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0"><dict>'
    echo "  <key>Label</key><string>$label</string>"
    echo "  <key>ProgramArguments</key><array>"; printf "%b" "$args"; echo "  </array>"
    cat   # le reste (RunAtLoad/KeepAlive/StartCalendarInterval/logs) vient de STDIN
    echo '</dict></plist>'
  }
}

# moteur résident
plist_prog com.vassili.spotlight-sens-daemon "$PY" "$DEST/serve.py" <<PLIST > "$LA/com.vassili.spotlight-sens-daemon.plist"
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$DEST/serve.log</string>
  <key>StandardErrorPath</key><string>$DEST/serve.log</string>
PLIST

# application
plist_prog com.vassili.spotlightsens-app "$DEST/app/SpotlightSens.app/Contents/MacOS/SpotlightSens" <<PLIST > "$LA/com.vassili.spotlightsens-app.plist"
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
PLIST

# taux $/€ (07h00)
plist_prog com.vassili.spotlight-sens-rate "$PY" "$DEST/rate_update.py" <<PLIST > "$LA/com.vassili.spotlight-sens-rate.plist"
  <key>RunAtLoad</key><true/>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$DEST/rate.log</string>
  <key>StandardErrorPath</key><string>$DEST/rate.log</string>
PLIST

# ré-index nocturne (03h10)
plist_prog com.vassili.spotlight-sens-reindex /bin/bash "$DEST/reindex_all.sh" <<PLIST > "$LA/com.vassili.spotlight-sens-reindex.plist"
  <key>Nice</key><integer>10</integer>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>10</integer></dict>
  <key>StandardOutPath</key><string>$DEST/reindex.log</string>
  <key>StandardErrorPath</key><string>$DEST/reindex.log</string>
PLIST
ok "4 services écrits"

# ---------------------------------------------------------------------
say "Premier index (mails + documents)"
echo "  Cette étape lit tes mails Apple Mail et tes documents pour construire l'index."
echo "  C'est le plus long (~10-15 min selon le volume). Tu peux la lancer maintenant"
echo "  ou plus tard (menu de l'app → « Ré-indexer »)."
printf "  Lancer l'indexation maintenant ? [O/n] "
read -r rep || rep="o"
if [[ ! "$rep" =~ ^[Nn] ]]; then
  "$PY" "$DEST/mail_index.py"  || echo "  (indexation mails : à relancer plus tard)"
  "$PY" "$DEST/docs_index.py"  || echo "  (indexation documents : à relancer plus tard)"
  ok "index construit"
else
  ok "indexation reportée"
fi

# ---------------------------------------------------------------------
say "Démarrage des services"
for s in daemon app rate reindex; do
  lab="com.vassili.spotlight-sens-$s"; [ "$s" = app ] && lab="com.vassili.spotlightsens-app"
  launchctl bootout   "gui/$UID_N/$lab" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_N" "$LA/$lab.plist" 2>/dev/null || true
done
ok "services chargés"

printf "\n\033[1;32m✔ Installation terminée.\033[0m\n"
echo   "   Presse ⌘ + Espace pour ouvrir Spotlight par le sens."
echo   "   (Si ⌘+Espace ouvre le Spotlight d'Apple : Réglages → Clavier → Raccourcis →"
echo   "    Spotlight, et décoche « Afficher la recherche Spotlight ».)"
