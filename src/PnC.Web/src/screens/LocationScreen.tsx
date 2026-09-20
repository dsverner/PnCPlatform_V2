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
// #175 (2026-09-17): every level of the tree carries a Code — its one segment of the functional location — and the
// database composes the whole FLOC from the run of coded ancestors (location.Node.Code, location.Node.FlocCode; both on
// location.vNode). The owner, 2026-09-17: "for each of the various levels, ie. Y230, T3 etc. can we have a field 'code'
// which contains the code used in the FLOC and then many a Name and/or Description etc." So: Code is the segment
// (`Y230`), Name stays the descriptive label ("230 kV yard"), Notes stays the description. The FLOC itself is shown and
// never typed — composing it is what keeps it true when a node moves.
//
// #174 (2026-09-17): the tree is built here, by hand. The owner, 2026-09-17: "lets start building out the terminal
// equipment FLOCS for Eel River… I believe that the application needs to be able to create these… for now, lets work on
// user functionality." So: a child is added inside this node (location.AddNode), the node itself is renamed or its
// subtype and notes changed (location.RenameNode), and a child is withdrawn (location.Node_SoftDelete). The types
// offered are only those ref.vLocationNodeTypeParent allows under THIS node's type — the rule lives in the database and
// is read, never restated in the client. Every refusal shown is the procedure's own message.
//
// #176 (2026-09-17): a device is placed at a position from here. The owner, 2026-09-17, having built a Building and a
// Panel at Eel River by hand: "Now how do I associate a protection with this panel?" The chain is panel → device
// position → protection function, and the relay is *placed* at the position — asset.PlaceAsset, the one way to say
// where an asset is (§4.4). So a position node shows what is placed at it and offers to place a device there; every
// other node keeps the read-only list of what is placed beneath it, because asset.PlaceAsset refuses a device anywhere
// but a DevicePosition or a custody location (50215) and the screen should not offer what the database forbids.
import { useRef, useState, type ReactNode } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ApiError, fmtDate, proc, s, sqlNumber, view, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type RecordParams, type Screen, screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status, inputClass } from '@/components/ui/ui'
import { AssetPicker, modelLabel, useModels } from '@/components/pickers'
import { workTypes, raiseAndAdvance } from '@/lib/actions'
import { ClassificationPanel, NODE_KINDS, NodeLink, bit } from './PrimaryAssetScreen'
import { INSTRUMENT_TRANSFORMER_TYPES } from './InstrumentTransformerScreen'
import { saveAssetCharacteristic, useTemplateDefs } from '@/components/CharacteristicsPanel'

/** #202 (the owner, 2026-09-19): on the transmission network an instrument transformer is a child of the Yard, not of a bay
 * ("later on … bays within buildings … for now, they are in the yards only"); a panel-mounted auxiliary CT or VT stands at a
 * Panel. asset.PlaceAsset refuses anything else (50218), so the form is offered only where the database will accept it. */
const IT_NODE_TYPES = ['Yard', 'Panel']
const IT_TYPES_AT: Record<string, string[]> = { Yard: ['CT', 'VT', 'COUPLING_CAPACITOR_VT', 'CCPD', 'METERING_UNIT'], Panel: ['CT_AUX', 'VT_AUX'] }

/** The node types location.vFloc treats as a position — the places a device is installed (and the only node types
 * asset.PlaceAsset accepts for a device: it demands NodeTypeCode = 'DevicePosition' and throws 50215 otherwise). */
const POSITION_TYPES = ['DevicePosition', 'MeteringPosition', 'NetworkSwitchPosition']
/** asset.Placement, CK_Placement_Kind — the five kinds, in the order a person meets them. */
const PLACEMENT_KINDS = ['Installed', 'Attached', 'Stored', 'AtVendor', 'Retained']

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
  // #195 follow-up (owner, 2026-09-19): a panel, a position, any node inside a building shows the rating it inherits, read-only, with its source
  const cipAllQ = useViewAll('asset', 'vClassification', { SubjectKind: 'Node', ClassificationKindCode: 'CipImpactRating' }, undefined, !!r && s(r.NodeTypeCode) !== 'Building')
  // #196 (owner, 2026-09-19): "the final CIP rating will depend on whether the device is a cyber asset or not" — on a position
  // the placed device's derived BES Cyber Asset status is shown beside the building's rating; the rating applies only to a BCA
  const placedQ = useViewAll('asset', 'vPlacedAsset', { NodeEntityId: s(r?.EntityId) }, undefined, !!r && POSITION_TYPES.includes(s(r.NodeTypeCode)))
  const placedId = s(placedQ.data?.[0]?.AssetEntityId)
  const bcaQ = useViewAll('asset', 'vClassification', { SubjectKind: 'Asset', SubjectEntityId: placedId, ClassificationKindCode: 'BesCyberAsset' }, undefined, !!placedId)
  const { byId: modelsById } = useModels()
  if (!id) return <Status bad>No location in the address.</Status>
  if (rowQ.isPending) return <Status>Loading the location…</Status>
  if (!r) return <Status bad>No node with that id is readable by you.</Status>
  const isStation = s(r.NodeTypeCode) === 'Station'
  const canEdit = can('Node.Modify'); const canArchive = can('Node.Archive')
  const ancestors = ancestorsQ.data ?? []
  const station = isStation ? r : ancestors.find((a) => s(a.NodeTypeCode) === 'Station')
  const note = flocNote(r, ancestors)
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-wrap items-center gap-2"><h1 className="text-lg font-semibold text-slate-100">{s(r.Name)}</h1>{s(r.FlocCode) ? <FlocTag floc={s(r.FlocCode)} /> : null}<Pill tone="accent">{s(r.NodeTypeCode)}</Pill>{r.SubtypeCode ? <Pill>{s(r.SubtypeCode)}</Pill> : null}</div>
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
            {note && <Status>{note}</Status>}
            {canEdit
              ? <NodeForm key={s(r.EntityId)} r={r} />
              : <Facts cols={1} pairs={[['Code', s(r.Code) || '—'], ['Name', s(r.Name)], ['Subtype', s(r.SubtypeCode) || '—'], ['Notes', s(r.Notes) || '—']]} />}
          </div>
        </Panel>
        {/* #195 (owner, 2026-09-19): the CIP impact rating is the building's — offered on a Building page only; a station shows its buildings' ratings in the list below */}
        {s(r.NodeTypeCode) === 'Building'
          ? <ClassificationPanel title="Applicability classifications" subjectKind="Node" subjectEntityId={s(r.EntityId)} editable={can('Asset.Modify')} kinds={NODE_KINDS}
              note="The CIP-002 impact rating of this building — every BES Cyber Asset housed in it inherits it (#173, #177, #195). Recorded by you from the entity's own CIP-002 evaluation in this phase; a value saves at once, audited." />
          : (() => {
              const rated = [...ancestors].reverse().map((a) => ({ a, c: (cipAllQ.data ?? []).find((c) => s(c.SubjectEntityId).toLowerCase() === s(a.EntityId).toLowerCase()) })).find((x) => x.c)
              return (
                <Panel title="Applicability classifications">
                  {s(r.NodeTypeCode) !== 'Station' && <Facts cols={1} pairs={[['CIP impact rating', rated
                    ? <span>{s(rated.c!.ClassificationValue)} <span className="text-slate-500">— inherited from <NodeLink id={s(rated.a.EntityId)} name={s(rated.a.Name)} /> ({s(rated.a.NodeTypeCode)})</span></span>
                    : <span className="text-slate-500">none — no building above this carries a rating yet</span>],
                    ...(POSITION_TYPES.includes(s(r.NodeTypeCode)) ? [['Device here', (() => {
                      const x = placedQ.data?.[0]; if (!x) return <span className="text-slate-500">nothing placed</span>
                      const tech = s(modelsById.get(s(x.ModelId).toLowerCase())?.Technology)
                      const bca = bcaQ.data?.[0]?.ClassificationValue
                      return <span>{s(x.AssetName)} <span className="text-slate-500">({tech || 'technology unknown'})</span> — {bca === 'BCA'
                        ? <span className="text-amber-200">BES Cyber Asset{rated ? `: ${s(rated.c!.ClassificationValue)} impact, from the building` : ''}</span>
                        : bca === 'Not BCA' ? <span className="text-slate-300">not a cyber asset; the building's rating does not apply to it</span>
                        : <span className="text-slate-500">cyber status not derived yet — evaluate compliance on its settings record</span>}</span>
                    })()] as [string, ReactNode]] : [])]} />}
                  <Status>The CIP-002 impact rating is recorded on a building — the BES Cyber Systems it houses take it. {s(r.NodeTypeCode) === 'Station' ? 'This station\'s buildings and their ratings are in the list below.' : 'Open the building to change it.'}</Status>
                </Panel>)
            })()}
      </div>
      <div className="grid gap-3 lg:grid-cols-2">
        <Inside node={r} canEdit={canEdit} canArchive={canArchive} />
        {POSITION_TYPES.includes(s(r.NodeTypeCode))
          ? <PlacedHere node={r} canPlace={can('Asset.Modify')} canRetract={can('Asset.Archive')} canRaise={can('WorkRequest.Modify')} />
          : <DevicesHere node={r} station={station} isStation={isStation} />}
      </div>
      {/* #201: the instrument transformers placed at this node — a bay, an equipment position, a yard, a panel — and a form to
          make one here. asset.PlaceAsset accepts a non-device asset at any node; the CT/VT is placed where it stands. */}
      {IT_NODE_TYPES.includes(s(r.NodeTypeCode)) && <InstrumentTransformersHere node={r} canEdit={can('Asset.Modify')} />}
      {/* a terminal and a scheme are asked of a station: neither question means anything for a building, a room or a panel */}
      {isStation && (
        <div className="grid gap-3 lg:grid-cols-2">
          <PrimaryAssetsHere stationId={s(r.EntityId)} />
          <SchemesHere stationId={s(r.EntityId)} />
        </div>)}
    </div>
  )
}

