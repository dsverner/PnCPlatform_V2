// #173 (2026-09-17): the locations index — every station with the buildings inside it, each a link to its LOCATION page.
// Until now the sidebar's only Locations entry was the legacy /floc.html tree, so no React page could reach a node to
// classify it (the owner: there is "no way to classify a location").
//
// Why this is plain React and not the generic list kind: the generic list draws one row per row of one view and cannot
// join, and location.vNode carries no column naming a station's children — a station's buildings are a second read,
// grouped by ParentEntityId. The definition still names the data (LOCATIONS, location.vNode, stations); this component
// adds the one thing the generic kind cannot do (the #167 rule: a one-off screen is plain code).
//
// #175 (2026-09-17): each node's Code — its segment of the FLOC — is shown in front of its name, and the filter matches
// it, so a person working from a tag list can type 4403 and can see at a glance what is coded and what is not.
import { useMemo, useState } from 'react'
import { s, type Row } from '@/lib/api'
import { useViewAll } from '@/lib/hooks'
import { Panel, Status, inputClass } from '@/components/ui/ui'
import { CodeName } from './LocationScreen'

export default function LocationsScreen() {
  const stationsQ = useViewAll('location', 'vNode', { NodeTypeCode: 'Station' }, 'Name')
  const buildingsQ = useViewAll('location', 'vNode', { NodeTypeCode: 'Building' }, 'Name')
  const [filter, setFilter] = useState('')
  const byParent = useMemo(() => {
    const m = new Map<string, Row[]>()
    for (const b of buildingsQ.data ?? []) {
      const k = s(b.ParentEntityId).toLowerCase()
      m.set(k, [...(m.get(k) ?? []), b])
    }
    return m
  }, [buildingsQ.data])
  const stations = stationsQ.data ?? []
  const f = filter.trim().toLowerCase()
  const visible = f ? stations.filter((x) => s(x.Name).toLowerCase().includes(f) || s(x.Code).toLowerCase().includes(f) || s(x.SubtypeCode).toLowerCase().includes(f)) : stations
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-end gap-2">
        <input className={`${inputClass} w-56`} placeholder="filter by name or code…" value={filter} onChange={(e) => setFilter(e.target.value)} />
        {stationsQ.isError
          ? <Status bad>The locations could not be read: {(stationsQ.error as Error).message}</Status>
          : <Status>{stationsQ.isPending ? 'Loading…' : `${visible.length} station(s) of ${stations.length}`}</Status>}
      </div>
      <Panel title="Stations and the buildings inside them">
        <ul className="grid gap-x-6 gap-y-2 text-sm md:grid-cols-2 lg:grid-cols-3">
          {visible.map((st) => (
            <li key={s(st.EntityId)}>
              <CodeName id={s(st.EntityId)} code={s(st.Code)} name={s(st.Name)} />
              {st.SubtypeCode ? <span className="ml-2 text-xs text-slate-500">{s(st.SubtypeCode)}</span> : null}
              <ul className="ml-3 mt-0.5 space-y-0.5 text-xs">
                {(byParent.get(s(st.EntityId).toLowerCase()) ?? []).map((b) => (
                  <li key={s(b.EntityId)}>└ <CodeName id={s(b.EntityId)} code={s(b.Code)} name={s(b.Name)} /></li>))}
                {!(byParent.get(s(st.EntityId).toLowerCase()) ?? []).length && !buildingsQ.isPending && <li className="text-slate-500">└ no building recorded</li>}
              </ul>
            </li>))}
        </ul>
        {!stationsQ.isPending && !visible.length && <Status>No station matches that filter.</Status>}
        <Status>Open a station for its code and FLOC, its CIP-002 impact rating, what is inside it and the devices placed there. A building's page shows the same for the building. Locations (legacy tree) in the menu still shows the whole tree.</Status>
      </Panel>
    </div>
  )
}
