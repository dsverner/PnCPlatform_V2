// #170 (2026-09-16): the primary asset — a line, transformer, bus, breaker, generator, capacitor, reactor or the system —
// the subject of the applicability classifications (the owner: they belong to the primary asset a device protects, not to the
// device). In this phase the values are recorded by a person from the entity's own procedures (the CIP-002 evaluation, the
// A-10 study), with who, when and the list or study they came from; a later phase derives them. Plain React (the #167 rule).
//
// The asset has terminals, as many as it has (a capacitor one, a transformer two, a line n): a station, a voltage and the bus
// the terminal connects to. The NPCC A-10 test is a bus test (the owner): the BPS declaration is recorded on busses only and a
// line or transformer inherits it at each end from its bus. The schemes protecting the asset are listed by terminal end on the
// right, where a scheme at that station is assigned to the end it protects from.
import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ApiError, fmtWhen, s, view, viewAll, proc, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type RecordParams, type Screen, screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status, inputClass } from '@/components/ui/ui'

/** The kinds and the values in the standards' own words (a later phase's derivation writes the same values with Basis Derived).
 * NPCC BPS applies to a bus only — the A-10 test is a bus test; every other element inherits it at its terminals. */
export const CLASSIFICATION_KINDS: { code: string; label: string; values: string[]; help: string; busOnly?: boolean }[] = [
  { code: 'BesStatus', label: 'BES status', values: ['BES', 'Not BES'], help: 'Bulk Electric System element (NERC definition)' },
  { code: 'CipImpactRating', label: 'CIP impact rating', values: ['High', 'Medium', 'Low', 'None'], help: 'CIP-002: the impact rating of the BES asset this element belongs to; the cyber systems protecting it follow' },
  { code: 'NpccBulkPowerSystem', label: 'NPCC bulk power system', values: ['BPS', 'Not BPS'], help: 'This bus declared BPS (or not) by the entity\'s A-10 study; the NPCC directories then apply to the protections at it', busOnly: true },
  { code: 'Prc023', label: 'PRC-023', values: ['Listed', 'Not listed'], help: 'On the entity\'s PRC-023 list of impactful lines: the relay loadability calculation applies' },
]
const ZONES = ['Primary', 'Backup', 'Overlap']
const STATUSES = ['Planned', 'InService', 'OutOfService', 'Retired']

export function useClassifications(subjectKind: string, subjectEntityId: string) {
  return useViewAll('asset', 'vClassification', { SubjectKind: subjectKind, SubjectEntityId: subjectEntityId }, undefined, !!subjectEntityId)
}
const useTerminals = (assetId: string) => useViewAll('asset', 'vAssetTerminalDetail', { AssetEntityId: assetId }, 'TerminalNo', !!assetId)

