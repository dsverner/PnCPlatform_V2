// #201 (2026-09-19): an instrument transformer as equipment in its own right — the vision §4.3 (auxiliary equipment
// first-class in Phase 1: "a relay setting is expressed against the instrument transformers that feed it") and §10.1
// (CTs and PTs/VTs are Hybrid: one foot at primary voltage). The owner, 2026-09-19: "Instrument transformers should be first
// class devices in their own right with testing (saturation curves, ratio and polarity etc.)."
// #206 (2026-09-20): the owner: "the application must [allow] the editing/adding/deleting etc. of instrument transformers
// so that the user can also manually correct any outliers" — most transformers now come from the migration rule, unplaced
// and with what the legacy record declared. So the page edits the equipment (asset.Asset_Revise), places it (a yard of its
// station, made here when the station has none — location.AddNode — then asset.PlaceAsset; a panel for an auxiliary),
// works its scheme memberships (in service, the connection note, remove: SchemeSourceActions), retires it
// (Asset_Revise, Status Retired) and deletes it (asset.Asset_SoftDelete) once no scheme names it.
// What the page shows: what it is and where it is, its nameplate (the CT_Template / VT_Template characteristics, editable),
// the schemes it feeds, and its tests (#204). Plain React (#167); the INSTRUMENT_TRANSFORMER definition names
// asset.vInstrumentTransformer and this component reads it.
import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ApiError, fmtDate, fmtWhen, proc, s, view, viewAll, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { workTypes, raiseAndStart } from '@/lib/actions'
import { type RecordParams, type Screen, screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status, inputClass } from '@/components/ui/ui'
import { AssetCharacteristics } from '@/components/CharacteristicsPanel'
import { SchemeSourceActions, sourceRoleLabel } from '@/components/SchemeSourceActions'
import { NodeLink } from './PrimaryAssetScreen'

/** The asset types this page and the location page treat as instrument transformers (the set asset.vInstrumentTransformer lists). */
export const INSTRUMENT_TRANSFORMER_TYPES = ['CT', 'VT', 'CT_AUX', 'VT_AUX', 'COUPLING_CAPACITOR_VT', 'CCPD', 'METERING_UNIT']
/** Which source role an instrument transformer plays in a scheme by default: current types feed as CT source, voltage types as VT source. */
export const sourceRoleFor = (assetTypeCode: string) => (['CT', 'CT_AUX', 'METERING_UNIT'].includes(assetTypeCode) ? 'CtSource' : 'VtSource')
/** The roles a transformer of a type may take: a voltage type may also be the single-phase sync PT (#206). */
export const rolesFor = (assetTypeCode: string) => (sourceRoleFor(assetTypeCode) === 'CtSource' ? ['CtSource'] : ['VtSource', 'SyncVtSource'])
/** Where a type stands (#202): CT, VT, CVT, CCPD and metering units in a Yard; the auxiliaries at a Panel. */
export const standsAt = (assetTypeCode: string) => (['CT_AUX', 'VT_AUX'].includes(assetTypeCode) ? 'Panel' : 'Yard')

