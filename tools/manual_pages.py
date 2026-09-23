"""The page map of a relay manual: its printed page labels ("3-24", "5-11") against the PDF's physical pages (#235).

The manual's own cites are printed labels; a browser opens a PDF at a physical page (#page=N). Each page of an SEL manual
carries its label in its first or last lines of text (the PDF's OCR layer), so the map is read from the PDF itself and every
page that shows no label is listed for a person to settle. Nothing is guessed: a page without a readable label is left out.

    python tools/manual_pages.py <manual.pdf> <out.json>

Output: {"source": <file name>, "pages": <physical page count>, "labels": {"3-24": 100, ...}, "unlabelled": [1, 2, ...],
"duplicates": {"5-9": [133, 135]}} — physical pages are 1-based, as #page=N takes them.
"""
import json
import re
import sys
from pathlib import Path

from pypdf import PdfReader

LABEL = re.compile(r"^(?:.*\s)?((?:[1-9]|1[0-2]|[A-H])-\d{1,3})$")   # "5-11", "A-3"; the label stands alone at a line end


def label_of(text: str) -> str | None:
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    for ln in lines[:2] + lines[-3:]:
        m = LABEL.match(ln)
        if m:
            return m.group(1)
    return None


def main(pdf: str, out: str) -> None:
    reader = PdfReader(pdf)
    labels: dict[str, list[int]] = {}
    unlabelled = []
    for i, page in enumerate(reader.pages, start=1):
        lab = label_of(page.extract_text() or "")
        if lab is None:
            unlabelled.append(i)
        else:
            labels.setdefault(lab, []).append(i)
    result = {
        "source": Path(pdf).name,
        "pages": len(reader.pages),
        "labels": {k: v[0] for k, v in labels.items()},
        "unlabelled": unlabelled,
        "duplicates": {k: v for k, v in labels.items() if len(v) > 1},
    }
    Path(out).write_text(json.dumps(result, indent=1), encoding="utf-8")
    print(f"{len(result['labels'])} labels over {result['pages']} pages; {len(unlabelled)} unlabelled; {len(result['duplicates'])} duplicated")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
