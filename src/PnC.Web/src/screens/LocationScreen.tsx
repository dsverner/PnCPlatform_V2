// #173 (2026-09-17): the location page, for ANY node of the location tree — a region, a station, a building, a room, a
// panel, a position. It was the station page (#171) and refused everything else; the owner found there was "no way to
// classify a location" with a High/Medium/Low CIP impact rating, and the estate has a Building between every Station and
// its Panels, so a building has to be reachable and classifiable in its own right.
//
// What the page shows: the node, where it sits (its ancestors as links), its CIP-002 impact rating, the nodes inside it,
// and the devices placed at or under it. A station also shows the primary assets with a terminal here and the schemes
// here — neither question means anything for a room or a panel, so neither is asked there.
// Plain React (the #167 rule); the LOCATION screen definition names location.vNode and this component reads it.
//
// #174 (2026-09-17): the tree is built here, by hand. The owner, 2026-09-17: "lets start building out the terminal
// equipment FLOCS for Eel River… I believe that the application needs to be able to create these… for now, lets work on
// user functionality." So: a child is added inside this node (location.AddNode), the node itself is renamed or its
// subtype and notes changed (location.RenameNode), and a child is withdrawn (location.Node_SoftDelete). The types
// offered are only those ref.vLocationNodeTypeParent allows under THIS node's type — the rule lives in the database and
// is read, never restated in the client. Every refusal shown is the procedure's own message.
import { useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ApiError, proc, s, view, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type RecordParams, type Screen, screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status, inputClass } from '@/components/ui/ui'
import { ClassificationPanel, NODE_KINDS, NodeLink } from './PrimaryAssetScreen'

/** location.vNode.Path is the ancestors' chain — the node's own id excluded, each id followed by '/' (#94). */
const ancestorIds = (path: unknown) => s(path).split('/').map((x) => x.trim()).filter(Boolean)

/** The ancestors of a node, root first, each with its name and type (location.vNode, one read per level — a station sits
 * three or four levels down, so this is a handful of reads). */
function useAncestors(path: unknown) {
  const ids = ancestorIds(path)
  return useQuery({ queryKey: ['nodeAncestors', ids], enabled: ids.length > 0, staleTime: 60_000, queryFn: async () => {
    const out: Row[] = []
    for (const id of ids) {
      const n = (await view('location', 'vNode', { EntityId: id }, { take: 1 })).rows[0]
      if (n) out.push(n)
    }
    return out
  } })
}

