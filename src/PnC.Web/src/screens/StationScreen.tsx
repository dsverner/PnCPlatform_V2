// #171 (2026-09-16): the station page. The CIP-002 impact rating is the station's (the owner: applicability comes from the
// primary asset and the station; a device inherits it from what it protects plus its own cyber nature), so this is where it
// is recorded. Beside it, what is at the station: the primary assets with a terminal here and the schemes here.
// Plain React (the #167 rule); the STATION screen definition names location.vNode and this component reads it.
import { useQuery } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { s, view, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type RecordParams, type Screen, screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status } from '@/components/ui/ui'
import { ClassificationPanel, STATION_KINDS } from './PrimaryAssetScreen'

export default function StationScreen({ params: p, id }: { screen: Screen; params: RecordParams; id?: string }) {
  const navigate = useNavigate(); const can = useCan()
  const rowQ = useViewAll('location', 'vNode', { [p.key]: id ?? '' }, undefined, !!id)
  const r = rowQ.data?.[0]
  if (!id) return <Status bad>No station in the address.</Status>
  if (rowQ.isPending) return <Status>Loading the station…</Status>
  if (!r) return <Status bad>No node with that id is readable by you.</Status>
  if (s(r.NodeTypeCode) !== 'Station') return <Status bad>{s(r.Name)} is a {s(r.NodeTypeCode)}, not a station.</Status>
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2"><h1 className="text-lg font-semibold text-slate-100">{s(r.Name)}</h1><Pill tone="accent">{s(r.NodeTypeCode)}</Pill>{r.SubtypeCode ? <Pill>{s(r.SubtypeCode)}</Pill> : null}</div>
        <div className="flex gap-2"><Button onClick={() => navigate(-1)}>Close</Button></div>
      </header>
      <div className="grid gap-3 lg:grid-cols-2">
        <Panel title="Station">
          <Facts cols={1} pairs={[['Name', s(r.Name)], ['Type', s(r.NodeTypeCode)], ['Subtype', s(r.SubtypeCode) || '—'], ['Notes', s(r.Notes) || '—']]} />
        </Panel>
        <ClassificationPanel title="Applicability classifications" subjectKind="Node" subjectEntityId={s(r.EntityId)} editable={can('Asset.Modify')} kinds={STATION_KINDS}
          note="The CIP-002 impact rating of the station — every BES Cyber Asset at it inherits it. Recorded by you from the entity's own CIP-002 evaluation in this phase; a value saves at once, audited." />
      </div>
      <div className="grid gap-3 lg:grid-cols-2">
        <PrimaryAssetsHere stationId={s(r.EntityId)} />
        <SchemesHere stationId={s(r.EntityId)} />
      </div>
    </div>
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
