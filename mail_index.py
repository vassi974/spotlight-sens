#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mail_index.py — index recherche par le sens + mot exact + fautes, sur les
mails Apple Mail (~/Library/Mail).

Meme moule que ~/Scripts/memindex : un SQLite (FTS5 mot exact + FTS5 trigram
pour les fautes) et un .npy de vecteurs fastembed (MiniLM multilingue).
Un .emlx = 1re ligne = longueur en octets, puis le message RFC822, puis un plist.

  ~/Scripts/semsearch/venv/bin/python ~/Scripts/spotlight-sens/mail_index.py
"""
import os, re, sys, html, sqlite3, hashlib, email
from email import policy
from email.utils import parsedate_to_datetime
import numpy as np

MAILROOT = os.path.expanduser("~/Library/Mail")
DIR = os.path.expanduser("~/Scripts/spotlight-sens")
DB = os.path.join(DIR, "mail.sqlite")
NPY = os.path.join(DIR, "mail_vecs.npy")
MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
MAXI = 1600
BODYCAP = 4000
TAG = re.compile(r"<[^>]+>")
WS = re.compile(r"[ \t\r\f\v]+")
NL = re.compile(r"\n{3,}")


def dec(part):
    try:
        b = part.get_payload(decode=True) or b""
    except Exception:
        return ""
    cs = part.get_content_charset() or "utf-8"
    for enc in (cs, "utf-8", "latin-1"):
        try:
            return b.decode(enc, "replace")
        except Exception:
            continue
    return ""


def strip_html(t):
    t = re.sub(r"(?is)<(script|style).*?</\1>", " ", t)
    t = TAG.sub(" ", t)
    return html.unescape(t)


def body_of(msg):
    plain, htm = [], []
    if msg.is_multipart():
        for p in msg.walk():
            ct = p.get_content_type()
            if "attachment" in str(p.get("Content-Disposition", "")):
                continue
            if ct == "text/plain":
                plain.append(dec(p))
            elif ct == "text/html":
                htm.append(dec(p))
    else:
        ct = msg.get_content_type()
        (plain if ct == "text/plain" else htm).append(dec(msg))
    txt = "\n".join(plain).strip() or strip_html("\n".join(htm))
    return NL.sub("\n\n", WS.sub(" ", txt)).strip()


def hdr(msg, name):
    v = msg.get(name, "")
    try:
        return str(email.header.make_header(email.header.decode_header(v)))
    except Exception:
        return v or ""


def dateiso(msg):
    try:
        d = parsedate_to_datetime(msg.get("Date"))
        return d.strftime("%Y-%m-%d") if d else ""
    except Exception:
        return ""


def parse_emlx(path):
    try:
        with open(path, "rb") as f:
            first = f.readline()
            n = int(first.strip() or b"0")
            raw = f.read(n) if n else f.read()
        msg = email.message_from_bytes(raw, policy=policy.compat32)
    except Exception:
        return None
    subj, frm, to = hdr(msg, "Subject"), hdr(msg, "From"), hdr(msg, "To")
    mid = (msg.get("Message-ID") or "").strip()
    body = body_of(msg)
    if not mid:
        mid = "sha:" + hashlib.sha1((subj + frm + dateiso(msg)).encode("utf-8", "replace")).hexdigest()
    return {"mid": mid, "subject": subj, "frm": frm, "to": to,
            "date": dateiso(msg), "body": body,
            "partial": path.endswith(".partial.emlx"), "path": path}


def walk_mails():
    for r, d, ns in os.walk(MAILROOT):
        for n in ns:
            if n.endswith(".emlx"):
                yield os.path.join(r, n)


def main():
    os.makedirs(DIR, exist_ok=True)
    best, seen = {}, 0
    for p in walk_mails():
        seen += 1
        if seen % 5000 == 0:
            print("  lus %d, uniques %d" % (seen, len(best)))
        rec = parse_emlx(p)
        if not rec:
            continue
        prev = best.get(rec["mid"])
        if prev is None or len(rec["body"]) > len(prev["body"]) or (prev["partial"] and not rec["partial"]):
            best[rec["mid"]] = rec
    recs = list(best.values())
    print("%d mails lus -> %d messages uniques" % (seen, len(recs)))

    blocs = []
    for rec in recs:
        base = (rec["subject"] + "\n" + rec["body"]).strip()[:BODYCAP]
        if len(base) < 8:
            base = rec["subject"] or rec["frm"]
        parts = [base] if len(base) <= MAXI else [
            rec["subject"] + "\n" + base[j:j + MAXI] for j in range(0, len(base), MAXI - 200)]
        for k, mo in enumerate(parts):
            blocs.append({**rec, "part": k, "texte": mo})
    print("%d bloc(s) a indexer" % len(blocs))

    if os.path.exists(DB):
        os.remove(DB)
    c = sqlite3.connect(DB)
    c.execute("""CREATE TABLE bloc(id INTEGER PRIMARY KEY, mid TEXT, frm TEXT, dst TEXT,
                 subject TEXT, date TEXT, part INT, partial INT, path TEXT, texte TEXT)""")
    c.execute("""CREATE VIRTUAL TABLE fts USING fts5(texte, subject, frm,
                 content='bloc', content_rowid='id',
                 tokenize="unicode61 remove_diacritics 2")""")
    c.execute("""CREATE VIRTUAL TABLE tri USING fts5(texte, subject, frm,
                 content='bloc', content_rowid='id', tokenize="trigram")""")
    c.executemany("INSERT INTO bloc(id,mid,frm,dst,subject,date,part,partial,path,texte) "
                  "VALUES (?,?,?,?,?,?,?,?,?,?)",
                  [(i + 1, b["mid"], b["frm"], b["to"], b["subject"], b["date"],
                    b["part"], 1 if b["partial"] else 0, b["path"], b["texte"])
                   for i, b in enumerate(blocs)])
    for t in ("fts", "tri"):
        c.execute("INSERT INTO %s(rowid,texte,subject,frm) "
                  "SELECT id,texte,subject,frm FROM bloc" % t)
    c.commit()
    print("FTS5 (mot exact + trigram) construits.")

    from fastembed import TextEmbedding
    emb = TextEmbedding(model_name=MODEL)
    vecs = np.zeros((len(blocs), 384), dtype="float32")
    lot, n = [], 0
    for i, b in enumerate(blocs):
        lot.append(b["subject"] + "\n" + b["texte"])
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
