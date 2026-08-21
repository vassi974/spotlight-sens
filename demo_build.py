#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""demo_build.py — fabrique une FAUSSE base de démo (mails + documents fictifs)
pour filmer une démo publique de « Spotlight par le sens » SANS exposer de
données personnelles.

Produit, à côté des vrais index :
  demo_mail.sqlite / demo_mail_vecs.npy
  demo_docs.sqlite / demo_docs_vecs.npy

Mêmes schémas et même modèle de vecteurs que les vrais indexeurs, pour que la
recherche par le sens fonctionne pareil. Rien de tout ceci n'est réel.

  ~/Scripts/semsearch/venv/bin/python demo_build.py
"""
import os, sqlite3
import numpy as np
from fastembed import TextEmbedding

DIR = os.path.expanduser("~/Scripts/spotlight-sens")
MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
EMB = TextEmbedding(model_name=MODEL)


def vecs_for(textes):
    out = np.zeros((len(textes), 384), dtype="float32")
    n = 0
    for v in EMB.embed(textes):
        v = np.asarray(v, dtype="float32")
        out[n] = v / (np.linalg.norm(v) + 1e-9)
        n += 1
    return out


# ------------------------------------------------------------------ FAUX MAILS
# (subject, frm, dst, date, texte)  -- tout est fictif
MAILS = [
    ("Votre échéancier d'énergie est disponible", "EDF Client <client@edf.fr>", "moi@exemple.fr", "2024-03-12",
     "Bonjour, votre relevé de consommation d'énergie du mois de mars est disponible. Consommation 412 kWh, puissance souscrite 9 kVA, montant prélevé 89,40 €. Cordialement, votre service client."),
    ("Votre facture d'abonnement de janvier", "Orange <facture@orange.fr>", "moi@exemple.fr", "2024-01-08",
     "Votre facture d'abonnement fibre et mobile est disponible. Montant : 39,99 €. Prélèvement le 15 du mois."),
    ("Relevé de compte disponible", "Ma Banque <no-reply@mabanque.fr>", "moi@exemple.fr", "2024-04-02",
     "Votre relevé de compte du mois d'avril est consultable dans votre espace en ligne."),
    ("Avis d'échéance — assurance habitation", "AssurTop <contact@assurtop.fr>", "moi@exemple.fr", "2024-02-20",
     "Votre cotisation annuelle d'assurance multirisque habitation arrive à échéance. Montant 214 €."),
    ("Quittance de loyer — avril", "Gérance Lopez <gerance@exemple.fr>", "moi@exemple.fr", "2024-04-03",
     "Veuillez trouver votre quittance de loyer d'avril : loyer 750 € et charges 90 €."),
    ("Votre avis d'imposition", "impots.gouv <ne-pas-repondre@dgfip.fr>", "moi@exemple.fr", "2023-09-05",
     "Votre avis d'imposition sur le revenu est disponible dans votre espace particulier."),
    ("Votre commande a été expédiée", "Boutique Outillage <exp@shop-exemple.fr>", "moi@exemple.fr", "2024-03-28",
     "Votre commande n°12345 (perceuse-visseuse sans fil) a été expédiée. Livraison prévue sous 3 jours."),
    ("Rappel : rendez-vous garage lundi", "Garage du Centre <contact@garage-exemple.fr>", "moi@exemple.fr", "2024-03-18",
     "Rappel de votre rendez-vous pour la révision de votre véhicule lundi à 9h. Pensez au carnet d'entretien."),
]

# ------------------------------------------------------------------ FAUX DOCS
# (name, typ, mtime, texte)
DOCS = [
    ("EDF - relevé de consommation.pdf", "pdf", "2024-03-12",
     "Relevé de consommation d'énergie électrique. 412 kWh sur le mois. Puissance souscrite 9 kVA. Montant 89,40 euros. Prochaine relève estimée dans 60 jours."),
    ("Facture Orange fibre.pdf", "pdf", "2024-01-08",
     "Facture d'abonnement fibre et forfait mobile. Total 39,99 euros TTC."),
    ("Bail commercial - local Saint-Denis.pdf", "pdf", "2023-11-04",
     "Contrat de bail commercial portant sur le local situé à Saint-Denis, durée 9 ans, loyer trimestriel."),
    ("Devis rénovation toiture.pdf", "pdf", "2024-02-15",
     "Devis pour la réfection complète de la toiture : dépose, fourniture et pose de tuiles, zinguerie. Total 12 400 euros."),
    ("Quittance de loyer - avril.pdf", "pdf", "2024-04-03",
     "Quittance de loyer du mois d'avril. Loyer 750 euros, charges 90 euros, total réglé 840 euros."),
    ("Attestation assurance habitation.pdf", "pdf", "2024-02-20",
     "Attestation d'assurance multirisque habitation valable pour l'année en cours."),
    ("Bulletin de salaire - mars.pdf", "pdf", "2024-03-31",
     "Bulletin de paie du mois de mars. Salaire brut 3120 euros, net à payer 2450 euros."),
    ("Devis panneaux solaires.pdf", "pdf", "2024-03-05",
     "Devis installation photovoltaïque : 8 panneaux, onduleur, pose comprise. Production estimée 3200 kWh par an."),
    ("CV - Alex Martin.pdf", "pdf", "2024-01-22",
     "Curriculum vitae. Expériences professionnelles, formation, compétences et langues."),
    ("Plan cuisine.jpg", "image", "2024-02-11", "Plan cuisine"),
    ("support-lampe.stl", "3d", "2024-03-01", "support lampe"),
    ("Factures 2024", "folder", "2024-04-01", "Factures 2024"),
    ("Maison & travaux", "folder", "2024-03-20", "Maison travaux"),
]


def build_mail():
    db = os.path.join(DIR, "demo_mail.sqlite")
    if os.path.exists(db):
        os.remove(db)
    c = sqlite3.connect(db)
    c.execute("""CREATE TABLE bloc(id INTEGER PRIMARY KEY, mid TEXT, frm TEXT, dst TEXT,
                 subject TEXT, date TEXT, part INT, partial INT, path TEXT, texte TEXT)""")
    c.execute("""CREATE VIRTUAL TABLE fts USING fts5(texte, subject, frm,
                 content='bloc', content_rowid='id', tokenize="unicode61 remove_diacritics 2")""")
    c.execute("""CREATE VIRTUAL TABLE tri USING fts5(texte, subject, frm,
                 content='bloc', content_rowid='id', tokenize="trigram")""")
    rows = []
    for i, (subj, frm, dst, date, texte) in enumerate(MAILS, 1):
        mid = "<demo-%d@spotlight.local>" % i
        rows.append((i, mid, frm, dst, subj, date, 0, 0, "", texte))
    c.executemany("INSERT INTO bloc(id,mid,frm,dst,subject,date,part,partial,path,texte) "
                  "VALUES (?,?,?,?,?,?,?,?,?,?)", rows)
    for t in ("fts", "tri"):
        c.execute("INSERT INTO %s(rowid,texte,subject,frm) SELECT id,texte,subject,frm FROM bloc" % t)
    c.commit(); c.close()
    np.save(os.path.join(DIR, "demo_mail_vecs.npy"),
            vecs_for([m[0] + "\n" + m[4] for m in MAILS]))
    print("demo_mail : %d mails" % len(MAILS))


def build_docs():
    db = os.path.join(DIR, "demo_docs.sqlite")
    if os.path.exists(db):
        os.remove(db)
    c = sqlite3.connect(db)
    c.execute("""CREATE TABLE bloc(id INTEGER PRIMARY KEY, path TEXT, name TEXT, typ TEXT,
                 mtime TEXT, part INT, texte TEXT)""")
    c.execute("""CREATE VIRTUAL TABLE fts USING fts5(texte, name,
                 content='bloc', content_rowid='id', tokenize="unicode61 remove_diacritics 2")""")
    c.execute("""CREATE VIRTUAL TABLE tri USING fts5(texte, name,
                 content='bloc', content_rowid='id', tokenize="trigram")""")
    rows = []
    for i, (name, typ, mtime, texte) in enumerate(DOCS, 1):
        path = os.path.expanduser("~/Documents/Démo/%s" % name)
        rows.append((i, path, name, typ, mtime, 0, name + "\n" + texte))
    c.executemany("INSERT INTO bloc(id,path,name,typ,mtime,part,texte) VALUES (?,?,?,?,?,?,?)", rows)
    for t in ("fts", "tri"):
        c.execute("INSERT INTO %s(rowid,texte,name) SELECT id,texte,name FROM bloc" % t)
    c.commit(); c.close()
    np.save(os.path.join(DIR, "demo_docs_vecs.npy"),
            vecs_for([d[0] + "\n" + d[3] for d in DOCS]))
    print("demo_docs : %d documents" % len(DOCS))


if __name__ == "__main__":
    build_mail()
    build_docs()
    print("Fausse base de démo prête.")
