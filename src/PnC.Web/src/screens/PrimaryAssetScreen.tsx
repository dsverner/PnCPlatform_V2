// #170 (2026-09-16): the primary asset — a line, transformer, bus, breaker, generator, capacitor, reactor or the system —
// the subject of the applicability classifications (the owner: they belong to the primary asset a device protects, not to the
// device). In this phase the values are recorded by a person from the entity's own procedures (the CIP-002 evaluation, the
// A-10 study), with who, when and the list or study they came from; a later phase derives them. Plain React (the #167 rule).
//
// The asset has terminals, as many as it has (a capacitor one, a transformer two, a line n): a station, a voltage and the bus
// the terminal connects to. The NPCC A-10 test is a bus test (the owner): the BPS declaration is recorded on busses only and a
// line or transformer inherits it at each end from its bus. The schemes protecting the asset are listed by terminal end on the
// right, where a scheme at that station is assigned to the end it protects from.
import { useMemo, useState, type ReactNode } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ApiError, fmtWhen, s, view, viewAll, proc, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type RecordParams, type Screen, screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status, inputClass } from '@/components/ui/ui'
import { AssetCharacteristics } from '@/components/CharacteristicsPanel'
import { statusWords } from '@/lib/labels'

/** The kinds and the values in the standards' own words. The **values** are still the client's; **which kinds apply** is
 * reference data (#173, the owner 2026-09-17: "a bus is not PRC-023 applicable and has no rating") —
 * `ref.vClassificationKind.AppliesToAssetTypes` (a JSON array of AssetTypeCode, NULL = every type) decides, and
 * `DerivedByDefinitionKey` (non-null) says the platform derives the kind, so no screen offers a control for it.
 * #171 (2026-09-16): each kind names the subject it is recorded against (ref.ClassificationKind.SubjectKinds seeds the same
 * list). The CIP impact rating left the primary asset — it is the location's, and the device inherits it from where it sits. */
export const CLASSIFICATION_KINDS: { code: string; label: string; values: string[]; help: string; subject: 'asset' | 'node' | 'device' }[] = [
  { code: 'BesStatus', label: 'BES status', values: ['BES', 'Not BES'], help: 'Bulk Electric System element (NERC definition)', subject: 'asset' },
  { code: 'CipImpactRating', label: 'CIP impact rating', values: ['High', 'Medium', 'Low', 'None'], help: 'CIP-002: the impact rating of this location — every BES Cyber Asset in it inherits it', subject: 'node' },
  { code: 'NpccBulkPowerSystem', label: 'NPCC bulk power system', values: ['BPS', 'Not BPS'], help: 'This bus declared BPS (or not) by the entity\'s A-10 study; the NPCC directories then apply to the protections at it', subject: 'asset' },
  { code: 'Prc023', label: 'PRC-023', values: ['Listed', 'Not listed'], help: 'On the entity\'s PRC-023 list of impactful lines: the relay loadability calculation applies', subject: 'asset' },
  { code: 'BesCyberAsset', label: 'BES Cyber Asset', values: ['BCA', 'Not BCA'], help: 'CIP-002: a microprocessor-based device protecting a BES element is a BES Cyber Asset. Worked out from the device and what it protects, not entered by hand', subject: 'device' },
  // #171 (2026-09-17): ERC is recorded by hand until a network-analysis module can determine it
  { code: 'ExternalRoutableConnectivity', label: 'External routable connectivity', values: ['ERC', 'No ERC'], help: 'CIP-005: the device is reachable by a routable protocol from outside the electronic security perimeter. Recorded by hand', subject: 'device' },
]
/** #237: a read model's summary string ("BesStatus=BES; Prc023=Listed") as labelled pairs, each kind by its name
 * ("BES status", "PRC-023"); a kind not in the list above keeps its code. Never shown to a user as the raw string. */
export function classificationPairs(summary: unknown): { code: string; label: string; value: string }[] {
  return s(summary).split(';').map((x) => x.trim()).filter(Boolean).map((x) => {
    const at = x.indexOf('='); const code = at < 0 ? x : x.slice(0, at).trim(); const value = at < 0 ? '' : x.slice(at + 1).trim()
    return { code, label: CLASSIFICATION_KINDS.find((k) => k.code === code)?.label ?? code, value }
  })
}

/** The kinds each screen records: the primary asset's, the location node's, the device's (#171). */
export const PRIMARY_ASSET_KINDS = ['BesStatus', 'NpccBulkPowerSystem', 'Prc023']
export const NODE_KINDS = ['CipImpactRating']
export const DEVICE_KINDS = ['BesCyberAsset', 'ExternalRoutableConnectivity']

/** The reference data behind the two rules above (#173). Read once and shared by query key; a kind or type the reference
 * does not carry falls back to "it applies", so the screens keep working before the seed reaches a database. */