export default function InstrumentTransformerScreen({ params: p, id }: { screen: Screen; params: RecordParams; id?: string }) {
  const navigate = useNavigate(); const can = useCan(); const qc = useQueryClient()
  const rowQ = useViewAll('asset', 'vInstrumentTransformer', { [p.key]: id ?? '' }, undefined, !!id)
  const r = rowQ.data?.[0]
  const typeQ = useViewAll('ref', 'vAssetType', { AssetTypeCode: s(r?.AssetTypeCode) }, undefined, !!r)
  const [edit, setEdit] = useState(false)
  if (!id) return <Status bad>No instrument transformer in the address.</Status>
  if (rowQ.isPending) return <Status>Loading the instrument transformer…</Status>
  if (!r) return <Status bad>No instrument transformer with that id is readable by you.</Status>
  const editable = can('Asset.Modify')
  const template = s(typeQ.data?.[0]?.DefaultTemplateDefinitionEntityId)
  const refresh = () => { qc.invalidateQueries({ queryKey: ['view', 'asset'] }); qc.invalidateQueries({ queryKey: ['view', 'scheme'] }); qc.invalidateQueries({ queryKey: ['view', 'location'] }) }
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2"><h1 className="text-lg font-semibold text-slate-100">{s(r.Name)}</h1><Pill tone="accent">{s(r.AssetTypeName)}</Pill><Pill tone={r.Status === 'InService' ? 'good' : r.Status === 'Retired' ? 'bad' : 'neutral'}>{s(r.Status)}</Pill>
          {r.IsPlaced === false && <Pill tone="warn" title="nothing says where this transformer stands yet">not placed</Pill>}</div>
        <div className="flex gap-2">{editable && <Button onClick={() => setEdit(!edit)}>{edit ? 'Cancel edit' : 'Edit'}</Button>}<Button onClick={() => navigate(-1)}>Close</Button></div>
      </header>
      <div className="grid gap-3 lg:grid-cols-2">
        <Panel title="Equipment">
          {edit ? <EditEquipment r={r} onDone={() => { setEdit(false); refresh() }} />
            : <Facts cols={1} pairs={[['Type', <span>{s(r.AssetTypeName)} <span className="text-xs text-slate-500">{s(r.AssetClassCode)} — {r.AssetClassCode === 'Hybrid' ? 'one foot at primary voltage' : 'on the secondary circuit'}</span></span>],
              ['Phases', r.Phases == null ? <span className="text-slate-500">not recorded (the nameplate below)</span> : s(r.Phases) === '1' ? 'single-phase' : `${s(r.Phases)}-phase set`],
              ['Serial number', s(r.SerialNumber) || '—'], ['Model', s(r.ModelCode) || '—'], ['Voltage class', s(r.VoltageClassCode) || '—'],
              ['Station', r.StationNodeEntityId ? <span><NodeLink id={s(r.StationNodeEntityId)} name={s(r.StationName)} />{r.StationSource === 'scheme' ? <span className="text-xs text-slate-500"> · by the scheme it feeds; not placed yet</span> : null}</span> : <span className="text-slate-500">unknown — it feeds no scheme and is not placed</span>],
              ['Commissioned', r.CommissionedAt ? fmtDate(r.CommissionedAt) : '—'], ['Retired', r.RetiredAt ? fmtDate(r.RetiredAt) : '—'], ['Notes', s(r.Notes) || '—']]} />}
          {!!r.MigrationSource && <Status>Made by the migration rule (#206) from the legacy record: the scheme's devices declared this ratio, or their functions need this input. Correct it here if the yard says otherwise.</Status>}
        </Panel>
        <WhereItStands r={r} canPlace={editable} canMakeNode={can('Node.Modify')} onChanged={refresh} />
      </div>
      <Feeds r={r} editable={can('Scheme.Modify')} canRemove={can('Scheme.Archive') || can('Scheme.Modify')} onChanged={refresh} />
      <AssetCharacteristics assetEntityId={s(r.EntityId)} definitionEntityId={template} editable={editable}
        emptyNote={typeQ.isPending ? 'Loading the type…' : `The type ${s(r.AssetTypeCode)} names no nameplate template yet.`} />
      <Tests r={r} canRaise={can('WorkRequest.Modify')} />
      <RetireOrDelete r={r} canModify={editable} canDelete={can('Asset.Archive') || editable} onChanged={refresh} />
    </div>
  )
}

/** #206: the equipment facts a person corrects — name, voltage class, notes — written whole through asset.Asset_Revise (audited). */
function EditEquipment({ r, onDone }: { r: Row; onDone: () => void }) {
  const voltagesQ = useViewAll('ref', 'vVoltageClass', {}, 'DisplayOrder')
  const [name, setName] = useState(s(r.Name)); const [voltage, setVoltage] = useState(s(r.VoltageClassCode)); const [notes, setNotes] = useState(s(r.Notes))
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const save = async () => {
    if (!name.trim()) return
    setBusy(true); setMsg(null)
    try {
      await proc('asset', 'Asset_Revise', { EntityId: r.EntityId, AssetTypeCode: r.AssetTypeCode, Name: name.trim(), VoltageClassCode: voltage || null, ManufacturerEntityId: r.ManufacturerEntityId ?? null, ModelId: r.ModelId ?? null,
        Status: r.Status, CommissionedAt: r.CommissionedAt ?? null, RetiredAt: r.RetiredAt ?? null, Notes: notes.trim() || null })
      onDone()
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }); setBusy(false) }
  }
  return (
    <div className="space-y-2 text-sm">
      <label className="flex flex-col gap-1 text-xs text-slate-400">Name<input className={`${inputClass} w-full`} value={name} disabled={busy} onChange={(e) => setName(e.target.value)} /></label>
      <label className="flex flex-col gap-1 text-xs text-slate-400">Voltage class
        <select className={`${inputClass} w-48`} value={voltage} disabled={busy} onChange={(e) => setVoltage(e.target.value)}>
          <option value="">—</option>
          {voltage && voltagesQ.data && !voltagesQ.data.some((v) => s(v.VoltageClassCode) === voltage) && <option value={voltage}>{voltage} (retired)</option>}
          {(voltagesQ.data ?? []).map((v) => <option key={s(v.VoltageClassCode)} value={s(v.VoltageClassCode)}>{s(v.VoltageClassCode)}{v.NominalKv != null ? ` (${Number(v.NominalKv)} kV)` : ''}</option>)}
        </select></label>
      <label className="flex flex-col gap-1 text-xs text-slate-400">Notes<textarea className={`${inputClass} w-full`} rows={3} value={notes} disabled={busy} onChange={(e) => setNotes(e.target.value)} /></label>
      <div className="flex gap-2"><Button kind="primary" disabled={busy || !name.trim()} onClick={() => void save()}>Save</Button></div>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </div>
  )
}

