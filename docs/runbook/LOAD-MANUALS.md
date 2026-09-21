# Loading a device model's instruction manual (#216)

A manual is kept with the model's asset template: a document of class `InstructionManual` whose revision holds the PDF
(`document.FileStore`) and links *About* the template definition (`CharacteristicSchema.AssetTemplate`). Every relay of a
model bound to that template opens it from its settings record's **Manual** tab and from the template screen. It is
readable by anyone holding `Document.Read` at any scope (`security.fHasPermission`, #216): a manual is the manufacturer's
book, not a site's record.

The PDF never enters git (CLAUDE.md: large artefacts stay on Z:). It is loaded **per environment**, after the deploy that
seeds the template, by a tool that reads the file from where it is and writes it once (a linked file with the same
SHA-256 is left alone, so the step can be repeated):

```
python tools/load_manual.py --server 10.10.70.25 --database PnCPlatform_V2_DEV --template SEL221F_Template ^
    --file "Z:\Archive-WorkingData-Cloud\Work\DATA\Manuals\SEL\221F-2-3-4_IM_19981207.pdf" ^
    --title "SEL-221F-2, -3, -4 / SEL-121F-2, -3 Instruction Manual, date code 981207"
```

The password is read as the schema tools read it (`PNC_DEV_PWD` or `dev.local`). The tool refuses any database not named
`PnCPlatform_V2_*`.

| Environment | Manual | Loaded |
|---|---|---|
| `PnCPlatform_V2_DEV` | SEL-221F IM 981207 (7 658 721 bytes) | 2026-09-21 |
| `PnCPlatform_V2_QA` | — | not yet |

The API smoke checks the served file (inline `application/pdf`, readable by the Node-scoped engineer) when a manual is
present and reports the check skipped when none is.
