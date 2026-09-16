// #170 (2026-09-16): the protection scheme — its members, and the primary assets it protects (scheme.SchemeProtects, the
// link the applicability classifications flow through: a device inherits from the primary asset via its scheme). "Protects"
// is entered here, a few seconds per scheme: pick an existing primary asset at the station or create one (a name, a type,
// the station — nothing more in this phase). Plain React (the #167 rule).
import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ApiError, s, view, viewAll, proc, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type RecordParams, type Screen, screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status, Field, inputClass } from '@/components/ui/ui'
import { DataGrid } from '@/components/ui/data-grid'

const ZONES = ['Primary', 'Backup', 'Overlap']

export default function SchemeScreen({ params: p, id }: { screen: Screen; params: RecordParams; id?: string }) {
  const navigate = useNavigate(); const can = useCan(); const qc = useQueryClient()
  const rowQ = useViewAll('scheme', 'vScheme', { [p.key]: id ?? '' }, undefined, !!id)
  const r = rowQ.data?.[0]
  // the station: the settings records of the scheme's devices carry it
  const stationQ = useQuery({ queryKey: ['schemeStation', id], enabled: !!id, staleTime: 5 * 60_000, queryFn: async () => (await view('document', 'vSettingsRecord', { SchemeEntityId: id! }, { take: 1 })).rows[0] ?? null })
  const membersQ = useQuery({ queryKey: ['schemeMembers', id], enabled: !!id, queryFn: async () => {
    const ms = await viewAll('scheme', 'vSchemeMember', { SchemeEntityId: id! })
    const out: Row[] = []
    for (const m of ms) {
      let name = ''
      if (m.MemberKind === 'ProtectionFunction' || m.MemberKind === 'Node') name = s((await view('location', 'vNode', { EntityId: s(m.MemberEntityId) }, { take: 1 })).rows[0]?.Name)
      else if (m.MemberKind === 'Asset' || m.MemberKind === 'Device') name = s((await view('asset', 'vAsset', { EntityId: s(m.MemberEntityId) }, { take: 1 })).rows[0]?.Name)
      out.push({ ...m, MemberName: name })
    }
    return out
  } })
  const protectsQ = useQuery({ queryKey: ['schemeProtects', id], enabled: !!id, queryFn: async () => {
    const links = await viewAll('scheme', 'vSchemeProtects', { SchemeEntityId: id! })
    const out: Row[] = []
    for (const l of links) { const a = (await view('asset', 'vPrimaryAsset', { EntityId: s(l.PrimaryAssetEntityId) }, { take: 1 })).rows[0]; out.push({ ...l, ...(a ?? {}), LinkEntityId: l.EntityId }) }
    return out
  } })
  const typesQ = useViewAll('ref', 'vAssetType', { AssetClassCode: 'Primary' })
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const [pick, setPick] = useState(''); const [find, setFind] = useState(''); const [zone, setZone] = useState('Primary')
  const [newType, setNewType] = useState('Line'); const [newName, setNewName] = useState(''); const [busy, setBusy] = useState(false)
  const station = stationQ.data
  const candidatesQ = useViewAll('asset', 'vPrimaryAsset', station?.StationNodeEntityId ? { StationNodeEntityId: s(station.StationNodeEntityId) } : {}, 'Name', !!station)
  const candidates = useMemo(() => (candidatesQ.data ?? []).filter((x) => !find || s(x.Name).toLowerCase().includes(find.toLowerCase())), [candidatesQ.data, find])
  const editable = can('Scheme.Modify')
  const refresh = () => { qc.invalidateQueries({ queryKey: ['schemeProtects', id] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vPrimaryAsset'] }) }
  const link = async (assetId: string, label: string) => {
    setBusy(true)
    try { await proc('scheme', 'SchemeProtects_Add', { SchemeEntityId: id, PrimaryAssetEntityId: assetId, ZoneRole: zone }); setMsg({ text: `${s(r?.Name)} protects ${label} (${zone.toLowerCase()}).` }); setPick(''); refresh() }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const create = async () => {
    if (!newName.trim() || !station?.StationNodeEntityId) return
    setBusy(true)
    try {
      const a = await proc<Row>('asset', 'Asset_Add', { AssetTypeCode: newType, Name: newName.trim(), Status: 'InService' })
      const assetId = s(a.EntityId)
      await proc('asset', 'PlaceAsset', { AssetEntityId: assetId, NodeEntityId: s(station.StationNodeEntityId), PlacementKind: 'Installed' })
      setNewName('')
      await link(assetId, `${newName.trim()} (new ${newType.toLowerCase()} at ${s(station.StationName)})`)
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }); setBusy(false) }
  }
  const unlink = async (x: Row) => {
    try { await proc('scheme', 'SchemeProtects_SoftDelete', { EntityId: x.LinkEntityId }); setMsg({ text: `${s(x.Name)} no longer listed as protected by ${s(r?.Name)}.` }); refresh() }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) }
  }
  if (!id) return <Status bad>No scheme in the address.</Status>
  if (rowQ.isPending) return <Status>Loading the scheme…</Status>
  if (!r) return <Status bad>No scheme with that id is readable by you.</Status>
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2"><h1 className="text-lg font-semibold text-slate-100">{s(r.Name)}</h1><Pill tone={r.Status === 'InService' ? 'good' : 'neutral'}>{s(r.Status)}</Pill></div>
        <div className="flex gap-2">{!!station?.StationNodeEntityId && <Button onClick={() => navigate(screenPath('SETTINGS_BOOK') + `?StationNodeEntityId=${station.StationNodeEntityId}`)}>Settings book</Button>}<Button onClick={() => navigate(-1)}>Close</Button></div>
      </header>
      <div className="grid gap-3 lg:grid-cols-2">
        <Panel title="Scheme"><Facts cols={1} pairs={[['Name', s(r.Name)], ['System designation', s(r.SystemDesignation) || '—'], ['Station', station ? s(station.StationName) : stationQ.isPending ? '…' : 'no device of this scheme has a settings record'], ['Status', s(r.Status)], ['Notes', s(r.Notes) || '—']]} /></Panel>
        <Panel title={`Members · ${membersQ.isPending ? '…' : (membersQ.data ?? []).length}`}>
          <DataGrid rows={membersQ.data ?? []} rowKey={(x) => s(x.EntityId)} emptyText="No members." columns={[{ key: 'MemberName', label: 'Member' }, { key: 'MemberKind', label: 'Kind' }, { key: 'MemberRoleCode', label: 'Role' }, { key: 'IsInService', label: 'In service', render: (x) => (x.IsInService ? 'yes' : 'no') }]} />
        </Panel>
      </div>
      <Panel title={`Protects · ${protectsQ.isPending ? '…' : (protectsQ.data ?? []).length} primary asset(s)`}>
        {msg && <Status bad={msg.bad}>{msg.text}</Status>}
        <DataGrid rows={protectsQ.data ?? []} rowKey={(x) => s(x.LinkEntityId)} emptyText="Nothing recorded yet: which primary asset does this scheme protect?" columns={[
          { key: 'Name', label: 'Primary asset', render: (x) => <a className="text-sky-300 underline" href={screenPath('PRIMARY_ASSET', s(x.PrimaryAssetEntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('PRIMARY_ASSET', s(x.PrimaryAssetEntityId))) }}>{s(x.Name) || s(x.PrimaryAssetEntityId).slice(0, 8)}</a> },
          { key: 'AssetTypeName', label: 'Type' }, { key: 'StationName', label: 'Station' }, { key: 'ZoneRole', label: 'Zone' },
          { key: 'Classifications', label: 'Classifications', render: (x) => <span className="text-xs text-slate-400">{s(x.Classifications) || 'none recorded'}</span> },
          ...(editable ? [{ key: '_x', label: '', render: (x: Row) => <Button kind="mini" onClick={() => void unlink(x)}>remove</Button> }] : [])]} />
        {editable && (
          <div className="mt-3 grid gap-3 lg:grid-cols-2">
            <div className="rounded border border-slate-800 p-2">
              <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400">Add an existing primary asset{station ? ` at ${s(station.StationName)}` : ''}</h4>
              <div className="mt-1 flex flex-wrap items-end gap-2">
                <Field label="Find"><input className={inputClass} value={find} onChange={(e) => setFind(e.target.value)} placeholder="name contains…" /></Field>
                <Field label="Primary asset"><select className={inputClass} value={pick} onChange={(e) => setPick(e.target.value)}><option value="">— choose —</option>{candidates.map((x) => <option key={s(x.EntityId)} value={s(x.EntityId)}>{s(x.Name)} · {s(x.AssetTypeName)}</option>)}</select></Field>
                <Field label="Zone"><select className={inputClass} value={zone} onChange={(e) => setZone(e.target.value)}>{ZONES.map((z) => <option key={z}>{z}</option>)}</select></Field>
                <Button kind="primary" disabled={!pick || busy} onClick={() => void link(pick, s(candidates.find((x) => s(x.EntityId) === pick)?.Name))}>Protects</Button>
              </div>
            </div>
            <div className="rounded border border-slate-800 p-2">
              <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400">Or create one{station ? ` at ${s(station.StationName)}` : ' (the scheme has no station yet)'}</h4>
              <div className="mt-1 flex flex-wrap items-end gap-2">
                <Field label="Type"><select className={inputClass} value={newType} onChange={(e) => setNewType(e.target.value)}>{(typesQ.data ?? []).map((t) => <option key={s(t.AssetTypeCode)} value={s(t.AssetTypeCode)}>{s(t.Name)}</option>)}</select></Field>
                <Field label="Name"><input className={inputClass} value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="e.g. Line 0012" /></Field>
                <Button kind="primary" disabled={!newName.trim() || !station?.StationNodeEntityId || busy} onClick={() => void create()}>Create and protect</Button>
              </div>
              <div className="mt-1 text-xs text-slate-500">A name, a type and the station — nothing more in this phase. The power-system model (the TLM project) attaches later.</div>
            </div>
          </div>
        )}
      </Panel>
    </div>
  )
}