/** The composed functional location, as a person reads it off the equipment (location.vNode.FlocCode). Monospace and
 * select-all, so one click takes the whole tag; the copy button disappears rather than misbehaves where the clipboard
 * is refused. Never editable: the database composes it from the codes down the tree (#175). */
function FlocTag({ floc }: { floc: string }) {
  const [copied, setCopied] = useState(false); const [canCopy, setCanCopy] = useState(true)
  const copy = async () => {
    try { await navigator.clipboard.writeText(floc); setCopied(true); window.setTimeout(() => setCopied(false), 1500) }
    catch { setCanCopy(false) }
  }
  return (
    <span className="flex items-center gap-1">
      <code title="The functional location — composed by the platform from the code at each level, never typed"
        className="select-all rounded border border-slate-700 bg-slate-950 px-2 py-0.5 font-mono text-sm tracking-wide text-sky-200">{floc}</code>
      {canCopy && <Button kind="mini" onClick={() => void copy()}>{copied ? 'copied' : 'copy'}</Button>}
    </span>
  )
}

/** Why there is no FLOC, in plain words, said once. The rule (#175, ruled 2026-09-17): a node with no Code has no FLOC;
 * otherwise the FLOC is the unbroken run of coded ancestors ending here, so a coded node under an uncoded parent gets
 * only the part below that parent — never a guessed segment. Both cases are read off the ancestor chain already loaded
 * for "Where it sits". Nothing is said when the FLOC is whole: no code is the normal state across the estate today and
 * the screen does not nag about it. */
function flocNote(r: Row, ancestors: Row[]): string | null {
  if (!s(r.Code)) return 'No code yet — the FLOC needs one.'
  const parent = ancestors[ancestors.length - 1]
  if (parent && !s(parent.Code)) return `Partial — ${s(parent.Name)} has no code, so this is only the part below it.`
  return null
}

/** A node in a list: its code first where it has one, then its name as the link — `Y230 · 230 kV yard`. A node with no
 * code shows its name alone, with nothing in the code's place (#175). */
export function CodeName({ id, code, name }: { id: string; code: string; name: string }) {
  if (!code) return <NodeLink id={id} name={name} />
  return (
    <span className="inline-flex items-baseline gap-1">
      <span className="font-mono text-slate-300">{code}</span><span className="text-slate-600">·</span>
      <NodeLink id={id} name={name} />
    </span>)
}

/** Children in the order a person reads a tag list: the coded ones first, by code, then the uncoded by name. */
function byCodeThenName(a: Row, b: Row) {
  const ac = s(a.Code), bc = s(b.Code)
  if (ac && bc) return ac.localeCompare(bc, undefined, { numeric: true }) || s(a.Name).localeCompare(s(b.Name))
  if (ac !== bc) return ac ? -1 : 1
  return s(a.Name).localeCompare(s(b.Name))
}

/** Every location node type and the subtype enumeration attached to it, if it has one (ref.vLocationNodeType —
 * NodeTypeCode, Name, SubtypeListDefinitionRowId). One read, shared by every caller through the query cache. */
/** #180: does a node of this type add a segment to the FLOC? A protection function does not — the owner ruled that a
 * relay's tag ends at the position it stands in (TN-4134-BDG1-PNL12-21A), because the elements inside a microprocessor
 * relay would make a schematic drawing unreadable. ref.LocationNodeType.CarriesFlocSegment is the answer, and
 * location.AssertNodeCode refuses a code on such a type whatever a screen does. NULL means yes, for a type seeded
 * before the column existed. */
