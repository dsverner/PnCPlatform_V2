# How the application talks

Owner, 2026-09-22: *"the text wording in much of this document seem very convoluted and complex, I would like your
wording to be more in line with what a protection and control human would understand and write. This goes for the
wording in the entire application."*

Every word a user reads is written as a P&C engineer would say it to a technician standing beside them. Short
sentences. The trade's own words. Nothing about how the platform is built.

## Write like this

- **Say what the person sees or does.** "Pick the date the settings were verified in the field." Not "the
  return-to-service step is Ready".
- **Use the trade's words**: relay, scheme, station, panel, position, in service, outstanding, issued, change request,
  setting, pickup, zone, mask, CT, PT, winding, tap, ratio, test, verified.
- **One idea per sentence**, under about 20 words. Two short sentences beat one with dashes and brackets.
- **An empty state says what is missing and what to do next.** "No CT is recorded for this scheme. Add one from the
  Analog inputs tab."
- **A refusal says what the person cannot do here**, in plain words: "You may not change settings on this record."
  Never the permission code.
- **A number a person needs is a number**; a number the platform needs stays out of sight.

## Never on screen

| Not this | Because |
|---|---|
| `#144`, `(#217)`, "W8 round-2" | decision numbers are ours, not the user's — keep them in a code comment on the line |
| "the owner, 2026-09-17", any date as a reason | how a thing was decided is not what a user needs |
| `vSettingsRecord`, `SetParsedSetting`, `Asset.Modify`, `Definition.Read`, `CharacteristicSchema.…` | database, procedure and permission names |
| `tools/load_manual.py`, any script path | the user does not run our tools |
| "entity", "RowId", "payload", "read model", "valid time", "definition version", "soft delete" | our nouns, not theirs |
| "the platform writes / derives / evaluates …" as the subject | say what happens: "the settings file is written when the settings step commits" |
| "audited as your change", "a value saves at once, audited" | every act is audited; saying so on every field is noise |
| "in this phase", "a later phase", "not built yet" as an aside | if it matters, say what the person can do today |

## Always kept

- **A manual's or a standard's own words stay verbatim, with their citation.** Setting descriptions, mask purposes,
  Relay Word bit meanings, PRC-023 and NPCC clause text, the rationale template's statements: these are quotations and
  are not rewritten.
- **Reference data keeps its codes** (voltage classes, ANSI device numbers, setting codes).
- **Traceability.** A decision number that leaves a screen goes into the code comment on the same line, so the reason
  is still one grep away.

## Where design is explained

In `docs/design`, in the decision log, and in code comments. A screen may carry one plain paragraph under "About this
screen", closed by default (the 2026-09-18 rule: working content first, documentation below).

## Checking

`python tools/check_wording.py` reads the React sources and the screen definitions and lists any rendered string that
carries a decision number, an owner quote, a schema or permission name, or a tool path. It is run before a commit that
touches the interface, and it is part of bringing a model in (`docs/runbook/BRING-A-MODEL-IN.md`).
