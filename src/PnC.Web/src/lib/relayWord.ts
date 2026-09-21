// #215 (2026-09-20): a relay's Relay Word as data — the Program.RelayWord definition seeded from the instruction manual
// (tools/relay_word_sel221f.py) — and the two pure functions between a mask's filed text ("F0 A4 00", three hex bytes,
// one per row) and its 24 bits. The byte order is the manual's (3-15): the left bit of a row is the most significant
// bit of its byte, so "A4" over 67N 51NP 51NT 50NG 50P 50H IN1 REJO reads 1010 0100. The Settings tab's mask editor
// reads the definition matched to the settings template; nothing about a relay is written in code.
import { useQuery } from '@tanstack/react-query'
import { s, view, viewAll } from '@/lib/api'

export interface RelayWordBit { code: string; meaning: string; cite: string }
export interface RelayWordMask { name: string; purpose: string; caution: string; typical: string[]; never: string[]; neverNote: string; example: string; cite: string }
export interface RelayWord {
  key: string; name: string; settingsTemplate: string; source: string; bitOrder: string; footnote?: string
  rows: RelayWordBit[][]
  variants: { models: string; row: number; bit: number; code: string; note: string; cite: string }[]
  testing?: { bits: string[]; note: string; cite: string }
  masks: Record<string, RelayWordMask>
}

/** The filed text of a mask → one boolean per bit, row by row, left to right. Accepts "F0 A4 00", "F0A400", "F0-A4-00";
 * an empty or unreadable text is every bit off (the caller says "not set" from the value itself). */
export function parseMask(text: string, rows: number, bits = 8): boolean[] {
  const hex = (text || '').replace(/[^0-9a-fA-F]/g, '')
  const out: boolean[] = []
  for (let r = 0; r < rows; r++) {
    const byte = hex.length >= (r + 1) * 2 ? parseInt(hex.slice(r * 2, r * 2 + 2), 16) : 0
    for (let b = 0; b < bits; b++) out.push(((byte >> (bits - 1 - b)) & 1) === 1)
  }
  return out
}

/** The bits → the filed text: one upper-case hex byte per row, space-separated ("F0 A4 00"), as the relay prints them. */
export function formatMask(on: boolean[], rows: number, bits = 8): string {
  const bytes: string[] = []
  for (let r = 0; r < rows; r++) {
    let byte = 0
    for (let b = 0; b < bits; b++) if (on[r * bits + b]) byte |= 1 << (bits - 1 - b)
    bytes.push(byte.toString(16).toUpperCase().padStart(2, '0'))
  }
  return bytes.join(' ')
}

/** Is the text a readable mask for this many rows (nothing but hex digits and separators, the right number of digits)? */
export function isMaskText(text: string, rows: number): boolean {
  const t = (text || '').trim()
  if (t === '') return true
  return /^[0-9a-fA-F\s-]+$/.test(t) && t.replace(/[^0-9a-fA-F]/g, '').length === rows * 2
}

/** The Relay Word bound to a settings template, from the Effective Program.RelayWord definition whose document names it. */
export function useRelayWord(settingsTemplateKey: string | null | undefined) {
  return useQuery({ queryKey: ['relayWord', settingsTemplateKey], enabled: !!settingsTemplateKey, staleTime: 10 * 60_000, queryFn: async (): Promise<RelayWord | null> => {
    const defs = await viewAll('config', 'vDefinition', { DefinitionKind: 'Program.RelayWord' })
    for (const d of defs) {
      const ver = (await view('config', 'vDefinitionVersion', { DefinitionEntityId: s(d.EntityId), Status: 'Effective' }, { take: 1 })).rows[0]
      if (!ver) continue
      try {
        const doc = JSON.parse(s(ver.PayloadText)) as RelayWord
        if (doc.settingsTemplate === settingsTemplateKey) return doc
      } catch { /* an unreadable document is not this relay's */ }
    }
    return null
  } })
}
