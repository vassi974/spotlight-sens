#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rate_update.py — recupere le taux USD/EUR une fois par jour et l'ecrit dans
rate.json. La barre (Hammerspoon) lit ce fichier en local -> aucune latence.

Lance par le LaunchAgent com.vassili.spotlight-sens-rate (heure fixe + RunAtLoad).
Si la recuperation echoue, on garde l'ancien fichier.
"""
import json, os, sys, ssl, urllib.request, datetime
try:
    import certifi
    _CTX = ssl.create_default_context(cafile=certifi.where())
except Exception:
    _CTX = ssl.create_default_context()

OUT = os.path.expanduser("~/Scripts/spotlight-sens/rate.json")
SOURCES = [
    "https://api.frankfurter.app/latest?from=USD&to=EUR",   # rates.EUR (BCE, sans cle)
    "https://api.frankfurter.dev/v1/latest?base=USD&symbols=EUR",
    "https://open.er-api.com/v6/latest/USD",
]


def fetch():
    for url in SOURCES:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "spotlight-sens/1.0"})
            with urllib.request.urlopen(req, timeout=12, context=_CTX) as r:
                d = json.load(r)
            eur = (d.get("rates") or {}).get("EUR")
            if eur and eur > 0:
                return float(eur), url
        except Exception:
            continue
    return None, None


def main():
    usd_eur, src = fetch()
    if not usd_eur:
        print("echec recuperation taux ; ancien fichier conserve", file=sys.stderr)
        return 1
    data = {
        "usd_eur": round(usd_eur, 6),          # 1 USD = x EUR
        "eur_usd": round(1.0 / usd_eur, 6),    # 1 EUR = x USD
        "date": datetime.date.today().isoformat(),
        "source": src,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    print("taux ecrit : 1 USD = %.4f EUR (%s)" % (usd_eur, data["date"]))
    _battre("com.vassili.spotlight-sens-rate")
    return 0


def _battre(service):
    """Battement de cœur pour le poste de contrôle."""
    import time
    p = os.path.expanduser("~/Scripts/poste-controle-battements.json")
    try:
        d = {}
        if os.path.exists(p):
            with open(p, encoding="utf-8") as f:
                d = json.load(f)
        d[service] = time.time()
        tmp = p + ".ratetmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(d, f)
        os.replace(tmp, p)
    except Exception:
        pass


if __name__ == "__main__":
    sys.exit(main())
