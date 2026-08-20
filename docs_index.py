#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""docs_index.py — index recherche par le sens + mot exact + fautes, sur les
DOCUMENTS de ~/Documents et ~/Desktop (PDF, Word, notes, texte).

Même moule que mail_index : docs.sqlite (FTS5 mot exact + trigram) + docs_vecs.npy.
Extraction : pdftotext (PDF), textutil (doc/docx/rtf/html), lecture directe (txt/md).

  ~/Scripts/semsearch/venv/bin/python ~/Scripts/spotlight-sens/docs_index.py
"""
import os, re, sys, subprocess, sqlite3
import numpy as np

def load_roots():
    import json
    default = [os.path.expanduser(p) for p in ("~/Documents", "~/Desktop", "~/Downloads", "/Applications")]
    try:
        j = json.load(open(os.path.expanduser("~/Scripts/spotlight-sens/config.json"), encoding="utf-8"))
        f = j.get("folders")
        if isinstance(f, list) and f:
            return [os.path.expanduser(p) for p in f if os.path.isdir(os.path.expanduser(p))] or default
    except Exception:
        pass
    return default


ROOTS = load_roots()
# les documents viennent des dossiers config (sauf /Applications, traité à part) ;
# les applications viennent de TOUS les dossiers d'apps si /Applications est coché.
DOC_ROOTS = [r for r in ROOTS if r.rstrip("/") != "/Applications"]
INDEX_APPS = "/Applications" in [r.rstrip("/") for r in ROOTS]
APP_ROOTS = ["/Applications", os.path.expanduser("~/Applications"),
             "/System/Applications", "/System/Applications/Utilities"]
DIR = os.path.expanduser("~/Scripts/spotlight-sens")
DB = os.path.join(DIR, "docs.sqlite")
NPY = os.path.join(DIR, "docs_vecs.npy")
MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
MAXI = 1600
FILECAP = 20000
EXCL = re.compile(r"/(Memoire Claude|node_modules|Library|\.cache|\.cargo|\.rustup|\.npm|\.git|venv|\.venv|"
                  r"site-packages|dist-packages|\.Trash|Caches|DerivedData|Pods|vendor|build|__pycache__)/")
TEXT_EXT = {"txt", "md", "markdown", "csv", "log", "text"}
TU_EXT = {"doc", "docx", "odt", "rtf", "html", "htm"}
# indexés par NOM seulement (pas de texte à extraire) : 3D/CAO, images, archives, médias, tableurs…
NAME_EXT = {"stl", "obj", "3mf", "step", "stp", "scad", "gcode", "f3d", "dwg", "dxf",
            "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "tif", "tiff", "bmp", "eps",
            "ai", "psd", "sketch", "fig", "xcf",
            "zip", "rar", "7z", "tar", "gz", "dmg",
            "mp4", "mov", "avi", "mkv", "mp3", "wav", "m4a", "aiff",
            "xlsx", "xls", "numbers", "pptx", "key", "pages"}
OK_EXT = TEXT_EXT | TU_EXT | NAME_EXT | {"pdf"}
WS = re.compile(r"[ \t\r\f\v]+")
NL = re.compile(r"\n{3,}")


def run(cmd, timeout=25):
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=timeout)
        return r.stdout.decode("utf-8", "replace")
    except Exception:
        return ""


def typ_of(ext):
    if ext == "pdf": return "pdf"
    if ext in ("doc", "docx", "odt", "rtf", "pages"): return "word"
    if ext in ("md", "markdown"): return "note"
    if ext in ("html", "htm"): return "web"
    if ext in ("stl", "obj", "3mf", "step", "stp", "scad", "gcode", "f3d"): return "3d"
    if ext in ("dwg", "dxf"): return "cad"
    if ext in ("png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "tif", "tiff", "bmp", "eps"): return "image"
    if ext in ("ai", "psd", "sketch", "fig", "xcf"): return "design"
    if ext in ("zip", "rar", "7z", "tar", "gz", "dmg"): return "archive"
    if ext in ("mp4", "mov", "avi", "mkv", "mp3", "wav", "m4a", "aiff"): return "media"
    if ext in ("xlsx", "xls", "numbers", "csv"): return "sheet"
    if ext in ("pptx", "key"): return "slides"
    if ext == "app": return "app"
    if ext == "folder": return "folder"
    return "text"


def extract(path, ext):
    if ext in TEXT_EXT:
        try:
            return open(path, encoding="utf-8", errors="replace").read(FILECAP * 2)
        except Exception:
            return ""
    if ext == "pdf":
        return run(["pdftotext", "-q", "-nopgbrk", "-l", "8", path, "-"])
    if ext in TU_EXT:
        return run(["textutil", "-convert", "txt", "-stdout", path])
    return ""


def app_label(path):
    """Nom cherchable d'une app : nom de fichier + nom affiché (souvent FR).
    Ex. Preview.app -> 'Preview Aperçu', Calculator.app -> 'Calculator Calculatrice'."""
    base = re.sub(r"\.app$", "", os.path.basename(path), flags=re.I)
    dn = run(["mdls", "-raw", "-name", "kMDItemDisplayName", path], timeout=5).strip()
    dn = re.sub(r"\.app$", "", dn, flags=re.I) if dn and dn != "(null)" else ""
    return base + (" " + dn if dn and dn.lower() != base.lower() else "")


def walk_apps():
    """Trouve les .app, y compris imbriquées dans un sous-dossier
    (ex. /Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app),
    sans jamais descendre à l'intérieur d'une app."""
    vus = set()
    for root in APP_ROOTS:
        if not os.path.isdir(root):
            continue
        for r, dirs, files in os.walk(root):
            keep = []
            for x in sorted(dirs):
                if x.lower().endswith(".app"):
                    p = os.path.join(r, x)
                    if p not in vus:
                        vus.add(p); yield (p, "app")   # trouvée, on n'y descend pas
                elif not x.startswith("."):
                    keep.append(x)
            dirs[:] = keep


# --- Panneaux de Réglages système : label FR + mots-clés + identifiant d'URL ---
SETTINGS_CURATED = [
    ("Wi-Fi", "com.apple.wifi-settings-extension", "wifi wi-fi reseau sans fil internet"),
    ("Bluetooth", "com.apple.BluetoothSettings", "bluetooth appairage"),
    ("Réseau", "com.apple.preference.network", "reseau network ethernet ip proxy"),
    ("VPN", "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension", "vpn"),
    ("Écrans", "com.apple.preference.displays", "ecran ecrans display moniteur resolution affichage"),
    ("Son", "com.apple.preference.sound", "son sound audio volume haut-parleur micro sortie entree"),
    ("Casque", "com.apple.HeadphoneSettings", "casque ecouteurs airpods headphone"),
    ("Notifications", "com.apple.Notifications-Settings.extension", "notifications alertes"),
    ("Concentration", "com.apple.Focus-Settings.extension", "concentration focus ne pas deranger"),
    ("Général", "com.apple.preference.general", "general a propos about stockage nom"),
    ("Apparence", "com.apple.preference.appearance", "apparence clair sombre theme couleur accent"),
    ("Bureau et Dock", "com.apple.Desktop-Settings.extension", "bureau dock mission control spaces coins"),
    ("Fond d'écran", "com.apple.preference.desktopscreeneffect", "fond ecran wallpaper economiseur screensaver"),
    ("Batterie", "com.apple.Battery-Settings.extension", "batterie energie autonomie alimentation"),
    ("Clavier", "com.apple.preference.keyboard", "clavier raccourcis touches saisie dictee"),
    ("Souris", "com.apple.preference.mouse", "souris mouse pointeur"),
    ("Trackpad", "com.apple.preference.trackpad", "trackpad pave tactile gestes clic"),
    ("Imprimantes et scanners", "com.apple.preference.printfax", "imprimante scanner impression print"),
    ("Accessibilité", "com.apple.Accessibility-Settings.extension", "accessibilite voiceover zoom vision audition"),
    ("Confidentialité et sécurité", "com.apple.preference.security", "confidentialite securite privacy permission camera micro localisation pare-feu"),
    ("Touch ID et mot de passe", "com.apple.Touch-ID-Settings.extension", "touch id empreinte mot de passe password"),
    ("Utilisateurs et groupes", "com.apple.preferences.users", "utilisateurs comptes groupes users login"),
    ("Identifiant Apple", "com.apple.systempreferences.AppleIDSettings", "apple id identifiant icloud compte"),
    ("Comptes Internet", "com.apple.Internet-Accounts-Settings.extension", "comptes internet mail contacts calendrier google"),
    ("Temps d'écran", "com.apple.Screen-Time-Settings.extension", "temps ecran screen time controle parental"),
    ("Famille", "com.apple.Family-Settings.extension", "famille partage familial"),
    ("Siri", "com.apple.Siri-Settings.extension", "siri assistant dictee"),
    ("Spotlight", "com.apple.Spotlight-Settings.extension", "spotlight recherche"),
    ("Date et heure", "com.apple.Date-Time-Settings.extension", "date heure fuseau horaire"),
    ("Langue et région", "com.apple.Localization-Settings.extension", "langue region format langage"),
    ("Mise à jour logicielle", "com.apple.Software-Update-Settings.extension", "mise a jour update logiciel macos"),
    ("Time Machine", "com.apple.Time-Machine-Settings.extension", "time machine sauvegarde backup"),
    ("Centre de contrôle", "com.apple.ControlCenter-Settings.extension", "centre de controle control center barre menu"),
    ("Partage", "com.apple.preferences.sharing", "partage sharing airdrop ecran fichiers"),
    ("Cartes et Apple Pay", "com.apple.WalletSettingsExtension", "wallet apple pay cartes paiement"),
    ("Game Center", "com.apple.Game-Center-Settings.extension", "game center jeux"),
]


def discover_settings():
    """Panneaux de réglages exposés en extension (fiables, propres à cette version)."""
    import glob, plistlib
    out = {}
    for appex in glob.glob("/System/Library/ExtensionKit/Extensions/*.appex"):
        try:
            with open(os.path.join(appex, "Contents", "Info.plist"), "rb") as f:
                pl = plistlib.load(f)
        except Exception:
            continue
        if pl.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.Settings.extension.ui":
            continue
        bid = pl.get("CFBundleIdentifier")
        if not bid:
            continue
        nm = pl.get("CFBundleName") or os.path.basename(appex)[:-6]
        out["x-apple.systempreferences:" + bid] = nm
    return out


def settings_blocs():
    """Fusionne panneaux auto-détectés + liste FR curée. Curé prioritaire pour le nom."""
    panes = {}
    for url, nm in discover_settings().items():
        panes[url] = (nm, nm)
    for label, bid, kw in SETTINGS_CURATED:
        url = "x-apple.systempreferences:" + bid
        panes[url] = (label, label + " " + kw)
    return [{"path": url, "name": label, "typ": "setting", "mtime": "", "part": 0, "texte": kw}
            for url, (label, kw) in panes.items()]


def walk_docs():
    for root in DOC_ROOTS:
        for r, d, ns in os.walk(root):
            d[:] = [x for x in d if not x.startswith(".") and not EXCL.search(r + "/" + x + "/")]
            d[:] = [x for x in d if not x.lower().endswith(".app")]   # ne pas descendre dans les apps
            for x in d:                                   # les dossiers eux-mêmes, cherchables par nom
                yield os.path.join(r, x), "folder"
            if EXCL.search(r + "/"):
                continue
            for n in ns:
                if n.startswith("."):
                    continue
                ext = n.rsplit(".", 1)[-1].lower() if "." in n else ""
                if ext in OK_EXT:
                    yield os.path.join(r, n), ext


def main():
    os.makedirs(DIR, exist_ok=True)
    blocs = []
    seen = 0
    import itertools
    sources = walk_docs()
    if INDEX_APPS:
        sources = itertools.chain(sources, walk_apps())
    for path, ext in sources:
        seen += 1
        if seen % 500 == 0:
            print("  scannes %d, blocs %d" % (seen, len(blocs)))
        name = os.path.basename(path)
        if ext == "app":
            txt = app_label(path)          # 'Preview Aperçu', 'Calculator Calculatrice'…
        elif ext == "folder":
            txt = name                     # dossier cherchable par son nom
        else:
            txt = NL.sub("\n\n", WS.sub(" ", extract(path, ext) or "")).strip()[:FILECAP]
            if len(txt) < 20:
                txt = name  # au moins cherchable par nom
        base = (name + "\n" + txt).strip()
        parts = [base] if len(base) <= MAXI else [
            name + "\n" + base[j:j + MAXI] for j in range(0, len(base), MAXI - 200)]
        mt = ""
        try:
            import datetime
            mt = datetime.date.fromtimestamp(os.path.getmtime(path)).isoformat()
        except Exception:
            pass
        for k, mo in enumerate(parts):
            blocs.append({"path": path, "name": name, "typ": typ_of(ext),
                          "mtime": mt, "part": k, "texte": mo})
    if INDEX_APPS:                                    # panneaux de Réglages système
        sb = settings_blocs()
        blocs.extend(sb)
        print("  + %d panneaux de réglages" % len(sb))
    print("%d fichiers -> %d blocs" % (seen, len(blocs)))

    if os.path.exists(DB):
        os.remove(DB)
    c = sqlite3.connect(DB)
    c.execute("""CREATE TABLE bloc(id INTEGER PRIMARY KEY, path TEXT, name TEXT, typ TEXT,
                 mtime TEXT, part INT, texte TEXT)""")
    c.execute("""CREATE VIRTUAL TABLE fts USING fts5(texte, name,
                 content='bloc', content_rowid='id', tokenize="unicode61 remove_diacritics 2")""")
    c.execute("""CREATE VIRTUAL TABLE tri USING fts5(texte, name,
                 content='bloc', content_rowid='id', tokenize="trigram")""")
    c.executemany("INSERT INTO bloc(id,path,name,typ,mtime,part,texte) VALUES (?,?,?,?,?,?,?)",
                  [(i + 1, b["path"], b["name"], b["typ"], b["mtime"], b["part"], b["texte"])
                   for i, b in enumerate(blocs)])
    for t in ("fts", "tri"):
        c.execute("INSERT INTO %s(rowid,texte,name) SELECT id,texte,name FROM bloc" % t)
    c.commit()
    print("FTS5 construits.")

    from fastembed import TextEmbedding
    emb = TextEmbedding(model_name=MODEL)
    vecs = np.zeros((len(blocs), 384), dtype="float32")
    lot, n = [], 0
    for i, b in enumerate(blocs):
        lot.append(b["name"] + "\n" + b["texte"])
        if len(lot) == 256 or i == len(blocs) - 1:
            for v in emb.embed(lot):
                v = np.asarray(v, dtype="float32")
                vecs[n] = v / (np.linalg.norm(v) + 1e-9)
                n += 1
            lot = []
            if n % 5120 == 0 or n == len(blocs):
                print("  vecteurs %d/%d" % (n, len(blocs)))
    np.save(NPY, vecs)
    print("FINI : %d vecteurs -> %s" % (n, NPY))


if __name__ == "__main__":
    main()
