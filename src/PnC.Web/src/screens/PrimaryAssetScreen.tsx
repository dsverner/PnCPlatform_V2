// #170 (2026-09-16): the primary asset — a line, transformer, bus, breaker, generator, capacitor, reactor or the system —
// the subject of the applicability classifications (the owner: they belong to the primary asset a device protects, not to the
// device). In this phase the values are recorded by a person from the entity's own procedures (the CIP-002 evaluation, the
// A-10 study), with who, when and the list or study they came from; a later phase derives them. Plain React (the #167 rule).
import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ApiError, fmtWhen, s, view, viewAll, proc, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type RecordParams, type Screen, screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status, inputClass } from '@/components/ui/ui'
import { DataGrid } from '@/components/ui/data-grid'

/** The kinds and the values in the standards' own words (a later phase's derivation writes the same values with Basis Derived). */
export const CLASSIFICATION_KINDS: { code: string; label: string; values: string[]; help: string }[] = [
  { code: 'BesStatus', label: 'BES status', values: ['BES', 'Not BES'], help: 'Bulk Electric System element (NERC definition)' },
  { code: 'CipImpactRating', label: 'CIP impact rating', values: ['High', 'Medium', 'Low', 'None'], help: 'CIP-002: the impact rating of the BES asset this element belongs to; the cyber systems protecting it follow' },
  { code: 'NpccBulkPowerSystem', label: 'NPCC bulk power system', values: ['BPS', 'Not BPS'], help: 'Declared a BPS bus (or not) by the entity\'s A-10 study; the NPCC directories then apply' },
  { code: 'Prc023', label: 'PRC-023', values: ['Listed', 'Not listed'], help: 'On the entity\'s PRC-023 list of impactful lines: the relay loadability calculation applies' },
]

export function useClassifications(subjectKind: string, subjectEntityId: string) {
  return useViewAll('asset', 'vClassification', { SubjectKind: subjectKind, SubjectEntityId: subjectEntityId }, undefined, !!subjectEntityId)
}