export const useClassificationKindRef = () => useViewAll('ref', 'vClassificationKind', {}, 'ClassificationKindCode')
export const useAssetTypeRef = () => useViewAll('ref', 'vAssetType', {}, 'AssetTypeCode')
export const bit = (v: unknown) => v === true || v === 1 || v === '1' || String(v).toLowerCase() === 'true'
/** ref.ClassificationKind.AppliesToAssetTypes: a JSON array of AssetTypeCode; NULL — or a column not yet in the view — = every type. */
export function kindApplies(kindRef: Row | undefined, assetTypeCode?: string): boolean {
  if (!assetTypeCode || !kindRef || !('AppliesToAssetTypes' in kindRef)) return true
  const raw = s(kindRef.AppliesToAssetTypes); if (!raw) return true
  try { const list: unknown = JSON.parse(raw); return Array.isArray(list) ? list.some((x) => String(x).toLowerCase() === assetTypeCode.toLowerCase()) : true } catch { return true }
}
/** ref.ClassificationKind.DerivedByDefinitionKey: non-null = the platform derives the kind, so no screen offers a control. */
export const derivedBy = (kindRef: Row | undefined) => (kindRef && 'DerivedByDefinitionKey' in kindRef ? s(kindRef.DerivedByDefinitionKey) : '')
/** ref.AssetType.CarriesRating: a bus, breaker or generator carries no Facility Rating, so its page has no Ratings panel. */
export const carriesRating = (typeRef: Row | undefined) => (typeRef && 'CarriesRating' in typeRef ? bit(typeRef.CarriesRating) : true)
const ZONES = ['Primary', 'Backup', 'BreakerFailure']   // the owner, 2026-09-16: Primary, Backup, Breaker Failure
const STATUSES = ['Planned', 'InService', 'OutOfService', 'Retired']

export function useClassifications(subjectKind: string, subjectEntityId: string) {
  return useViewAll('asset', 'vClassification', { SubjectKind: subjectKind, SubjectEntityId: subjectEntityId }, undefined, !!subjectEntityId)
}
const useTerminals = (assetId: string) => useViewAll('asset', 'vAssetTerminalDetail', { AssetEntityId: assetId }, 'TerminalNo', !!assetId)

/** The classification panel: one row per kind that applies to this subject; editable when the person may modify it.
 * `kinds` names the codes this screen records (#171: the primary asset's, the location node's, the device's).
 * #173: a kind the asset type does not carry is not shown at all (ref.ClassificationKind.AppliesToAssetTypes), and a
 * derived kind (DerivedByDefinitionKey) is a stated result with its reason and no control — every caller obeys both,
 * because both are decided here. `reasons` lets a caller put the derivation's own words beside the value: `reason` sits
 * after the value, and `label` replaces the whole line while no derived value has been written — the panel never says why
 * a value is what it is, nor what it would be, on its own. */