export default function LocationScreen({ params: p, id }: { screen: Screen; params: RecordParams; id?: string }) {
  const navigate = useNavigate(); const can = useCan()
  const rowQ = useViewAll('location', 'vNode', { [p.key]: id ?? '' }, undefined, !!id)
  const r = rowQ.data?.[0]
  const ancestorsQ = useAncestors(r?.Path)
  if (!id) return <Status bad>No location in the address.</Status>
  if (rowQ.isPending) return <Status>Loading the location…</Status>
  if (!r) return <Status bad>No node with that id is readable by you.</Status>
  const isStation = s(r.NodeTypeCode) === 'Station'
  const canEdit = can('Node.Modify'); const canArchive = can('Node.Archive')
  const ancestors = ancestorsQ.data ?? []
  const station = isStation ? r : ancestors.find((a) => s(a.NodeTypeCode) === 'Station')
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2"><h1 className="text-lg font-semibold text-slate-100">{s(r.Name)}</h1><Pill tone="accent">{s(r.NodeTypeCode)}</Pill>{r.SubtypeCode ? <Pill>{s(r.SubtypeCode)}</Pill> : null}</div>
        <div className="flex gap-2"><Button onClick={() => navigate(-1)}>Close</Button></div>
      </header>
      <div className="grid gap-3 lg:grid-cols-2">
        <Panel title="Location">
          <div className="space-y-3">
            <Facts cols={1} pairs={[
              ['Type', s(r.NodeTypeCode)],
              ['Where it sits', ancestorsQ.isPending ? '…' : ancestors.length
                ? <span>{ancestors.map((a, i) => <span key={s(a.EntityId)}>{i > 0 ? ' › ' : ''}<NodeLink id={s(a.EntityId)} name={s(a.Name)} /><span className="ml-1 text-xs text-slate-500">{s(a.NodeTypeCode)}</span></span>)}</span>
                : 'the top of the tree']]} />
            {canEdit
              ? <NodeForm key={s(r.EntityId)} r={r} />
              : <Facts cols={1} pairs={[['Name', s(r.Name)], ['Subtype', s(r.SubtypeCode) || '—'], ['Notes', s(r.Notes) || '—']]} />}
          </div>
        </Panel>
        <ClassificationPanel title="Applicability classifications" subjectKind="Node" subjectEntityId={s(r.EntityId)} editable={can('Asset.Modify')} kinds={NODE_KINDS}
          note="The CIP-002 impact rating of this location — every BES Cyber Asset in it inherits it, and a rating on a building beats the station's for the devices in that building (#173). Recorded by you from the entity's own CIP-002 evaluation in this phase; a value saves at once, audited." />
      </div>
      <div className="grid gap-3 lg:grid-cols-2">
        <Inside node={r} canEdit={canEdit} canArchive={canArchive} />
        <DevicesHere node={r} station={station} isStation={isStation} />
      </div>
      {/* a terminal and a scheme are asked of a station: neither question means anything for a building, a room or a panel */}
      {isStation && (
        <div className="grid gap-3 lg:grid-cols-2">
          <PrimaryAssetsHere stationId={s(r.EntityId)} />
          <SchemesHere stationId={s(r.EntityId)} />
        </div>)}
    </div>
  )
}

/** Every location node type and the subtype enumeration attached to it, if it has one (ref.vLocationNodeType —
 * NodeTypeCode, Name, SubtypeListDefinitionRowId). One read, shared by every caller through the query cache. */
function useNodeTypes() {
  const q = useViewAll('ref', 'vLocationNodeType', {}, 'Name')
  const byCode = new Map((q.data ?? []).map((t) => [s(t.NodeTypeCode), t]))
  return { byCode, isPending: q.isPending }
}

/** The values a type's subtype may take: the enumeration named by ref.LocationNodeType.SubtypeListDefinitionRowId
 * (config.vEnumerationValue by DefinitionVersionRowId), which is what location.AddNode and location.RenameNode check
 * against. A type with no list attached takes free text and the procedure decides. */
function useSubtypes(nodeTypeCode: string) {
  const { byCode } = useNodeTypes()
  const listId = s(byCode.get(nodeTypeCode)?.SubtypeListDefinitionRowId)
  const q = useViewAll('config', 'vEnumerationValue', { DefinitionVersionRowId: listId }, 'DisplayOrder', !!listId)
  return { values: q.data ?? [], hasList: !!listId }
}

/** A subtype box: the type's enumeration when it has one, otherwise free text (the procedure refuses a bad value). */
function SubtypeBox({ nodeTypeCode, value, onChange, disabled }: { nodeTypeCode: string; value: string; onChange: (v: string) => void; disabled?: boolean }) {
  const { values } = useSubtypes(nodeTypeCode)
  if (values.length) return (
    <select className={`${inputClass} w-64`} value={value} disabled={disabled} onChange={(e) => onChange(e.target.value)}>
      <option value="">— none —</option>
      {values.map((v) => <option key={s(v.ValueCode)} value={s(v.ValueCode)}>{s(v.Name) || s(v.ValueCode)}</option>)}
    </select>)
  return <input className={`${inputClass} w-64`} value={value} disabled={disabled} onChange={(e) => onChange(e.target.value)} placeholder="optional" />
}