/** The classification panel: one row per kind that applies to this type; editable when the person may modify the subject. */
export function ClassificationPanel({ subjectKind, subjectEntityId, editable, assetTypeCode }: { subjectKind: string; subjectEntityId: string; editable: boolean; assetTypeCode?: string }) {
  const qc = useQueryClient()
  const q = useClassifications(subjectKind, subjectEntityId)
  const terminalsQ = useTerminals(assetTypeCode && assetTypeCode !== 'Bus' ? subjectEntityId : '')
  const rows = q.data ?? []
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const current = (code: string) => rows.find((r) => s(r.ClassificationKindCode) === code)
  const kinds = CLASSIFICATION_KINDS.filter((k) => !k.busOnly || assetTypeCode === 'Bus' || !assetTypeCode)
  const record = async (code: string, value: string) => {
    try {
      await proc('asset', 'RecordClassification', { SubjectKind: subjectKind, SubjectEntityId: subjectEntityId, ClassificationKindCode: code, ClassificationValue: value || null })
      setMsg({ text: `${CLASSIFICATION_KINDS.find((k) => k.code === code)?.label ?? code} ${value ? 'recorded: ' + value : 'withdrawn'}.` })
      qc.invalidateQueries({ queryKey: ['view', 'asset', 'vClassification'] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vPrimaryAsset'] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vAssetTerminalDetail'] })
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) }
  }
  return (
    <Panel title="Applicability classifications">
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      <dl className="grid grid-cols-1 gap-x-6 gap-y-2 text-sm">
        {kinds.map((k) => { const c = current(k.code); const v = c ? s(c.ClassificationValue) : ''
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
        {assetTypeCode && assetTypeCode !== 'Bus' && (
          <div className="grid grid-cols-[13rem_1fr] items-start gap-2">
            <dt className="text-slate-400" title="The A-10 test is a bus test: the BPS declaration is the bus's; this element inherits it at each terminal">NPCC bulk power system</dt>
            <dd className="min-w-0 text-slate-200">
              {(terminalsQ.data ?? []).length ? (terminalsQ.data ?? []).map((t) => <div key={s(t.TerminalEntityId)}>Terminal {s(t.TerminalNo)} · {s(t.StationName)}: {t.BusAssetEntityId ? <>{s(t.BusName)} — <span className={t.BusNpcc ? 'text-slate-100' : 'text-slate-500'}>{s(t.BusNpcc) || 'not recorded on the bus'}</span></> : <span className="text-slate-500">no bus linked at this terminal</span>}</div>) : <span className="text-slate-500">no terminals yet</span>}
              <div className="text-xs text-slate-600">Inherited from the bus at each end (the A-10 study declares busses, not lines); recorded on the bus's own page.</div>
            </dd>
          </div>)}
      </dl>
      <Status>{editable ? 'Recorded by you from the entity\'s own CIP-002 evaluation, A-10 study (the BPS declaration, on busses) and PRC-023 list (this phase); the platform derives them in a later phase and keeps both. A value saves at once, audited.' : 'Recorded values; the platform derives them in a later phase.'}</Status>
    </Panel>
  )
}

/** The asset's own fields (the owner, 2026-09-16: "there needs to be a way for the user to edit these fields"). asset.Asset_Revise; audited.
 * The terminals and the voltage at each are the Terminals list; the status is the asset's as a whole. */
function AssetForm({ r }: { r: Row }) {
  const qc = useQueryClient()
  const typesQ = useViewAll('ref', 'vAssetType', { AssetClassCode: 'Primary' })
  const [f, setF] = useState({ Name: s(r.Name), AssetTypeCode: s(r.AssetTypeCode), Status: s(r.Status), Notes: s(r.Notes) })
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null); const [busy, setBusy] = useState(false)
  const dirty = f.Name !== s(r.Name) || f.AssetTypeCode !== s(r.AssetTypeCode) || f.Status !== s(r.Status) || f.Notes !== s(r.Notes)
  const save = async () => {
    if (!f.Name.trim()) { setMsg({ text: 'A name is needed.', bad: true }); return }
    setBusy(true)
    try {
      await proc('asset', 'Asset_Revise', { EntityId: r.EntityId, AssetTypeCode: f.AssetTypeCode, Name: f.Name.trim(), VoltageClassCode: r.VoltageClassCode ?? null, Status: f.Status, Notes: f.Notes || null })
      setMsg({ text: `${f.Name.trim()} saved.` }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vPrimaryAsset'] })
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  return (
    <div className="space-y-2 text-sm">
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      <div className="grid grid-cols-[8rem_1fr] items-start gap-2">
        <label className="text-slate-400">Name</label><input className={`${inputClass} w-64`} value={f.Name} onChange={set('Name')} placeholder="e.g. L0012" />
        <label className="text-slate-400">Type</label><select className={`${inputClass} w-64`} value={f.AssetTypeCode} onChange={set('AssetTypeCode')}>{(typesQ.data ?? []).map((t) => <option key={s(t.AssetTypeCode)} value={s(t.AssetTypeCode)}>{s(t.Name)}</option>)}</select>
        <label className="text-slate-400">Terminals</label><Terminals r={r} />
        <label className="text-slate-400">Status</label><span><select className={`${inputClass} w-64`} value={f.Status} onChange={set('Status')}>{STATUSES.map((x) => <option key={x}>{x}</option>)}</select><span className="ml-2 text-xs text-slate-500">the asset as a whole, not a terminal</span></span>
        <label className="text-slate-400">Notes</label><textarea className={`${inputClass} w-full`} rows={2} value={f.Notes} onChange={set('Notes')} />
      </div>
      <Button kind="primary" disabled={!dirty || busy} onClick={() => void save()}>Save</Button>
    </div>
  )
}

/** The terminals, as many as the asset has: a station, the voltage at it and the bus it connects to (busses at that station), numbered in
 * order; "+ terminal" adds one, a change saves at once, remove withdraws it (asset.AssetTerminal, audited). Which schemes protect the
 * asset from each end is the tree on the right (ProtectedBy). */
function Terminals({ r, readOnly = false }: { r: Row; readOnly?: boolean }) {
  const qc = useQueryClient()
  const stationsQ = useViewAll('location', 'vNode', { NodeTypeCode: 'Station' }, 'Name')
  const voltagesQ = useViewAll('ref', 'vVoltageClass', {}, 'DisplayOrder')
  const bussesQ = useViewAll('asset', 'vPrimaryAsset', { AssetTypeCode: 'Bus' }, 'Name')
  const q = useTerminals(s(r.EntityId))
  const [msg, setMsg] = useState<string | null>(null); const [adding, setAdding] = useState(''); const [addVolt, setAddVolt] = useState(''); const [busy, setBusy] = useState(false)
  const rows = q.data ?? []
  const done = (text: string) => { setMsg(text); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vAssetTerminalDetail'] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vPrimaryAsset'] }) }
  const run = async (what: () => Promise<unknown>, text: string) => { setBusy(true); try { await what(); done(text) } catch (e) { setMsg(e instanceof ApiError ? e.message : String(e)) } finally { setBusy(false) } }
  const nextNo = rows.reduce((m, x) => Math.max(m, Number(x.TerminalNo)), 0) + 1
  const name = (id: unknown) => s((stationsQ.data ?? []).find((n) => s(n.EntityId).toLowerCase() === s(id).toLowerCase())?.Name)
  const voltageOptions = (voltagesQ.data ?? []).map((v) => <option key={s(v.VoltageClassCode)} value={s(v.VoltageClassCode)}>{v.NominalKv != null ? `${Number(v.NominalKv)} kV` : s(v.VoltageClassCode)}</option>)
  const bussesAt = (stationId: unknown) => (bussesQ.data ?? []).filter((b) => s(b.TerminalNodeIds).toLowerCase().includes(s(stationId).toLowerCase()) && s(b.EntityId) !== s(r.EntityId))
  const revise = (x: Row, patch: Row, text: string) => run(() => proc('asset', 'AssetTerminal_Revise', { EntityId: x.TerminalEntityId, AssetEntityId: r.EntityId, TerminalNo: x.TerminalNo, StationNodeEntityId: x.StationNodeEntityId, VoltageClassCode: x.VoltageClassCode ?? null, BusAssetEntityId: x.BusAssetEntityId ?? null, ...patch }), text)
  if (readOnly) return <span>{rows.length ? rows.map((x, i) => <span key={s(x.TerminalEntityId)}>{i > 0 ? ' – ' : ''}{s(x.StationName)}{x.VoltageClassCode ? <span className="ml-1 text-xs text-slate-400">{s(x.VoltageClassCode)}</span> : null}</span>) : '—'}</span>
  return (
    <div className="space-y-1">
      {rows.map((x) => (
        <div key={s(x.TerminalEntityId)} className="flex flex-wrap items-center gap-2">
          <span className="w-6 text-xs text-slate-500">{s(x.TerminalNo)}</span>
          <select className={`${inputClass} w-64`} value={s(x.StationNodeEntityId).toLowerCase()} disabled={busy} onChange={(e) => void revise(x, { StationNodeEntityId: e.target.value, BusAssetEntityId: null }, `terminal ${s(x.TerminalNo)}: ${name(e.target.value)}.`)}>
            {(stationsQ.data ?? []).map((n) => <option key={s(n.EntityId)} value={s(n.EntityId).toLowerCase()}>{s(n.Name)}</option>)}
          </select>
          <select className={`${inputClass} w-28`} value={s(x.VoltageClassCode)} disabled={busy} title="the voltage at this terminal" onChange={(e) => void revise(x, { VoltageClassCode: e.target.value || null }, `terminal ${s(x.TerminalNo)}: ${e.target.value || 'no voltage'}.`)}><option value="">— kV —</option>{voltageOptions}</select>
          {r.AssetTypeCode !== 'Bus' && <select className={`${inputClass} w-56`} value={s(x.BusAssetEntityId).toLowerCase()} disabled={busy} title="the bus this terminal connects to (the NPCC A-10 declaration is the bus's)" onChange={(e) => void revise(x, { BusAssetEntityId: e.target.value || null }, `terminal ${s(x.TerminalNo)}: bus ${bussesAt(x.StationNodeEntityId).find((b) => s(b.EntityId).toLowerCase() === e.target.value)?.Name ?? 'none'}.`)}>
            <option value="">— bus at {s(x.StationName)} —</option>{bussesAt(x.StationNodeEntityId).map((b) => <option key={s(b.EntityId)} value={s(b.EntityId).toLowerCase()}>{s(b.Name)}{b.Classifications ? ` (${s(b.Classifications).replace('NpccBulkPowerSystem=', 'NPCC ')})` : ''}</option>)}
          </select>}
          <Button kind="mini" disabled={busy} onClick={() => void run(() => proc('asset', 'AssetTerminal_SoftDelete', { EntityId: x.TerminalEntityId }), `terminal ${s(x.TerminalNo)} removed.`)}>remove</Button>
        </div>))}
      <div className="flex flex-wrap items-center gap-2">
        <span className="w-6 text-xs text-slate-500">{nextNo}</span>
        <select className={`${inputClass} w-64`} value={adding} disabled={busy} onChange={(e) => setAdding(e.target.value)}><option value="">— choose a station —</option>{(stationsQ.data ?? []).map((n) => <option key={s(n.EntityId)} value={s(n.EntityId).toLowerCase()}>{s(n.Name)}</option>)}</select>
        <select className={`${inputClass} w-28`} value={addVolt} disabled={busy} title="the voltage at this terminal" onChange={(e) => setAddVolt(e.target.value)}><option value="">— kV —</option>{voltageOptions}</select>
        <Button kind="mini" disabled={!adding || busy} onClick={() => void run(async () => { await proc('asset', 'AssetTerminal_Add', { AssetEntityId: r.EntityId, TerminalNo: nextNo, StationNodeEntityId: adding, VoltageClassCode: addVolt || null }); setAdding(''); setAddVolt('') }, `terminal ${nextNo}: ${name(adding)}${addVolt ? ' ' + addVolt : ''}.`)}>+ terminal</Button>
      </div>
      {msg && <div className="text-xs text-slate-400">{msg}</div>}
      {!rows.length && !q.isPending && <div className="text-xs text-slate-500">No terminal yet — a capacitor or reactor has one, a transformer two, a line two or more.</div>}
      {r.AssetTypeCode !== 'Bus' && rows.length > 0 && !bussesQ.isPending && (bussesQ.data ?? []).length === 0 && <div className="text-xs text-slate-500">No bus is recorded yet: create the station's busses as primary assets of type Bus (Primary assets, or a scheme's page) and link each terminal to its bus for the NPCC declaration.</div>}
    </div>
  )
}

