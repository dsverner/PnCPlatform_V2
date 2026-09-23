# Bringing a relay model into the platform

The steps that took the SEL-221F from a legacy model code to a working device template (decisions #153–#219, 2026-09-13
to 2026-09-21), written so the next model follows them without the back-and-forth. Owner, 2026-09-21: *"Be sure that we are
taking notes of all of these steps so that we can repeat them again for other relays without this back and forth."*

**The rule** (CLAUDE.md): an increment that adds a step, a tool or a ruling to this process adds it here in the same commit.

Standing rulings the whole process rests on (memory files, one line each):
- *Device templates first* — the daily-value work is device templates; the SEL-221F all the way through, then models in
  count order. Under ~100 settings the manual suffices; modern devices also need the client's standard settings files.
- *Native settings round trip* — settings are edited IN the platform and written out as the manufacturer's native file at
  implementation with no retyping; a reader and a writer per format, proven byte-identical; a format that cannot be
  written excludes the vendor from procurement.
- *References are the floor* — the legacy program and Dev_Final are the low bar; a screen that does less is not done.
- *Raise domain gaps* — where the model is thinner than the plant, say so with a recommendation; later phases are
  additions, never redesigns.

## The steps, in order

Each step: what is produced, the tool and command, where it registers, the decision row, the ruling it rests on.

