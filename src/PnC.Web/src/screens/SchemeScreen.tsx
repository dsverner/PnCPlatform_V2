// #170 (2026-09-16): the protection scheme — its members, and the primary assets it protects (scheme.SchemeProtects, the
// link the applicability classifications flow through: a device inherits from the primary asset via its scheme). "Protects"
// is entered here, a few seconds per scheme: pick an existing primary asset at the station or create one (a name, a type,
// the station — nothing more in this phase). Plain React (the #167 rule).
//
// #176 (2026-09-17): a member is added and removed here — the second half of the owner's question of 2026-09-17, "Now
// how do I associate a protection with this panel?" The chain is panel → device position → protection function, and the
// scheme names the protection function as a member. So the Members panel gained a kind, a chooser, a role and an add,
// and each member a remove. The station a scheme sits at now comes from scheme.vSchemeStation (#170) where it can, and
// is asked for once where it cannot — a scheme with no member placed anywhere has no station to derive.
import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ApiError, s, view, viewAll, proc, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type RecordParams, type Screen, screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status, Field, inputClass } from '@/components/ui/ui'
import { DataGrid } from '@/components/ui/data-grid'
import { AssetPicker } from '@/components/pickers'

const ZONES = ['Primary', 'Backup', 'BreakerFailure']   // the owner, 2026-09-16: Primary, Backup, Breaker Failure

