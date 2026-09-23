# Manual guide — the manual's own words on how each setting is set (#235)

The Settings tab shows, for each setting, an ⓘ that opens a floatover with **what the instruction manual says on how that setting is
set**, in the manual's own words, each quote with its page and a link that opens the manual at that page. This runbook is how a
model gets its guide. It was written doing the SEL-221F (all 46 settings, 151 quotes, 2026-09-23); the owner asked for "good notes
so that you can do the same for other templates". Step 15b of `BRING-A-MODEL-IN.md` points here.

## Why the rules are strict

These are protection settings. A floatover is read by an engineer deciding a value, so it must be the manufacturer's text and
nothing else — the platform's rule that compliance and settings are never from memory (#198, #221). A summary, a paraphrase, a
"corrected" figure or a word guessed from a blurred scan is a fabricated finding, however well meant.

## The steps

| # | Step | How | Notes |
|---|---|---|---|
| 1 | The manual is loaded against the model's asset template | `tools/load_manual.py` (`LOAD-MANUALS.md`) | The floatover's link opens this PDF; without it the page is shown as text, no link |
| 2 | The page map | `python tools/manual_pages.py <manual.pdf> docs/design/examples/templates/<model>.manual-pages.json` | Reads each page's printed label ("5-11") from its first/last lines. OCR misses labels on some pages (SEL-221F: 97 of 260) and doubles a few — use it to find pages, never trust it for a quote's PDF page |
| 3 | Find where each setting is discussed | The template's own cites (the `Description` of each row, e.g. "(3-24; 5-13/5-14)") and the manual's settings/applications section (SEL: Section 5 "Applications", one heading per setting with guidance, a worked example in a boxed summary, and "- Setting Limit Check") | SEL-221F: printed 5-n = PDF page 124+n; the breaker-failure settings are in Section 2 (2-51 = PDF 71) |
| 4 | Render the pages as images | PyMuPDF: `python -c "import pymupdf; d=pymupdf.open(r'<pdf>'); d[N-1].get_pixmap(dpi=110).save(r'<scratch>\p<N>.png')"` (dpi 160 for small print), then view each PNG | Install once: `pip install --user pymupdf`. pypdf cannot decode these pages (JBIG2 images, "jbig2dec binary is not available"); the Read tool cannot render PDFs on PC02 (no poppler) |
| 5 | Transcribe, verbatim, from the IMAGE | Per setting, 1–4 contiguous passages, each from one page: what it is, what to consider, the rule or formula, the worked example value, the limit check | **Never from the PDF's text layer** — it is OCR with errors ("SlNP" for S1NP on the SEL-221F). The text layer is only for finding pages |
| 6 | Put it in the model's data file | `docs/design/examples/templates/<model>.manual-guide.json` — `{key, name, model, settingsTemplate, source, sourceFile, pageOffsets, settings: {CODE: [{page, pdfPage, quote, checked}]}}` | `key` MANUAL_GUIDE_<MODEL>; `settingsTemplate` = the settings template's key (SETTINGS_TEXT_…); keep the template's setting order |
| 7 | Check a sample against the images | A second reader (the session, when agents transcribed) re-reads a sample of pages against the quotes; the owner spot-checks the first section | SEL-221F: 5-9…5-12 read and transcribed by the session; 5-3…5-8, 5-13…5-31 and 2-51 by four agents working from the images, and pages 5-17, 5-19 and 2-51 re-read against their quotes by the session — all matched |
| 8 | Generate | `python tools/manual_guide.py docs/design/examples/templates/<model>.manual-guide.json` → `docs/schema/ddl/PostDeploy/Seed_config_ManualGuide_<MODEL>.sql` + `<model>.manual-guide.md` | The generator refuses a quote without its printed page, PDF page or check note, and any quote holding `[?]` |
| 9 | Register the seed once | `:r .\Seed_config_ManualGuide_<MODEL>.sql` in `PostDeploy.sql`, after the Relay Word | The `Program.ManualGuide` kind is already seeded (`Seed_ref_DefinitionKind.sql`) |
| 10 | Deploy, smoke, look | `deploy.py --database PnCPlatform_V2_DEV --no-smoke --no-record`; the API smoke's #235 check (extend it with a quote of the new model); the Settings tab in the browser | A setting the guide covers loses its generic comment; the Comments column goes from any grid where nothing is left in it; a mask keeps its Relay Word purpose (#215) |

## Transcription conventions (settled on the SEL-221F — do not re-ask)

- **Verbatim**: the manual's words, capitals, punctuation, symbols (°, ∅, Ω, Δ, ½, ∠), units as printed ("kv" where it prints kv),
  its typos and inconsistencies (SEL-221F 2-51 prints "AITP and A1TD"; 5-15 prints "81.6 Ω" beside "81.16 Ω" elsewhere) — copied, not
  corrected. A known contradiction the platform had to settle is recorded in the template row's description (#168), not in a quote.
- **Layout, not words**: a line the manual sets on its own (an equation, a boxed setting "CTR = 200.00") keeps its own line (`\n`);
  a subscript is written inline ("V l-n", "V l-l"); a stacked fraction is written inline with "/" ("250 A primary / 200") — the "/"
  stands for the fraction bar; a word hyphenated across a line break is joined ("require-/ment" → "requirement"); a table cell's
  wrapped text is joined. A table whose columns carry meaning (the LOPE choices) keeps its columns with spaces — the floatover shows
  such a quote in a fixed-width font.
- **Elision**: whole sentences may be left out inside a passage, marked "…"; words are never changed.
- **One page per quote**: a sentence running over a page break is left out rather than stitched.
- **Nothing invented**: a setting the manual does not address gets no quote (the generator drops an empty list and the setting keeps
  its template comment). A dropped word is marked `[?]` and settled on the page before generating.
- **The same passage may serve several settings** (e.g. one paragraph on R1, X1, R0 and X0; the TIME1/TIME2 paragraph) — repeat it
  under each code.

## Using agents for the transcription

The SEL-221F's Section 5 was split by page range over four agents, each told: render the pages with PyMuPDF, view the images, copy
verbatim, never the text layer, never paraphrase, mark an unreadable word `[?]`, return JSON `{CODE: [{page, pdfPage, quote}]}` and a
list of anything uncertain. Their JSON was saved to the session's scratchpad and merged; the report of each listed its layout choices
(fractions, joined hyphens) — read those lists, they are where a transcription can drift. An agent that HTML-escapes "<" (as
`&lt;`) must have it restored before merging.

## Where things are

- Tools: `tools/manual_pages.py`, `tools/manual_guide.py`.
- Data: `docs/design/examples/templates/<model>.manual-guide.json` (+ generated `.md` for review), `<model>.manual-pages.json`.
- Seed: `docs/schema/ddl/PostDeploy/Seed_config_ManualGuide_<MODEL>.sql`.
- Screen: `src/PnC.Web/src/lib/manualGuide.ts` (load + context), `src/PnC.Web/src/components/ui/popover.tsx` (the floatover),
  `DeviceSettings.tsx` (`ManualQuotes`, the Setting column's ⓘ, the Comments column's rule), `lib/files.ts` (`openFileInTab(file, page)`).
- Decision log: #235 (first section), #236 (the SEL-221F complete; the generic generator and this runbook).