/** The schemes protecting the asset, by terminal end (the owner, 2026-09-16: a tree per terminal, where protection is assigned to the end
 * it protects from). A link names its terminal (SchemeProtects.AssetTerminalEntityId); an older link without one is shown under the
 * terminal whose station is the scheme's, else under "not tied to a terminal", with a way to tie it. */
function ProtectedBy({ r, editable }: { r: Row; editable: boolean }) {
  const qc = useQueryClient(); const navigate = useNavigate()
  const terminalsQ = useTerminals(s(r.EntityId))
  const linksQ = useQuery({ queryKey: ['protectedBy', s(r.EntityId)], enabled: !!r.EntityId, queryFn: async () => {
    const links = await viewAll('scheme', 'vSchemeProtects', { PrimaryAssetEntityId: s(r.EntityId) })
    const out: Row[] = []
    for (const l of links) {
      const st = (await view('scheme', 'vSchemeStation', { SchemeEntityId: s(l.SchemeEntityId) }, { take: 5 })).rows
      out.push({ ...l, SchemeName: s(st[0]?.SchemeName) || (await view('scheme', 'vScheme', { EntityId: s(l.SchemeEntityId) }, { take: 1 })).rows[0]?.Name, SchemeStatus: st[0]?.SchemeStatus, StationIds: st.map((x) => s(x.StationNodeEntityId).toLowerCase()) })
    }
    return out
  } })
  const [pick, setPick] = useState<Record<string, string>>({}); const [zone, setZone] = useState<Record<string, string>>({})
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null); const [busy, setBusy] = useState(false)
  const terminals = terminalsQ.data ?? []; const links = linksQ.data ?? []
  const refresh = () => { qc.invalidateQueries({ queryKey: ['protectedBy', s(r.EntityId)] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vAssetTerminalDetail'] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vPrimaryAsset'] }) }
  const run = async (what: () => Promise<unknown>, text: string) => { setBusy(true); try { await what(); setMsg({ text }); refresh() } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) } }
  const linksAt = (t: Row) => links.filter((l) => (l.AssetTerminalEntityId ? s(l.AssetTerminalEntityId).toLowerCase() === s(t.TerminalEntityId).toLowerCase() : (l.StationIds as string[]).includes(s(t.StationNodeEntityId).toLowerCase())))
  const untied = links.filter((l) => !terminals.some((t) => linksAt(t).includes(l)))
  const schemeLink = (l: Row) => <a className="text-sky-300 underline" href={screenPath('SCHEME', s(l.SchemeEntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('SCHEME', s(l.SchemeEntityId))) }}>{s(l.SchemeName) || s(l.SchemeEntityId).slice(0, 8)}</a>
  return (
    <Panel title={`Protected by · ${linksQ.isPending ? '…' : links.length} scheme(s)`}>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      {!terminals.length && <Status>Add the asset's terminals first; the protection at each end is assigned here.</Status>}
      <ul className="space-y-2 text-sm">
        {terminals.map((t) => (
          <li key={s(t.TerminalEntityId)}>
            <div className="font-semibold text-slate-200">Terminal {s(t.TerminalNo)} · {s(t.StationName)}{t.VoltageClassCode ? ` · ${s(t.VoltageClassCode)}` : ''}{t.BusName ? <span className="ml-2 text-xs font-normal text-slate-400">bus {s(t.BusName)}{t.BusNpcc ? ` · NPCC ${s(t.BusNpcc)}` : ''}</span> : null}</div>
            <ul className="ml-4 mt-1 space-y-1">
              {linksAt(t).map((l) => <li key={s(l.EntityId)} className="flex items-center gap-2">└ {schemeLink(l)} <span className="text-xs text-slate-500">{s(l.ZoneRole).toLowerCase()}{l.AssetTerminalEntityId ? '' : ' · by station'}</span>
                {editable && !l.AssetTerminalEntityId && <Button kind="mini" disabled={busy} onClick={() => void run(() => proc('scheme', 'SchemeProtects_Revise', { EntityId: l.EntityId, SchemeEntityId: l.SchemeEntityId, PrimaryAssetEntityId: r.EntityId, ZoneRole: l.ZoneRole, AssetTerminalEntityId: t.TerminalEntityId }), `${s(l.SchemeName)} tied to terminal ${s(t.TerminalNo)}.`)}>tie to this end</Button>}
                {editable && <Button kind="mini" disabled={busy} onClick={() => void run(() => proc('scheme', 'SchemeProtects_SoftDelete', { EntityId: l.EntityId }), `${s(l.SchemeName)} no longer listed.`)}>remove</Button>}</li>)}
              {!linksAt(t).length && <li className="text-xs text-slate-500">└ no protection assigned at this end</li>}
              {editable && <li><AssignRow t={t} pick={pick[s(t.TerminalEntityId)] ?? ''} zone={zone[s(t.TerminalEntityId)] ?? 'Primary'} busy={busy} exclude={linksAt(t).map((l) => s(l.SchemeEntityId).toLowerCase())}
                onPick={(v) => setPick({ ...pick, [s(t.TerminalEntityId)]: v })} onZone={(v) => setZone({ ...zone, [s(t.TerminalEntityId)]: v })}
                onAssign={(schemeId, schemeName, z) => void run(async () => { await proc('scheme', 'SchemeProtects_Add', { SchemeEntityId: schemeId, PrimaryAssetEntityId: r.EntityId, ZoneRole: z, AssetTerminalEntityId: t.TerminalEntityId }); setPick({ ...pick, [s(t.TerminalEntityId)]: '' }) }, `${schemeName} protects ${s(r.Name)} from terminal ${s(t.TerminalNo)} (${z.toLowerCase()}).`)} /></li>}
            </ul>
          </li>))}
        {untied.length > 0 && (
          <li><div className="font-semibold text-amber-300">Not tied to a terminal</div>
            <ul className="ml-4 mt-1 space-y-1">{untied.map((l) => <li key={s(l.EntityId)} className="flex items-center gap-2">└ {schemeLink(l)} <span className="text-xs text-slate-500">{s(l.ZoneRole).toLowerCase()} — the scheme's station is not one of the terminals</span>
              {editable && terminals.length > 0 && <select className={`${inputClass} w-40`} disabled={busy} defaultValue="" onChange={(e) => { const t = terminals.find((x) => s(x.TerminalEntityId) === e.target.value); if (t) void run(() => proc('scheme', 'SchemeProtects_Revise', { EntityId: l.EntityId, SchemeEntityId: l.SchemeEntityId, PrimaryAssetEntityId: r.EntityId, ZoneRole: l.ZoneRole, AssetTerminalEntityId: t.TerminalEntityId }), `${s(l.SchemeName)} tied to terminal ${s(t.TerminalNo)}.`) }}><option value="">tie to terminal…</option>{terminals.map((t) => <option key={s(t.TerminalEntityId)} value={s(t.TerminalEntityId)}>{s(t.TerminalNo)} · {s(t.StationName)}</option>)}</select>}
              {editable && <Button kind="mini" disabled={busy} onClick={() => void run(() => proc('scheme', 'SchemeProtects_SoftDelete', { EntityId: l.EntityId }), `${s(l.SchemeName)} no longer listed.`)}>remove</Button>}</li>)}</ul></li>)}
      </ul>
    </Panel>
  )
}

