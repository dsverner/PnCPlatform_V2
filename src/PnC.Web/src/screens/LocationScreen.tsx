// #173 (2026-09-17): the location page, for ANY node of the location tree — a region, a station, a building, a room, a
// panel, a position. It was the station page (#171) and refused everything else; the owner found there was "no way to
// classify a location" with a High/Medium/Low CIP impact rating, and the estate has a Building between every Station and
// its Panels, so a building has to be reachable and classifiable in its own right.
//
// What the page shows: the node, where it sits (its ancestors as links), its CIP-002 impact rating, the nodes inside it,
// and the devices placed at or under it. A station also shows the primary assets with a terminal here and the schemes
// here — neither question means anything for a room or a panel, so neither is asked there.
// Plain React (the #167 rule); the LOCATION screen definition names location.vNode and this component reads it.
import { useQuery } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { s, view, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type RecordParams, type Screen, screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status } from '@/components/ui/ui'
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
          <Facts cols={1} pairs={[
            ['Name', s(r.Name)], ['Type', s(r.NodeTypeCode)], ['Subtype', s(r.SubtypeCode) || '—'],
            ['Where it sits', ancestorsQ.isPending ? '…' : ancestors.length
              ? <span>{ancestors.map((a, i) => <span key={s(a.EntityId)}>{i > 0 ? ' › ' : ''}<NodeLink id={s(a.EntityId)} name={s(a.Name)} /><span className="ml-1 text-xs text-slate-500">{s(a.NodeTypeCode)}</span></span>)}</span>
              : 'the top of the tree'],
            ['Notes', s(r.Notes) || '—']]} />
        </Panel>
        <ClassificationPanel title="Applicability classifications" subjectKind="Node" subjectEntityId={s(r.EntityId)} editable={can('Asset.Modify')} kinds={NODE_KINDS}
          note="The CIP-002 impact rating of this location — every BES Cyber Asset in it inherits it, and a rating on a building beats the station's for the devices in that building (#173). Recorded by you from the entity's own CIP-002 evaluation in this phase; a value saves at once, audited." />
      </div>
      <div className="grid gap-3 lg:grid-cols-2">
        <Inside node={r} />
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

/** The nodes directly inside this one (location.vNode by ParentEntityId) — on a station, its buildings; on a building,
 * its panels. The estate's 250 buildings are one per station and all named "Building (unknown — legacy has no
 * buildings)"; the link is how they are reached at all (#173). */
function Inside({ node }: { node: Row }) {
  const q = useViewAll('location', 'vNode', { ParentEntityId: s(node.EntityId) }, 'Name', !!node.EntityId)
  const rows = q.data ?? []
  return (
    <Panel title={`Inside here · ${q.isPending ? '…' : rows.length}`}>
      {q.isError && <Status bad>Could not read what is inside: {(q.error as Error).message}</Status>}
      {!q.isPending && !rows.length && <Status>Nothing is recorded inside this {s(node.NodeTypeCode).toLowerCase()}.</Status>}
      <ul className="space-y-1 text-sm">
        {rows.map((n) => (
          <li key={s(n.EntityId)}>
            <NodeLink id={s(n.EntityId)} name={s(n.Name)} />
            <span className="ml-2 text-xs text-slate-500">{s(n.NodeTypeCode)}{n.SubtypeCode ? ' · ' + s(n.SubtypeCode) : ''}</span>
          </li>))}
      </ul>
    </Panel>
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
