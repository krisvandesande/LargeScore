#!/usr/bin/env python3
"""Converts PDFs with Audiveris under different settings and counts, for each result,
the bars whose notes don't add up to the time signature (the bars the Converter tints).

    python3 scripts/omr-compare.py <pdf folder> <out folder> [font ...]

Fonts are Audiveris's music font families (Leland, Bravura, FinaleJazz, JazzPerc).
Results go to <out>/<font>/; a table is printed and saved as <out>/results.tsv.
Run it on music kept outside the repository: the repo is public.
"""
import concurrent.futures, csv, os, subprocess, sys, tempfile, zipfile
import xml.etree.ElementTree as ET
from fractions import Fraction

AUDIVERIS = os.environ.get("AUDIVERIS", "vendor/audiveris/Audiveris.app/Contents/MacOS/Audiveris")


def musicxml(path):
    if path.endswith(".mxl"):
        with zipfile.ZipFile(path) as z:
            name = next(n for n in z.namelist() if n.endswith(".xml") and not n.startswith("META"))
            return z.read(name)
    return open(path, "rb").read()


def wrong_bars(xml):
    """(bars that don't add up, all bars), first part only; pickup and last bar excused."""
    root = ET.fromstring(xml)
    part = root.find("part")
    if part is None:
        return 0, 0
    divisions, beats, beat_type = 1, 4, 4
    measures = part.findall("measure")
    wrong = 0
    for i, m in enumerate(measures):
        attr = m.find("attributes")
        if attr is not None:
            if attr.findtext("divisions"):
                divisions = int(attr.findtext("divisions"))
            t = attr.find("time")
            if t is not None and t.findtext("beats") and t.findtext("beat-type"):
                try:
                    beats, beat_type = int(t.findtext("beats").split("+")[0]), int(t.findtext("beat-type"))
                except ValueError:
                    pass
        pos = longest = Fraction(0)
        rest_bars = False
        for el in m:
            if el.tag == "note":
                if el.find("chord") is not None or el.find("grace") is not None:
                    continue
                if el.find("rest") is not None and el.find("rest").get("measure") == "yes":
                    rest_bars = True
                pos += int(el.findtext("duration") or 0)
            elif el.tag == "backup":
                pos -= int(el.findtext("duration") or 0)
            elif el.tag == "forward":
                pos += int(el.findtext("duration") or 0)
            longest = max(longest, pos)
        expected = Fraction(divisions * 4 * beats, beat_type)
        if rest_bars:
            continue
        if longest != expected and not (i == 0 and longest < expected) and i != len(measures) - 1:
            wrong += 1
    return wrong, len(measures)


def convert(pdf, out, font):
    os.makedirs(out, exist_ok=True)
    base = os.path.splitext(os.path.basename(pdf))[0]
    done = [f for f in os.listdir(out) if f.startswith(base) and f.endswith(".mxl")] if os.path.isdir(out) else []
    if not done:
        with tempfile.TemporaryDirectory() as work:
            env = dict(os.environ, JAVA_TOOL_OPTIONS="-Djava.awt.headless=true -Dapple.awt.UIElement=true")
            subprocess.run([AUDIVERIS, "-batch", "-export",
                            "-option", f"org.audiveris.omr.ui.symbol.MusicFont.defaultMusicFamily={font}",
                            "-option", "org.audiveris.omr.Main.sheetStepTimeOut=1200",
                            "-output", work, "--", pdf], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for dirpath, _, files in os.walk(work):
                for f in files:
                    if f.endswith(".mxl"):
                        os.replace(os.path.join(dirpath, f), os.path.join(out, base + ".mxl"))
                        break
    path = os.path.join(out, base + ".mxl")
    if not os.path.exists(path):
        return None
    try:
        return wrong_bars(musicxml(path))
    except Exception:
        return None


def main():
    pdfs_dir, out = sys.argv[1], sys.argv[2]
    fonts = sys.argv[3:] or ["Leland", "Bravura"]
    pdfs = sorted(os.path.join(pdfs_dir, f) for f in os.listdir(pdfs_dir) if f.lower().endswith(".pdf"))
    if os.environ.get("LIMIT"):
        pdfs = pdfs[: int(os.environ["LIMIT"])]
    jobs = [(p, f) for p in pdfs for f in fonts]
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=int(os.environ.get("PARALLEL", "3"))) as pool:
        futures = {pool.submit(convert, p, os.path.join(out, f), f): (p, f) for p, f in jobs}
        for fut in concurrent.futures.as_completed(futures):
            results[futures[fut]] = fut.result()
    rows = []
    for p in pdfs:
        name = os.path.splitext(os.path.basename(p))[0]
        cells = []
        for f in fonts:
            r = results.get((p, f))
            cells.append("failed" if r is None else f"{r[0]}/{r[1]}")
        rows.append([name] + cells)
    with open(os.path.join(out, "results.tsv"), "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["piece"] + fonts)
        w.writerows(rows)
    for row in rows:
        print("\t".join(row))
    for i, f in enumerate(fonts):
        vals = [results.get((p, f)) for p in pdfs]
        ok = [v for v in vals if v]
        wrong = sum(v[0] for v in ok); total = sum(v[1] for v in ok)
        print(f"{f}: {len(ok)}/{len(pdfs)} converted, {wrong} of {total} bars don't add up ({100 * wrong / max(total, 1):.1f}%)")


if __name__ == "__main__":
    main()