export interface DerivedNote { label?: ReactNode; reason?: string }
export function ClassificationPanel({ subjectKind, subjectEntityId, editable, assetTypeCode, kinds: kindCodes, title, note, reasons }: { subjectKind: string; subjectEntityId: string; editable: boolean; assetTypeCode?: string; kinds?: string[]; title?: string; note?: string; reasons?: Record<string, DerivedNote> }) {
  const qc = useQueryClient()
  const q = useClassifications(subjectKind, subjectEntityId)
  const kindRefQ = useClassificationKindRef()
  const terminalsQ = useTerminals(assetTypeCode && assetTypeCode !== 'Bus' ? subjectEntityId : '')
  // the location's CIP-002 rating for each terminal's station (#171: it is no longer the primary asset's; it is shown, not edited, here)
  const stationCipQ = useViewAll('asset', 'vClassification', { SubjectKind: 'Node', ClassificationKindCode: 'CipImpactRating' }, undefined, !!assetTypeCode && assetTypeCode !== 'Bus')
  const rows = q.data ?? []
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const current = (code: string) => rows.find((r) => s(r.ClassificationKindCode) === code)
  const kindRef = (code: string) => (kindRefQ.data ?? []).find((k) => s(k.ClassificationKindCode) === code)
  const kinds = (kindCodes
    ? kindCodes.map((c) => CLASSIFICATION_KINDS.find((k) => k.code === c)).filter((k): k is (typeof CLASSIFICATION_KINDS)[number] => !!k)
    : CLASSIFICATION_KINDS.filter((k) => k.subject === 'asset'))
    .filter((k) => kindApplies(kindRef(k.code), assetTypeCode))
  const stationCip = (nodeId: unknown) => s((stationCipQ.data ?? []).find((c) => s(c.SubjectEntityId).toLowerCase() === s(nodeId).toLowerCase())?.ClassificationValue)
  const recordOnBus = async (busId: string, busName: string, bps: boolean) => {
    try {
      await proc('asset', 'RecordClassification', { SubjectKind: 'Asset', SubjectEntityId: busId, ClassificationKindCode: 'NpccBulkPowerSystem', ClassificationValue: bps ? 'BPS' : 'Not BPS' })
      setMsg({ text: `${busName}: NPCC ${bps ? 'BPS' : 'Not BPS'} recorded on the bus.` }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vAssetTerminalDetail'] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vClassification'] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vPrimaryAsset'] })
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) }
  }
  const record = async (code: string, value: string) => {
    try {
      await proc('asset', 'RecordClassification', { SubjectKind: subjectKind, SubjectEntityId: subjectEntityId, ClassificationKindCode: code, ClassificationValue: value || null })
      setMsg({ text: `${CLASSIFICATION_KINDS.find((k) => k.code === code)?.label ?? code} ${value ? 'recorded: ' + value : 'withdrawn'}.` })
      qc.invalidateQueries({ queryKey: ['view', 'asset', 'vClassification'] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vPrimaryAsset'] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vAssetTerminalDetail'] })
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) }
  }
  return (
    <Panel title={title ?? 'Applicability classifications'}>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      <dl className="grid grid-cols-1 gap-x-6 gap-y-2 text-sm">
        {kinds.map((k) => { const c = current(k.code); const v = c ? s(c.ClassificationValue) : ''
          // #173: a derived kind is a statement, not a judgement — the value, what it was derived from, and why
          const derived = !!derivedBy(kindRef(k.code)); const why = reasons?.[k.code]?.reason; const absent = reasons?.[k.code]?.label
          return (
            <div key={k.code} className="grid grid-cols-[13rem_1fr] items-start gap-2">
              <dt className="text-slate-400" title={k.help}>{k.label}</dt>
              <dd className="min-w-0">
                {derived
                  ? c
                    ? <span className="text-slate-100">{v}{` — ${s(c.Basis) === 'Derived' ? 'derived' : 'recorded'}${why ? ': ' + why : ''}`}</span>
                    : <span className="text-slate-500">{absent ?? `not determined${why ? ' — ' + why : ''}`}</span>
                  : editable
                  ? <select className={`${inputClass} w-48`} value={v} onChange={(e) => void record(k.code, e.target.value)}>
                      <option value="">— not recorded —</option>{k.values.map((x) => <option key={x} value={x}>{x}</option>)}
                    </select>
                  : <span className={v ? 'text-slate-100' : 'text-slate-500'}>{v || 'not recorded'}</span>}
                {c && <span className="ml-2 text-xs text-slate-500">{derived ? fmtWhen(c.DeterminedAt) : `${s(c.Basis)} · ${fmtWhen(c.DeterminedAt)}`}{c.ReferenceDocumentRevisionRowId ? ' · from a filed list' : ''}</span>}
                <div className="text-xs text-slate-600">{k.help}</div>
              </dd>
            </div>) })}
        {assetTypeCode && assetTypeCode !== 'Bus' && (
          <div className="grid grid-cols-[13rem_1fr] items-start gap-2">
            <dt className="text-slate-400" title="The A-10 test is a bus test: the BPS declaration is the bus's; this element inherits it at each terminal">NPCC bulk power system</dt>
            <dd className="min-w-0 text-slate-200">
              {/* a check box per terminal (the owner, 2026-09-16): ticked = the bus at that end is declared BPS; it records on the bus itself */}
              {(terminalsQ.data ?? []).length ? (terminalsQ.data ?? []).map((t) => (
                <label key={s(t.TerminalEntityId)} className={`flex items-center gap-2 ${t.BusAssetEntityId ? '' : 'text-slate-500'}`} title={t.BusAssetEntityId ? `recorded on ${s(t.BusName)}` : 'link a bus to this terminal first'}>
                  <input type="checkbox" disabled={!editable || !t.BusAssetEntityId} checked={s(t.BusNpcc) === 'BPS'} onChange={(e) => void recordOnBus(s(t.BusAssetEntityId), s(t.BusName), e.target.checked)} />
                  <span>Terminal {s(t.TerminalNo)} · {s(t.StationName)}{t.BusAssetEntityId ? ` — ${s(t.BusName)}` : ' — no bus linked'}</span>
                  <span className="text-xs text-slate-500">{t.BusAssetEntityId ? (s(t.BusNpcc) ? `${s(t.BusNpcc)}, recorded on the bus` : 'not recorded on the bus') : ''}</span>
                </label>)) : <span className="text-slate-500">no terminals yet</span>}
              <div className="text-xs text-slate-600">Tick the box when the A-10 study declares that bus BPS; untick it for Not BPS. The declaration belongs to the bus and shows on every element connected to it.</div>
            </dd>
          </div>)}
        {assetTypeCode && assetTypeCode !== 'Bus' && (
          /* #171: the CIP-002 impact rating is the station's, not this asset's — shown per terminal, edited on the station page */
          <div className="grid grid-cols-[13rem_1fr] items-start gap-2">
            <dt className="text-slate-400" title="CIP-002: the impact rating is the station's; this asset's terminals sit at these stations">CIP impact rating (station)</dt>
            <dd className="min-w-0 text-slate-200">
              {(terminalsQ.data ?? []).length ? (terminalsQ.data ?? []).map((t) => (
                <div key={s(t.TerminalEntityId)} className="flex flex-wrap items-center gap-2">
                  <span>Terminal {s(t.TerminalNo)} · <NodeLink id={s(t.StationNodeEntityId)} name={s(t.StationName)} /></span>
                  <span className="text-xs text-slate-500">{stationCipQ.isPending ? '…' : stationCip(t.StationNodeEntityId) || 'not recorded on the station'}</span>
                </div>)) : <span className="text-slate-500">no terminals yet</span>}
              {/* #171 (2026-09-16): the rating is the station's, recorded there */}
              <div className="text-xs text-slate-600">The rating is recorded on the station. Every BES Cyber Asset at it takes that rating. Open the station to record it.</div>
            </dd>
          </div>)}
      </dl>
      {/* #170, #173: recorded by hand now; derived later, and both are kept */}
      <Status>{note ?? (editable ? 'Record each value from the entity\'s own CIP-002 evaluation, its A-10 study (the BPS declaration, on busses) and its PRC-023 list.' : 'The values recorded here. You may not change them.')}</Status>
    </Panel>
  )
}