/** #206: where the transformer stands, and placing it — the yards (or, for an auxiliary, the panels) of its station; a yard made
 * here when the station has none (no migrated station has one). asset.PlaceAsset applies #202: a CT/VT in a Yard, an
 * auxiliary at a Panel; and a node holds one installed asset (a second auxiliary on the same panel is refused by the database). */
function WhereItStands({ r, canPlace, canMakeNode, onChanged }: { r: Row; canPlace: boolean; canMakeNode: boolean; onChanged: () => void }) {
  const station = s(r.StationNodeEntityId); const at = standsAt(s(r.AssetTypeCode))
  const yardsQ = useViewAll('location', 'vNode', { ParentEntityId: station, NodeTypeCode: 'Yard' }, 'Name', !!station && at === 'Yard')
  const panelsQ = useQuery({ queryKey: ['stationPanels', station], enabled: !!station && at === 'Panel', staleTime: 60_000, queryFn: async () => {
    const buildings = await viewAll('location', 'vNode', { ParentEntityId: station, NodeTypeCode: 'Building' }, 'Name')
    const out: Row[] = []
    for (const b of buildings) out.push(...(await viewAll('location', 'vNode', { ParentEntityId: s(b.EntityId), NodeTypeCode: 'Panel' }, 'Name')).map((x) => ({ ...x, Name: `${s(b.Name)} · ${s(x.Name)}` })))
    return out
  } })
  const options = at === 'Yard' ? yardsQ.data ?? [] : panelsQ.data ?? []
  const pending = at === 'Yard' ? yardsQ.isPending : panelsQ.isPending
  const [node, setNode] = useState(''); const [newYard, setNewYard] = useState(false); const [yardName, setYardName] = useState(''); const [yardCode, setYardCode] = useState('')
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const place = async (nodeId: string) => {
    setBusy(true); setMsg(null)
    try { await proc('asset', 'PlaceAsset', { AssetEntityId: r.EntityId, NodeEntityId: nodeId, PlacementKind: 'Installed' }); setNode(''); setNewYard(false); onChanged() }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const makeYardAndPlace = async () => {
    if (!yardName.trim()) return
    setBusy(true); setMsg(null)
    try {
      const n = await proc('location', 'AddNode', { NodeTypeCode: 'Yard', ParentEntityId: station, Name: yardName.trim(), Code: yardCode.trim() || null })
      await place(s(n.EntityId)); setYardName(''); setYardCode('')
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }); setBusy(false) }
  }
  return (
    <Panel title="Where it stands">
      {r.NodeEntityId
        ? <Facts cols={1} pairs={[['Placed at', <span><NodeLink id={s(r.NodeEntityId)} name={s(r.NodeName)} /> <span className="text-xs text-slate-500">{s(r.NodeTypeCode)} · {s(r.PlacementKind)}</span></span>]]} />
        : <Status>Not placed. {r.MigrationSource ? 'The migration rule knew the scheme, not the yard: ' : ''}{station ? `choose the ${at === 'Yard' ? 'yard' : 'panel'} at ${s(r.StationName)} below${at === 'Yard' ? ', or make the yard first' : ''}.` : 'nothing says which station it is at — name it as a scheme\'s source first, or place it from a yard\'s page.'}</Status>}
      {canPlace && station && (
        <div className="mt-2 space-y-2 border-t border-slate-800 pt-2 text-sm">
          <div className="flex flex-wrap items-end gap-2">
            <label className="flex flex-col gap-1 text-xs text-slate-400">{r.NodeEntityId ? 'Move to' : 'Place at'} — {at === 'Yard' ? 'a yard' : 'a panel'} of {s(r.StationName)}
              <select className={`${inputClass} w-72`} value={node} disabled={busy} onChange={(e) => setNode(e.target.value)}>
                <option value="">{pending ? '…' : options.length ? `choose a ${at.toLowerCase()}` : `${s(r.StationName)} has no ${at.toLowerCase()} yet`}</option>
                {options.map((x) => <option key={s(x.EntityId)} value={s(x.EntityId)}>{s(x.Name)}{x.FlocCode ? ` (${s(x.FlocCode)})` : ''}</option>)}
              </select></label>
            <Button kind="primary" disabled={busy || !node} onClick={() => void place(node)}>{r.NodeEntityId ? 'Move' : 'Place here'}</Button>
            {at === 'Yard' && canMakeNode && <Button kind="mini" disabled={busy} onClick={() => setNewYard(!newYard)}>New yard at {s(r.StationName)}</Button>}
          </div>
          {newYard && (
            <div className="flex flex-wrap items-end gap-2">
              <label className="flex flex-col gap-1 text-xs text-slate-400">Yard name<input className={`${inputClass} w-56`} value={yardName} disabled={busy} placeholder="e.g. 230 kV yard" onChange={(e) => setYardName(e.target.value)} /></label>
              <label className="flex flex-col gap-1 text-xs text-slate-400">FLOC code (optional)<input className={`${inputClass} w-28`} value={yardCode} disabled={busy} placeholder="Y230" onChange={(e) => setYardCode(e.target.value)} /></label>
              <Button kind="primary" disabled={busy || !yardName.trim()} onClick={() => void makeYardAndPlace()}>Make the yard and place here</Button>
            </div>)}
          <Status>{at === 'Yard' ? 'On the transmission network an instrument transformer stands in a yard (#202).' : 'A panel-mounted auxiliary stands at a panel (#202); a panel holds one installed item, so a second auxiliary needs a position of its own.'}</Status>
        </div>)}
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </Panel>
  )
}

