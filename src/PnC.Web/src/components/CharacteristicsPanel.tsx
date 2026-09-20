// #201 (2026-09-19): an asset's characteristics, by the template its type names (ref.AssetType.DefaultTemplateDefinitionEntityId
// → the CharacteristicSchema.AssetTemplate's Effective version → config.vCharacteristicDefinition), read from
// asset.vAssetCharacteristic and saved through asset.CharacteristicValue_Add / _Revise (audited). The first use is the
// instrument transformer's nameplate; any asset type given a default template draws the same way. The settings record's
// own characteristics editor (RecordScreen) keeps its migrated-value logic and its document host; this one is the asset's.
import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ApiError, proc, s, view, viewAll, type Row } from '@/lib/api'
import { useViewAll } from '@/lib/hooks'
import { Panel, Status, inputClass } from '@/components/ui/ui'

/** The Effective characteristic definitions of a template definition (by its DefinitionEntityId). */
export function useTemplateDefs(definitionEntityId: string) {
  return useQuery({ queryKey: ['templateDefs', definitionEntityId], enabled: !!definitionEntityId, staleTime: 10 * 60_000, queryFn: async () => {
    const v = (await view('config', 'vDefinitionVersion', { DefinitionEntityId: definitionEntityId, Status: 'Effective' }, { take: 5 })).rows[0]; if (!v) return [] as Row[]
    return viewAll('config', 'vCharacteristicDefinition', { DefinitionVersionRowId: s(v.RowId) }, 'DisplayOrder')
  } })
}

/** The value of one characteristic row as text, whatever its type. */
export function characteristicText(v: Row | undefined): string | null {
  if (!v) return null
  const x = v.TextValue ?? v.DecimalValue ?? v.IntegerValue ?? v.BooleanValue ?? v.DateTimeValue ?? v.ReferenceEntityId
  return x == null ? null : s(x)
}

/** Save one characteristic of an asset: add when none stands, revise when one does. */
export async function saveAssetCharacteristic(assetEntityId: string, def: Row, text: string, existing?: Row) {
  const typed: Row = { HostEntityId: assetEntityId, CharacteristicDefinitionRowId: def.RowId }
  if (def.DataType === 'Integer') typed.IntegerValue = Number(text)
  else if (def.DataType === 'Decimal') typed.DecimalValue = Number(text)
  else if (def.DataType === 'Boolean') typed.BooleanValue = /^(1|true|yes)$/i.test(text)
  else typed.TextValue = text
  if (existing) await proc('asset', 'CharacteristicValue_Revise', { EntityId: existing.EntityId, ...typed })
  else await proc('asset', 'CharacteristicValue_Add', typed)
}

export function AssetCharacteristics({ assetEntityId, definitionEntityId, editable, emptyNote }: { assetEntityId: string; definitionEntityId: string; editable: boolean; emptyNote?: string }) {
  const qc = useQueryClient()
  const defsQ = useTemplateDefs(definitionEntityId)
  const valuesQ = useViewAll('asset', 'vAssetCharacteristic', { AssetEntityId: assetEntityId }, undefined, !!assetEntityId)
  const [edits, setEdits] = useState<Record<string, string>>({})
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const defs = defsQ.data ?? []; const values = valuesQ.data ?? []
  const valueRow = (d: Row) => values.find((x) => s(x.CharacteristicDefinitionRowId).toLowerCase() === s(d.RowId).toLowerCase())
  const groups = useMemo(() => { const m = new Map<string, Row[]>(); for (const d of defs) { const g = s(d.DisplayGroup) || 'Characteristics'; if (!m.has(g)) m.set(g, []); m.get(g)!.push(d) } return m }, [defs])
  const save = async (d: Row) => {
    const key = s(d.RowId); const text = (edits[key] ?? '').trim(); if (!text) return
    try {
      await saveAssetCharacteristic(assetEntityId, d, text, valueRow(d))
      setMsg({ text: `${s(d.Name)} saved.` }); setEdits((e) => { const n = { ...e }; delete n[key]; return n })
      qc.invalidateQueries({ queryKey: ['view', 'asset'] }); qc.invalidateQueries({ queryKey: ['view', 'scheme'] })
    } catch (e) { setMsg({ text: `${s(d.Name)}: ${e instanceof ApiError ? e.message : String(e)}`, bad: true }) }
  }
  if (!definitionEntityId) return <Panel title="Nameplate"><Status>{emptyNote ?? 'This asset type names no characteristic template.'}</Status></Panel>
  if (defsQ.isPending) return <Panel title="Nameplate"><Status>Loading the template…</Status></Panel>
  if (!defs.length) return <Panel title="Nameplate"><Status>The type's template has no Effective version.</Status></Panel>
  return (
    <div className="grid gap-3 lg:grid-cols-3">
      {[...groups.entries()].map(([g, list]) => (
        <Panel key={g} title={g}>
          <dl className="grid grid-cols-1 gap-x-6 gap-y-1 text-sm">
            {list.map((d) => { const v = characteristicText(valueRow(d)); const key = s(d.RowId)
              return (
                <div key={key} className="grid grid-cols-[10rem_1fr] items-center gap-2" title={s(d.Description)}>
                  <dt className="text-slate-400">{s(d.Name)}{d.UnitCode ? <span className="text-slate-600"> ({s(d.UnitCode)})</span> : ''}</dt>
                  <dd className="min-w-0">
                    {editable
                      ? <input className={`${inputClass} w-full`} placeholder={v ?? ''} value={edits[key] ?? ''} aria-label={s(d.Name)}
                          onChange={(e) => setEdits({ ...edits, [key]: e.target.value })} onBlur={() => void save(d)} onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }} />
                      : <span className={v == null ? 'text-slate-500' : 'text-slate-200'}>{v ?? '—'}</span>}
                  </dd>
                </div>) })}
          </dl>
        </Panel>))}
      {msg && <div className="lg:col-span-3"><Status bad={msg.bad}>{msg.text}</Status></div>}
      {editable && <div className="lg:col-span-3"><Status>A value saves when you leave the field (audited as your change). Hover a name for what the nameplate field means.</Status></div>}
    </div>
  )
}