export const carriesFlocSegment = (typeRef: Row | undefined) =>
  !(typeRef && 'CarriesFlocSegment' in typeRef && bit(typeRef.CarriesFlocSegment) === false)

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

/** The node's own fields — its code, its name, its subtype and its notes. location.RenameNode, which keeps the node
 * where it is: the generated Node_Revise takes Path and Depth, which a client must never compute. A change saves at
 * once, audited.
 * #175: the Code goes through the same call. It is sent as a string always — never JSON null, which the dispatcher
 * reads as "not given" (SqlSession.cs) and which would leave a code impossible to remove; an empty string clears it.
 * What a code may contain is the procedure's rule, not this screen's: a code holding '-' or whitespace is refused
 * there and the refusal shown here, as #174 already does for a bad subtype. */
function NodeForm({ r }: { r: Row }) {
  const qc = useQueryClient()
  const [f, setF] = useState({ Code: s(r.Code), Name: s(r.Name), SubtypeCode: s(r.SubtypeCode), Notes: s(r.Notes) })
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null); const [busy, setBusy] = useState(false)
  const dirty = f.Code !== s(r.Code) || f.Name !== s(r.Name) || f.SubtypeCode !== s(r.SubtypeCode) || f.Notes !== s(r.Notes)
  const save = async () => {
    if (!f.Name.trim()) { setMsg({ text: 'A location needs a name.', bad: true }); return }
    setBusy(true)
    try {
      await proc('location', 'RenameNode', { EntityId: r.EntityId, Code: f.Code.trim(), Name: f.Name.trim(), SubtypeCode: f.SubtypeCode.trim() || null, Notes: f.Notes.trim() || null })
      setMsg({ text: `${f.Name.trim()} saved.` }); refreshTree(qc)
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  return (
    <div className="space-y-2 text-sm">
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      <div className="grid grid-cols-[8rem_1fr] items-start gap-2">
        <label className="text-slate-400">Code</label>
        <input className={`${inputClass} w-32 font-mono`} value={f.Code} disabled={busy} onChange={(e) => setF({ ...f, Code: e.target.value })} placeholder="e.g. Y230" />
        <label className="text-slate-400">Name</label>
        <input className={`${inputClass} w-64`} value={f.Name} disabled={busy} onChange={(e) => setF({ ...f, Name: e.target.value })} placeholder="e.g. 345 kV Yard" />
        <label className="text-slate-400">Subtype</label>
        <SubtypeBox nodeTypeCode={s(r.NodeTypeCode)} value={f.SubtypeCode} disabled={busy} onChange={(v) => setF({ ...f, SubtypeCode: v })} />
        <label className="text-slate-400">Notes</label>
        <textarea className={`${inputClass} w-full`} rows={2} value={f.Notes} disabled={busy} onChange={(e) => setF({ ...f, Notes: e.target.value })} />
      </div>
      <Button kind="primary" disabled={!dirty || busy} onClick={() => void save()}>Save</Button>
      <Status>The code is this level's one segment of the FLOC; the FLOC itself is composed from the codes above and is never typed. The name is the descriptive label and the notes the description.</Status>
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
  const rows = [...(q.data ?? [])].sort(byCodeThenName)
  // #195: a station's buildings carry the CIP impact rating; shown here, read-only, so the station still tells you
  const cipQ = useViewAll('asset', 'vClassification', { SubjectKind: 'Node', ClassificationKindCode: 'CipImpactRating' }, undefined, s(node.NodeTypeCode) === 'Station')
  const cipOf = (id: string) => (cipQ.data ?? []).find((c) => s(c.SubjectEntityId).toLowerCase() === id.toLowerCase())?.ClassificationValue
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
            <CodeName id={s(n.EntityId)} code={s(n.Code)} name={s(n.Name)} />
            <span className="text-xs text-slate-500">{s(n.NodeTypeCode)}{n.SubtypeCode ? ' · ' + s(n.SubtypeCode) : ''}</span>
            {s(node.NodeTypeCode) === 'Station' && s(n.NodeTypeCode) === 'Building' && (cipOf(s(n.EntityId))
              ? <span className="text-xs text-sky-300">CIP {s(cipOf(s(n.EntityId)))}</span>
              : <span className="text-xs text-slate-500">— no CIP rating yet; open the building to enter it</span>)}
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
 * Siblings are entered in a run: after a successful add the type and subtype stay chosen, the name and code clear and
 * the cursor goes back to the code, so the next yard or bay is two fields and one key.
 * #175: the code is entered beside the name and in front of it — a person working from a tag list types `Y230` first
 * and "230 kV yard" after — and goes to location.AddNode as @Code. */
function AddChild({ node }: { node: Row }) {
  const qc = useQueryClient()
  const parentType = s(node.NodeTypeCode)
  const rulesQ = useViewAll('ref', 'vLocationNodeTypeParent', { ParentNodeTypeCode: parentType }, 'ChildNodeTypeCode', !!parentType)
  const { byCode, isPending: typesPending } = useNodeTypes()
  const [type, setType] = useState(''); const [name, setName] = useState(''); const [code, setCode] = useState(''); const [sub, setSub] = useState(''); const [notes, setNotes] = useState('')
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null); const [busy, setBusy] = useState(false)
  const nameRef = useRef<HTMLInputElement>(null); const codeRef = useRef<HTMLInputElement>(null)
  const options = (rulesQ.data ?? [])
    .map((x) => ({ code: s(x.ChildNodeTypeCode), name: s(byCode.get(s(x.ChildNodeTypeCode))?.Name) || s(x.ChildNodeTypeCode), required: !!x.IsRequired }))
    .sort((a, b) => (Number(b.required) - Number(a.required)) || a.name.localeCompare(b.name))
  const chosen = options.some((o) => o.code === type) ? type : (options[0]?.code ?? '')
  // #180: a type whose nodes are not part of the tag is not asked for a code
  const takesCode = carriesFlocSegment(byCode.get(chosen))
  if (rulesQ.isPending || typesPending) return <p className="mt-3 border-t border-slate-800 pt-2 text-xs text-slate-500">…</p>
  if (rulesQ.isError) return <div className="mt-3 border-t border-slate-800 pt-2"><Status bad>Could not read what may go inside: {(rulesQ.error as Error).message}</Status></div>
  if (!options.length) return (
    <div className="mt-3 border-t border-slate-800 pt-2">
      <Status>Nothing may be recorded inside a {s(byCode.get(parentType)?.Name) || parentType} — it is the bottom of the tree.</Status>
    </div>)
  const add = async () => {
    const nm = name.trim(); const cd = code.trim()
    if (!nm) { setMsg({ text: 'A name is needed.', bad: true }); nameRef.current?.focus(); return }
    setBusy(true)
    try {
      await proc('location', 'AddNode', { NodeTypeCode: chosen, ParentEntityId: node.EntityId, Code: takesCode ? cd : '', Name: nm, SubtypeCode: sub.trim() || null, Notes: notes.trim() || null })
      setMsg({ text: `${takesCode && cd ? cd + ' · ' : ''}${nm} added inside ${s(node.Name)}.` })
      setType(chosen); setName(''); setCode(''); setNotes(''); refreshTree(qc)
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false); codeRef.current?.focus() }
  }
  return (
    <div className="mt-3 space-y-2 border-t border-slate-800 pt-2 text-sm">
      <div className="flex flex-wrap items-end gap-2">
        <label className="flex flex-col gap-1 text-xs text-slate-400">Add a
          <select className={`${inputClass} w-44`} value={chosen} disabled={busy} onChange={(e) => { setType(e.target.value); setSub('') }}>
            {options.map((o) => <option key={o.code} value={o.code}>{o.name}</option>)}
          </select></label>
        {takesCode && <label className="flex flex-col gap-1 text-xs text-slate-400">code
          <input ref={codeRef} className={`${inputClass} w-24 font-mono`} value={code} disabled={busy} placeholder="Y230"
            onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); void add() } }} /></label>}
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
      {/* #176: a device is placed at a position, never at a panel or a building — asset.PlaceAsset refuses it (50215) */}
      {!!stationId && <Status>A device is placed at a position, not at a {s(node.NodeTypeCode).toLowerCase()} — open the position in the last column to place, move or remove one.</Status>}
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

