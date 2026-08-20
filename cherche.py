#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cherche.py — recherche 3 couches dans l'index mails (spotlight-sens).

  exact    : FTS5 BM25 (mot/sigle/numero exact)
  flou     : difflib elargit chaque mot aux voisins du vocabulaire reel
             (brincks -> brinks, cotran -> cotrans), puis BM25 dessus
  sens     : vecteurs fastembed (paraphrase, meme modele que la memoire)
Fusion RRF (k=60). Corpus a preciser par CORPUS=mail (defaut).

  ~/Scripts/semsearch/venv/bin/python ~/Scripts/spotlight-sens/cherche.py "ma question"
  K=8  MODE=exact|flou|sens|hybride(defaut)  SEUIL=0.30  FORMAT=texte|raycast
"""
import os, re, sys, sqlite3, difflib
import numpy as np

DIR = os.path.expanduser("~/Scripts/spotlight-sens")
CORPUS = os.environ.get("CORPUS", "mail")
DB = os.path.join(DIR, "%s.sqlite" % CORPUS)
NPY = os.path.join(DIR, "%s_vecs.npy" % CORPUS)
MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
K = int(os.environ.get("K", "8"))
MODE = os.environ.get("MODE", "hybride")
SEUIL = float(os.environ.get("SEUIL", "0.30"))
FORMAT = os.environ.get("FORMAT", "texte")
PROFOND = 250
_voc = None


def mots(q):
    return [m for m in re.findall(r"\w+", q, re.UNICODE) if len(m) > 2]


def bm25(c, termes):
    if not termes:
        return []
    req = " OR ".join('"%s"' % m for m in termes)
    try:
        r = c.execute("SELECT rowid FROM fts WHERE fts MATCH ? "
                      "ORDER BY bm25(fts, 1.0, 2.0, 1.0) LIMIT ?", (req, PROFOND)).fetchall()
    except sqlite3.OperationalError:
        return []
    return [x[0] for x in r]


def vocabulaire(c):
    global _voc
    if _voc is not None:
        return _voc
    c.execute("CREATE VIRTUAL TABLE IF NOT EXISTS vfts USING fts5vocab('fts','row')")
    buckets = {}
    for (t,) in c.execute("SELECT term FROM vfts"):
        if len(t) >= 4 and t.isalpha():
            buckets.setdefault(t[:2], []).append(t)
    _voc = buckets
    return buckets


def flou_termes(c, q):
    buckets = vocabulaire(c)
    out = set()
    for w in mots(q):
        w = w.lower()
        if len(w) < 4:
            out.add(w)
            continue
        cands = buckets.get(w[:2], [])
        proches = difflib.get_close_matches(w, cands, n=4, cutoff=0.72)
        out.update(proches or [w])
    return list(out)


def vec(q):
    from fastembed import TextEmbedding
    mat = np.load(NPY, mmap_mode="r")
    emb = TextEmbedding(model_name=MODEL)
    v = np.asarray(next(emb.embed([q])), dtype="float32")
    v /= (np.linalg.norm(v) + 1e-9)
    s = np.asarray(mat @ v)
    ordre = np.argsort(-s)[:PROFOND]
    return [int(i) + 1 for i in ordre if s[i] >= SEUIL]


def main():
    q = " ".join(sys.argv[1:]).strip()
    if not q:
        print(__doc__)
        return 1
    if not os.path.exists(DB):
        print("Index absent : %s (lance l'indexeur d'abord)" % DB)
        return 1
    c = sqlite3.connect(DB)
    listes = []
    if MODE in ("exact", "hybride"):
        listes.append(bm25(c, mots(q)))
    if MODE in ("flou", "hybride"):
        listes.append(bm25(c, flou_termes(c, q)))
    if MODE in ("sens", "hybride"):
        listes.append(vec(q))

    pts = {}
    for l in listes:
        for rang, rid in enumerate(l):
            pts[rid] = pts.get(rid, 0.0) + 1.0 / (60 + rang + 1)

    sortie, vus = [], set()
    for rid, p in sorted(pts.items(), key=lambda x: -x[1]):
        r = c.execute("SELECT mid,frm,subject,date,texte,partial FROM bloc WHERE id=?", (rid,)).fetchone()
        if not r:
            continue
        if r[0] in vus:
            continue
        vus.add(r[0])
        sortie.append(r)
        if len(sortie) >= K:
            break

    if FORMAT == "raycast":
        for mid, frm, subj, dat, txt, part in sortie:
            url = "message://%3c" + mid.strip("<>") + "%3e"
            print("%s\t%s — %s\t%s" % (url, (subj or "(sans objet)")[:80], (frm or "")[:40], dat or ""))
        return 0

    print("« %s »  —  %s, %d resultat(s)\n" % (q, MODE, len(sortie)))
    for mid, frm, subj, dat, txt, part in sortie:
        corps = re.sub(r"\s+", " ", txt)[:200]
        flag = " [aperçu]" if part else ""
        print("%-12s %s%s" % (dat or "", (frm or "")[:46], flag))
        print("   %s" % (subj or "(sans objet)")[:96])
        print("   %s…" % corps)
        print("   → message://%3c" + mid.strip("<>") + "%3e\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