/** One "assign a scheme at this station" row under a terminal: the schemes whose devices sit at the terminal's station, not yet linked here. */
function AssignRow({ t, pick, zone, busy, exclude, onPick, onZone, onAssign }: { t: Row; pick: string; zone: string; busy: boolean; exclude: string[]; onPick: (v: string) => void; onZone: (v: string) => void; onAssign: (schemeId: string, schemeName: string, zone: string) => void }) {
  const q = useViewAll('scheme', 'vSchemeStation', { StationNodeEntityId: s(t.StationNodeEntityId) }, 'SchemeName', !!t.StationNodeEntityId)
  const options = useMemo(() => (q.data ?? []).filter((x) => !exclude.includes(s(x.SchemeEntityId).toLowerCase())), [q.data, exclude])
  return (
    <div className="flex flex-wrap items-center gap-2 text-xs">
      <span className="text-slate-500">└ assign</span>
      <select className={`${inputClass} w-56`} value={pick} disabled={busy} onChange={(e) => onPick(e.target.value)}><option value="">— a scheme at {s(t.StationName)} —</option>{options.map((x) => <option key={s(x.SchemeEntityId)} value={s(x.SchemeEntityId)}>{s(x.SchemeName)}</option>)}</select>
      <select className={`${inputClass} w-24`} value={zone} disabled={busy} onChange={(e) => onZone(e.target.value)}>{ZONES.map((z) => <option key={z}>{z}</option>)}</select>
      <Button kind="mini" disabled={!pick || busy} onClick={() => onAssign(pick, s(options.find((x) => s(x.SchemeEntityId) === pick)?.SchemeName), zone)}>protects from here</Button>
    </div>
  )
}