/** The classification panel: one row per kind; editable when the person may modify the subject. Records through asset.RecordClassification. */
export function ClassificationPanel({ subjectKind, subjectEntityId, editable }: { subjectKind: string; subjectEntityId: string; editable: boolean }) {
  const qc = useQueryClient()
  const q = useClassifications(subjectKind, subjectEntityId)
  const rows = q.data ?? []
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const current = (code: string) => rows.find((r) => s(r.ClassificationKindCode) === code)
  const record = async (code: string, value: string) => {
    try {
      await proc('asset', 'RecordClassification', { SubjectKind: subjectKind, SubjectEntityId: subjectEntityId, ClassificationKindCode: code, ClassificationValue: value || null })
      setMsg({ text: `${CLASSIFICATION_KINDS.find((k) => k.code === code)?.label ?? code} ${value ? 'recorded: ' + value : 'withdrawn'}.` })
      qc.invalidateQueries({ queryKey: ['view', 'asset', 'vClassification'] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vPrimaryAsset'] })
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) }
  }
  return (
    <Panel title="Applicability classifications">
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      <dl className="grid grid-cols-1 gap-x-6 gap-y-2 text-sm">
        {CLASSIFICATION_KINDS.map((k) => { const c = current(k.code); const v = c ? s(c.ClassificationValue) : ''
          return (
            <div key={k.code} className="grid grid-cols-[13rem_1fr] items-start gap-2">
              <dt className="text-slate-400" title={k.help}>{k.label}</dt>
              <dd className="min-w-0">
                {editable
                  ? <select className={`${inputClass} w-48`} value={v} onChange={(e) => void record(k.code, e.target.value)}>
                      <option value="">— not recorded —</option>{k.values.map((x) => <option key={x} value={x}>{x}</option>)}
                    </select>
                  : <span className={v ? 'text-slate-100' : 'text-slate-500'}>{v || 'not recorded'}</span>}
                {c && <span className="ml-2 text-xs text-slate-500">{s(c.Basis)} · {fmtWhen(c.DeterminedAt)}{c.ReferenceDocumentRevisionRowId ? ' · from a filed list' : ''}</span>}
                <div className="text-xs text-slate-600">{k.help}</div>
              </dd>
            </div>) })}
      </dl>
      <Status>{editable ? 'Recorded by you from the entity\'s own CIP-002 evaluation, A-10 study (the BPS declaration) and PRC-023 list (this phase); the platform derives them in a later phase and keeps both. A value saves at once, audited.' : 'Recorded values; the platform derives them in a later phase.'}</Status>
    </Panel>
  )
}

const STATUSES = ['Planned', 'InService', 'OutOfService', 'Retired']

/** The primary asset's own fields, editable by anyone who may modify assets (the owner, 2026-09-16: "there needs to be a way for the
 * user to edit these fields" — Line 0012 should have been L0012). Saved through asset.Asset_Revise (the prior row closes in valid
 * time; audited). The terminals — one station for a transformer, bus or breaker, two for a line — are asset.AssetTerminal rows,
 * revised, added or withdrawn beside it. */
function AssetForm({ r }: { r: Row }) {
  const qc = useQueryClient()
  const typesQ = useViewAll('ref', 'vAssetType', { AssetClassCode: 'Primary' })
  const voltagesQ = useViewAll('ref', 'vVoltageClass', {})
  const stationsQ = useViewAll('location', 'vNode', { NodeTypeCode: 'Station' }, 'Name')
  const terminalsQ = useViewAll('asset', 'vAssetTerminal', { AssetEntityId: s(r.EntityId) })
  const [t1, setT1] = useState(s(r.Terminal1NodeEntityId)); const [t2, setT2] = useState(s(r.Terminal2NodeEntityId))
  const [f, setF] = useState({ Name: s(r.Name), AssetTypeCode: s(r.AssetTypeCode), VoltageClassCode: s(r.VoltageClassCode), Status: s(r.Status), Notes: s(r.Notes) })   // the terminals are t1 / t2 below
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null); const [busy, setBusy] = useState(false)
  const dirty = f.Name !== s(r.Name) || f.AssetTypeCode !== s(r.AssetTypeCode) || f.VoltageClassCode !== s(r.VoltageClassCode) || f.Status !== s(r.Status) || f.Notes !== s(r.Notes) || t1.toLowerCase() !== s(r.Terminal1NodeEntityId).toLowerCase() || t2.toLowerCase() !== s(r.Terminal2NodeEntityId).toLowerCase()
  const save = async () => {
    if (!f.Name.trim()) { setMsg({ text: 'A name is needed.', bad: true }); return }
    setBusy(true)
    try {
      await proc('asset', 'Asset_Revise', { EntityId: r.EntityId, AssetTypeCode: f.AssetTypeCode, Name: f.Name.trim(), VoltageClassCode: f.VoltageClassCode || null, Status: f.Status, Notes: f.Notes || null })
      // the terminals: one current row per terminal number — revised, added or withdrawn (asset.AssetTerminal, #170)
      for (const [no, chosen, was] of [[1, t1, s(r.Terminal1NodeEntityId)], [2, t2, s(r.Terminal2NodeEntityId)]] as [number, string, string][]) {
        if (chosen.toLowerCase() === was.toLowerCase()) continue
        const row = (terminalsQ.data ?? []).find((x) => Number(x.TerminalNo) === no)
        if (!chosen && row) await proc('asset', 'AssetTerminal_SoftDelete', { EntityId: row.EntityId })
        else if (chosen && row) await proc('asset', 'AssetTerminal_Revise', { EntityId: row.EntityId, AssetEntityId: r.EntityId, TerminalNo: no, StationNodeEntityId: chosen })
        else if (chosen) await proc('asset', 'AssetTerminal_Add', { AssetEntityId: r.EntityId, TerminalNo: no, StationNodeEntityId: chosen })
      }
      setMsg({ text: `${f.Name.trim()} saved.` }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vPrimaryAsset'] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vAssetTerminal'] })
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  return (
    <div className="space-y-2 text-sm">
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      <div className="grid grid-cols-[8rem_1fr] items-center gap-2">
        <label className="text-slate-400">Name</label><input className={`${inputClass} w-64`} value={f.Name} onChange={set('Name')} placeholder="e.g. L0012" />
        <label className="text-slate-400">Type</label><select className={`${inputClass} w-64`} value={f.AssetTypeCode} onChange={set('AssetTypeCode')}>{(typesQ.data ?? []).map((t) => <option key={s(t.AssetTypeCode)} value={s(t.AssetTypeCode)}>{s(t.Name)}</option>)}</select>
        <label className="text-slate-400">Terminal 1</label><select className={`${inputClass} w-64`} value={t1} onChange={(e) => setT1(e.target.value)}><option value="">—</option>{(stationsQ.data ?? []).map((n) => <option key={s(n.EntityId)} value={s(n.EntityId).toLowerCase()}>{s(n.Name)}</option>)}</select>
        <label className="text-slate-400">Terminal 2</label><span><select className={`${inputClass} w-64`} value={t2} onChange={(e) => setT2(e.target.value)}><option value="">— (a line's far end; none for a transformer, bus or breaker) —</option>{(stationsQ.data ?? []).map((n) => <option key={s(n.EntityId)} value={s(n.EntityId).toLowerCase()}>{s(n.Name)}</option>)}</select></span>
        <label className="text-slate-400">Protected from</label><span className="text-slate-200">{s(r.ProtectedFrom) || <span className="text-slate-500">no scheme yet</span>}<span className="ml-2 text-xs text-slate-500">the stations of the schemes that name it — should be among its terminals</span></span>
        <label className="text-slate-400">Voltage</label><select className={`${inputClass} w-64`} value={f.VoltageClassCode} onChange={set('VoltageClassCode')}><option value="">—</option>{(voltagesQ.data ?? []).map((v) => <option key={s(v.VoltageClassCode)} value={s(v.VoltageClassCode)}>{s(v.VoltageClassCode)}{v.NominalKv != null ? ` · ${s(v.NominalKv)} kV` : ''}</option>)}</select>
        <label className="text-slate-400">Status</label><select className={`${inputClass} w-64`} value={f.Status} onChange={set('Status')}>{STATUSES.map((x) => <option key={x}>{x}</option>)}</select>
        <label className="text-slate-400">Notes</label><textarea className={`${inputClass} w-full`} rows={2} value={f.Notes} onChange={set('Notes')} />
      </div>
      <Button kind="primary" disabled={!dirty || busy} onClick={() => void save()}>Save</Button>
    </div>
  )
}

export default function PrimaryAssetScreen({ params: p, id }: { screen: Screen; params: RecordParams; id?: string }) {
  const navigate = useNavigate(); const can = useCan()
  const rowQ = useViewAll('asset', 'vPrimaryAsset', { [p.key]: id ?? '' }, undefined, !!id)
  const r = rowQ.data?.[0]
  const protectedByQ = useQuery({ queryKey: ['protectedBy', id], enabled: !!id, queryFn: async () => {
    const links = await viewAll('scheme', 'vSchemeProtects', { PrimaryAssetEntityId: id! })
    const out: Row[] = []
    for (const l of links) { const sc = (await view('scheme', 'vScheme', { EntityId: s(l.SchemeEntityId) }, { take: 1 })).rows[0]; out.push({ ...l, SchemeName: sc?.Name ?? '', SchemeStatus: sc?.Status ?? '' }) }
    return out
  } })
  if (!id) return <Status bad>No primary asset in the address.</Status>
  if (rowQ.isPending) return <Status>Loading the primary asset…</Status>
  if (!r) return <Status bad>No primary asset with that id is readable by you.</Status>
  const editable = can('Asset.Modify')
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2"><h1 className="text-lg font-semibold text-slate-100">{s(r.Name)}</h1><Pill tone="accent">{s(r.AssetTypeName)}</Pill><Pill tone={r.Status === 'InService' ? 'good' : 'neutral'}>{s(r.Status)}</Pill></div>
        <div className="flex gap-2">{!!r.StationNodeEntityId && <Button onClick={() => navigate(screenPath('SETTINGS_BOOK') + `?StationNodeEntityId=${r.StationNodeEntityId}`)}>Settings book</Button>}<Button onClick={() => navigate(-1)}>Close</Button></div>
      </header>
      <div className="grid gap-3 lg:grid-cols-2">
        <Panel title="Primary asset">
          {editable ? <AssetForm r={r} /> : <Facts cols={1} pairs={[['Name', s(r.Name)], ['Type', s(r.AssetTypeName)], ['Terminal 1', s(r.Terminal1StationName) || '—'], ['Terminal 2', s(r.Terminal2StationName) || '—'], ['Protected from', s(r.ProtectedFrom) || 'no scheme yet'], ['Voltage', s(r.VoltageClassCode) || '—'], ['Status', s(r.Status)], ['Notes', s(r.Notes) || '—']]} />}
          <Status>A thin record for this phase: a name, a type and where it terminates — one station for a transformer, bus or breaker, two for a line. Connectivity, impedances and, for a line, its route and structures come from the power-system model (the TLM project) in a later phase.</Status></Panel>
        <Panel title={`Protected by · ${protectedByQ.isPending ? '…' : (protectedByQ.data ?? []).length} scheme(s)`}>
          <DataGrid rows={protectedByQ.data ?? []} rowKey={(x) => s(x.EntityId)} emptyText="No scheme names this asset yet — on a scheme's page, “protects”." columns={[
            { key: 'SchemeName', label: 'Scheme', render: (x) => <a className="text-sky-300 underline" href={screenPath('SCHEME', s(x.SchemeEntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('SCHEME', s(x.SchemeEntityId))) }}>{s(x.SchemeName)}</a> },
            { key: 'ZoneRole', label: 'Zone' }, { key: 'SchemeStatus', label: 'Status' }]} />
        </Panel>
      </div>
      <ClassificationPanel subjectKind="Asset" subjectEntityId={s(r.EntityId)} editable={editable} />
    </div>
  )
}
