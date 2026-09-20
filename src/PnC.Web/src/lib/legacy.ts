// No legacy record number or field name on screen (owner, 2026-09-14). The migrated asset name ends "[0225]" and the
// migrated request title ends "— A0225"; both are stripped for display only — stored values are untouched and text
// filters still match them. The migrated record's overflow columns (class, use, CT/PT ratios, remarks…) landed as the
// revision record's summary (W7, #140) and are read back under the platform's own labels.
const LEGACY_NO = /\s*(\[[A-Za-z]?\d{3,5}\]|—\s*[AMPD]\d{4})\s*$/

export const legacyFree = (text: unknown): string => (text == null ? '' : String(text).replace(LEGACY_NO, ''))

const DETAIL: Record<string, ['notes' | 'mp', string]> = {
  SETTINGS2: ['notes', 'Settings (continued)'], DESC1: ['notes', 'Description 1'], DESC2: ['notes', 'Description 2'], DESC3: ['notes', 'Description 3'], DESC4: ['notes', 'Description 4'],
  REMARKS1: ['notes', 'Remarks 1'], REMARKS2: ['notes', 'Remarks 2'], REMARKS3: ['notes', 'Remarks 3'], REMARKS4: ['notes', 'Remarks 4'], REMARKS5: ['notes', 'Remarks 5'],
  // #206 (2026-09-20): CT_MAIN1-4, PT_MAIN, CT_AUX1-4 and PT_AUX are no longer read here — the owner: the legacy section "can be
  // retired completely"; the migration rule makes the scheme's instrument transformers from those strings, and the record's
  // Analog inputs tab shows the transformers. The segments stay in the summary as the imported text the rule reads.
  // #194 (2026-09-19): CLASS, USE, RESPONSIBILITY, Bulk_Power_Element, Protection_Group, ELEMENT, LINE_TYPE and NUMBER OF RELAYS
  // are no longer read — the owner: "I do not trust any of the data in those fields"; the importer no longer carries them.
}
export interface LegacyDetail { notes: [string, string][]; mp: [string, string][] }
export function legacyDetail(summary: unknown): LegacyDetail {
  const out: LegacyDetail = { notes: [], mp: [] }
  for (const seg of String(summary ?? '').split(';')) {
    const i = seg.indexOf('='); if (i < 0) continue
    const key = seg.slice(0, i).trim(), value = seg.slice(i + 1).trim(); const d = DETAIL[key]
    if (d && value) out[d[0]].push([d[1], value])
  }
  return out
}
