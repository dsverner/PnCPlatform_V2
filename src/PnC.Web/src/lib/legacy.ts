// No legacy record number or field name on screen (owner, 2026-09-14). The migrated asset name ends "[0225]" and the
// migrated request title ends "— A0225"; both are stripped for display only — stored values are untouched and text
// filters still match them. The migrated record's overflow columns (class, use, CT/PT ratios, remarks…) landed as the
// revision record's summary (W7, #140) and are read back under the platform's own labels.
const LEGACY_NO = /\s*(\[[A-Za-z]?\d{3,5}\]|—\s*[AMPD]\d{4})\s*$/

export const legacyFree = (text: unknown): string => (text == null ? '' : String(text).replace(LEGACY_NO, ''))

const DETAIL: Record<string, ['notes' | 'mp' | 'it', string]> = {
  SETTINGS2: ['notes', 'Settings (continued)'], DESC1: ['notes', 'Description 1'], DESC2: ['notes', 'Description 2'], DESC3: ['notes', 'Description 3'], DESC4: ['notes', 'Description 4'],
  REMARKS1: ['notes', 'Remarks 1'], REMARKS2: ['notes', 'Remarks 2'], REMARKS3: ['notes', 'Remarks 3'], REMARKS4: ['notes', 'Remarks 4'], REMARKS5: ['notes', 'Remarks 5'],
  CT_MAIN1: ['it', 'CT main 1'], CT_MAIN2: ['it', 'CT main 2'], CT_MAIN3: ['it', 'CT main 3'], CT_MAIN4: ['it', 'CT main 4'], PT_MAIN: ['it', 'PT main'],
  CT_AUX1: ['it', 'CT aux 1'], CT_AUX2: ['it', 'CT aux 2'], CT_AUX3: ['it', 'CT aux 3'], CT_AUX4: ['it', 'CT aux 4'], PT_AUX: ['it', 'PT aux'],
  CLASS: ['mp', 'Class'], USE: ['mp', 'Use'], RESPONSIBILITY: ['mp', 'Responsibility'], Bulk_Power_Element: ['mp', 'Bulk power element'], Protection_Group: ['mp', 'Protection group'],
  ELEMENT: ['mp', 'Element'], LINE_TYPE: ['mp', 'Line type'], 'NUMBER OF RELAYS': ['mp', 'Number of relays'],
}
export interface LegacyDetail { notes: [string, string][]; mp: [string, string][]; it: [string, string][] }
export function legacyDetail(summary: unknown): LegacyDetail {
  const out: LegacyDetail = { notes: [], mp: [], it: [] }
  for (const seg of String(summary ?? '').split(';')) {
    const i = seg.indexOf('='); if (i < 0) continue
    const key = seg.slice(0, i).trim(), value = seg.slice(i + 1).trim(); const d = DETAIL[key]
    if (d && value) out[d[0]].push([d[1], value])
  }
  return out
}