export default function SchemeScreen({ params: p, id }: { screen: Screen; params: RecordParams; id?: string }) {
  const navigate = useNavigate(); const can = useCan(); const qc = useQueryClient()
  const rowQ = useViewAll('scheme', 'vScheme', { [p.key]: id ?? '' }, undefined, !!id)
  const r = rowQ.data?.[0]
  // the station: the settings records of the scheme's devices carry it
  const stationQ = useQuery({ queryKey: ['schemeStation', id], enabled: !!id, staleTime: 5 * 60_000, queryFn: async () => (await view('document', 'vSettingsRecord', { SchemeEntityId: id! }, { take: 1 })).rows[0] ?? null })
  // #176: scheme.vSchemeStation is the view written for this question (#170) — the scheme's Asset members' placements
  // walked up to the Station. It answers for a scheme whose devices have no settings record yet, which the settings
  // record read above cannot; whichever resolves is used, and both carry StationNodeEntityId and StationName.
  const schemeStationQ = useViewAll('scheme', 'vSchemeStation', { SchemeEntityId: id ?? '' }, undefined, !!id)
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
  const station = schemeStationQ.data?.[0] ?? stationQ.data
  // every primary asset, any station: a line has two ends and both ends' schemes protect the one line (2103 B-PROT at Bathurst and at Eel River, 2026-09-16)
  const candidatesQ = useViewAll('asset', 'vPrimaryAsset', {}, 'Name')
  const candidates = useMemo(() => { const f = find.toLowerCase(); const all = candidatesQ.data ?? []; const hit = all.filter((x) => !f || s(x.Name).toLowerCase().includes(f) || s(x.Stations).toLowerCase().includes(f)); const here = (x: Row) => s(x.TerminalNodeIds).toLowerCase().includes(s(station?.StationNodeEntityId).toLowerCase()) && station?.StationNodeEntityId ? 0 : 1; return hit.sort((a, b) => here(a) - here(b) || s(a.Name).localeCompare(s(b.Name))) }, [candidatesQ.data, find, station])
  const editable = can('Scheme.Modify')
  const refresh = () => { qc.invalidateQueries({ queryKey: ['schemeProtects', id] }); qc.invalidateQueries({ queryKey: ['view', 'asset', 'vPrimaryAsset'] }) }
  const link = async (assetId: string, label: string, terminalId?: string) => {
    setBusy(true)
    try {
      // the terminal end this scheme protects from: the asset's terminal at this scheme's station (#170 — a line's ends have their own schemes)
      let term = terminalId ?? ''
      if (!term && station?.StationNodeEntityId) { const ts = await viewAll('asset', 'vAssetTerminalDetail', { AssetEntityId: assetId }); term = s(ts.find((x) => s(x.StationNodeEntityId).toLowerCase() === s(station.StationNodeEntityId).toLowerCase())?.TerminalEntityId) }
      await proc('scheme', 'SchemeProtects_Add', { SchemeEntityId: id, PrimaryAssetEntityId: assetId, ZoneRole: zone, AssetTerminalEntityId: term || null }); setMsg({ text: `${s(r?.Name)} protects ${label} (${zone.toLowerCase()})${term ? ' from this end' : ' — no terminal of the asset is at this station; set one on its page'}.` }); setPick(''); refresh() }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const create = async () => {
    if (!newName.trim() || !station?.StationNodeEntityId) return
    setBusy(true)
    try {
      const a = await proc<Row>('asset', 'Asset_Add', { AssetTypeCode: newType, Name: newName.trim(), Status: 'InService' })
      const assetId = s(a.EntityId)
      const term = await proc<Row>('asset', 'AssetTerminal_Add', { AssetEntityId: assetId, TerminalNo: 1, StationNodeEntityId: s(station.StationNodeEntityId) })   // terminal 1: this scheme's station; the other ends on the asset's page
      setNewName('')
      await link(assetId, `${newName.trim()} (new ${newType.toLowerCase()}, terminal 1 ${s(station.StationName)})`, s(term.EntityId))
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }); setBusy(false) }
  }
  const unlink = async (x: Row) => {
    try { await proc('scheme', 'SchemeProtects_SoftDelete', { EntityId: x.LinkEntityId }); setMsg({ text: `${s(x.Name)} no longer listed as protected by ${s(r?.Name)}.` }); refresh() }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) }
  }
  if (!id) return <Status bad>No scheme was named. Pick one from Schemes.</Status>
  if (rowQ.isPending) return <Status>Loading the scheme…</Status>
  if (!r) return <Status bad>You may not read this scheme.</Status>
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2"><h1 className="text-lg font-semibold text-slate-100">{s(r.Name)}</h1><Pill tone={r.Status === 'InService' ? 'good' : 'neutral'}>{s(r.Status)}</Pill></div>
        <div className="flex gap-2">{!!station?.StationNodeEntityId && <Button onClick={() => navigate(screenPath('SETTINGS_BOOK') + `?StationNodeEntityId=${station.StationNodeEntityId}`)}>Settings book</Button>}<Button onClick={() => navigate(-1)}>Close</Button></div>
      </header>
      <div className="grid gap-3 lg:grid-cols-2">
        <Panel title="Scheme"><Facts cols={1} pairs={[['Name', s(r.Name)], ['System designation', s(r.SystemDesignation) || '—'], ['Station', station ? s(station.StationName) : (stationQ.isPending || schemeStationQ.isPending) ? '…' : 'not known yet — no member of this scheme is placed anywhere'], ['Status', s(r.Status)], ['Notes', s(r.Notes) || '—']]} /></Panel>
        <MembersPanel schemeId={id} stationNodeEntityId={s(station?.StationNodeEntityId)} stationName={s(station?.StationName)} />
      </div>
      <Panel title={`Protects · ${protectsQ.isPending ? '…' : (protectsQ.data ?? []).length} primary asset(s)`}>
        {msg && <Status bad={msg.bad}>{msg.text}</Status>}
        <DataGrid rows={protectsQ.data ?? []} rowKey={(x) => s(x.LinkEntityId)} emptyText="Nothing recorded yet: which primary asset does this scheme protect?" columns={[
          { key: 'Name', label: 'Primary asset', render: (x) => <a className="text-sky-300 underline" href={screenPath('PRIMARY_ASSET', s(x.PrimaryAssetEntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('PRIMARY_ASSET', s(x.PrimaryAssetEntityId))) }}>{s(x.Name) || s(x.PrimaryAssetEntityId).slice(0, 8)}</a> },
          { key: 'AssetTypeName', label: 'Type' }, { key: 'Stations', label: 'Terminals' }, { key: 'ProtectedFrom', label: 'Protected from' }, { key: 'ZoneRole', label: 'Zone' },
          { key: 'Classifications', label: 'Classifications', render: (x) => <span className="text-xs text-slate-400">{s(x.Classifications) || 'none recorded'}</span> },
          ...(editable ? [{ key: '_x', label: '', render: (x: Row) => <Button kind="mini" onClick={() => void unlink(x)}>remove</Button> }] : [])]} />
        {editable && (
          <div className="mt-3 grid gap-3 lg:grid-cols-2">
            <div className="rounded border border-slate-800 p-2">
              <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400">Add an existing primary asset (any station — a line has two ends){station ? `; ${s(station.StationName)} first` : ''}</h4>
              <div className="mt-1 flex flex-wrap items-end gap-2">
                <Field label="Find"><input className={inputClass} value={find} onChange={(e) => setFind(e.target.value)} placeholder="name contains…" /></Field>
                <Field label="Primary asset"><select className={inputClass} value={pick} onChange={(e) => setPick(e.target.value)}><option value="">— choose —</option>{candidates.map((x) => <option key={s(x.EntityId)} value={s(x.EntityId)}>{s(x.Name)} · {s(x.AssetTypeName)}{x.Stations ? ' · ' + s(x.Stations) : ''}</option>)}</select></Field>
                <Field label="Zone"><select className={inputClass} value={zone} onChange={(e) => setZone(e.target.value)}>{ZONES.map((z) => <option key={z} value={z}>{z === 'BreakerFailure' ? 'Breaker failure' : z}</option>)}</select></Field>
                <Button kind="primary" disabled={!pick || busy} onClick={() => void link(pick, s(candidates.find((x) => s(x.EntityId) === pick)?.Name))}>Protects</Button>
              </div>
            </div>
            <div className="rounded border border-slate-800 p-2">
              <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400">Or create one{station ? ` at ${s(station.StationName)}` : ' (the scheme has no station yet)'}</h4>
              <div className="mt-1 flex flex-wrap items-end gap-2">
                <Field label="Type"><select className={inputClass} value={newType} onChange={(e) => setNewType(e.target.value)}>{(typesQ.data ?? []).map((t) => <option key={s(t.AssetTypeCode)} value={s(t.AssetTypeCode)}>{s(t.Name)}</option>)}</select></Field>
                <Field label="Name"><input className={inputClass} value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="e.g. L0012" /></Field>
                <Button kind="primary" disabled={!newName.trim() || !station?.StationNodeEntityId || busy} onClick={() => void create()}>Create and protect</Button>
              </div>
              <div className="mt-1 text-xs text-slate-500">A name, a type, and this station as terminal 1. The other end of a line is set on the asset's page.</div>
            </div>
          </div>
        )}
      </Panel>
    </div>
  )
}

