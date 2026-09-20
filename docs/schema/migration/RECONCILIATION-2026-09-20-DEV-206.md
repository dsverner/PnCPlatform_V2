# Reconciliation — DEV, 2026-09-20, rule #206 (instrument transformers from the legacy record)

The rule `Seed_asset_InstrumentTransformersFromLegacy` ran on PnCPlatform_V2_DEV as part of the deploy (a replayable
migration rule, not a hand edit; it re-runs on every deploy and changes nothing the second time). Counts read back from
the database after the deploy (asset.AlternateKey kind MigrationSource; asset.vInstrumentTransformer):

| What | Count |
|---|---|
| CT sets from declared CT_MAIN1..4 ratios (one per distinct ratio per scheme) | 1803 |
| PT sets from declared PT_MAIN ratios | 816 |
| CT sets with the ratio unknown (a device's functions need current; no string) | 3 |
| PT sets with the ratio unknown (a device's functions need voltage; no string) | 34 |
| Single-phase sync PTs (a device has a 25) | 44 |
| Auxiliary CTs and PTs (CT_AUX1..4, PT_AUX), per device | 502 (at their panel 502, unplaced 0) |
| Schemes given at least one source by the rule | 1178 |
| Instrument transformers on DEV in all (incl. the hand-made and smoke ones) | 3214 |
| Placement rows re-flagged as sharing their node (Seed_asset_PlacementOccupancy) | 515 |

The main sets stand **unplaced** (no migrated station has a Yard); the station shown is the scheme's. A person places
each from its page (a yard of the station, made there if none). The real cutover re-imports and replays this rule; this
note records what the rule made on DEV so a later count can be compared.