/** The schemes this transformer feeds, each with its role, input, in-service state and connection note. #211: read first, edit
 * on purpose — view mode is information only; Edit feeds turns on an Actions column (SchemeSourceActions) and the add form:
 * the schemes at its station, in the role chosen (the type's default; a voltage type may be the sync VT source). */
function Feeds({ r, editable, canRemove, onChanged }: { r: Row; editable: boolean; canRemove: boolean; onChanged: () => void }) {
  const navigate = useNavigate()
  const asset = s(r.EntityId)
  const feedsQ = useViewAll('scheme', 'vSchemeSource', { AssetEntityId: asset }, undefined, !!asset)
  const schemesQ = useViewAll('scheme', 'vSchemeStation', { StationNodeEntityId: s(r.StationNodeEntityId) }, 'SchemeName', !!r.StationNodeEntityId && editable)
  const roles = rolesFor(s(r.AssetTypeCode))
  const [editing, setEditing] = useState(false)
  const [scheme, setScheme] = useState(''); const [role, setRole] = useState(roles[0]); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const rows = feedsQ.data ?? []
  const add = async () => {
    if (!scheme) return
    setBusy(true); setMsg(null)
    try {
      await proc('scheme', 'AddSchemeMember', { SchemeEntityId: scheme, MemberKind: 'Asset', MemberEntityId: asset, MemberRoleCode: role, IsInService: true })
      setMsg({ text: `${s(r.Name)} now feeds ${s((schemesQ.data ?? []).find((x) => s(x.SchemeEntityId) === scheme)?.SchemeName)} as ${sourceRoleLabel(role)} — on that scheme's first input of the kind, or a new one; the record's Analog inputs tab moves it if it belongs elsewhere.` })
      setScheme(''); onChanged()
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  return (
    <Panel title={`Feeds · ${feedsQ.isPending ? '…' : rows.length}`} actions={editable ? <Button kind={editing ? 'primary' : 'default'} onClick={() => setEditing(!editing)}>{editing ? 'Done' : 'Edit feeds'}</Button> : undefined}>
      {!feedsQ.isPending && !rows.length && <Status>No scheme names this transformer as a source yet. A relay's CTR or PTR can only be checked once it does.{editable ? ' Edit feeds to name one.' : ''}</Status>}
      {rows.length > 0 && (
        <table className="w-full text-sm">
          <thead><tr className="text-left text-xs uppercase tracking-wide text-slate-500"><th className="py-1 pr-2 font-normal">Scheme</th><th className="py-1 pr-2 font-normal">Role · input</th><th className="py-1 pr-2 font-normal">Status</th><th className="py-1 pr-2 font-normal">Note</th>{editing && <th className="py-1 font-normal">Actions</th>}</tr></thead>
          <tbody>
            {rows.map((x) => (
              <tr key={s(x.MemberEntityId)} className="border-t border-slate-800 align-top">
                <td className="py-1 pr-2"><SchemeName id={s(x.SchemeEntityId)} onOpen={() => navigate(screenPath('SCHEME', s(x.SchemeEntityId)))} /></td>
                <td className="py-1 pr-2 text-slate-300">{sourceRoleLabel(x.MemberRoleCode)}{x.InputCode ? ` · ${s(x.InputCode)}` : ''}{x.RatioInUse ? <span className="text-xs text-slate-500"> · {s(x.RatioInUse)}{x.Ratio != null ? ` = ${s(x.Ratio)}` : ''}</span> : null}</td>
                <td className="py-1 pr-2"><span className="flex flex-wrap gap-1">{x.IsInService === false ? <Pill tone="warn">not in service</Pill> : <Pill tone="good">in service</Pill>}{Number(x.ParallelCount ?? 0) >= 2 && <InputPartners inputId={s(x.AnalogInputEntityId)} self={s(r.Name)} />}</span></td>
                <td className="py-1 pr-2 text-xs text-slate-300">{s(x.Notes) || <span className="text-slate-600">—</span>}</td>
                {editing && <td className="py-1"><SchemeSourceActions x={x} canModify={editable} canRemove={canRemove} onChanged={onChanged} /></td>}
              </tr>))}
          </tbody>
        </table>)}
      {editing && editable && !!r.StationNodeEntityId && (
        <div className="mt-2 flex flex-wrap items-end gap-2 border-t border-slate-800 pt-2 text-sm">
          <label className="flex flex-col gap-1 text-xs text-slate-400">Feed a scheme at {s(r.StationName)}
            <select className={`${inputClass} w-72`} value={scheme} disabled={busy} onChange={(e) => setScheme(e.target.value)}>
              <option value="">{schemesQ.isPending ? '…' : 'choose a scheme'}</option>
              {(schemesQ.data ?? []).map((x) => <option key={s(x.SchemeEntityId)} value={s(x.SchemeEntityId)}>{s(x.SchemeName)}</option>)}
            </select></label>
          {roles.length > 1 && <label className="flex flex-col gap-1 text-xs text-slate-400">as
            <select className={`${inputClass} w-40`} value={role} disabled={busy} onChange={(e) => setRole(e.target.value)}>{roles.map((x) => <option key={x} value={x}>{sourceRoleLabel(x)}</option>)}</select></label>}
          <Button kind="primary" disabled={busy || !scheme} onClick={() => void add()}>Add as {sourceRoleLabel(role)}</Button>
        </div>)}
      {editing && editable && !r.StationNodeEntityId && <Status>Place the transformer first; the schemes offered are its station's.</Status>}
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </Panel>
  )
}

/** #206: retiring (Status Retired, the date now — the row stays, its history with it) and deleting (asset.Asset_SoftDelete —
 * only once no scheme names it, so a relay's check never points at nothing). A second click confirms; no browser dialog. */
function RetireOrDelete({ r, canModify, canDelete, onChanged }: { r: Row; canModify: boolean; canDelete: boolean; onChanged: () => void }) {
  const navigate = useNavigate()
  const [confirm, setConfirm] = useState<'retire' | 'delete' | null>(null)
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const feeds = Number(r.FeedsCount ?? 0)
  const retire = async () => {
    setBusy(true); setMsg(null)
    try {
      await proc('asset', 'Asset_Revise', { EntityId: r.EntityId, AssetTypeCode: r.AssetTypeCode, Name: r.Name, VoltageClassCode: r.VoltageClassCode ?? null, ManufacturerEntityId: r.ManufacturerEntityId ?? null, ModelId: r.ModelId ?? null,
        Status: 'Retired', CommissionedAt: r.CommissionedAt ?? null, RetiredAt: new Date().toISOString(), Notes: r.Notes ?? null })
      setConfirm(null); onChanged()
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const del = async () => {
    setBusy(true); setMsg(null)
    try { await proc('asset', 'Asset_SoftDelete', { EntityId: r.EntityId }); navigate(screenPath('INSTRUMENT_TRANSFORMERS')) }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }); setBusy(false) }
  }
  if (!canModify && !canDelete) return null
  return (
    <Panel title="Retire or delete">
      <div className="flex flex-wrap items-center gap-2 text-sm">
        {canModify && r.Status !== 'Retired' && (confirm === 'retire'
          ? <span className="flex items-center gap-2"><span className="text-slate-300">Retire {s(r.Name)} as of today? It stays on record, retired.</span><Button kind="primary" disabled={busy} onClick={() => void retire()}>Yes, retire</Button><Button disabled={busy} onClick={() => setConfirm(null)}>No</Button></span>
          : <Button disabled={busy} onClick={() => setConfirm('retire')}>Retire</Button>)}
        {canDelete && (feeds > 0
          ? <span className="text-xs text-slate-500">Delete is offered once no scheme names it as a source — remove it from its {feeds === 1 ? 'scheme' : `${feeds} schemes`} above first.</span>
          : confirm === 'delete'
            ? <span className="flex items-center gap-2"><span className="text-slate-300">Delete {s(r.Name)}? It leaves every list (soft delete; the audit keeps it).</span><Button kind="primary" disabled={busy} onClick={() => void del()}>Yes, delete</Button><Button disabled={busy} onClick={() => setConfirm(null)}>No</Button></span>
            : <Button disabled={busy} onClick={() => setConfirm('delete')}>Delete</Button>)}
      </div>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </Panel>
  )
}

/** #204: the transformer's tests. A test is a procedure (CT_TEST: ratio, polarity, excitation curve, engineer's review;
 * VT_TEST: ratio, polarity, review) run under a request scoped to this transformer; each step's captures are the readings
 * and each commit is a test sheet (record.Record, kind TestSheet; the review an Attestation). Nothing here computes a
 * verdict — the technician's outcome and the engineer's review are the record. The bi-temporal acceptance of a sheet
 * (record.AcceptRecord) and the record.TestSheet / TestReading rows are the Doble-import shape, not written yet. */
function Tests({ r, canRaise }: { r: Row; canRaise: boolean }) {
  const navigate = useNavigate()
  const asset = s(r.EntityId)
  const typeKey = sourceRoleFor(s(r.AssetTypeCode)) === 'CtSource' ? 'CT_TEST' : 'VT_TEST'
  const typesQ = useQuery({ queryKey: ['workTypes'], queryFn: workTypes, staleTime: 5 * 60_000 })
  const wt = (typesQ.data ?? []).find((t) => t.key === typeKey)
  const reqQ = useViewAll('work', 'vChangeRequestStatus', { ScopeKind: 'Asset', ScopeEntityId: asset }, '-RequestedAt', !!asset)
  const recQ = useViewAll('record', 'vRecord', { SubjectKind: 'Asset', SubjectEntityId: asset }, '-OccurredAt', !!asset)
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const requests = (reqQ.data ?? []).filter((x) => ['CT_TEST', 'VT_TEST'].includes(s(x.WorkTypeKey)))
  const sheets = (recQ.data ?? []).filter((x) => ['TestSheet', 'Attestation'].includes(s(x.RecordKindCode)))
  const raise_ = async () => {
    if (!wt) return
    setBusy(true); setMsg(null)
    try {
      const id = await raiseAndStart({ workTypeVersionRowId: wt.versionRowId, title: `${s(r.Name)} — ${typeKey === 'CT_TEST' ? 'ratio, polarity and excitation' : 'ratio and polarity'} test`, scopeKind: 'Asset', scopeEntityId: asset, workflowKey: wt.workflowKey })
      navigate(screenPath('WORK_ITEM', id))
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }); setBusy(false) }
  }
  return (
    <Panel title={`Tests · ${recQ.isPending ? '…' : sheets.length} sheet${sheets.length === 1 ? '' : 's'}`} actions={canRaise
      ? <Button kind="primary" disabled={busy || !wt} title={wt ? `raises a ${wt.name} request on this transformer and opens it` : typesQ.isPending ? 'loading the work types' : `no Effective work type ${typeKey}`} onClick={() => void raise_()}>{busy ? 'Raising…' : 'Test this transformer'}</Button>
      : undefined}>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      {requests.length > 0 && (
        <div className="mb-2 text-sm">
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-400">Test requests</div>
          <ul className="mt-1 space-y-1">
            {requests.map((x) => (
              <li key={s(x.WorkRequestEntityId)} className="flex flex-wrap items-center gap-2">
                <a className="text-sky-300 underline" href={screenPath('WORK_ITEM', s(x.WorkRequestEntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('WORK_ITEM', s(x.WorkRequestEntityId))) }}>{s(x.Title)}</a>
                <Pill tone={x.RequestState === 'Closed' ? 'good' : x.RequestState === 'Cancelled' ? 'neutral' : 'warn'}>{s(x.RequestState) || 'raised'}</Pill>
                <span className="text-xs text-slate-500">{s(x.WorkTypeName)} · {fmtWhen(x.RequestedAt)}{x.RequestedByDisplayName ? ` · ${s(x.RequestedByDisplayName)}` : ''}</span>
              </li>))}
          </ul>
        </div>)}
      {!recQ.isPending && !sheets.length && <Status>No test sheet is recorded against this transformer yet. {canRaise ? 'Test this transformer raises the request; the technician records the ratio, the polarity and the excitation curve step by step, and the engineer reviews.' : ''}</Status>}
      {sheets.length > 0 && (
        <table className="w-full text-sm">
          <thead><tr className="border-b border-slate-700 text-left text-xs uppercase tracking-wide text-slate-400">
            <th className="py-1 pr-2">When</th><th className="py-1 pr-2">Sheet</th><th className="py-1 pr-2">Outcome</th><th className="py-1">Readings</th></tr></thead>
          <tbody>
            {sheets.map((x) => (
              <tr key={s(x.RowId)} className="border-b border-slate-800 align-top">
                <td className="py-1 pr-2 text-xs text-slate-400">{fmtWhen(x.OccurredAt)}</td>
                <td className="py-1 pr-2 text-slate-200">{x.RecordKindCode === 'Attestation' ? 'Engineer review' : 'Test sheet'}<div className="text-xs text-slate-500">{s(x.Summary)}</div></td>
                <td className="py-1 pr-2"><Pill tone={['Pass', 'Accepted'].includes(s(x.OverallResult)) ? 'good' : ['Fail', 'Rejected'].includes(s(x.OverallResult)) ? 'bad' : 'neutral'}>{s(x.OverallResult) || '—'}</Pill></td>
                <td className="py-1"><Readings requestId={s(x.WorkRequestEntityId)} recordEntityId={s(x.EntityId)} /></td>
              </tr>))}
          </tbody>
        </table>)}
      <Status>A test is the CT_TEST or VT_TEST procedure run under a request on this transformer: each step's captures are its readings and each commit a sheet. No reading limit is enforced yet — a ratio-error acceptance depends on the accuracy class, a rule to come as data; the technician's outcome and the engineer's review are the verdict.</Status>
    </Panel>
  )
}

/** The captures the committed step of a request wrote as this record (process.vStepInstance.Draft, CommittedRecordEntityId). */
function Readings({ requestId, recordEntityId }: { requestId: string; recordEntityId: string }) {
  const q = useQuery({ queryKey: ['testReadings', requestId, recordEntityId], enabled: !!requestId && !!recordEntityId, staleTime: 60_000, queryFn: async () => {
    const insts = (await view('process', 'vProcedureInstance', { WorkRequestEntityId: requestId }, { take: 10 })).rows
    for (const inst of insts) {
      const blocks = await viewAll('process', 'vBlockInstance', { ProcedureInstanceEntityId: s(inst.EntityId) })
      for (const b of blocks) {
        const steps = await viewAll('process', 'vStepInstance', { BlockInstanceEntityId: s(b.EntityId), State: 'Committed' })
        const hit = steps.find((st) => s(st.CommittedRecordEntityId).toLowerCase() === recordEntityId.toLowerCase())
        if (hit) { let draft: Record<string, unknown> = {}; try { draft = JSON.parse(s(hit.Draft) || '{}') } catch { /* an unreadable draft shows as none */ } return { stepId: s(hit.StepId), draft } }
      }
    }
    return null
  } })
  if (q.isPending) return <span className="text-xs text-slate-500">…</span>
  if (!q.data) return <span className="text-xs text-slate-500">no captured readings found for this sheet</span>
  const entries = Object.entries(q.data.draft)
  return (
    <div className="text-xs">
      <span className="text-slate-400">{q.data.stepId}</span>
      {entries.length === 0 ? <span className="ml-1 text-slate-500">— no fields captured</span>
        : <ul className="mt-0.5 space-y-0.5">{entries.map(([k, v]) => <li key={k}><span className="text-slate-400">{k}</span> <span className="whitespace-pre-wrap text-slate-200">{Array.isArray(v) ? v.join(', ') : s(v)}</span></li>)}</ul>}
    </div>
  )
}

/** #208: the other transformers paralleled into the same analog input (scheme.vSchemeInput.Transformers). */
function InputPartners({ inputId, self }: { inputId: string; self: string }) {
  const q = useViewAll('scheme', 'vSchemeInput', { EntityId: inputId }, undefined, !!inputId)
  const names = s(q.data?.[0]?.Transformers).split('; ').filter((n) => n && n !== self)
  return <Pill tone="accent" title="two or more CTs feed this one input: they are connected in parallel before the relay">in parallel{names.length ? ` with ${names.join(', ')}` : ''}</Pill>
}

function SchemeName({ id, onOpen }: { id: string; onOpen: () => void }) {
  const q = useViewAll('scheme', 'vScheme', { EntityId: id }, undefined, !!id)
  const name = s(q.data?.[0]?.Name) || id.slice(0, 8)
  return <a className="text-sky-300 underline" href={screenPath('SCHEME', id)} onClick={(e) => { e.preventDefault(); onOpen() }}>{name}</a>
}
