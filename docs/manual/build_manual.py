"""Arma docs/manual/manual.html desde manual.src.html.

La tabla de controles de Ajuste se copia de lib/balancin_v2/widgets/tuning_sheet.dart
(los mismos textos del botón «?») y los valores de fábrica de core/params.dart, así
el manual no se desfasa de la app. Uso (desde la raíz del repo):

    python docs/manual/build_manual.py

Luego se imprime a PDF con Edge o Chrome sin interfaz (ver el final de este archivo).
"""

import html
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs/manual/manual.src.html"
OUT = ROOT / "docs/manual/manual.html"


def dart_strings(text):
    """Une los literales 'a' 'b' adyacentes de Dart."""
    return "".join(re.findall(r"'((?:[^'\\]|\\.)*)'", text))


def factory_defaults():
    src = (ROOT / "lib/balancin_v2/core/params.dart").read_text(encoding="utf-8")
    body = src.split("factory SyncParams.blind()")[1]
    return {k: float(v) for k, v in re.findall(r"^\s+double (\w+) = ([\d.]+);", body, re.M)}


def controls():
    src = (ROOT / "lib/balancin_v2/widgets/tuning_sheet.dart").read_text(encoding="utf-8")
    src = src.split("const List<TuneSection> tuneSections = [")[1].split("\n];")[0]
    sections = []
    for sec in re.split(r"\n  TuneSection\(", src)[1:]:
        title = re.match(r"'([^']*)'", sec).group(1)
        specs = []
        for block in re.split(r"\n    TuneSpec\(", sec)[1:]:
            key, label = re.match(r"'(\w+)', '([^']*)'", block).groups()

            def field(name):
                m = re.search(name + r":\s*((?:'(?:[^'\\]|\\.)*'\s*)+)", block)
                return dart_strings(m.group(1)) if m else ""

            def num(name, default):
                m = re.search(name + r":\s*([\d.]+)", block)
                return float(m.group(1)) if m else default

            kind = "toggle" if "TuneKind.toggle" in block else "choice" if "TuneKind.choice" in block else "slider"
            choices = re.findall(r"'([^']*)'", re.search(r"choices: \[([^\]]*)\]", block).group(1)) if kind == "choice" else []
            m = re.search(r"unit: '([^']*)'", block)
            specs.append(dict(key=key, label=label, kind=kind, choices=choices, unit=m.group(1) if m else "",
                              dec=int(num("dec", 0)), what=field("what"), why=field("why"), how=field("how")))
        sections.append((title, specs))
    return sections


def fmt(spec, v):
    if spec["kind"] == "toggle":
        return "Sí" if v > 0 else "No"
    if spec["kind"] == "choice":
        return spec["choices"][round(v)]
    return f"{v:.{spec['dec']}f}".replace(".", ",") + spec["unit"]


def main():
    version = re.search(r"^version: ([^+\s]+)", (ROOT / "pubspec.yaml").read_text(encoding="utf-8"), re.M).group(1)
    defaults = factory_defaults()
    rows = []
    for title, specs in controls():
        rows.append(f'<tr class="sec"><td colspan="4">{html.escape(title)}</td></tr>')
        for s in specs:
            if s["key"] not in defaults:
                sys.exit(f"sin valor de fábrica: {s['key']}")
            rows.append(
                "<tr>"
                f"<td>{html.escape(s['label'])}</td>"
                f"<td>{html.escape(s['what'])} <i>{html.escape(s['why'])}</i></td>"
                f"<td>{html.escape(s['how'])}</td>"
                f'<td class="def">{html.escape(fmt(s, defaults[s["key"]]))}</td>'
                "</tr>"
            )
    out = (SRC.read_text(encoding="utf-8")
           .replace("{{CONTROLS}}", "\n    ".join(rows))
           .replace("{{VERSION}}", version)
           .replace("{{DATE}}", date.today().strftime("%d-%m-%Y")))
    OUT.write_text(out, encoding="utf-8")
    print(f"{OUT} · versión {version} · {sum(len(s) for _, s in controls())} controles")


if __name__ == "__main__":
    main()

# PDF (Windows):
#   "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --headless --disable-gpu
#     --no-pdf-header-footer --print-to-pdf="entregable\Balancin_Manual_de_usuario.pdf" docs\manual\manual.html
