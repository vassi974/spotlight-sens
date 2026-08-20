# Spotlight par le sens

Un lanceur de recherche **local** pour macOS qui trouve par le **sens**, pas
seulement par le nom de fichier. On presse `Cmd+Space`, on tape, et ça cherche
dans les mails Apple Mail, les documents, les applications, les réglages système
et les dossiers — sans avoir à dire quoi ni où chercher.

Tout tourne en local, sur la machine. Aucune donnée ne part sur un serveur.

![catégorie : lanceur macOS](https://img.shields.io/badge/macOS-13%2B-black)

## Ce que ça fait

- **Recherche par le sens** sur les mails et documents (comprend « facture
  d'électricité » même si le mot exact n'y est pas).
- **Lanceur d'applications** : taper le nom (FR ou EN) fait remonter l'app en tête
  (« pag » → Pages, « calc » → Calculatrice).
- **Lanceur de réglages système** : « wifi », « écran », « bluetooth » ouvrent le
  bon panneau des Réglages.
- **Aperçu latéral** : Quick Look interactif pour les fichiers (un STL tourne, un
  PDF se feuillette) et un panneau texte pour les mails.
- **Calcul et conversion** de devises directement dans la barre.
- Fenêtre native en verre dépoli, thèmes, onglets par catégorie, tri par date.

## Comment ça marche

Moteur de recherche **hybride à 3 couches**, fusionnées par *Reciprocal Rank
Fusion* (RRF) :

1. **Mot exact** — SQLite FTS5 (BM25) + trigrammes.
2. **Fautes de frappe** — `difflib` sur le vocabulaire réellement indexé
   (« brincks » → Brinks).
3. **Sens** — vecteurs [fastembed](https://github.com/qdrant/fastembed) (modèle
   MiniLM multilingue, 384 dimensions).

Un **daemon résident** (`serve.py`, port 8799 en local) garde le modèle et les
index en mémoire pour répondre en ~15 ms — indispensable pour la recherche en
direct pendant la frappe.

## Fichiers

| Fichier | Rôle |
|---|---|
| `serve.py` | Moteur résident (HTTP local) : `/search`, `/mailbody`, `/ping`. |
| `mail_index.py` | Indexe Apple Mail (`.emlx`) → `mail.sqlite` + vecteurs. |
| `docs_index.py` | Indexe documents, applications, réglages système, dossiers. |
| `cherche.py` | Moteur de recherche 3 couches (utilisé en CLI et par le daemon). |
| `rate_update.py` | Taux USD/EUR du jour pour la conversion. |
| `import_theme.py` | Importe un thème Linux (base16, KDE `.colors`, Xresources, iTerm). |
| `app/main.swift` | L'application native (AppKit) : fenêtre, hotkey, aperçus. |
| `app/build.sh` | Compile `SpotlightSens.app`. |
| `themes/` | Thèmes prêts à l'emploi (Nord, Dracula, Catppuccin, Gruvbox…). |

## Construire l'application

```bash
bash app/build.sh          # produit app/SpotlightSens.app
open app/SpotlightSens.app
```

Le moteur a besoin de Python 3 avec `fastembed` et `numpy` (le projet réutilise
un venv dédié). Première utilisation :

```bash
python3 mail_index.py      # indexe les mails
python3 docs_index.py      # indexe documents / apps / réglages / dossiers
python3 serve.py           # lance le moteur résident (port 8799)
```

## Vie privée

Les index (`*.sqlite`, `*.npy`), la configuration et les journaux **ne sont pas**
dans ce dépôt (voir `.gitignore`) : ils contiennent le contenu réel des mails et
documents. Seul le code est publié. Tout s'exécute en local.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE) — libre en usage non commercial.