// ---------------------------------------------------------------- #176: what is placed at this position

/**
 * What is placed at this position, and how a device is placed here.
 *
 * The read is asset.vPlacedAsset filtered by NodeEntityId — the view written for exactly this question (the placement
 * joined to the asset, so the name comes back with it; asset.vPlacement carries ids and no name at all). Its columns:
 * EntityId (the placement), NodeEntityId, AssetEntityId, AssetName, AssetTypeCode, AssetStatus, VoltageClassCode,
 * ModelId, ManufacturerEntityId, CommissionedAt, PlacementKind, CustodyLocationEntityId, WorkRequestEntityId,
 * PlacedFrom, PlacedTo.
 *
 * The write is asset.PlaceAsset (Asset.Modify) — the one way to say where an asset is. It writes the placement as an
 * Add, or as a Revise that closes the asset's prior fact, and for a device it writes the Installed / Removed lifecycle
 * events in the same transaction, so the two never disagree (§5.4).
 */
/**
 * #181: the elements in service at this position. What the relay CAN do is its model's scheme.vFunctionCapability list,
 * authored by an admin from the manufacturer's manual; what it DOES here is a tick against the position, one
 * scheme.CommissionedFunction row each, read back through scheme.vPositionFunction with the element's name.
 *
 * The owner, 2026-09-17: "the devices really do have all those different elements and they are used", and, on what a
 * newly placed relay starts with, "If a new device is added, none ticked but when a standard template is used then it
 * should follow the template." So nothing is ticked by itself; the standard-template preselect is its own increment.
 *
 * A model nobody has written a capability list for says so, rather than showing an empty box a person cannot fill: the
 * list is the admin's to author, not the technician's to invent.
 */
function FunctionChecklist({ nodeId, modelId, editable }: { nodeId: string; modelId: string; editable: boolean }) {
  const qc = useQueryClient()
  const caps = useViewAll('scheme', 'vFunctionCapability', { ModelId: modelId }, 'AnsiCode', !!modelId)
  const on = useViewAll('scheme', 'vPositionFunction', { PositionNodeEntityId: nodeId }, 'AnsiCode', !!nodeId)
  const names = useViewAll('ref', 'vAnsiFunction', {}, 'AnsiCode')
  const [busy, setBusy] = useState('')
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const nameOf = new Map((names.data ?? []).map((a) => [s(a.AnsiCode), s(a.Name)]))
  // #182, the owner: elements with no device number "are part of the device and must be included. When no numbers can be
  // found for the functionality, wording will have to suffice." So a C37.2 number is shown as a number and everything
  // else is shown as its words alone — never as a code pretending to be one.
  const isNum = new Map((names.data ?? []).map((a) => [s(a.AnsiCode), bit(a.IsDeviceNumber)]))
  const ticked = new Map((on.data ?? []).map((r) => [s(r.AnsiCode), r]))
  const list = caps.data ?? []
  const refresh = () => qc.invalidateQueries({ queryKey: ['view', 'scheme'] })
  const toggle = async (code: string) => {
    setBusy(code); setMsg(null)
    try {
      const row = ticked.get(code)
      if (row) { await proc('scheme', 'CommissionedFunction_SoftDelete', { EntityId: row.EntityId }); setMsg({ text: `${code} is no longer in service here.` }) }
      else { await proc('scheme', 'CommissionedFunction_Add', { ProtectionFunctionNodeEntityId: nodeId, AnsiCode: code }); setMsg({ text: `${code} ${nameOf.get(code) ?? ''} is in service here.` }) }
      refresh()
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy('') }
  }
  if (caps.isPending) return null
  if (!list.length) return (
    <div className="mt-2 border-t border-slate-800 pt-2">
      <Status>No element list has been recorded for this model yet. An administrator builds it from the manufacturer's manual, and it then appears here for every relay of this model.</Status>
    </div>)
  return (
    <div className="mt-2 space-y-1 border-t border-slate-800 pt-2">
      <div className="text-xs text-slate-400">Elements in service here — what this model can do, from its manual</div>
      <div className="flex flex-wrap gap-x-4 gap-y-1">
        {list.map((c) => { const code = s(c.AnsiCode); const isOn = ticked.has(code)
          return (
            <label key={code} className="flex items-center gap-1.5 text-sm">
              <input type="checkbox" id={`fn-${nodeId}-${code}`} checked={isOn} disabled={!editable || busy === code}
                onChange={() => void toggle(code)} />
              <span className={isOn ? 'text-slate-200' : 'text-slate-500'}>
                {isNum.get(code) ? <><span className="font-mono">{code}</span> {nameOf.get(code) ?? ''}</> : (nameOf.get(code) || code)}
              </span>
            </label>) })}
      </div>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      {!editable && <Status>You may not change what is in service here.</Status>}
    </div>)
}