/** The node's own fields — its name, its subtype and its notes. location.RenameNode, which keeps the node where it is:
 * the generated Node_Revise takes Path and Depth, which a client must never compute. A change saves at once, audited. */
function NodeForm({ r }: { r: Row }) {
  const qc = useQueryClient()
  const [f, setF] = useState({ Name: s(r.Name), SubtypeCode: s(r.SubtypeCode), Notes: s(r.Notes) })
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null); const [busy, setBusy] = useState(false)
  const dirty = f.Name !== s(r.Name) || f.SubtypeCode !== s(r.SubtypeCode) || f.Notes !== s(r.Notes)
  const save = async () => {
    if (!f.Name.trim()) { setMsg({ text: 'A location needs a name.', bad: true }); return }
    setBusy(true)
    try {
      await proc('location', 'RenameNode', { EntityId: r.EntityId, Name: f.Name.trim(), SubtypeCode: f.SubtypeCode.trim() || null, Notes: f.Notes.trim() || null })
      setMsg({ text: `${f.Name.trim()} saved.` }); refreshTree(qc)
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  return (
    <div className="space-y-2 text-sm">
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      <div className="grid grid-cols-[8rem_1fr] items-start gap-2">
        <label className="text-slate-400">Name</label>
        <input className={`${inputClass} w-64`} value={f.Name} disabled={busy} onChange={(e) => setF({ ...f, Name: e.target.value })} placeholder="e.g. 345 kV Yard" />
        <label className="text-slate-400">Subtype</label>
        <SubtypeBox nodeTypeCode={s(r.NodeTypeCode)} value={f.SubtypeCode} disabled={busy} onChange={(v) => setF({ ...f, SubtypeCode: v })} />
        <label className="text-slate-400">Notes</label>
        <textarea className={`${inputClass} w-full`} rows={2} value={f.Notes} disabled={busy} onChange={(e) => setF({ ...f, Notes: e.target.value })} />
      </div>
      <Button kind="primary" disabled={!dirty || busy} onClick={() => void save()}>Save</Button>
    </div>
  )
}

/** Every read that shows the tree, after a node is added, renamed or withdrawn. */
function refreshTree(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['view', 'location'] })
  qc.invalidateQueries({ queryKey: ['nodeAncestors'] })
}

/** The nodes directly inside this one (location.vNode by ParentEntityId) — on a station, its yards and its building; on
 * a building, its panels. The estate's 250 buildings are one per station and all named "Building (unknown — legacy has
 * no buildings)"; the link is how they are reached at all (#173). #174: a child is added and withdrawn here. */