| # | Step | Artefact | Tool / command | Registers in | Decision |
|---|---|---|---|---|---|
| 0 | The model row and an "as found" template exist from migration | `Seed_config_SettingsTemplates_SEL.sql` — spelled as the vendor software spells them | generated 2026-09-13 from `docs/schema/migration/profile_set1.py` | `PostDeploy.sql` | #153, #61; #166: a text file whose model has no template is kept as filed, `ParseStatus = NoTemplate`, never refused |
| 1 | Get the manual; decide the model is next | the PDF on Z: (`Z:\Archive-WorkingData-Cloud\Work\DATA\Manuals\<vendor>\…`) | by hand | — | #168; ruling: every template row cites its manual page; what the manual does not settle is asked, never assumed |
| 2 | The settings template (settings by function) from the manual | `Seed_config_SettingsTemplate_<MODEL>.sql` + `docs/design/examples/templates/<model>.template.md` (one source, two outputs) | `python tools/template_sel221f.py` — copy it for the next model | `PostDeploy.sql` after `Seed_ref_AnsiFunction_Core.sql`; binds per model code through `ref.FirmwareVersion.ParseTransformDefinitionEntityId` | #168, #183. Per row: unit, base, range, closed list, ANSI, aliases, `Format`, `DisplayOrder` = the SET order = the writer's order; the manual's self-contradictions recorded in the description |
| 3 | Give the ANSI codes the template cites their C37.2 names | `Seed_ref_AnsiFunction_Core.sql` | by hand (SQL) | `PostDeploy.sql` before the template | #168, #182: `Seed_ref_AnsiFunction_Core` wins over a capability seed on the name |
| 4 | Reader and writer, and the round trip | `process.ParseSettingsText` (reader), `process.RenderSettingsText` (writer), `SetParsedSetting`, `CopyRevisionAsDraft`, `IssueRenderedSettings`, `RefileRevision` | a new vendor format = new parser/render rules in those procedures + the smoke's round trip | — | #168. One format exists today: the SEL `name=value` list in SET order with `LOGIC SETTINGS:`. Ruling: every template increment includes the writer and its round-trip test. #230: the writer runs after every edit of an outstanding record, so a model whose file the template does not fully read (ParseStatus Partial) cannot be edited in the platform until the template reads every setting in the file |
| 5 | The migration text must be whole before the round trip means anything | `legacy_import.py`; `RECONCILIATION-<date>.md` | `python docs/schema/migration/roundtrip_settings.py --database PnCPlatform_V2_DEV --model "<code>" --report …`; after a parser change `python docs/schema/migration/reparse_settings.py --database … --model …` | — | #168 (51 of 53 221F texts were truncated at 255 characters; found by looking) |
| 6 | The device sheet (settings by function) in the browser | `src/PnC.Web/src/screens/DeviceSettings.tsx` in `RecordScreen.tsx` | nothing per model: a template for another relay draws the same way | — | #168, #167 (a one-off screen is plain React) |
| 7 | Editing in the platform; the M as a copy of the A | the procedures of step 4; the edit cell on the sheet | — | — | #168 increment 2; proof `evidence/W8-fourstep-221f-*.jpg` |
| 8 | Compliance — nothing per model | `tools/compliance_rules.py` → `Seed_config_Formulas_PRC023.sql`, `Seed_config_ObligationRules.sql` | `python tools/compliance_rules.py` (needs dotnet; compiles through `tools/FormulaCompile`) | `PostDeploy.sql` | #171, #173, #184, #185, #214. Rules scope over facts, not models; a new model only needs the settings its formulas read to be in its template (221F: Z3%, R1, X1, MTA, 50H) |
| 9 | What the relay can do: the capability list from the manual | `Seed_scheme_FunctionCapability_<MODEL>.sql` + `docs/design/examples/templates/<model>.capabilities.md` | `python tools/capability_sel221f.py` — copy it | `PostDeploy.sql` before `Seed_scheme_RepointCommissionedFunctions.sql` | #181, #182: the manual's own Functional Specifications headings, each row citing heading and page |
| 10 | The bundle: the device template definition | `Seed_config_AssetTemplate_<MODEL>.sql` — `CharacteristicSchema.AssetTemplate` key `<MODEL>_Template`, bound to the model codes by `config.DefinitionAppliesTo` (Model); seeds its enumerations; groups Identity / Inputs / Bundle / Hardware | `python tools/template_bundle_sel221f.py` — copy it | `PostDeploy.sql` | #184, #216. Idempotent: a version is added only when no Effective version carries the change note |
| 11 | The screens and the nav | `docs/design/examples/screens/device-template.screen.json`, `device-templates.screen.json`; `DeviceTemplateScreen.tsx` | `python tools/seed_screens.py` → `Seed_config_Screens.sql`; commit both | `PostDeploy.sql`; the nav's group order is `PAGES` in `AppLayout.tsx` | #185 (`menu: null` is not done), #186 (working content top, documentation below, closed) |
| 12 | Placing a relay of the model; its first settings from the template | `LocationScreen.tsx` (New relay), `lib/actions.ts` `raiseAndAdvance`, `CopyRevisionAsDraft` (the empty first draft) | write order `asset.Asset_Add` → `device.Device_Add` → `asset.AlternateKey_Add` (SerialNumber) → `asset.PlaceAsset` | — | #187 |
| 13 | Analog inputs: the ratio settings say how many CT/VT inputs the relay has | `Seed_scheme_AnalogInputs.sql`, `Seed_asset_InstrumentWindings.sql`; `isRatio` in the web | one ratio setting per analog input in the settings template (221F: CTR, PTR, SPTR) | `PostDeploy.sql` | #200 → #205 → #211; #212, #213 |
| 14 | The Relay Word and the mask editor (relays with logic masks) | `Seed_config_RelayWord_<MODEL>.sql` + `docs/design/examples/templates/<model>.relay-word.md` — `Program.RelayWord` naming the settings template | `python tools/relay_word_sel221f.py` — copy it | `PostDeploy.sql` after the settings template | #215. Save writes the filed shape (`F0 A4 00`) through `SetParsedSetting`; another relay with masks is another definition, no new code |
| 15 | Hardware configuration (jumpers, ports) as a template group; the manual in the page | the bundle's `Hardware` group (step 10); `asset.SetAssetCharacteristic`; the manual document (class `InstructionManual`) linked About the template | `python tools/load_manual.py --server … --database PnCPlatform_V2_DEV --template <MODEL>_Template --file "Z:\…pdf" --title "…"` per environment — `docs/runbook/LOAD-MANUALS.md` | — | #216. A reference document (linked About a Definition) is readable at any scope |
| 15b | The manual guide: the manual's own words on how each setting is set — the Settings tab's floatover, with a link that opens the manual at the page | `Seed_config_ManualGuide_<MODEL>.sql` + `docs/design/examples/templates/<model>.manual-guide.md` — `Program.ManualGuide` naming the settings template; `docs/design/examples/templates/<model>.manual-pages.json` (printed label → PDF page) | `python tools/manual_pages.py <pdf> <json>` (the page map; unlabelled pages are settled by eye); `python tools/manual_guide_sel221f.py` — copy it. Pages are viewed with PyMuPDF (`pip install --user pymupdf`; the manual's page images are JBIG2, which pypdf cannot decode) | `PostDeploy.sql` after the Relay Word | #235. **Every quote verbatim from the page IMAGE** — the PDF's text layer is an OCR with errors ("SlNP" for S1NP), a draft only; each quote carries the printed page and the PDF page, both read off the image; an equation keeps its own line; "…" marks an elision; a setting the manual does not address gets no entry, never a summary. Done a section at a time: the SEL-221F's Close Supervision settings first |
| 16 | Rationale: the legacy documents by rule; the ELEMENT MAP on the Relay Word (each element's capability, outputs, owned settings, supervision from the manual's logic equations — the sheet's sub-groups); the RATIONALE TEMPLATE (`Program.Rationale`: inputs, sections per element, formulas, statements; defaults labelled by source); the line's impedance on the line (`LINE_Template`) | legacy: `legacy_import.py rationale_stage` (`--docs`); generated: `Seed_config_Rationale_<MODEL>_<FUNCTION>.sql` + `docs/design/examples/templates/<model>.rationale.md` (`CharacteristicSchema.RationaleDevice`) | `python tools/rationale_sel221f.py` — copy it; the line's impedances on the line asset (`LINE_Template`, `tools/template_line.py`) | `PostDeploy.sql` | #217 (by number AND station; a number is reused after retirement), #218 (opens in Word through a signed link), #219 |
| 16b | The words on every screen the model touches | — | `python tools/check_wording.py` (zero before the commit) | — | #221: the wording rule, `docs/design/UI-WORDING.md` — no decision number, owner quote, view or permission name on a screen; the manual's own words stay |
| 17 | Publish, seed, re-parse, verify | — | `python docs/schema/ddl/tools/generate.py` → `deploy.py --database PnCPlatform_V2_DEV` → `reparse_settings.py` → `roundtrip_settings.py` → `docs/schema/ddl/tools/smoke.py` (~30 min) → `src/PnC.Api.Smoke` → Chrome on DEV, screen by screen → DECISION-LOG row → this runbook | — | every increment |

## Settled — do not ask again

| Question | Answer | Where |
|---|---|---|
| How are settings grouped on the sheet? | By the manual's few Specifications headings (the 221F: twelve). Its Section-5 headings gave 22 tabs — too many | #168; memory *device templates first* |
| Should any setting be hidden? | No. *"all settings will be grouped … but none will be hidden....for now"* | #183 |
| Is there a standard-settings file for this relay? | For the 221F no — deferred; `SEL221F_StandardProt` dropped. When one comes it is `config.StandardSettingEntry` under a `CharacteristicSchema.StandardSettings` definition bound to protection application × model, not a flag on the setting | #168, #183, #184 |
| Do functions without an ANSI number get left out? | No. The manufacturer's own abbreviation, `IsDeviceNumber = 0`; *"wording will have to suffice"* | #182 |
| Where does the capability list come from? | The manual's own Functional Specifications headings, each row citing heading and page; nothing inferred | #181 |
| What does a newly placed relay start with? | *"none ticked but when a standard template is used then it should follow the template"* | #181 |
| Does compliance belong in the template? | No. *"compliance is really a function of it's own, outside of the template … PRC-023 will be compulsory, no matter what physical device"* | #185 |
| Can an admin switch compliance on per device? | No — *"not something that an admin can turn on or off"*; calculated from the primary elements' study values | #184 |
| Does a screen need a menu entry? | Always. Everything reachable from the left navigation; a new area of function gets its own group | #185; memory *reachable from the nav* |
| Where do facts and working content sit? | Working content at the top; documentation in a closed section below | #186; memory *working content first* |
| Do the ratio settings live on the Analog inputs tab? | No — they are settings. The Analog inputs tab is "feeding this protection": the scheme's CT/VT sources | #200 then #205 |
| How many CT/PT inputs does the relay have — ask? | Never. One ratio setting per analog input in the template. No template → no known capability, invent nothing | #211 |
| Are the port settings in the template? | Only if the manual has them as settings. The 221F's baud is a jumper (JMP105); hardware is a `Hardware` group on the template, recorded per relay, never written to the settings file | #216 |
| Where does the manual live? | On Z:, never in git; loaded per environment by `tools/load_manual.py`; a Manual tab on the record and the template screen | #216, LOAD-MANUALS.md |
| Are the platform's settings just a reading of the vendor file? | No. Reader and writer per format, proven byte-identical | memory *native settings round trip* |
| Which model next? | Models in count order after the 221F | memory *device templates first* |
| What if the manual contradicts itself? | Take the SET-list limit and say so in the row's description | #168 |
| What if a model code carries other relays' texts? | A finding, not a merge (the SEL-221S codes were not bound: their texts carry 67ND) | #168 |
| A settings editor for logic masks? | Yes, from the relay's Relay Word, opened by the row's arrow; no manual recommendations, no tick line; the last column is "Comments" (each mask's purpose) | #215 |
| Where does the rationale's line impedance live? | On the line asset (`LINE_Template`), never only in the relay's settings | #219 |
| Is the legacy Word rationale ever updated? | No — frozen at its revision; from the next change the platform generates the rationale | #217 |

## Traps recorded

- A generated `_Upsert` procedure does not take a new column's parameter until the publish **after** the one that adds the
  column; set such a flag by a plain `UPDATE` in the seed (#182, `ref.AnsiFunction.IsDeviceNumber`).
- A capability seed must name an ANSI code only when the catalogue does not already hold it, or it overwrites the C37.2
  names (#182).
- The template screen must read `config.vAssetTemplate` (Effective only), never walk `vDefinitionAppliesTo` and take the
  first binding — it took the retired v1 once (#185).
- `PostDeploy.sql` order is load-bearing: `Seed_config_SettingsTemplates_SEL` and `Seed_ref_AnsiFunction_Core` before the
  model's settings template; the relay word after it; the capability seed before the repoint; the bundle after both.
- A screen document seeded with `menu: null` is invisible (#185); a group missing from `PAGES` in `AppLayout.tsx` lands
  after Administration.
- The migration text may be truncated (SET1 + SETTINGS2 split at 255 characters, #168): run the round trip before trusting
  a model's texts.
- The generator (`tools/generate.py`) owns every `v<Table>`; a hand-written view must not be named that way (#213).
- A legacy record number is reused after retirement: match legacy things by number AND station, never number alone (#217).

## The checklist for the next model

Copy into the model's plan and tick off:

1. The manual on Z: (path), the model codes in `ref.Model` (from migration), the count of records (why it is next).
2. `tools/template_<model>.py` from `template_sel221f.py`: every setting from the SET list in its order, page-cited; groups
   = the manual's Specifications headings; ANSI codes; aliases from the legacy texts; `Format`; the ratio settings.
3. `Seed_ref_AnsiFunction_Core.sql`: any C37.2 name the template cites and the catalogue lacks.
4. The reader/writer: does the vendor's file format parse and render byte-identical? If a new format: parser rules,
   writer rules, the smoke's round trip. If it cannot be written: a finding for procurement, not a template.
5. `roundtrip_settings.py --model` on DEV: identical / values-equal / mismatch; `reparse_settings.py` after any rule change.
6. `tools/capability_<model>.py`: the manual's functional headings, page-cited; no-ANSI functions by the manufacturer's word.
7. `tools/template_bundle_<model>.py`: `<MODEL>_Template` — Identity, Inputs, Bundle, Hardware (jumpers, ports), the
   enumerations; bound to every model code.
8. If the relay has logic masks: `tools/relay_word_<model>.py`.
9. `tools/load_manual.py` on each environment; the LOAD-MANUALS table.
10. Screens: nothing per model unless a new kind of thing appears; if a screen is added, `seed_screens.py`, a `menu`, `PAGES`.
    A screen with tabs also declares them in `tools/view_items.py` (#226), so a person can turn off the ones they do not
    use; a tab left undeclared is simply always shown.
11. Element map: `elements` and `groups` in `tools/relay_word_<model>.py` — every setting in exactly one owner; supervision from the manual's logic equations, quoted with the page. Rationale: `tools/rationale_<model>_<function>.py` — the sections, inputs, formulas and statements from the model's
    legacy rationale documents (Files and records of its records) and the manual; the plant facts it reads must exist on
    the assets (line impedance, ratios).
12. Register every seed in `PostDeploy.sql` in the order above; `generate.py`; deploy; the two smokes; Chrome on DEV.
13. DECISION-LOG row; this runbook (a new step, ruling or trap); commit with the standard trailers.

## Still by hand (no tool yet)

- Reading the manual into rows (page cites, ranges, lists, aliases) — a person transcribes; no extraction tool.
- The four generators are copy-and-edit per model (`template_`, `capability_`, `template_bundle_`, `relay_word_`); no
  shared scaffold or `--model` parameter yet.
- `Seed_ref_AnsiFunction_Core.sql`, `PostDeploy.sql` registration, the screen JSON's `menu` and the `PAGES` order.
- A second vendor format's parser and writer (only the SEL name=value form exists).
- Model variants (-2/-3/-4) are not on the model row; breaker failure is recorded against both codes (#215/#216).
- The manual's page cites are printed labels; the viewer takes physical pages (a page map per manual would let a cite open
  its page, #216).
- Verification's last mile is a person in Chrome; the API smoke covers the data, not the layout.