// ---------------------------------------------------------------- #176: the scheme's members

/**
 * The scheme's members, and how one is added.
 *
 * scheme.AddSchemeMember (Scheme.Modify) takes @SchemeEntityId, @MemberKind, @MemberEntityId, @MemberRoleCode,
 * @IsInService (default 1) and @Notes, and checks the kind itself: ProtectionFunction must name a current
 * location.vNode of NodeTypeCode 'ProtectionFunction'; Asset and Channel a current asset.vAsset; Connection a current
 * connection.vConnection. Anything else, or a member that is not current, is 50271 in the procedure's own words.
 *
 * A device is not on that list, and the header says why: members are functions, assets and connections, never devices,
 * so a relay swap leaves the scheme intact. The screen says it in one line, because it is the reason a person cannot
 * find the relay they are looking at.
 *
 * Connection is left off the kind list here: connection.vConnection has no name — it is FromKind/FromEntityId to
 * ToKind/ToEntityId with a RealisationCode — so there is nothing to choose it by from this screen yet.
 *
 * Removal is scheme.SchemeMember_SoftDelete (Scheme.Archive by the permission map's suffix rule: _SoftDelete →
 * <Class>.Archive, and the scheme schema's class is Scheme). Decision 71 again: it closes the belief, ValidTo untouched.
 */
