// #201 (2026-09-19): an asset's characteristics, by the template its type names (ref.AssetType.DefaultTemplateDefinitionEntityId
// → the CharacteristicSchema.AssetTemplate's Effective version → config.vCharacteristicDefinition), read from
// asset.vAssetCharacteristic and saved through asset.SetAssetCharacteristic (#216: the key resolved against the asset's
// template, the value typed and checked against its closed list, the prior row closed, the work request and the change
// audited). The first use was the instrument transformer's nameplate (#201); #216 adds a relay's HARDWARE configuration
// (the SEL-221F's jumper positions) as a group of the model's template shown alone on the settings record — `groups`
// picks which DisplayGroups a mount shows. A closed list (Enumeration) is a select; a Boolean is Yes / No.
import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ApiError, proc, s, view, viewAll, type Row } from '@/lib/api'
import { useViewAll } from '@/lib/hooks'
import { Panel, Status, inputClass } from '@/components/ui/ui'

const NOT_RECORDED = '\u2014 not recorded'

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

/** Save one characteristic of an asset by its key — asset.SetAssetCharacteristic types it, checks a closed list, closes the
 * prior row and audits the change with the work request (#216). An empty text clears the value. */
export async function saveAssetCharacteristic(assetEntityId: string, def: Row, text: string, _existing?: Row, workRequestEntityId?: string) {
  await proc('asset', 'SetAssetCharacteristic', { AssetEntityId: assetEntityId, CharacteristicKey: s(def.CharacteristicKey), Value: text.trim() || null, WorkRequestEntityId: workRequestEntityId || null })
}

/** The values of every closed list the definitions name (config.vEnumerationValue by AllowedValuesDefinitionRowId). */
function useEnumValues(defs: Row[]) {
  const ids = [...new Set(defs.map((d) => s(d.AllowedValuesDefinitionRowId)).filter(Boolean))].sort()
  return useQuery({ queryKey: ['enumValues', ids], enabled: ids.length > 0, staleTime: 10 * 60_000, queryFn: async () => {
    const m = new Map<string, Row[]>()
    for (const id of ids) m.set(id.toLowerCase(), await viewAll('config', 'vEnumerationValue', { DefinitionVersionRowId: id }, 'DisplayOrder'))
    return m
  } })
}

