// #235 (2026-09-23): a relay model's manual guide — the instruction manual's own words on how each setting is set, verbatim
// from the page, with the manual's printed page ("5-11") and the PDF's page (where the link opens) — a Program.ManualGuide
// definition seeded by tools/manual_guide_sel221f.py. The Settings tab shows it as a floatover on each setting; a setting the
// guide does not cover shows none. Nothing about a relay is written in code.
import { createContext, useContext } from 'react'
import { useQuery } from '@tanstack/react-query'
import { s, view, viewAll } from '@/lib/api'

export interface ManualQuote { quote: string; page: string; pdfPage: number; checked: string }
export interface ManualGuide { key: string; name: string; settingsTemplate: string; source: string; settings: Record<string, ManualQuote[]> }

/** The guide bound to a settings template, from the Effective Program.ManualGuide definition whose document names it. */
export function useManualGuide(settingsTemplateKey: string | null | undefined) {
  return useQuery({ queryKey: ['manualGuide', settingsTemplateKey], enabled: !!settingsTemplateKey, staleTime: 10 * 60_000, queryFn: async (): Promise<ManualGuide | null> => {
    const defs = await viewAll('config', 'vDefinition', { DefinitionKind: 'Program.ManualGuide' })
    for (const d of defs) {
      const ver = (await view('config', 'vDefinitionVersion', { DefinitionEntityId: s(d.EntityId), Status: 'Effective' }, { take: 1 })).rows[0]
      if (!ver) continue
      try {
        const doc = JSON.parse(s(ver.PayloadText)) as ManualGuide
        if (doc.settingsTemplate === settingsTemplateKey) return doc
      } catch { /* an unreadable document is not this relay's */ }
    }
    return null
  } })
}

/** What a settings grid needs to show a setting's floatover: the guide and the manual's file (for the link to the page). */
export interface ManualHelp { guide: ManualGuide | null; manualFileRowId: string | null }
export const ManualHelpContext = createContext<ManualHelp>({ guide: null, manualFileRowId: null })
export const useManualHelp = () => useContext(ManualHelpContext)