/** A location node's name as a link to its page (#171; #173: the LOCATION screen takes any node type, not stations only). */
export function NodeLink({ id, name }: { id: string; name: string }) {
  const navigate = useNavigate()
  if (!id) return <span>{name || '—'}</span>
  return <a className="text-sky-300 underline" href={screenPath('LOCATION', id)} onClick={(e) => { e.preventDefault(); navigate(screenPath('LOCATION', id)) }}>{name || id.slice(0, 8)}</a>
}

/** The line ratings the PRC-023 criteria are judged against (#171). Hand-entered until the ratings connector exists: the
 * owner, 2026-09-16 — "make room for the given values in our application", the DMZ connector comes later and writes its own
 * SourceSystem. asset.AssetRating_Add / _Revise / _SoftDelete; a change saves at once, audited. */
const RATING_KINDS: [string, string][] = [
  ['Continuous', 'continuous'], ['FourHour', '4-hour'], ['FifteenMinute', '15-minute'], ['PracticalLimitation', 'practical limitation, R3'],
]
const SEASONS = ['Summer', 'Winter', 'Spring', 'Fall', 'All']
function Ratings({ r, editable }: { r: Row; editable: boolean }) {
  const qc = useQueryClient()
  const q = useViewAll('asset', 'vAssetRatingDetail', { AssetEntityId: s(r.EntityId) }, 'RatingKind', !!r.EntityId)
  const rows = q.data ?? []
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null); const [busy, setBusy] = useState(false)
  const [add, setAdd] = useState({ RatingKind: '', Season: 'Summer', Amperes: '' })
  const run = async (what: () => Promise<unknown>, text: string) => {
    setBusy(true)
    try { await what(); setMsg({ text }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vAssetRatingDetail'] }) }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const label = (k: unknown) => RATING_KINDS.find(([c]) => c === s(k))?.[1] ?? s(k)
  // the revise proc takes every column (as AssetTerminal_Revise does); the patch names what changed
  const revise = (x: Row, patch: Row, text: string) => run(() => proc('asset', 'AssetRating_Revise', {
    EntityId: x.RatingEntityId, AssetEntityId: r.EntityId, RatingKind: x.RatingKind, Season: x.Season,
    Amperes: x.Amperes, Source: x.Source ?? null, Notes: x.Notes ?? null, ...patch }), text)
  const removeRating = (x: Row) => run(() => proc('asset', 'AssetRating_SoftDelete', { EntityId: x.RatingEntityId }), `${label(x.RatingKind)} ${s(x.Season)} removed.`)
  const addRating = () => run(async () => {
    await proc('asset', 'AssetRating_Add', { AssetEntityId: r.EntityId, RatingKind: add.RatingKind, Season: add.Season, Amperes: Number(add.Amperes) })
    setAdd({ RatingKind: '', Season: 'Summer', Amperes: '' })
  }, `${label(add.RatingKind)} ${add.Season}: ${add.Amperes} A added.`)
  return (
    <Panel title={`Ratings · ${q.isPending ? '…' : rows.length}`}>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      <div className="space-y-1 text-sm">
        {rows.map((x) => (
          <div key={s(x.RatingEntityId)} className="flex flex-wrap items-center gap-2">
            {editable ? <>
              <select className={`${inputClass} w-48`} value={s(x.RatingKind)} disabled={busy} onChange={(e) => void revise(x, { RatingKind: e.target.value }, `${label(e.target.value)} rating saved.`)}>{RATING_KINDS.map(([c, l]) => <option key={c} value={c}>{l}</option>)}</select>
              <select className={`${inputClass} w-28`} value={s(x.Season)} disabled={busy} onChange={(e) => void revise(x, { Season: e.target.value }, `${label(x.RatingKind)} ${e.target.value} saved.`)}>{SEASONS.map((v) => <option key={v}>{v}</option>)}</select>
              <input className={`${inputClass} w-28`} type="number" defaultValue={s(x.Amperes)} disabled={busy} title="amperes" onBlur={(e) => { if (e.target.value !== s(x.Amperes) && e.target.value !== '') void revise(x, { Amperes: Number(e.target.value) }, `${label(x.RatingKind)} ${s(x.Season)}: ${e.target.value} A saved.`) }} />
              <span className="text-xs text-slate-500">A</span>
              <input className={`${inputClass} w-64`} defaultValue={s(x.Source)} disabled={busy} placeholder="the document or system the value came from" onBlur={(e) => { if (e.target.value !== s(x.Source)) void revise(x, { Source: e.target.value || null }, `${label(x.RatingKind)} ${s(x.Season)}: source saved.`) }} />
              <span className="text-xs text-slate-500">{s(x.SourceSystem)}</span>
              <Button kind="mini" disabled={busy} onClick={() => void removeRating(x)}>remove</Button>
            </> : <span>{label(x.RatingKind)} · {s(x.Season)} · {s(x.Amperes)} A{x.Source ? ` · ${s(x.Source)}` : ''} <span className="text-xs text-slate-500">{s(x.SourceSystem)}</span></span>}
          </div>))}
        {!rows.length && !q.isPending && <div className="text-xs text-slate-500">No rating recorded. Add the 4-hour, 15-minute and practical-limitation ratings: PRC-023 criteria 1, 2 and 13 are judged against them, and are skipped without them.</div>}
        {editable && (
          <div className="flex flex-wrap items-center gap-2">
            <select className={`${inputClass} w-48`} value={add.RatingKind} disabled={busy} onChange={(e) => setAdd({ ...add, RatingKind: e.target.value })}><option value="">— a rating kind —</option>{RATING_KINDS.map(([c, l]) => <option key={c} value={c}>{l}</option>)}</select>
            <select className={`${inputClass} w-28`} value={add.Season} disabled={busy} onChange={(e) => setAdd({ ...add, Season: e.target.value })}>{SEASONS.map((v) => <option key={v}>{v}</option>)}</select>
            <input className={`${inputClass} w-28`} type="number" value={add.Amperes} disabled={busy} placeholder="amperes" onChange={(e) => setAdd({ ...add, Amperes: e.target.value })} />
            <Button kind="mini" disabled={busy || !add.RatingKind || !add.Amperes} onClick={() => void addRating()}>+ rating</Button>
          </div>)}
      </div>
      {/* #171: hand-entered until the ratings connector exists, when the values come from the ratings database */}
      <Status>Enter each rating by hand, with the document or system the value came from.</Status>
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
        <label className="text-slate-400">Status</label><span><select className={`${inputClass} w-64`} value={f.Status} onChange={set('Status')}>{STATUSES.map((x) => <option key={x} value={x}>{statusWords(x)}</option>)}</select><span className="ml-2 text-xs text-slate-500">the asset as a whole, not a terminal</span></span>
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
  const removeTerminal = (x: Row) => run(() => proc('asset', 'AssetTerminal_SoftDelete', { EntityId: x.TerminalEntityId }), `terminal ${s(x.TerminalNo)} removed.`)
  const addTerminal = () => run(async () => {
    await proc('asset', 'AssetTerminal_Add', { AssetEntityId: r.EntityId, TerminalNo: nextNo, StationNodeEntityId: adding, VoltageClassCode: addVolt || null })
    setAdding(''); setAddVolt('')
  }, `terminal ${nextNo}: ${name(adding)}${addVolt ? ' ' + addVolt : ''}.`)
  if (readOnly) return <span>{rows.length ? rows.map((x, i) => <span key={s(x.TerminalEntityId)}>{i > 0 ? ' – ' : ''}<NodeLink id={s(x.StationNodeEntityId)} name={s(x.StationName)} />{x.VoltageClassCode ? <span className="ml-1 text-xs text-slate-400">{s(x.VoltageClassCode)}</span> : null}</span>) : '—'}</span>
  return (
    <div className="space-y-1">
      {rows.map((x) => (
        <div key={s(x.TerminalEntityId)} className="flex flex-wrap items-center gap-2">
          <span className="w-6 text-xs text-slate-500">{s(x.TerminalNo)}</span>
          <select className={`${inputClass} w-64`} value={s(x.StationNodeEntityId).toLowerCase()} disabled={busy} onChange={(e) => void revise(x, { StationNodeEntityId: e.target.value, BusAssetEntityId: null }, `terminal ${s(x.TerminalNo)}: ${name(e.target.value)}.`)}>
            {(stationsQ.data ?? []).map((n) => <option key={s(n.EntityId)} value={s(n.EntityId).toLowerCase()}>{s(n.Name)}</option>)}
          </select>
          <select className={`${inputClass} w-28`} value={s(x.VoltageClassCode)} disabled={busy} title="the voltage at this terminal" onChange={(e) => void revise(x, { VoltageClassCode: e.target.value || null }, `terminal ${s(x.TerminalNo)}: ${e.target.value || 'no voltage'}.`)}><option value="">— kV —</option>{!!x.VoltageClassCode && !(voltagesQ.data ?? []).some((v) => s(v.VoltageClassCode) === s(x.VoltageClassCode)) && <option value={s(x.VoltageClassCode)}>{s(x.VoltageClassCode)} (retired)</option>}{voltageOptions}</select>
          {r.AssetTypeCode !== 'Bus' && <select className={`${inputClass} w-56`} value={s(x.BusAssetEntityId).toLowerCase()} disabled={busy} title="the bus this terminal connects to (the NPCC A-10 declaration is the bus's)" onChange={(e) => void revise(x, { BusAssetEntityId: e.target.value || null }, `terminal ${s(x.TerminalNo)}: bus ${bussesAt(x.StationNodeEntityId).find((b) => s(b.EntityId).toLowerCase() === e.target.value)?.Name ?? 'none'}.`)}>
            <option value="">— bus at {s(x.StationName)} —</option>{bussesAt(x.StationNodeEntityId).map((b) => <option key={s(b.EntityId)} value={s(b.EntityId).toLowerCase()}>{s(b.Name)}{b.Classifications ? ` (${classificationPairs(b.Classifications).map((p) => `${p.label}: ${p.value}`).join(', ')})` : ''}</option>)}
          </select>}
          <NodeLink id={s(x.StationNodeEntityId)} name="the station" />
          <Button kind="mini" disabled={busy} onClick={() => void removeTerminal(x)}>remove</Button>
        </div>))}
      <div className="flex flex-wrap items-center gap-2">
        <span className="w-6 text-xs text-slate-500">{nextNo}</span>
        <select className={`${inputClass} w-64`} value={adding} disabled={busy} onChange={(e) => setAdding(e.target.value)}><option value="">— choose a station —</option>{(stationsQ.data ?? []).map((n) => <option key={s(n.EntityId)} value={s(n.EntityId).toLowerCase()}>{s(n.Name)}</option>)}</select>
        <select className={`${inputClass} w-28`} value={addVolt} disabled={busy} title="the voltage at this terminal" onChange={(e) => setAddVolt(e.target.value)}><option value="">— kV —</option>{voltageOptions}</select>
        <Button kind="mini" disabled={!adding || busy} onClick={() => void addTerminal()}>+ terminal</Button>
      </div>
      {msg && <div className="text-xs text-slate-400">{msg}</div>}
      {!rows.length && !q.isPending && <div className="text-xs text-slate-500">No terminal yet — a capacitor or reactor has one, a transformer two, a line two or more.</div>}
      {r.AssetTypeCode !== 'Bus' && rows.length > 0 && !bussesQ.isPending && (bussesQ.data ?? []).length === 0 && <div className="text-xs text-slate-500">No bus is recorded yet. Create the station's busses as primary assets of type Bus, then link each terminal to its bus for the NPCC declaration.</div>}
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
  const tie = (l: Row, t: Row) => run(() => proc('scheme', 'SchemeProtects_Revise', { EntityId: l.EntityId, SchemeEntityId: l.SchemeEntityId, PrimaryAssetEntityId: r.EntityId, ZoneRole: l.ZoneRole, AssetTerminalEntityId: t.TerminalEntityId }), `${s(l.SchemeName)} tied to terminal ${s(t.TerminalNo)}.`)
  const drop = (l: Row) => run(() => proc('scheme', 'SchemeProtects_SoftDelete', { EntityId: l.EntityId }), `${s(l.SchemeName)} no longer listed.`)
  const linksAt = (t: Row) => links.filter((l) => (l.AssetTerminalEntityId ? s(l.AssetTerminalEntityId).toLowerCase() === s(t.TerminalEntityId).toLowerCase() : (l.StationIds as string[]).includes(s(t.StationNodeEntityId).toLowerCase())))
  const untied = links.filter((l) => !terminals.some((t) => linksAt(t).includes(l)))
  const schemeLink = (l: Row) => <a className="text-sky-300 underline" href={screenPath('SCHEME', s(l.SchemeEntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('SCHEME', s(l.SchemeEntityId))) }}>{s(l.SchemeName) || s(l.SchemeEntityId).slice(0, 8)}</a>
  return (
    <Panel title={`Protected by · ${linksQ.isPending ? '…' : links.length} scheme(s)`}>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      {!terminals.length && <Status>No terminal yet. Add the asset's terminals first, then assign the protection at each end here.</Status>}
      <ul className="space-y-2 text-sm">
        {terminals.map((t) => (
          <li key={s(t.TerminalEntityId)}>
            {/* #237: the end, then its bus on a line of its own — not one run of facts */}
            <div className="font-semibold text-slate-200">Terminal {s(t.TerminalNo)} at {s(t.StationName)}{t.VoltageClassCode ? <span className="font-normal text-slate-400">, {s(t.VoltageClassCode)}</span> : ''}</div>
            <div className="text-xs text-slate-400">Bus: {t.BusName ? <>{s(t.BusName)} <span className="text-slate-500">— NPCC:</span> {s(t.BusNpcc) || <span className="text-slate-500">not recorded</span>}</> : <span className="text-slate-500">none linked</span>}</div>
            <ul className="ml-4 mt-1 space-y-1">
              {linksAt(t).map((l) => <li key={s(l.EntityId)} className="flex items-center gap-2">└ {schemeLink(l)} <span className="text-xs text-slate-500">{s(l.ZoneRole) === 'BreakerFailure' ? 'breaker failure' : s(l.ZoneRole).toLowerCase()}{l.AssetTerminalEntityId ? '' : ' · by station'}</span>
                {editable && !l.AssetTerminalEntityId && <Button kind="mini" disabled={busy} onClick={() => void tie(l, t)}>tie to this end</Button>}
                {editable && <Button kind="mini" disabled={busy} onClick={() => void drop(l)}>remove</Button>}</li>)}
              {!linksAt(t).length && <li className="text-xs text-slate-500">└ no protection assigned at this end</li>}
              {editable && <li><AssignRow t={t} pick={pick[s(t.TerminalEntityId)] ?? ''} zone={zone[s(t.TerminalEntityId)] ?? 'Primary'} busy={busy} exclude={linksAt(t).map((l) => s(l.SchemeEntityId).toLowerCase())}
                onPick={(v) => setPick({ ...pick, [s(t.TerminalEntityId)]: v })} onZone={(v) => setZone({ ...zone, [s(t.TerminalEntityId)]: v })}
                onAssign={(schemeId, schemeName, z) => void run(async () => { await proc('scheme', 'SchemeProtects_Add', { SchemeEntityId: schemeId, PrimaryAssetEntityId: r.EntityId, ZoneRole: z, AssetTerminalEntityId: t.TerminalEntityId }); setPick({ ...pick, [s(t.TerminalEntityId)]: '' }) }, `${schemeName} protects ${s(r.Name)} from terminal ${s(t.TerminalNo)} (${z.toLowerCase()}).`)} /></li>}
            </ul>
          </li>))}
        {untied.length > 0 && (
          <li><div className="font-semibold text-amber-300">Not tied to a terminal</div>
            <ul className="ml-4 mt-1 space-y-1">{untied.map((l) => <li key={s(l.EntityId)} className="flex items-center gap-2">└ {schemeLink(l)} <span className="text-xs text-slate-500">{s(l.ZoneRole).toLowerCase()} — the scheme's station is not one of the terminals</span>
              {editable && terminals.length > 0 && <select className={`${inputClass} w-40`} disabled={busy} defaultValue="" onChange={(e) => { const t = terminals.find((x) => s(x.TerminalEntityId) === e.target.value); if (t) void tie(l, t) }}><option value="">tie to terminal…</option>{terminals.map((t) => <option key={s(t.TerminalEntityId)} value={s(t.TerminalEntityId)}>{s(t.TerminalNo)} · {s(t.StationName)}</option>)}</select>}
              {editable && <Button kind="mini" disabled={busy} onClick={() => void drop(l)}>remove</Button>}</li>)}</ul></li>)}
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
      <select className={`${inputClass} w-24`} value={zone} disabled={busy} title="the zone of the scheme you are about to assign" onChange={(e) => onZone(e.target.value)}>{ZONES.map((z) => <option key={z} value={z}>{z === 'BreakerFailure' ? 'Breaker failure' : z}</option>)}</select>
      {/* choosing a scheme assigns it at once — like every other drop-down on this page (the owner picked one and waited, 2026-09-16) */}
      <select className={`${inputClass} w-56`} value={pick} disabled={busy} onChange={(e) => { const v = e.target.value; onPick(v); if (v) onAssign(v, s(options.find((x) => s(x.SchemeEntityId) === v)?.SchemeName), zone) }}><option value="">— a scheme at {s(t.StationName)}: choose to assign —</option>{options.map((x) => <option key={s(x.SchemeEntityId)} value={s(x.SchemeEntityId)}>{s(x.SchemeName)}</option>)}</select>
    </div>
  )
}

export default function PrimaryAssetScreen({ params: p, id }: { screen: Screen; params: RecordParams; id?: string }) {
  const navigate = useNavigate(); const can = useCan()
  const rowQ = useViewAll('asset', 'vPrimaryAsset', { [p.key]: id ?? '' }, undefined, !!id)
  const typesQ = useAssetTypeRef()
  const r = rowQ.data?.[0]
  if (!id) return <Status bad>No primary asset was named. Pick one from Primary assets.</Status>
  if (rowQ.isPending) return <Status>Loading the primary asset…</Status>
  if (!r) return <Status bad>You may not read this primary asset.</Status>
  const editable = can('Asset.Modify')
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2"><h1 className="text-lg font-semibold text-slate-100">{s(r.Name)}</h1><Pill tone="accent">{s(r.AssetTypeName)}</Pill><Pill tone={r.Status === 'InService' ? 'good' : 'neutral'}>{statusWords(r.Status)}</Pill></div>
        <div className="flex gap-2"><Button onClick={() => navigate(-1)}>Close</Button></div>
      </header>
      <div className="grid gap-3 lg:grid-cols-2">
        <Panel title="Primary asset">
          {editable ? <AssetForm r={r} /> : <Facts cols={1} pairs={[['Name', s(r.Name)], ['Type', s(r.AssetTypeName)], ['Terminals', <Terminals r={r} readOnly />], ['Status', s(r.Status)], ['Notes', s(r.Notes) || '—']]} />}
          {/* #170: connectivity, impedances and a line's route come from the power-system model (the TLM project) later */}
          <Status>A name, a type and its terminals: one station for a capacitor or reactor, two for a transformer, two or more for a line. Each terminal carries its voltage and the bus it connects to.</Status></Panel>
        <ProtectedBy r={r} editable={can('Scheme.Modify')} />
      </div>
      {s(r.AssetTypeCode) === 'Line' && <LineImpedance r={r} editable={editable} />}   {/* #219 */}
      <ClassificationPanel subjectKind="Asset" subjectEntityId={s(r.EntityId)} editable={editable} assetTypeCode={s(r.AssetTypeCode)} kinds={PRIMARY_ASSET_KINDS} />
      {/* #173 (the owner, 2026-09-17): a bus has no rating — the Ratings panel belongs to the asset types that carry one
          (ref.AssetType.CarriesRating), because the rating exists to answer PRC-023 R1's criteria 1, 2 and 13. */}
      {!typesQ.isPending && carriesRating((typesQ.data ?? []).find((t) => s(t.AssetTypeCode) === s(r.AssetTypeCode))) && <Ratings r={r} editable={editable} />}
    </div>
  )
}

/** #219 (the owner, 2026-09-21): the line's impedance and length live on the line, not in a relay's settings — the type's default
 * template (LINE_Template, tools/template_line.py) through the guarded save (asset.SetAssetCharacteristic, #216). */
function LineImpedance({ r, editable }: { r: Row; editable: boolean }) {
  const typeQ = useViewAll('ref', 'vAssetType', { AssetTypeCode: 'Line' }, undefined, true)
  const template = s(typeQ.data?.[0]?.DefaultTemplateDefinitionEntityId)
  // the line template (LINE_Template, seeded by tools/template_line.py) has not reached this database yet
  if (!template) return <Panel title="Impedance"><Status>{typeQ.isPending ? 'Loading the line template…' : 'No impedance sheet is set up for lines yet. An administrator sets it up before impedance can be recorded here.'}</Status></Panel>
  return <AssetCharacteristics assetEntityId={s(r.EntityId)} definitionEntityId={template} editable={editable} groups={['Impedance']} title="Impedance"
    note="Recorded once on the line. Every relay rationale on this line reads it: R1, X1, R0, X0 in ohms primary end to end, and the length in miles. The legacy rationales wrote Z1 = R1 + jX1." />
}
