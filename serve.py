#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""serve.py — moteur RESIDENT unifié (mails + documents) pour la barre.

Charge une fois le modèle + les deux index (mail, docs), puis répond à
  GET /search?q=...&k=12  ->  JSON [{title,sub,symbol,open,isFile}]
Fusionne les deux corpus par RRF. Réponses en quelques millisecondes.

  ~/Scripts/semsearch/venv/bin/python ~/Scripts/spotlight-sens/serve.py
"""
import os, re, json, sqlite3, unicodedata, time, threading, urllib.request
from urllib.parse import urlparse, parse_qs, unquote_plus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import numpy as np
import importlib.util

_spec = importlib.util.spec_from_file_location(
    "cherche", os.path.expanduser("~/Scripts/spotlight-sens/cherche.py"))
ch = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(ch)

PORT = 8799
DIR = os.path.expanduser("~/Scripts/spotlight-sens")
MODEL = ch.MODEL
SYM = {"mail": "envelope.fill", "pdf": "pdf-badge", "word": "doc.text",
       "note": "note.text", "text": "doc.plaintext", "web": "safari",
       "3d": "cube", "cad": "ruler", "image": "photo", "design": "paintbrush",
       "archive": "archivebox", "media": "play.rectangle", "sheet": "tablecells",
       "slides": "rectangle.on.rectangle", "setting": "gearshape"}
CAT = {"pdf": "Documents", "word": "Documents", "note": "Documents", "text": "Documents",
       "web": "Documents", "sheet": "Documents", "slides": "Documents",
       "image": "Images", "media": "Médias", "3d": "3D", "cad": "3D",
       "archive": "Archives", "design": "Design", "app": "Applications",
       "folder": "Dossiers", "setting": "Réglages"}

def fr(iso):
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", iso or "")
    return "%s/%s/%s" % (m.group(3), m.group(2), m.group(1)) if m else (iso or "")

print("Chargement modèle + index…", flush=True)
from fastembed import TextEmbedding
EMB = TextEmbedding(model_name=MODEL); list(EMB.embed(["warmup"]))


class Corpus:
    def __init__(self, kind, db, npy):
        self.kind = kind
        self.conn = sqlite3.connect(db, check_same_thread=False)
        self.mat = np.load(npy)
        self._voc = None
        # vocabulaire flou propre à ce corpus
        self.conn.execute("CREATE VIRTUAL TABLE IF NOT EXISTS vfts USING fts5vocab('fts','row')")
        self.buckets = {}
        for (t,) in self.conn.execute("SELECT term FROM vfts"):
            if len(t) >= 4 and t.isalpha():
                self.buckets.setdefault(t[:2], []).append(t)

    def flou(self, q):
        import difflib
        out = set()
        for w in ch.mots(q):
            w = w.lower()
            if len(w) < 4:
                out.add(w); continue
            out.update(difflib.get_close_matches(w, self.buckets.get(w[:2], []), n=4, cutoff=0.72) or [w])
        return list(out)

    def rank(self, q, qvec):
        listes = [ch.bm25(self.conn, ch.mots(q)), ch.bm25(self.conn, self.flou(q))]
        s = self.mat @ qvec
        ordre = np.argsort(-s)[:ch.PROFOND]
        listes.append([int(i) + 1 for i in ordre if s[i] >= ch.SEUIL])
        pts = {}
        for l in listes:
            for rang, rid in enumerate(l):
                pts[rid] = pts.get(rid, 0.0) + 1.0 / (60 + rang + 1)
        return [rid for rid, _ in sorted(pts.items(), key=lambda x: -x[1])][:ch.PROFOND]

    def fetch(self, rid):
        if self.kind == "mail":
            r = self.conn.execute("SELECT mid,frm,subject,date,texte FROM bloc WHERE id=?", (rid,)).fetchone()
            if not r: return None
            mid, frm, subj, dat, txt = r
            who = re.sub(r'".*?"|<.*?>', "", frm).strip() or frm
            sub = who + ("  ·  " + fr(dat) if dat else "") + "   —   " + re.sub(r"\s+", " ", txt)[:140]
            return {"key": mid, "mid": mid, "title": subj or "(sans objet)", "sub": sub, "symbol": SYM["mail"],
                    "open": "message://%3c" + mid.strip("<>") + "%3e", "isFile": False, "cat": "Mail", "date": dat or ""}
        else:
            r = self.conn.execute("SELECT path,name,typ,mtime,texte FROM bloc WHERE id=?", (rid,)).fetchone()
            if not r: return None
            path, name, typ, mt, txt = r
            if typ == "setting":
                return {"key": path, "title": name, "sub": "Réglage système",
                        "symbol": "gearshape", "open": path, "isFile": False,
                        "cat": "Réglages", "date": ""}
            folder = os.path.basename(os.path.dirname(path))
            sub = folder + ("  ·  " + fr(mt) if mt else "") + "   —   " + re.sub(r"\s+", " ", txt)[:140]
            return {"key": path, "title": name, "sub": sub, "symbol": SYM.get(typ, "doc"),
                    "open": path, "isFile": True, "cat": CAT.get(typ, "Documents"), "date": mt or ""}


MAIL = Corpus("mail", os.path.join(DIR, "mail.sqlite"), os.path.join(DIR, "mail_vecs.npy"))
DOCS = Corpus("docs", os.path.join(DIR, "docs.sqlite"), os.path.join(DIR, "docs_vecs.npy"))
CORPORA = [MAIL, DOCS]
print("Prêt sur http://127.0.0.1:%d/search  (mails + documents)" % PORT, flush=True)


def _noacc(s):
    return "".join(c for c in unicodedata.normalize("NFD", s or "")
                   if unicodedata.category(c) != "Mn")


def app_boost(q):
    """Coup de pouce 'lanceur' : les applications dont le nom colle à la
    requête (préfixe du nom, ou d'un de ses mots) remontent tout en haut.
    Ex. 'pag' -> Pages en n°1 dans 'Tout'."""
    ql = _noacc(q.lower().strip())
    if len(ql) < 3:
        return []
    hits = []
    for rid, name, texte in DOCS.conn.execute("SELECT id,name,texte FROM bloc WHERE typ IN ('app','setting')"):
        base = _noacc(re.sub(r"\.app$", "", name or "", flags=re.I).lower())
        # mots cherchables : nom de fichier + nom affiché FR (Aperçu, Calculatrice…), sans accents
        mots = set(_noacc(w) for w in re.split(r"[\s\-_./]+", (base + " " + (texte or "")).lower()) if w)
        best = 0.0
        if base.startswith(ql):                       # préfixe du nom complet : fort
            best = 2.0 + len(ql) / max(1, len(base))
        for w in mots:                                # ou préfixe d'un mot (nom fichier ou FR)
            if w.startswith(ql):
                best = max(best, 1.0 + len(ql) / max(1, len(w)))
        if best > 0:
            hits.append((rid, base == ql or ql in mots, best))
    # meilleur d'abord : match exact, puis nom qui colle le mieux
    hits.sort(key=lambda x: (-int(x[1]), -x[2]))
    return hits[:6]


def mailbody(mid):
    """Reconstitue un mail (en-tête + corps) pour l'aperçu latéral."""
    rows = MAIL.conn.execute(
        "SELECT frm,dst,subject,date,texte FROM bloc WHERE mid=? ORDER BY part", (mid,)).fetchall()
    if not rows:
        return None
    frm, dst, subj, dat = rows[0][0] or "", rows[0][1] or "", rows[0][2] or "", rows[0][3] or ""
    body = "\n".join((r[4] or "") for r in rows)
    return {"from": frm, "to": dst, "subject": subj or "(sans objet)",
            "date": fr(dat), "body": body[:12000]}


def recherche(q, k=12):
    q = (q or "").strip()
    if len(q) < 2:
        return []
    v = np.asarray(next(EMB.embed([q])), dtype="float32")
    v /= (np.linalg.norm(v) + 1e-9)
    pts = {}
    for cp in CORPORA:
        for rang, rid in enumerate(cp.rank(q, v)):
            pts[(cp, rid)] = 1.0 / (60 + rang + 1)
    # lanceur : les apps qui collent au nom passent devant tout le reste
    for i, (rid, _exact, sc) in enumerate(app_boost(q)):
        key = (DOCS, rid)
        pts[key] = pts.get(key, 0.0) + (100.0 if i == 0 else 50.0) - i * 0.5 + sc
    out, vus = [], set()
    for (cp, rid), _ in sorted(pts.items(), key=lambda x: -x[1]):
        rec = cp.fetch(rid)
        if not rec or rec["key"] in vus:
            continue
        vus.add(rec["key"]); rec.pop("key")
        out.append(rec)
        if len(out) >= k:
            break
    return out


BATT = os.path.expanduser("~/Scripts/poste-controle-battements.json")


def _battre(service):
    """Battement de cœur pour le poste de contrôle (écriture atomique)."""
    try:
        d = {}
        if os.path.exists(BATT):
            with open(BATT, encoding="utf-8") as f:
                d = json.load(f)
        d[service] = time.time()
        tmp = BATT + ".daemontmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(d, f)
        os.replace(tmp, BATT)
    except Exception:
        pass


def _heartbeat_loop():
    """Toutes les 60 s : se teste soi-même sur /ping. Ne bat le cœur QUE si le
    port répond vraiment — un process vivant mais dont le serveur HTTP est mort
    ne battra pas, et le poste de contrôle le verra."""
    while True:
        try:
            with urllib.request.urlopen("http://127.0.0.1:%d/ping" % PORT, timeout=5) as r:
                if r.status == 200:
                    _battre("com.vassili.spotlight-sens-daemon")
        except Exception:
            pass
        time.sleep(60)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        u = urlparse(self.path)
        qs = parse_qs(u.query)
        if u.path == "/ping":
            self.send_response(200)
            self.send_header("Content-Length", "2"); self.end_headers()
            self.wfile.write(b"ok"); return
        if u.path == "/mailbody":
            mid = unquote_plus((qs.get("mid") or [""])[0])
            try:
                body = json.dumps(mailbody(mid) or {}, ensure_ascii=False).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers(); self.wfile.write(body)
            except Exception as e:
                self.send_response(500); self.end_headers(); self.wfile.write(str(e).encode("utf-8"))
            return
        if u.path != "/search":
            self.send_response(404); self.end_headers(); return
        q = unquote_plus((qs.get("q") or [""])[0])
        k = int((qs.get("k") or ["12"])[0])
        try:
            body = json.dumps(recherche(q, k), ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers(); self.wfile.write(body)
        except Exception as e:
            self.send_response(500); self.end_headers(); self.wfile.write(str(e).encode("utf-8"))


if __name__ == "__main__":
    threading.Thread(target=_heartbeat_loop, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