function Inside({ node, canEdit, canArchive }: { node: Row; canEdit: boolean; canArchive: boolean }) {
  const qc = useQueryClient()
  const q = useViewAll('location', 'vNode', { ParentEntityId: s(node.EntityId) }, 'Name', !!node.EntityId)
  const rows = q.data ?? []
  const [confirmId, setConfirmId] = useState(''); const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const remove = async (n: Row) => {
    setBusy(true)
    try {
      await proc('location', 'Node_SoftDelete', { EntityId: n.EntityId })
      setMsg({ text: `${s(n.Name)} withdrawn.` }); setConfirmId(''); refreshTree(qc)
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  return (
    <Panel title={`Inside here · ${q.isPending ? '…' : rows.length}`}>
      {q.isError && <Status bad>Could not read what is inside: {(q.error as Error).message}</Status>}
      {!q.isPending && !rows.length && <Status>Nothing is recorded inside this {s(node.NodeTypeCode).toLowerCase()}.</Status>}
      <ul className="space-y-1 text-sm">
        {rows.map((n) => (
          <li key={s(n.EntityId)} className="flex flex-wrap items-center gap-2">
            <NodeLink id={s(n.EntityId)} name={s(n.Name)} />
            <span className="text-xs text-slate-500">{s(n.NodeTypeCode)}{n.SubtypeCode ? ' · ' + s(n.SubtypeCode) : ''}</span>
            {canArchive && (confirmId === s(n.EntityId)
              ? <span className="flex items-center gap-1 text-xs text-amber-300">withdraw {s(n.Name)}?
                  <Button kind="mini" disabled={busy} onClick={() => void remove(n)}>yes, withdraw</Button>
                  <Button kind="mini" disabled={busy} onClick={() => setConfirmId('')}>keep</Button></span>
              : <Button kind="mini" disabled={busy} onClick={() => { setMsg(null); setConfirmId(s(n.EntityId)) }}>remove</Button>)}
          </li>))}
      </ul>
      {msg && <div className="mt-2"><Status bad={msg.bad}>{msg.text}</Status></div>}
      {canEdit && <AddChild node={node} />}
    </Panel>
  )
}

/** Add a location inside this one. The types offered are exactly those ref.vLocationNodeTypeParent allows under this
 * node's type — a Yard under a Station, a Bay under a Yard, an EquipmentPosition under a Bay — so the screen never
 * restates the rule the database holds. location.AddNode checks it again and its refusal is what is shown.
 * Siblings are entered in a run: after a successful add the type and subtype stay chosen, the name clears and takes the
 * cursor back, so the next yard or bay is one field and one key. */
function AddChild({ node }: { node: Row }) {
  const qc = useQueryClient()
  const parentType = s(node.NodeTypeCode)
  const rulesQ = useViewAll('ref', 'vLocationNodeTypeParent', { ParentNodeTypeCode: parentType }, 'ChildNodeTypeCode', !!parentType)
  const { byCode, isPending: typesPending } = useNodeTypes()
  const [type, setType] = useState(''); const [name, setName] = useState(''); const [sub, setSub] = useState(''); const [notes, setNotes] = useState('')
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null); const [busy, setBusy] = useState(false)
  const nameRef = useRef<HTMLInputElement>(null)
  const options = (rulesQ.data ?? [])
    .map((x) => ({ code: s(x.ChildNodeTypeCode), name: s(byCode.get(s(x.ChildNodeTypeCode))?.Name) || s(x.ChildNodeTypeCode), required: !!x.IsRequired }))
    .sort((a, b) => (Number(b.required) - Number(a.required)) || a.name.localeCompare(b.name))
  const chosen = options.some((o) => o.code === type) ? type : (options[0]?.code ?? '')
  if (rulesQ.isPending || typesPending) return <p className="mt-3 border-t border-slate-800 pt-2 text-xs text-slate-500">…</p>
  if (rulesQ.isError) return <div className="mt-3 border-t border-slate-800 pt-2"><Status bad>Could not read what may go inside: {(rulesQ.error as Error).message}</Status></div>
  if (!options.length) return (
    <div className="mt-3 border-t border-slate-800 pt-2">
      <Status>Nothing may be recorded inside a {s(byCode.get(parentType)?.Name) || parentType} — it is the bottom of the tree.</Status>
    </div>)
  const add = async () => {
    const nm = name.trim()
    if (!nm) { setMsg({ text: 'A name is needed.', bad: true }); nameRef.current?.focus(); return }
    setBusy(true)
    try {
      await proc('location', 'AddNode', { NodeTypeCode: chosen, ParentEntityId: node.EntityId, Name: nm, SubtypeCode: sub.trim() || null, Notes: notes.trim() || null })
      setMsg({ text: `${nm} added inside ${s(node.Name)}.` })
      setType(chosen); setName(''); setNotes(''); refreshTree(qc)
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false); nameRef.current?.focus() }
  }
  return (
    <div className="mt-3 space-y-2 border-t border-slate-800 pt-2 text-sm">
      <div className="flex flex-wrap items-end gap-2">
        <label className="flex flex-col gap-1 text-xs text-slate-400">Add a
          <select className={`${inputClass} w-44`} value={chosen} disabled={busy} onChange={(e) => { setType(e.target.value); setSub('') }}>
            {options.map((o) => <option key={o.code} value={o.code}>{o.name}</option>)}
          </select></label>
        <label className="flex flex-col gap-1 text-xs text-slate-400">called
          <input ref={nameRef} className={`${inputClass} w-56`} value={name} disabled={busy} placeholder="e.g. 345 kV Yard"
            onChange={(e) => setName(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); void add() } }} /></label>
        <label className="flex flex-col gap-1 text-xs text-slate-400">subtype
          <SubtypeBox nodeTypeCode={chosen} value={sub} disabled={busy} onChange={setSub} /></label>
        <Button kind="primary" disabled={busy} onClick={() => void add()}>Add</Button>
      </div>
      <label className="flex flex-col gap-1 text-xs text-slate-400">Notes (optional)
        <textarea className={`${inputClass} w-full`} rows={1} value={notes} disabled={busy} onChange={(e) => setNotes(e.target.value)} /></label>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </div>
  )
}