function PlacedHere({ node, canPlace, canRetract, canRaise }: { node: Row; canPlace: boolean; canRetract: boolean; canRaise: boolean }) {
  const qc = useQueryClient()
  const nodeId = s(node.EntityId)
  const q = useViewAll('asset', 'vPlacedAsset', { NodeEntityId: nodeId }, 'AssetName', !!nodeId)
  const { byId } = useModels()
  const rows = q.data ?? []
  const refresh = () => { qc.invalidateQueries({ queryKey: ['view', 'asset'] }); qc.invalidateQueries({ queryKey: ['placementOf'] }); qc.invalidateQueries({ queryKey: ['view', 'location'] }) }
  return (
    <Panel title={`Placed here · ${q.isPending ? '…' : rows.length}`}>
      {q.isError && <Status bad>Could not read what is placed here: {(q.error as Error).message}</Status>}
      {!q.isPending && !rows.length && <Status>Nothing is placed at this position.</Status>}
      <ul className="space-y-2 text-sm">
        {rows.map((x) => (
          <PlacedRow key={s(x.EntityId)} x={x} model={byId.get(s(x.ModelId).toLowerCase())} nodeName={s(node.Name)}
            canPlace={canPlace} canRetract={canRetract} onDone={refresh} />))}
      </ul>
      {/* #181: the elements the placed relay performs here */}
      {rows.length > 0 && <FunctionChecklist nodeId={nodeId} modelId={s(rows[0].ModelId)} editable={canPlace} />}
      {/* #187: the first settings of a relay placed here that has none */}
      {rows.length > 0 && <FirstSettings node={node} relay={rows[0]} canRaise={canRaise} />}
      {canPlace
        ? <>
            <PlaceForm node={node} onDone={refresh} />
            {!rows.length && <NewRelayForm node={node} onDone={refresh} />}
          </>
        : <div className="mt-3 border-t border-slate-800 pt-2"><Status>Placing a device needs Asset.Modify.</Status></div>}
    </Panel>
  )
}

/**
 * One placed asset, and the three things that can be done to it — all of them the database's own, none invented:
 *  - change the kind: asset.PlaceAsset at this same node with another PlacementKind. A device that was Installed and
 *    becomes anything else gets its Removed lifecycle event written in the same transaction.
 *  - send it to custody: asset.PlaceAsset with @CustodyLocationEntityId instead of @NodeEntityId. This is how a
 *    placement at a position ENDS: asset.Placement demands exactly one of the two (CK_Placement_OneLocation, and 50211
 *    in the procedure), so an asset is never nowhere. There is no "unplace" and none is offered.
 *  - recorded in error: asset.Placement_SoftDelete (Asset.Archive). Decision 71 — a soft delete closes the belief only
 *    and leaves ValidTo untouched. It says the placement was never true, not that the relay was taken out; the wording
 *    on the button says so, because the two are different facts and the second one is the custody move above.
 */
function PlacedRow({ x, model, nodeName, canPlace, canRetract, onDone }: {
  x: Row; model: Row | undefined; nodeName: string; canPlace: boolean; canRetract: boolean; onDone: () => void }) {
  const [open, setOpen] = useState(false)
  const [kind, setKind] = useState(s(x.PlacementKind))
  const [custody, setCustody] = useState('')
  const [confirm, setConfirm] = useState(false)
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const custodyQ = useViewAll('location', 'vCustodyLocation', {}, 'Name', open)
  const run = async (body: Row, said: string) => {
    setBusy(true)
    try { await proc('asset', 'PlaceAsset', body); setMsg({ text: said }); setOpen(false); onDone() }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const retract = async () => {
    setBusy(true)
    try { await proc('asset', 'Placement_SoftDelete', { EntityId: x.EntityId }); setMsg({ text: `The record of ${s(x.AssetName)} at ${nodeName} is withdrawn.` }); setConfirm(false); onDone() }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  return (
    <li className="rounded border border-slate-800 p-2">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-slate-200">{s(x.AssetName)}</span>
        <span className="text-xs text-slate-500">{modelLabel(model) || s(x.AssetTypeCode)}</span>
        <Pill tone={x.PlacementKind === 'Installed' ? 'good' : 'neutral'}>{s(x.PlacementKind)}</Pill>
        {x.AssetStatus ? <span className="text-xs text-slate-500">{s(x.AssetStatus)}</span> : null}
        {x.PlacedFrom ? <span className="text-xs text-slate-500">since {fmtDate(x.PlacedFrom)}</span> : null}
        {(canPlace || canRetract) && <Button kind="mini" disabled={busy} onClick={() => { setMsg(null); setOpen(!open) }}>{open ? 'done' : 'change…'}</Button>}
      </div>
      {open && (
        <div className="mt-2 space-y-2 border-t border-slate-800 pt-2">
          {canPlace && (
            <div className="flex flex-wrap items-end gap-2">
              <label className="flex flex-col gap-1 text-xs text-slate-400">Kind
                <select className={`${inputClass} w-36`} value={kind} disabled={busy} onChange={(e) => setKind(e.target.value)}>
                  {PLACEMENT_KINDS.map((k) => <option key={k} value={k}>{k}</option>)}
                </select></label>
              <Button kind="mini" disabled={busy || kind === s(x.PlacementKind)}
                onClick={() => void run({ AssetEntityId: x.AssetEntityId, NodeEntityId: x.NodeEntityId, PlacementKind: kind },
                  `${s(x.AssetName)} is now ${kind.toLowerCase()} at ${nodeName}.`)}>Change the kind</Button>
            </div>)}
          {canPlace && (
            <div className="flex flex-wrap items-end gap-2">
              <label className="flex flex-col gap-1 text-xs text-slate-400">Or send it to
                <select className={`${inputClass} w-56`} value={custody} disabled={busy} onChange={(e) => setCustody(e.target.value)}>
                  <option value="">— a custody location —</option>
                  {(custodyQ.data ?? []).map((c) => <option key={s(c.EntityId)} value={s(c.EntityId)}>{s(c.Name)}{c.CustodyKind ? ` · ${s(c.CustodyKind)}` : ''}</option>)}
                </select></label>
              <Button kind="mini" disabled={busy || !custody}
                onClick={() => void run({ AssetEntityId: x.AssetEntityId, CustodyLocationEntityId: custody, PlacementKind: 'Stored' },
                  `${s(x.AssetName)} is stored in custody; the position is free.`)}>Remove to custody</Button>
              <Status>This is how a placement here ends — an asset is at a node or in a custody location, never nowhere.</Status>
            </div>)}
          {canRetract && (confirm
            ? <div className="flex flex-wrap items-center gap-2 text-xs text-amber-300">Withdraw the record that {s(x.AssetName)} is here — it was entered in error?
                <Button kind="mini" disabled={busy} onClick={() => void retract()}>yes, withdraw the record</Button>
                <Button kind="mini" disabled={busy} onClick={() => setConfirm(false)}>keep it</Button></div>
            : <Button kind="mini" disabled={busy} onClick={() => setConfirm(true)}>recorded in error…</Button>)}
        </div>)}
      {msg && <div className="mt-1"><Status bad={msg.bad}>{msg.text}</Status></div>}
    </li>
  )
}

/**
 * Place a device at this position. asset.PlaceAsset, with @NodeEntityId (never both locations — 50211) and a
 * @PlacementKind defaulting to Installed, because that is what a technician is doing when they stand at the panel.
 *
 * Every refusal is the procedure's own words. The one a person actually hits is the device category against the
 * position subtype (§5.7), and the two numbers behind it are different questions:
 *   50216 — the categories differ AND the actor holds no PlacementOverride grant. A reason cannot help; the message
 *           says what is missing and the entry stays as it is.
 *   50217 — the actor holds the grant but gave no @OverrideReason. That one is answerable here: the reason box opens,
 *           the chosen device and kind stay, and the same Place button tries again with the reason, which the
 *           procedure logs through audit.LogAction as an Override.
 * The others (50212 not a current asset, 50213 a routed asset has a route and not a placement, 50214 not a current
 * node, 50215 a device belongs at a DevicePosition) are shown as they come.
 *
 * Nothing is pre-empted in the client — in particular the position's filtered unique index
 * (UX_Placement_InstalledAtNode: one Installed asset per node) is left to say no, and the API returns it as a 409.
 */
function PlaceForm({ node, onDone }: { node: Row; onDone: () => void }) {
  const [picked, setPicked] = useState<Row | null>(null)
  const [kind, setKind] = useState('Installed')
  const [notes, setNotes] = useState('')
  const [reason, setReason] = useState('')
  const [askReason, setAskReason] = useState(false)
  const [busy, setBusy] = useState(false)
  const [round, setRound] = useState(0)
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const place = async () => {
    if (!picked) return
    setBusy(true)
    try {
      await proc('asset', 'PlaceAsset', {
        AssetEntityId: picked.EntityId, NodeEntityId: node.EntityId, PlacementKind: kind,
        Notes: notes.trim() || null, OverrideReason: reason.trim() || null,
      })
      setMsg({ text: `${s(picked.Name)} is ${kind.toLowerCase()} at ${s(node.Name)}.` })
      setPicked(null); setNotes(''); setReason(''); setAskReason(false); setRound(round + 1); onDone()
    } catch (e) {
      setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true })
      if (sqlNumber(e) === 50217) setAskReason(true)          // the grant is held; the reason is what is missing
    } finally { setBusy(false) }
  }
  return (
    <div className="mt-3 space-y-2 border-t border-slate-800 pt-2 text-sm">
      <div className="flex flex-wrap items-end gap-2">
        <AssetPicker value={picked} onChange={(a) => { setPicked(a); setMsg(null) }} label="Place a device" autoFocusKey={`place-${round}`}
          note="any part of the name; two of the same name are told apart by the model" disabled={busy} />
        <label className="flex flex-col gap-1 text-xs text-slate-400">as
          <select className={`${inputClass} w-36`} value={kind} disabled={busy} onChange={(e) => setKind(e.target.value)}>
            {PLACEMENT_KINDS.map((k) => <option key={k} value={k}>{k}</option>)}
          </select></label>
        <Button kind="primary" disabled={!picked || busy} onClick={() => void place()}>Place</Button>
      </div>
      {picked && <PlacedNow assetEntityId={s(picked.EntityId)} hereNodeEntityId={s(node.EntityId)} />}
      <label className="flex flex-col gap-1 text-xs text-slate-400">Notes (optional — they go on the lifecycle event)
        <textarea className={`${inputClass} w-full`} rows={1} value={notes} disabled={busy} onChange={(e) => setNotes(e.target.value)} /></label>
      {askReason && (
        <label className="flex flex-col gap-1 text-xs text-amber-300">Override reason — the device's category and this position's subtype differ; the reason is logged with your name
          <input className={`${inputClass} w-full`} value={reason} disabled={busy} placeholder="why this device goes in this position"
            onChange={(e) => setReason(e.target.value)} /></label>)}
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </div>
  )
}

