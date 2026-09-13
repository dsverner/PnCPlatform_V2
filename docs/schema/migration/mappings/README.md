# Mapping tables the loaders read

Owner-maintained. A legacy value absent from these files is loaded **unmapped and flagged**
(`FLAG:UnmappedManufacturer`, `FLAG:UnmappedModel`, `FLAG:UnmappedAssetType`), never guessed.
Only rows whose basis is stated were seeded; the rehearsal report lists the unmapped values by
frequency so the owner can extend these files (MIGRATION-PLAN.md §9).

| File | Maps | To |
|---|---|---|
| `manufacturer.csv` | `SETTINGS.MANUFACTURER` (trimmed, case-insensitive) | `ref.Manufacturer.ShortCode` (from the predecessor's `core.Vendor.Code`). From rehearsal 2 a row may name a `ShortCode` not yet in `ref.Manufacturer`; the loader then creates the `party.Entity` (kind Manufacturer) and `ref.Manufacturer` row using `manufacturer_name`, with provenance and flag `ManufacturerCreatedFromMapping` (MIGRATION-PLAN M-13). Rows added on the owner's Q3 decision of 2026-09-04 carry that basis. |
| `device_model.csv` | `SETTINGS.DEVICE` (trimmed, case-insensitive) | `ref.Model.ModelCode`; in addition the loader matches a DEVICE string that **equals** a model code exactly |
| `asset_type.csv` | `SETTINGS.DEVICE` | `ref.AssetType.AssetTypeCode`; rows whose model maps to a model of category RELAY become `RELAY` without needing an entry; everything else unmapped becomes `LEGACY_UNCLASSIFIED` |