/** The devices placed at or under this node. location.vFloc is the read — it is the only one that gives the device's name
 * beside its position and panel (asset.vPlacement carries AssetEntityId and NodeEntityId and no name at all). vFloc can be
 * filtered by station, so the station's rows are read and, for a node below the station, kept when the position's Path
 * runs through this node (Path is the ancestors' chain, so a building's id is in every position's Path beneath it). */
function DevicesHere({ node, station, isStation }: { node: Row; station: Row | undefined; isStation: boolean }) {
  const stationId = s(station?.EntityId)
  const q = useViewAll('location', 'vFloc', { StationNodeEntityId: stationId }, 'PositionName', !!stationId)
  const me = s(node.EntityId).toLowerCase()
  const rows = (q.data ?? []).filter((x) => x.InstalledAssetEntityId && (isStation || ancestorIds(x.Path).some((a) => a.toLowerCase() === me) || s(x.NodeEntityId).toLowerCase() === me))
  return (
    <Panel title={`Devices placed here · ${!stationId ? '—' : q.isPending ? '…' : rows.length}`}>
      {!stationId && <Status>This node is above any station, so the devices are listed on the stations inside it.</Status>}
      {q.isError && <Status bad>Could not read the devices: {(q.error as Error).message}</Status>}
      {!!stationId && !q.isPending && !rows.length && <Status>No device is placed here.</Status>}
      {rows.length > 0 && (
        <table className="w-full text-sm">
          <thead><tr className="border-b border-slate-700 text-left text-xs uppercase tracking-wide text-slate-400">
            <th className="py-1 pr-2">Device</th><th className="py-1 pr-2">Model</th><th className="py-1 pr-2">Panel</th><th className="py-1">Position</th></tr></thead>
          <tbody>
            {rows.map((x) => (
              <tr key={s(x.NodeEntityId)} className="border-b border-slate-800">
                <td className="py-1 pr-2 text-slate-200">{s(x.InstalledAssetName)}<div className="text-xs text-slate-500">{s(x.Functions)}</div></td>
                <td className="py-1 pr-2 text-slate-400">{s(x.ModelCode) || s(x.ModelName)}{x.Technology ? <span className="ml-1 text-xs text-slate-500">{s(x.Technology)}</span> : null}</td>
                <td className="py-1 pr-2"><NodeLink id={s(x.PanelNodeEntityId)} name={s(x.PanelName)} /></td>
                <td className="py-1 text-slate-200"><NodeLink id={s(x.NodeEntityId)} name={s(x.PositionName)} /></td>
              </tr>))}
          </tbody>
        </table>)}
    </Panel>
  )
}

/** The primary assets with a terminal at this station (asset.vAssetTerminalDetail by station; the asset's name and type
 * come from asset.vPrimaryAsset, which the terminal view does not carry). */