/** Where the chosen asset is recorded now (asset.vPlacement by AssetEntityId, then the node's or custody location's
 * name). Not a warning and not a pre-emption of a rule: asset.PlaceAsset revises an asset's existing placement rather
 * than refusing it, so placing a relay that is installed elsewhere MOVES it and writes its Removed event. A person
 * should see that before they press the button, not discover it after. */
function PlacedNow({ assetEntityId, hereNodeEntityId }: { assetEntityId: string; hereNodeEntityId: string }) {
  const q = useQuery({ queryKey: ['placementOf', assetEntityId], enabled: !!assetEntityId, staleTime: 30_000, queryFn: async () => {
    const p = (await view('asset', 'vPlacement', { AssetEntityId: assetEntityId }, { take: 1 })).rows[0]
    if (!p) return null
    const where = p.NodeEntityId
      ? (await view('location', 'vNode', { EntityId: s(p.NodeEntityId) }, { take: 1 })).rows[0]
      : (await view('location', 'vCustodyLocation', { EntityId: s(p.CustodyLocationEntityId) }, { take: 1 })).rows[0]
    return { ...p, WhereName: s(where?.Name), WhereFloc: s(where?.FlocCode) } as Row
  } })
  if (q.isPending || !q.data) return null
  const p = q.data
  if (s(p.NodeEntityId).toLowerCase() === hereNodeEntityId.toLowerCase())
    return <Status>It is already recorded here as {s(p.PlacementKind)}.</Status>
  return <Status>It is recorded now as {s(p.PlacementKind)} at {s(p.WhereName) || 'a place you cannot read'}{p.WhereFloc ? ` (${s(p.WhereFloc)})` : ''} — placing it here moves it, and its removal from there is written in the same transaction.</Status>
}

/** The triggers step [1] of the settings-change procedure accepts (settings-change.procedure.json, capture `trigger`). */
const TRIGGERS = ['Project', 'Obligation', 'Finding', 'Misoperation', 'Advisory', 'Other']

/**
 * #187: the first settings request for the relay placed here. The owner, 2026-09-18, went the intuitive way — the
 * building, the panel, the record — and could not tell whether the relay had a template or how its settings would
 * begin; and "New setting here" was a right-click on a settings-book ROW, which a relay with no record does not have.
 * So the button sits with the relay, at its position. It appears only while the relay has no record in the settings
 * book (document.vSettingsRecord by DeviceEntityId — none). Raising it: a SETTINGS_ADD request scoped to this position
 * (as the settings book's own command scopes it), step [1] committed with the trigger chosen here, step [2] claimed and
 * its `devices` set drafted with this relay; the engineer finishes [2] (scheme, philosophy) at the work item, and its
 * commit drafts the settings from the model's template — every setting "not set", editable in the sheet.
 */