function MembersPanel({ schemeId, stationNodeEntityId, stationName }: { schemeId: string; stationNodeEntityId: string; stationName: string }) {
  const qc = useQueryClient()
  const can = useCan()
  const canAdd = can('Scheme.Modify'); const canRemove = can('Scheme.Archive')
  const membersQ = useQuery({ queryKey: ['schemeMembers', schemeId], enabled: !!schemeId, queryFn: async () => {
    const ms = await viewAll('scheme', 'vSchemeMember', { SchemeEntityId: schemeId })
    const out: Row[] = []
    for (const m of ms) {
      let name = ''
      if (m.MemberKind === 'ProtectionFunction' || m.MemberKind === 'Node') name = s((await view('location', 'vNode', { EntityId: s(m.MemberEntityId) }, { take: 1 })).rows[0]?.Name)
      else if (m.MemberKind === 'Asset' || m.MemberKind === 'Channel' || m.MemberKind === 'Device') name = s((await view('asset', 'vAsset', { EntityId: s(m.MemberEntityId) }, { take: 1 })).rows[0]?.Name)
      out.push({ ...m, MemberName: name })
    }
    return out
  } })
  const [busy, setBusy] = useState(false)
  const [confirmId, setConfirmId] = useState('')
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const refresh = () => { qc.invalidateQueries({ queryKey: ['schemeMembers', schemeId] }); qc.invalidateQueries({ queryKey: ['view', 'location'] }) }
  const remove = async (m: Row) => {
    setBusy(true)
    try { await proc('scheme', 'SchemeMember_SoftDelete', { EntityId: m.EntityId }); setMsg({ text: `${s(m.MemberName) || s(m.MemberKind)} is no longer a member.` }); setConfirmId(''); refresh() }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const ask = (m: Row) => { setMsg(null); setConfirmId(s(m.EntityId)) }
  const rows = membersQ.data ?? []
  return (
    <Panel title={`Members · ${membersQ.isPending ? '…' : rows.length}`}>
      <DataGrid rows={rows} rowKey={(x) => s(x.EntityId)} emptyText="No member yet. Add the protection function this scheme runs on, below." columns={[
        { key: 'MemberName', label: 'Member' }, { key: 'MemberKind', label: 'Kind' }, { key: 'MemberRoleCode', label: 'Role' },
        { key: 'IsInService', label: 'In service', render: (x) => (x.IsInService ? 'yes' : 'no') },
        ...(canRemove ? [{ key: '_x', label: '', render: (x: Row) => (confirmId === s(x.EntityId)
          ? <span className="flex items-center gap-1 text-xs text-amber-300">remove?
              <Button kind="mini" disabled={busy} onClick={() => void remove(x)}>yes</Button>
              <Button kind="mini" disabled={busy} onClick={() => setConfirmId('')}>keep</Button></span>
          : <Button kind="mini" disabled={busy} onClick={() => ask(x)}>remove</Button>) }] : [])]} />
      {msg && <div className="mt-2"><Status bad={msg.bad}>{msg.text}</Status></div>}
      <div className="mt-2"><Status>A member is a protection function, an asset or a channel. Never a device, so swapping a relay leaves the scheme intact.</Status></div>
      {canAdd && <AddMember schemeId={schemeId} stationNodeEntityId={stationNodeEntityId} stationName={stationName} onAdded={refresh} />}
    </Panel>
  )
}

/**
 * Add one member. The role list is ref.vSchemeMemberRole (MemberRoleCode, Name, Description) — fifteen roles seeded at
 * Seed_ref_SchemeMemberRole: Member, CtSource, VtSource, DcSource, TripCircuit, LockoutRelay, EndA, EndB and the rest.
 *
 * The protection-function chooser is scoped to the scheme's station rather than the estate, in two reads and never a
 * walk of the tree:
 *   1. location.vFloc filtered by StationNodeEntityId — one row per position under the station, with PanelName,
 *      PositionName, InstalledAssetName, Functions and FunctionCount. It is the view the FLOC screens already read per
 *      station (and the one DevicesHere uses on the location page), and it is the only read that gives a position its
 *      panel without climbing ParentEntityId a level at a time.
 *   2. location.vNode filtered by ParentEntityId = the chosen position and NodeTypeCode = 'ProtectionFunction' — the
 *      function nodes themselves, which vFloc aggregates into ANSI codes and does not carry the ids of.
 * Two equality filters, two requests, and the person sees panel → position → function, which is the chain they are
 * standing in front of. The search box narrows the station's own positions in the browser; that set is one station's,
 * not the estate's.
 *
 * Entering several in a row: after a successful add the kind and the role stay chosen, the member clears, and the
 * cursor returns to the chooser.
 */
function AddMember({ schemeId, stationNodeEntityId, stationName, onAdded }: { schemeId: string; stationNodeEntityId: string; stationName: string; onAdded: () => void }) {
  const [kind, setKind] = useState('ProtectionFunction')
  const [role, setRole] = useState('Member')
  const [inService, setInService] = useState(true)
  const [notes, setNotes] = useState('')
  const [positionId, setPositionId] = useState('')
  const [functionId, setFunctionId] = useState('')
  const [find, setFind] = useState('')
  const [asset, setAsset] = useState<Row | null>(null)
  const [busy, setBusy] = useState(false)
  const [round, setRound] = useState(0)
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  // a scheme with no member placed anywhere has no station of its own (scheme.vSchemeStation walks its Asset members'
  // placements). A new scheme is exactly that case, so the station is asked for once and the chooser scopes to it.
  const [pickStation, setPickStation] = useState('')
  const stationsQ = useViewAll('location', 'vNode', { NodeTypeCode: 'Station' }, 'Name', kind === 'ProtectionFunction' && !stationNodeEntityId)
  const station = stationNodeEntityId || pickStation
  const rolesQ = useViewAll('ref', 'vSchemeMemberRole', {}, 'Name')
  const flocQ = useViewAll('location', 'vFloc', { StationNodeEntityId: station }, 'PositionName', !!station && kind === 'ProtectionFunction')
  const functionsQ = useViewAll('location', 'vNode', { ParentEntityId: positionId, NodeTypeCode: 'ProtectionFunction' }, 'Name', !!positionId)
  const positions = useMemo(() => {
    const f = find.trim().toLowerCase()
    return (flocQ.data ?? [])
      .filter((x) => !f || [x.PositionName, x.PanelName, x.InstalledAssetName, x.Functions].some((v) => s(v).toLowerCase().includes(f)))
      .sort((a, b) => s(a.PanelName).localeCompare(s(b.PanelName)) || s(a.PositionName).localeCompare(s(b.PositionName)))
  }, [flocQ.data, find])
  const memberId = kind === 'ProtectionFunction' ? functionId : s(asset?.EntityId)
  const add = async () => {
    if (!memberId) return
    setBusy(true)
    try {
      await proc('scheme', 'AddSchemeMember', { SchemeEntityId: schemeId, MemberKind: kind, MemberEntityId: memberId, MemberRoleCode: role, IsInService: inService, Notes: notes.trim() || null })   // a BIT parameter takes a JSON boolean; 1/0 is refused as a bad value (SqlSession.ConvertValue)
      const label = kind === 'ProtectionFunction' ? s((functionsQ.data ?? []).find((x) => s(x.EntityId) === functionId)?.Name) : s(asset?.Name)
      setMsg({ text: `${label || 'The member'} added as ${role}.` })
      setFunctionId(''); setAsset(null); setNotes(''); setRound(round + 1); onAdded()      // the kind and the role stay for the next one
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  return (
    <div className="mt-3 space-y-2 border-t border-slate-800 pt-2 text-sm">
      <div className="flex flex-wrap items-end gap-2">
        <Field label="Kind">
          <select className={inputClass} value={kind} disabled={busy} onChange={(e) => { setKind(e.target.value); setFunctionId(''); setAsset(null); setMsg(null) }}>
            <option value="ProtectionFunction">Protection function</option>
            <option value="Asset">Asset</option>
            <option value="Channel">Channel</option>
          </select></Field>
        <Field label="Role">
          <select className={inputClass} value={role} disabled={busy} onChange={(e) => setRole(e.target.value)}>
            {(rolesQ.data ?? []).map((x) => <option key={s(x.MemberRoleCode)} value={s(x.MemberRoleCode)}>{s(x.Name) || s(x.MemberRoleCode)}</option>)}
          </select></Field>
        <label className="flex items-center gap-1 pb-1 text-xs text-slate-400">
          <input type="checkbox" checked={inService} disabled={busy} onChange={(e) => setInService(e.target.checked)} />in service</label>
        <Button kind="primary" disabled={!memberId || busy} onClick={() => void add()}>Add member</Button>
      </div>
      {kind === 'ProtectionFunction' ? (
        <div className="space-y-2">
          {!stationNodeEntityId && (
            <div className="flex flex-wrap items-end gap-2">
              <Field label="Station">
                <select className={`${inputClass} w-72`} value={pickStation} disabled={busy} onChange={(e) => { setPickStation(e.target.value); setPositionId(''); setFunctionId('') }}>
                  <option value="">— which station? —</option>
                  {(stationsQ.data ?? []).map((x) => <option key={s(x.EntityId)} value={s(x.EntityId)}>{s(x.Code) ? `${s(x.Code)} · ` : ''}{s(x.Name)}</option>)}
                </select></Field>
              <Status>No member of this scheme is placed anywhere yet, so its station is not known. Choose it once.</Status>
            </div>)}
          {!!station && (
            <div className="flex flex-wrap items-end gap-2">
              <Field label={`Find at ${stationName || 'this station'}`}>
                <input className={`${inputClass} w-48`} value={find} disabled={busy} placeholder="panel, position, relay or ANSI code"
                  onChange={(e) => setFind(e.target.value)} /></Field>
              <Field label={`Position · ${flocQ.isPending ? '…' : positions.length}`}>
                <select className={`${inputClass} w-72`} value={positionId} disabled={busy} onChange={(e) => { setPositionId(e.target.value); setFunctionId('') }}>
                  <option value="">— choose a position —</option>
                  {positions.map((x) => <option key={s(x.NodeEntityId)} value={s(x.NodeEntityId)}>
                    {s(x.PanelName) || 'no panel'} · {s(x.PositionName)}{x.InstalledAssetName ? ` · ${s(x.InstalledAssetName)}` : ''}{x.Functions ? ` · ${s(x.Functions)}` : ''}</option>)}
                </select></Field>
              <Field label={`Protection function${positionId ? ` · ${(functionsQ.data ?? []).length}` : ''}`}>
                <select className={`${inputClass} w-56`} value={functionId} disabled={busy || !positionId} onChange={(e) => setFunctionId(e.target.value)}>
                  <option value="">{!positionId ? '— pick a position first —' : functionsQ.isPending ? '…' : (functionsQ.data ?? []).length ? '— choose a function —' : 'this position has none'}</option>
                  {(functionsQ.data ?? []).map((x) => <option key={s(x.EntityId)} value={s(x.EntityId)}>{s(x.Code) ? `${s(x.Code)} · ` : ''}{s(x.Name)}</option>)}
                </select></Field>
            </div>)}
        </div>
      ) : (
        <AssetPicker value={asset} onChange={(a) => { setAsset(a); setMsg(null) }} disabled={busy} autoFocusKey={`member-${round}`}
          label={kind === 'Channel' ? 'Channel' : 'Asset'} note="any part of the name; two of the same name are told apart by the model" />)}
      <label className="flex flex-col gap-1 text-xs text-slate-400">Notes (optional)
        <textarea className={`${inputClass} w-full`} rows={1} value={notes} disabled={busy} onChange={(e) => setNotes(e.target.value)} /></label>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </div>
  )
}