function PrimaryAssetsHere({ stationId }: { stationId: string }) {
  const navigate = useNavigate()
  const q = useQuery({ queryKey: ['stationTerminals', stationId], enabled: !!stationId, staleTime: 60_000, queryFn: async () => {
    const terms = (await view('asset', 'vAssetTerminalDetail', { StationNodeEntityId: stationId }, { take: 500, orderBy: 'TerminalNo' })).rows
    const names = new Map<string, Row>()
    const out: Row[] = []
    for (const t of terms) {
      const key = s(t.AssetEntityId).toLowerCase()
      if (!names.has(key)) names.set(key, (await view('asset', 'vPrimaryAsset', { EntityId: s(t.AssetEntityId) }, { take: 1 })).rows[0] ?? {})
      const a = names.get(key)!
      out.push({ ...t, AssetName: a.Name, AssetTypeName: a.AssetTypeName })
    }
    return out.sort((x, y) => s(x.AssetName).localeCompare(s(y.AssetName)))
  } })
  const rows = q.data ?? []
  return (
    <Panel title={`Primary assets with a terminal here · ${q.isPending ? '…' : rows.length}`}>
      {q.isError && <Status bad>Could not read the terminals: {(q.error as Error).message}</Status>}
      {!q.isPending && !rows.length && <Status>No primary asset has a terminal recorded at this station.</Status>}
      {rows.length > 0 && (
        <table className="w-full text-sm">
          <thead><tr className="border-b border-slate-700 text-left text-xs uppercase tracking-wide text-slate-400">
            <th className="py-1 pr-2">Primary asset</th><th className="py-1 pr-2">Type</th><th className="py-1 pr-2">Terminal</th><th className="py-1 pr-2">kV</th><th className="py-1">Bus</th></tr></thead>
          <tbody>
            {rows.map((t) => (
              <tr key={s(t.TerminalEntityId)} className="border-b border-slate-800">
                <td className="py-1 pr-2"><a className="text-sky-300 underline" href={screenPath('PRIMARY_ASSET', s(t.AssetEntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('PRIMARY_ASSET', s(t.AssetEntityId))) }}>{s(t.AssetName) || s(t.AssetEntityId).slice(0, 8)}</a></td>
                <td className="py-1 pr-2 text-slate-400">{s(t.AssetTypeName)}</td>
                <td className="py-1 pr-2 text-slate-200">{s(t.TerminalNo)}</td>
                <td className="py-1 pr-2 text-slate-200">{s(t.VoltageClassCode) || '—'}</td>
                <td className="py-1 text-slate-200">{s(t.BusName) || <span className="text-slate-500">no bus linked</span>}{t.BusNpcc ? <span className="ml-2 text-xs text-slate-500">NPCC {s(t.BusNpcc)}</span> : null}</td>
              </tr>))}
          </tbody>
        </table>)}
    </Panel>
  )
}

/** The schemes whose devices sit at this station (scheme.vSchemeStation). */
function SchemesHere({ stationId }: { stationId: string }) {
  const navigate = useNavigate()
  const q = useViewAll('scheme', 'vSchemeStation', { StationNodeEntityId: stationId }, 'SchemeName', !!stationId)
  const rows = q.data ?? []
  return (
    <Panel title={`Schemes here · ${q.isPending ? '…' : rows.length}`}>
      {!q.isPending && !rows.length && <Status>No scheme has a device placed at this station.</Status>}
      <ul className="space-y-1 text-sm">
        {rows.map((x) => (
          <li key={s(x.SchemeEntityId)}>
            <a className="text-sky-300 underline" href={screenPath('SCHEME', s(x.SchemeEntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('SCHEME', s(x.SchemeEntityId))) }}>{s(x.SchemeName)}</a>
            <span className="ml-2 text-xs text-slate-500">{s(x.SchemeStatus)}</span>
          </li>))}
      </ul>
    </Panel>
  )
}