function FirstSettings({ node, relay, canRaise }: { node: Row; relay: Row; canRaise: boolean }) {
  const navigate = useNavigate()
  const relayId = s(relay.AssetEntityId)   // asset.vPlacedAsset: EntityId is the placement, AssetEntityId the relay
  const recQ = useViewAll('document', 'vSettingsRecord', { DeviceEntityId: relayId }, 'RevisionLabel', !!relayId)
  const typesQ = useQuery({ queryKey: ['workTypes'], queryFn: workTypes, staleTime: 5 * 60_000 })
  const [open, setOpen] = useState(false)
  const [trigger, setTrigger] = useState('Project')
  const [reference, setReference] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  if (recQ.isPending || (recQ.data ?? []).length > 0) return null
  const wt = (typesQ.data ?? []).find((t) => t.key === 'SETTINGS_ADD')
  const title = `New setting — ${s(relay.AssetName)} at ${s(node.Name)}`
  const go = async () => {
    if (!wt) return
    setBusy(true); setErr('')
    try {
      const id = await raiseAndAdvance({
        workTypeVersionRowId: wt.versionRowId, title, scopeKind: 'Node', scopeEntityId: s(node.EntityId), workflowKey: wt.workflowKey,
        commit: [{ stepId: 'REQUEST', capture: { trigger, sourceReference: reference.trim() || `first settings for ${s(relay.AssetName)} at ${s(node.Name)}` } }],
        draft: { stepId: 'SCOPE', values: { devices: [relayId] } },
      })
      navigate(screenPath('WORK_ITEM', id))
    } catch (e) { setErr('Refused: ' + (e instanceof ApiError ? e.status + ' ' : '') + (e as Error).message); setBusy(false) }
  }
  return (
    <div className="mt-3 space-y-2 border-t border-slate-800 pt-2 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-slate-400">{s(relay.AssetName)} has no settings in the settings book yet.</span>
        {canRaise
          ? <Button kind="primary" disabled={!wt || busy} title={wt ? undefined : 'the SETTINGS_ADD work type is not effective'} onClick={() => setOpen(!open)}>New setting</Button>
          : <span className="text-xs text-slate-500">(raising a request needs WorkRequest.Modify)</span>}
      </div>
      {open && (
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-xs text-slate-400">Trigger
            <select className={`${inputClass} w-40`} value={trigger} disabled={busy} onChange={(e) => setTrigger(e.target.value)}>
              {TRIGGERS.map((x) => <option key={x} value={x}>{x}</option>)}
            </select></label>
          <label className="flex flex-col gap-1 text-xs text-slate-400">Reference (optional — the project, finding or advisory)
            <input className={`${inputClass} w-72`} value={reference} disabled={busy} onChange={(e) => setReference(e.target.value)} /></label>
          <Button kind="primary" disabled={busy || !wt} onClick={() => void go()}>Raise and start</Button>
          <span className="text-xs text-slate-500">the request opens at step [2] with {s(relay.AssetName)} already in it; its commit drafts the settings from the model's template</span>
        </div>)}
      {err && <Status bad>{err}</Status>}
    </div>
  )
}

/** #201: the instrument transformers placed at this node, each a link to its page, and a form to make one here. */
function InstrumentTransformersHere({ node, canEdit }: { node: Row; canEdit: boolean }) {
  const navigate = useNavigate(); const qc = useQueryClient()
  const nodeId = s(node.EntityId)
  const q = useViewAll('asset', 'vInstrumentTransformer', { NodeEntityId: nodeId }, 'Name', !!nodeId)
  const rows = q.data ?? []
  const refresh = () => { qc.invalidateQueries({ queryKey: ['view', 'asset'] }) }
  return (
    <Panel title={`Instrument transformers here · ${q.isPending ? '…' : rows.length}`}>
      {q.isError && <Status bad>Could not read the transformers here: {(q.error as Error).message}</Status>}
      {!q.isPending && !rows.length && <Status>{s(node.NodeTypeCode) === 'Panel' ? 'No auxiliary CT or VT is mounted on' : 'No CT, VT or CVT stands in'} {s(node.Name)}.</Status>}
      {rows.length > 0 && (
        <ul className="space-y-1 text-sm">
          {rows.map((x) => (
            <li key={s(x.EntityId)} className="flex flex-wrap items-center gap-2">
              <a className="text-sky-300 underline" href={screenPath('INSTRUMENT_TRANSFORMER', s(x.EntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('INSTRUMENT_TRANSFORMER', s(x.EntityId))) }}>{s(x.Name)}</a>
              <span className="text-xs text-slate-500">{s(x.AssetTypeName)}{x.RatioInUse ? ` · ${s(x.RatioInUse)}` : ' · no ratio recorded'}{x.SerialNumber ? ` · serial ${s(x.SerialNumber)}` : ''}</span>
              <span className="text-xs text-slate-500">{x.FeedsSchemes ? `feeds ${s(x.FeedsSchemes)}` : 'feeds no scheme yet'}</span>
            </li>))}
        </ul>)}
      {canEdit ? <NewInstrumentTransformerForm node={node} onDone={refresh} /> : <Status>Making a transformer here needs Asset.Modify.</Status>}
    </Panel>
  )
}

/** #201: a CT, VT or auxiliary transformer that is not yet in the platform, made and placed here in one go — the #187 relay
 * form's shape. The writes, in order: asset.Asset_Add (the type chosen, InService), asset.AlternateKey_Add (SerialNumber,
 * when given), asset.PlaceAsset (Installed here — a non-device asset may stand at any node), and the nameplate's Ratio in
 * use as its characteristic (asset.CharacteristicValue_Add against the type's CT_Template / VT_Template). A refusal
 * part-way leaves what was written and names it. */