export default function PrimaryAssetScreen({ params: p, id }: { screen: Screen; params: RecordParams; id?: string }) {
  const navigate = useNavigate(); const can = useCan()
  const rowQ = useViewAll('asset', 'vPrimaryAsset', { [p.key]: id ?? '' }, undefined, !!id)
  const r = rowQ.data?.[0]
  if (!id) return <Status bad>No primary asset in the address.</Status>
  if (rowQ.isPending) return <Status>Loading the primary asset…</Status>
  if (!r) return <Status bad>No primary asset with that id is readable by you.</Status>
  const editable = can('Asset.Modify')
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2"><h1 className="text-lg font-semibold text-slate-100">{s(r.Name)}</h1><Pill tone="accent">{s(r.AssetTypeName)}</Pill><Pill tone={r.Status === 'InService' ? 'good' : 'neutral'}>{s(r.Status)}</Pill></div>
        <div className="flex gap-2"><Button onClick={() => navigate(-1)}>Close</Button></div>
      </header>
      <div className="grid gap-3 lg:grid-cols-2">
        <Panel title="Primary asset">
          {editable ? <AssetForm r={r} /> : <Facts cols={1} pairs={[['Name', s(r.Name)], ['Type', s(r.AssetTypeName)], ['Terminals', <Terminals r={r} readOnly />], ['Status', s(r.Status)], ['Notes', s(r.Notes) || '—']]} />}
          <Status>A thin record for this phase: a name, a type and its terminals — one station for a capacitor or reactor, two for a transformer, two or more for a line — each with its voltage and the bus it connects to. Connectivity, impedances and, for a line, its route and structures come from the power-system model (the TLM project) in a later phase.</Status></Panel>
        <ProtectedBy r={r} editable={can('Scheme.Modify')} />
      </div>
      <ClassificationPanel subjectKind="Asset" subjectEntityId={s(r.EntityId)} editable={editable} assetTypeCode={s(r.AssetTypeCode)} />
    </div>
  )
}