export function AssetCharacteristics({ assetEntityId, definitionEntityId, editable, emptyNote, groups: only, title, note, workRequestEntityId }: {
  assetEntityId: string; definitionEntityId: string; editable: boolean; emptyNote?: string
  groups?: string[]; title?: string; note?: string; workRequestEntityId?: string
}) {
  const qc = useQueryClient()
  const defsQ = useTemplateDefs(definitionEntityId)
  const valuesQ = useViewAll('asset', 'vAssetCharacteristic', { AssetEntityId: assetEntityId }, undefined, !!assetEntityId)
  const [edits, setEdits] = useState<Record<string, string>>({})
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const allDefs = defsQ.data ?? []; const values = valuesQ.data ?? []
  const defs = useMemo(() => (only ? allDefs.filter((d) => only.includes(s(d.DisplayGroup))) : allDefs), [allDefs, only])
  const enumsQ = useEnumValues(defs)
  const valueRow = (d: Row) => values.find((x) => s(x.CharacteristicDefinitionRowId).toLowerCase() === s(d.RowId).toLowerCase())
  const groups = useMemo(() => { const m = new Map<string, Row[]>(); for (const d of defs) { const g = s(d.DisplayGroup) || 'Characteristics'; if (!m.has(g)) m.set(g, []); m.get(g)!.push(d) } return m }, [defs])
  const shown = (d: Row): string | null => {
    const v = characteristicText(valueRow(d)); if (v == null) return null
    if (s(d.DataType) === 'Boolean') return /^(1|true)$/i.test(v) ? 'Yes' : 'No'
    if (s(d.DataType) === 'Enumeration') { const opts = enumsQ.data?.get(s(d.AllowedValuesDefinitionRowId).toLowerCase()) ?? []; const o = opts.find((x) => s(x.ValueCode) === v); return o ? `${s(o.ValueCode)} — ${s(o.Name)}` : v }
    return v
  }
  const save = async (d: Row, text: string) => {
    const key = s(d.RowId)
    try {
      await saveAssetCharacteristic(assetEntityId, d, text, valueRow(d), workRequestEntityId)
      setMsg({ text: text.trim() ? `${s(d.Name)} saved.` : `${s(d.Name)} cleared.` }); setEdits((e) => { const n = { ...e }; delete n[key]; return n })
      qc.invalidateQueries({ queryKey: ['view', 'asset'] }); qc.invalidateQueries({ queryKey: ['view', 'scheme'] })
    } catch (e) { setMsg({ text: `${s(d.Name)}: ${e instanceof ApiError ? e.message : String(e)}`, bad: true }) }
  }
  const fallback = title ?? 'Nameplate'
  if (!definitionEntityId) return <Panel title={fallback}><Status>{emptyNote ?? 'This asset type names no characteristic template.'}</Status></Panel>
  if (defsQ.isPending) return <Panel title={fallback}><Status>Loading the template…</Status></Panel>
  if (!defs.length) return <Panel title={fallback}><Status>{only ? `The template has no ${only.join(', ')} group.` : "The type's template has no Effective version."}</Status></Panel>
  return (
    <div className={`grid gap-3 ${groups.size > 1 ? 'lg:grid-cols-3' : ''}`}>
      {[...groups.entries()].map(([g, list]) => (
        <Panel key={g} title={title && groups.size === 1 ? title : g}>
          <dl className="grid grid-cols-1 gap-x-6 gap-y-1 text-sm">
            {list.map((d) => { const raw = characteristicText(valueRow(d)); const v = shown(d); const key = s(d.RowId); const type = s(d.DataType)
              const opts = type === 'Enumeration' ? (enumsQ.data?.get(s(d.AllowedValuesDefinitionRowId).toLowerCase()) ?? []) : []
              return (
                <div key={key} className="grid grid-cols-[14rem_1fr] items-center gap-2" title={s(d.Description)}>
                  <dt className="text-slate-400">{s(d.Name)}{d.UnitCode ? <span className="text-slate-600"> ({s(d.UnitCode)})</span> : ''}</dt>
                  <dd className="min-w-0">
                    {!editable ? <span className={v == null ? 'text-slate-500' : 'text-slate-200'}>{v ?? NOT_RECORDED}</span>
                      : type === 'Enumeration'
                        ? <select className={`${inputClass} w-full`} value={raw ?? ''} aria-label={s(d.Name)} onChange={(e) => void save(d, e.target.value)}>
                            <option value="">{NOT_RECORDED}</option>
                            {opts.map((o) => <option key={s(o.ValueCode)} value={s(o.ValueCode)}>{s(o.ValueCode)} — {s(o.Name)}</option>)}
                          </select>
                      : type === 'Boolean'
                        ? <select className={`${inputClass} w-full`} value={raw == null ? '' : /^(1|true)$/i.test(raw) ? 'Y' : 'N'} aria-label={s(d.Name)} onChange={(e) => void save(d, e.target.value)}>
                            <option value="">{NOT_RECORDED}</option><option value="Y">Yes</option><option value="N">No</option>
                          </select>
                      : <input className={`${inputClass} w-full`} placeholder={v ?? ''} value={edits[key] ?? ''} aria-label={s(d.Name)}
                          onChange={(e) => setEdits({ ...edits, [key]: e.target.value })} onBlur={() => { const x = (edits[key] ?? '').trim(); if (x) void save(d, x) }} onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }} />}
                  </dd>
                </div>) })}
          </dl>
        </Panel>))}
      {msg && <div className={groups.size > 1 ? 'lg:col-span-3' : ''}><Status bad={msg.bad}>{msg.text}</Status></div>}
      {editable && <div className={groups.size > 1 ? 'lg:col-span-3' : ''}><Status>{note ?? 'A value saves when you leave the field (audited as your change). Hover a name for what the field means.'}</Status></div>}
    </div>
  )
}

/** #212: a new instrument transformer's first secondary winding, S1, carrying the ratio typed — the winding is where a ratio lives now. */
export async function addFirstWinding(assetEntityId: string, ratioInUse: string, purpose: 'Protection' | 'Metering' | 'Sync' = 'Protection'): Promise<string> {
  const w = await proc('asset', 'InstrumentWinding_Add', { AssetEntityId: assetEntityId, WindingNo: 1, Code: 'S1', Purpose: purpose, RatioInUse: ratioInUse.trim() || null })
  return s(w.EntityId)
}