function NewInstrumentTransformerForm({ node, onDone }: { node: Row; onDone: () => void }) {
  const typesQ = useViewAll('ref', 'vAssetType', {}, 'Name')
  const allowed = IT_TYPES_AT[s(node.NodeTypeCode)] ?? INSTRUMENT_TRANSFORMER_TYPES
  const types = (typesQ.data ?? []).filter((t) => allowed.includes(s(t.AssetTypeCode)))
  const [open, setOpen] = useState(false)
  const [type, setType] = useState(allowed[0])
  const [name, setName] = useState('')
  const [serial, setSerial] = useState('')
  const [ratio, setRatio] = useState('')
  const [phases, setPhases] = useState('3')   // #206
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const chosen = types.find((t) => s(t.AssetTypeCode) === type)
  const defsQ = useTemplateDefs(s(chosen?.DefaultTemplateDefinitionEntityId))
  const make = async () => {
    if (!name.trim() || !chosen) return
    setBusy(true); setMsg(null)
    let assetId = ''
    try {
      const a = await proc('asset', 'Asset_Add', { AssetTypeCode: type, Name: name.trim(), Status: 'InService' })
      assetId = s(a.EntityId)
      if (serial.trim()) await proc('asset', 'AlternateKey_Add', { SubjectEntityId: assetId, KeyKindCode: 'SerialNumber', KeyValue: serial.trim(), IsPrimaryLabel: true })
      await proc('asset', 'PlaceAsset', { AssetEntityId: assetId, NodeEntityId: node.EntityId, PlacementKind: 'Installed' })
      const def = (defsQ.data ?? []).find((d) => s(d.CharacteristicKey) === 'RatioInUse')
      if (ratio.trim() && def) await saveAssetCharacteristic(assetId, def, ratio.trim())
      const pdef = (defsQ.data ?? []).find((d) => s(d.CharacteristicKey) === 'Phases')
      if (phases && pdef) await saveAssetCharacteristic(assetId, pdef, phases)
      setMsg({ text: `${name.trim()} (${s(chosen.Name)}${ratio.trim() ? ', ' + ratio.trim() : ''}${serial.trim() ? ', serial ' + serial.trim() : ''}) ${s(node.NodeTypeCode) === 'Panel' ? 'is mounted on' : 'stands in'} ${s(node.Name)}.${ratio.trim() && !def ? ' The ratio was not saved: the type names no nameplate template.' : ''}` })
      setName(''); setSerial(''); setRatio(''); setOpen(false); onDone()
    } catch (e) {
      const why = e instanceof ApiError ? e.message : String(e)
      setMsg({ text: assetId ? `${name.trim()} was created but not finished: ${why} — open it from the Instrument transformers list.` : why, bad: true })
    } finally { setBusy(false) }
  }
  return (
    <div className="mt-3 space-y-2 border-t border-slate-800 pt-2 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-slate-400">A transformer not in the platform yet?</span>
        <Button kind="mini" disabled={busy} onClick={() => setOpen(!open)}>New instrument transformer</Button>
      </div>
      {open && (
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-xs text-slate-400">Type
            <select className={`${inputClass} w-56`} value={type} disabled={busy || typesQ.isPending} onChange={(e) => setType(e.target.value)}>
              {types.map((t) => <option key={s(t.AssetTypeCode)} value={s(t.AssetTypeCode)}>{s(t.Name)}</option>)}
            </select></label>
          <label className="flex flex-col gap-1 text-xs text-slate-400">Name
            <input className={`${inputClass} w-48`} value={name} disabled={busy} placeholder="e.g. L2103 line CT" onChange={(e) => setName(e.target.value)} /></label>
          <label className="flex flex-col gap-1 text-xs text-slate-400">Ratio in use
            <input className={`${inputClass} w-28`} value={ratio} disabled={busy} placeholder="1200:5" onChange={(e) => setRatio(e.target.value)} /></label>
          <label className="flex flex-col gap-1 text-xs text-slate-400">Phases
            <select className={`${inputClass} w-20`} value={phases} disabled={busy} onChange={(e) => setPhases(e.target.value)}><option value="3">3</option><option value="1">1</option></select></label>
          <label className="flex flex-col gap-1 text-xs text-slate-400">Serial number (optional)
            <input className={`${inputClass} w-40`} value={serial} disabled={busy} onChange={(e) => setSerial(e.target.value)} /></label>
          <Button kind="primary" disabled={busy || !chosen || !name.trim()} onClick={() => void make()}>Create and place here</Button>
        </div>)}
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </div>
  )
}

/**
 * #187: a relay that is not yet in the platform, made and placed here in one go. Until now no screen created a relay
 * (the only Asset_Add in the app makes primary assets); the proof relays went in through the API. The four writes are
 * the database's own, in order: asset.Asset_Add (ProtectiveRelay, InService), device.Device_Add (the device row, part
 * number = the model code), asset.AlternateKey_Add (SerialNumber, when given), asset.PlaceAsset (Installed here). A
 * refusal part-way leaves what was written — an asset with no placement is a real thing and is named in the message so
 * it can be placed with the picker above rather than made twice.
 */
function NewRelayForm({ node, onDone }: { node: Row; onDone: () => void }) {
  const { byId, isPending } = useModels()
  const [open, setOpen] = useState(false)
  const [modelId, setModelId] = useState('')
  const [name, setName] = useState('')
  const [serial, setSerial] = useState('')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const models = [...byId.values()].filter((m) => s(m.AssetTypeCode) === 'ProtectiveRelay' || s(m.DeviceCategory) === 'ProtectiveRelay')
    .sort((a, b) => s(a.ModelCode).localeCompare(s(b.ModelCode)))
  const model = byId.get(modelId.toLowerCase())
  const make = async () => {
    if (!model || !name.trim()) return
    setBusy(true); setMsg(null)
    let assetId = ''
    try {
      const a = await proc('asset', 'Asset_Add', { AssetTypeCode: 'ProtectiveRelay', Name: name.trim(), ModelId: model.ModelId, Status: 'InService' })
      assetId = s(a.EntityId)
      await proc('device', 'Device_Add', { EntityId: assetId, PartNumber: s(model.ModelCode) })
      if (serial.trim()) await proc('asset', 'AlternateKey_Add', { SubjectEntityId: assetId, KeyKindCode: 'SerialNumber', KeyValue: serial.trim(), IsPrimaryLabel: true })
      await proc('asset', 'PlaceAsset', { AssetEntityId: assetId, NodeEntityId: node.EntityId, PlacementKind: 'Installed' })
      setMsg({ text: `${name.trim()} (${s(model.ModelCode)}${serial.trim() ? ', serial ' + serial.trim() : ''}) is installed at ${s(node.Name)}.` })
      setName(''); setSerial(''); setOpen(false); onDone()
    } catch (e) {
      const why = e instanceof ApiError ? e.message : String(e)
      setMsg({ text: assetId ? `${name.trim()} was created but not placed: ${why} — place it with the picker above.` : why, bad: true })
    } finally { setBusy(false) }
  }
  return (
    <div className="mt-3 space-y-2 border-t border-slate-800 pt-2 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-slate-400">Not in the platform yet?</span>
        <Button kind="mini" disabled={busy} onClick={() => setOpen(!open)}>New relay</Button>
      </div>
      {open && (
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-xs text-slate-400">Model
            <select className={`${inputClass} w-64`} value={modelId} disabled={busy || isPending} onChange={(e) => setModelId(e.target.value)}>
              <option value="">{isPending ? '…' : 'choose a model'}</option>
              {models.map((m) => <option key={s(m.ModelId)} value={s(m.ModelId)}>{s(m.ModelCode)}{m.ModelName && s(m.ModelName) !== s(m.ModelCode) ? ' — ' + s(m.ModelName) : ''}</option>)}
            </select></label>
          <label className="flex flex-col gap-1 text-xs text-slate-400">Name (as the settings book will list it)
            <input className={`${inputClass} w-48`} value={name} disabled={busy} placeholder="e.g. 3445" onChange={(e) => setName(e.target.value)} /></label>
          <label className="flex flex-col gap-1 text-xs text-slate-400">Serial number (optional)
            <input className={`${inputClass} w-40`} value={serial} disabled={busy} onChange={(e) => setSerial(e.target.value)} /></label>
          <Button kind="primary" disabled={busy || !model || !name.trim()} onClick={() => void make()}>Create and install here</Button>
        </div>)}
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </div>
  )
}
