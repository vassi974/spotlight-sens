#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""import_theme.py — convertit un thème externe en thème maison (.json) pour la
barre « Spotlight par le sens ». Formats détectés automatiquement :
  - base16 / base24  (.yaml/.yml)   : base00..base0F
  - KDE Plasma       (.colors)      : sections [Colors:*]
  - terminal Xresources (.Xresources/.xres/.txt) : *background, *color0..15
  - iTerm            (.itermcolors) : plist

Écrit ~/Scripts/spotlight-sens/themes/<slug>.json

  ~/Scripts/semsearch/venv/bin/python import_theme.py <fichier> [nom]
"""
import os, re, sys, json, plistlib, configparser

THEMES = os.path.expanduser("~/Scripts/spotlight-sens/themes")


def norm(h):
    h = h.strip().lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return "#" + h.lower()[:6]


def rgb(r, g, b):
    return "#%02x%02x%02x" % (int(r), int(g), int(b))


def lum(hexc):
    h = hexc.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "theme"


def write(theme):
    os.makedirs(THEMES, exist_ok=True)
    theme["dark"] = lum(theme["bg"]) < 0.5
    theme.setdefault("opacity", 0.5)
    theme.setdefault("corner", 18)
    p = os.path.join(THEMES, slug(theme["name"]) + ".json")
    json.dump(theme, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("écrit : %s  (%s)" % (p, "sombre" if theme["dark"] else "clair"))
    return p


def from_base16(path, name):
    d = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\s*([A-Za-z0-9_]+)\s*:\s*[\"']?#?([0-9A-Fa-f]{6}|[^\"'\n]+)", line)
        if m:
            d[m.group(1).lower()] = m.group(2).strip()
    def c(k):
        v = d.get(k, "")
        return norm(v) if re.fullmatch(r"#?[0-9A-Fa-f]{3,6}", v or "") else None
    nm = name or d.get("scheme") or d.get("name") or os.path.basename(path)
    return {"name": nm, "bg": c("base00") or "#1e1e1e", "text": c("base05") or "#e0e0e0",
            "subtext": c("base04") or c("base03") or "#9aa0a6", "accent": c("base0d") or "#5b9bd5",
            "result": c("base0a") or "#e0c060", "border": c("base02") or "#333333"}


def from_kde(path, name):
    cp = configparser.ConfigParser(strict=False)
    cp.read(path, encoding="utf-8")
    def col(sec, key, default):
        try:
            r, g, b = (cp.get(sec, key).split(",") + ["0", "0", "0"])[:3]
            return rgb(r, g, b)
        except Exception:
            return default
    nm = name or (cp.get("General", "Name", fallback=None) if cp.has_section("General") else None) or os.path.basename(path)
    return {"name": nm,
            "bg": col("Colors:View", "BackgroundNormal", col("Colors:Window", "BackgroundNormal", "#2e3440")),
            "text": col("Colors:View", "ForegroundNormal", "#e0e0e0"),
            "subtext": col("Colors:View", "ForegroundInactive", "#9aa0a6"),
            "accent": col("Colors:Selection", "BackgroundNormal", "#5b9bd5"),
            "result": col("Colors:View", "ForegroundNeutral", col("Colors:Selection", "BackgroundNormal", "#e0c060")),
            "border": col("Colors:Window", "BackgroundNormal", "#333333")}


def from_xres(path, name):
    d = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.search(r"(background|foreground|color\d{1,2})\s*:\s*(#[0-9A-Fa-f]{3,6})", line, re.I)
        if m:
            d[m.group(1).lower()] = norm(m.group(2))
    nm = name or os.path.basename(path)
    return {"name": nm, "bg": d.get("background", "#1e1e1e"), "text": d.get("foreground", "#e0e0e0"),
            "subtext": d.get("color8", "#9aa0a6"), "accent": d.get("color4", "#5b9bd5"),
            "result": d.get("color3", "#e0c060"), "border": d.get("color0", "#333333")}


def from_iterm(path, name):
    d = plistlib.load(open(path, "rb"))
    def col(key, default):
        c = d.get(key)
        if not c:
            return default
        return rgb(c.get("Red Component", 0) * 255, c.get("Green Component", 0) * 255, c.get("Blue Component", 0) * 255)
    nm = name or os.path.splitext(os.path.basename(path))[0]
    return {"name": nm, "bg": col("Background Color", "#1e1e1e"), "text": col("Foreground Color", "#e0e0e0"),
            "subtext": col("Ansi 8 Color", "#9aa0a6"), "accent": col("Ansi 4 Color", "#5b9bd5"),
            "result": col("Ansi 3 Color", "#e0c060"), "border": col("Ansi 0 Color", "#333333")}


def main():
    if len(sys.argv) < 2:
        print(__doc__); return 1
    path = os.path.expanduser(sys.argv[1])
    name = sys.argv[2] if len(sys.argv) > 2 else None
    ext = path.rsplit(".", 1)[-1].lower()
    if ext in ("yaml", "yml"):
        t = from_base16(path, name)
    elif ext == "colors":
        t = from_kde(path, name)
    elif ext == "itermcolors":
        t = from_iterm(path, name)
    else:
        t = from_xres(path, name)
    write(t)
    return 0


if __name__ == "__main__":
    sys.exit(main())
