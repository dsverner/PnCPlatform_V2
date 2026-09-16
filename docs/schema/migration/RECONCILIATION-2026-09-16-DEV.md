# Reconciliation — dbRelay (the legacy copy) → PnCPlatform_V2_DEV — 2026-09-16 (fresh reload for #168)

Run `4BAEC9B4-837A-4068-940C-062DD6D58E71` · 572,331 procedure calls · 7,304 s (first pass) · second pass 0 rows written in 154 s ·
`REHEARSAL-2026-09-16-DEV.md`. The database was dropped and re-created (`deploy.py --fresh`) because #168 adds columns
(`config.SettingDefinition` DisplayOrder/Aliases/Format, `document.ParsedSetting` RawValue) and changes what the migration files
(SET1 + SETTINGS2 as one settings text). Order as `project-deploy-smoke-environment` records it: deploy --fresh → API smoke
(218 passed, 0 failed, 1 skipped on the empty database) → `run_rehearsal.py` → `verify_chains.py` → the sweep → `--close` →
`reparse_settings.py --all` → `roundtrip_settings.py`.

## What the reload changed against 2026-09-15

| Item | 2026-09-15 (resumed load) | 2026-09-16 (fresh) | Why |
|---|---:|---:|---|
| Settings text filed per A/M/P row | `SET1` only (255 characters) | `SET1` + `, ` + `SETTINGS2` — 1,855 texts gained their tail | #168: the legacy split one list at 255 characters; the logic masks sat in SETTINGS2 |
| `verify_chains.py` text check | 9,699 equal / 1,855 differ (SET1 hash) | **11,554 equal / 0 differ** | the check now hashes the importer's rule (SET1 + SETTINGS2) |
| Requests closed by the closing pass | 11,574 (105 M rows closed wrongly, #164) | **11,469** — M-row landings stay open | `close_landed` skips `Landing:M%` |
| Request workflows | 11,580 Closed / 272 In progress / 5 Cancelled | 11,470 Closed / 372 In progress / 1 Cancelled | the 105 M rows reopened by the reload; the four-step proof runs of 09-15 are gone |
| Settings records | 5,540 Active / 5,684 Archived / 355 Outstanding / 5 Withdrawn | 5,532 Active / 5,683 Archived / 351 Outstanding / 1 Withdrawn | the 09-15 proof runs (four-step, smoke fixtures) are gone |
| Parsed revisions (every templated model) | 221F: none; others as-found | **949 revisions, 22,991 settings matched, 3,517 names unmatched, 0 failed, 26 s** | template v3/v4 bound; `reparse_settings.py --all` |
| Sweep after the load | 531 instances, 0 changes | 526 instances, 0 changes | — |

Rows tagged with the run but lacking provenance: **3,007** (`scheme.CommissionedFunction`). Cause found: the importer wrote the
commissioned function's provenance keyed on its protection-function *node* (`entity_id=fnode`), and the rehearsal's gap check
matches the row's own EntityId. Corrected in `legacy_import.py` (the `_Add` procedure's EntityId output is the key) for the next
load; DEV keeps the 3,007 node-keyed rows (the attribution exists, under the node). The 2026-09-14 report showed 0 for the same
check — not re-examined; the 09-13 report showed the same 3,007.

## The SEL-221F texts after the reload (the #168 template)

| | Revisions | Note |
|---|---:|---|
| `SEL-221F Z1-3=.125-64 OHMS` Parsed | 143 | every name known to template v3 |
| `SEL-221F Z1-3=.125-64 OHMS` Partial | 21 | names the template does not know — listed below |
| `SEL-221F` (the code without the reach range) NotParsed | 17 | the seed could not bind the code on a fresh database: the migration creates that model row *after* PostDeploy runs. Fixed: the seed now creates the `SEL-221F` model row itself (the migration reuses a row of that code — `models_stage` looks it up by manufacturer and code); on DEV the binding was applied by the incremental deploy and the 17 re-parsed |

The unmatched names across the 221F texts (from `ParseError`, 2026-09-16, before template v4): `LOGIC SEETINGS: MTU` ×6 (a misspelt
marker glued to the first mask — the parser now reads any `LOGIC…TINGS:` as the marker), `MT0` ×4 (a zero for the letter O — alias
in template v4), `M4A` ×3 (MA4 transposed — one device, Woodstock 3464, three revisions), `AURO` ×2 (AUTO — Moncton 3724),
`TIME` ×2 and `T1`/`T2` (Keswick 2734 typed TIME1/TIME2 three ways), `0H` ×2 (a broken `50H` — Keswick 1227), `MBT` (Beechwood
4119), `676NP` (Marysville 0594), `TAP`/`T.D.` (Grand Falls 0747 — an overcurrent relay's text on a 221F row), and Memramcook
0404 revision 1 — a different relay's settings (USER LEVEL, SECURITY FEATURE, PH CT PRIMARY, CUR SHAPE …) filed on the 221F.
These are the record's own data-quality findings: each shows on the device sheet as "names the template does not know"; a
platform-written file carries the template's settings only, so a typo is dropped at re-issue unless it is an alias. The one-off
typos are not made aliases (an alias is for a systematic spelling: Z1 for Z1%, RO for R0, MT0 for MTO).

## The round trip (`ROUNDTRIP-2026-09-16-DEV-SEL221F.md`)

First run, template v3, the writer printing the masks on a second line: 181 revisions — 0 identical, 143 values-equal, 21
"mismatch", 17 unparsed. Every "mismatch" was a filed name the template does not know (above), which the writer cannot write —
re-classified as a note (`not in the template (not written)`), not a mismatch, because a mismatch means a *known* setting's value
differs. The writer now prints the masks inline after `, LOGIC SETTINGS: ` (the legacy field's own one-line form), so a text typed
in SET order with canonical spellings is byte-identical. After template v4 (alias MT0), the parser's marker tolerance, the `SEL-221F` binding, the missing-separator rule and the refined chain
rule (every 221F revision re-parsed with `reparse_settings.py --force`): **181 revisions — 0 identical, 181 values-equal, 0 mismatch,
0 unparsed**; the 53 Active the same. No legacy text is byte-identical because every one deviates from the canonical form somewhere (an
alias such as `Z1` for `Z1%`, a stray fragment, a different order); after the four-step walk the Active set reads 1 identical — the file the
platform wrote for Bathurst 0012 B-PROT revision 3. The round-trip tool was itself corrected on the way: it compared the filed text with a
re-parse of the rendered text, which read a chain the parser had kept whole (`MTO=MRI=…=00 00 00`) the same way on both sides and hid the
loss; it now compares with the stored rows.

## Findings for the owner

- Five devices sit on the model code `SEL-221F` and 57 on `SEL-221F Z1-3=.125-64 OHMS` — the same relay under two codes (a third,
  the 221S codes, is a different relay and is not bound). Two of the `SEL-221F` code's texts are other relays' settings
  (Grand Falls 0747 revision 1; Memramcook 0404 revision 1): the legacy row's model is wrong or its text was pasted from another relay.
- Several legacy texts miss a comma between two settings (`PSVC=S 27VLO=40`; `MTU=00 86 00 MRI=MPT=…`): a space, a name the template
  knows and `=` can only be a missing separator, so the parser reads it as one and notes `a separator was missing before: …` on the
  record (Bathurst 2371 and 5280 among them); a run-together the template cannot resolve stays one value, shown as the defect.
- 372 requests are In progress after the closing pass against 351 Outstanding records: the M rows whose revision never went in
  service stay open (the owner's reading of the M, #164); the difference (21) is not yet examined.
