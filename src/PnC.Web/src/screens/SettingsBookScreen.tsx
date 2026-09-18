// Screen kind "settingsBook" (#165): the legacy main window — a location on the left, its records grouped (collapsed,
// with counts), a row that unfolds to its card and filed text, the state toggle, the column chooser, filters by field,
// the right-click commands, Export CSV, the location report. Which view, columns, states, groupings and commands: the
// definition's. No legacy field name or record number on screen (owner, 2026-09-14); the text filter still matches them.
import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate, useSearchParams } from 'react-router'
import { getJson, s, type Row } from '@/lib/api'
import { useCan, useEntryState, useViewAll } from '@/lib/hooks'
import { settingsText } from '@/lib/actions'
import { type SettingsBookParams, type Screen, type Command, type ColumnDef, splitView, cellText, labelOf, fill, runCommand, commandEnabled, screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Tabs, Field, inputClass, Status } from '@/components/ui/ui'
import { DataGrid, ColumnChooser, downloadCsv, useChosenColumns, type Column } from '@/components/ui/data-grid'
import type { MenuItem } from '@/components/ui/context-menu'
import { RaiseRequest, type RaiseOpts } from '@/components/actions/RaiseRequest'
import { raiseOptsFor } from './ListScreen'

interface FieldFilter { key: string; value: string }
function stored(key: string, fallback: string) { try { return localStorage.getItem(key) || fallback } catch { return fallback } }
function store(key: string, v: string) { try { localStorage.setItem(key, v) } catch { /* lasts the page */ } }

export default function SettingsBookScreen({ screen, params: p }: { screen: Screen; params: SettingsBookParams }) {
  const [schema, view] = splitView(p.view); const [stSchema, stView] = splitView(p.stationsView ?? 'location.vNode')
  const [sp] = useSearchParams(); const qc = useQueryClient(); const can = useCan(); const navigate = useNavigate()
  const store_ = (k: string) => `pnc.${screen.key}.${k}`
  const rowKey = p.rowKey ?? 'RevisionRowId'; const deviceCol = p.deviceColumn ?? 'DeviceEntityId'
  const col = (k: string): ColumnDef => p.leadColumns.find((c) => c.key === k) ?? { key: k, label: p.labels?.[k] ?? k, format: p.formats?.[k] }
  const scopeDevice = sp.get(deviceCol); const scopeRequest = sp.get('WorkRequestEntityId')
  // #189: the working state — the state tab, the open groups, the unfolded record, the filters — belongs to the history
  // entry, so Back (and a reload) brings the book up as it was left, not pristine
  const [gridState, setGridState] = useEntryState('gridState', () => sp.get(p.stateColumn) || p.states[0].value)
  const [station, setStation] = useState(() => sp.get(p.stationColumn) || (scopeDevice || scopeRequest ? '' : stored(store_('station'), '')))
  const [stationFilter, setStationFilter] = useEntryState('stationFilter', '')
  const groupings = p.groupings ?? [{ key: 'none', label: 'No grouping' }]
  const [grouping, setGrouping] = useState(() => stored(store_('grouping'), groupings[0].key))
  const [open, setOpen] = useEntryState<Set<string>>('open', () => new Set(), { to: (v) => [...v], from: (raw) => new Set(Array.isArray(raw) ? raw as string[] : []) })
  const [expanded, setExpanded] = useEntryState<string | null>('expanded', null)
  const [filter, setFilter] = useEntryState('filter', ''); const [filters, setFilters] = useEntryState<FieldFilter[]>('filters', [])
  const [chosen, setChosen] = useChosenColumns(store_('columns'), p.defaultColumns)
  const [showColumns, setShowColumns] = useState(false); const [showFilter, setShowFilter] = useEntryState('showFilter', false)
  const [raise, setRaise] = useState<RaiseOpts | null>(null)

  // ---- the location list (legacy: the active location; round 4: a list first, the estate only by an explicit choice)
  // #179: WHICH node type is the definition's, because after #178 the unit a person picks is the BUILDING, not the
  // station — Eel River is one station with two buildings and only the building tells its 230 kV records from its
  // 138 kV ones. The list still reads location.vNode and still filters the grid by one column; both are named by the
  // definition, so moving the list another level costs no code here.
  const stationsQ = useViewAll(stSchema, stView, { NodeTypeCode: p.stationsNodeType ?? 'Station' }, 'Name')
  const stations = stationsQ.data ?? []
  const stationRows = stations.filter((x) => !stationFilter || String(x.Name).toLowerCase().includes(stationFilter.toLowerCase()))
  const stationName = stations.find((x) => String(x.EntityId).toLowerCase() === station.toLowerCase())?.Name
  const choose = (id: string) => {
    setStation(id); setOpen(new Set()); setExpanded(null); store(store_('station'), id)
    // #188/#189: a location is a new place in the history — pushed with the location and state in the address, so Back
    // returns to the entry it came from (the owner: "always taking me back to EEL RIVER 230 BDG no matter what I had
    // selected"); a replace would make a new entry key and lose the entry's working state (#189)
    navigate(screenPath(screen.key, null, { [p.stationColumn]: id, [p.stateColumn]: gridState }))
  }
  const chooseState = (k: string) => { setGridState(k); setExpanded(null) }
  // #188: the owner, 2026-09-18: the Locations list "should typically always be displayed and have a collapse button"
  const [locationsHidden, setLocationsHidden] = useState(() => stored(store_('locations.hidden'), 'false') === 'true')
  const toggleLocations = () => { setLocationsHidden(!locationsHidden); store(store_('locations.hidden'), String(!locationsHidden)) }

  // ---- the read: one state, one location; a state with badgeFrom also reads that state for the badges (round 5 B5)
  const scoped = !!(scopeDevice || scopeRequest)
  const scopeFilters: Record<string, string | null> = scopeDevice ? { [deviceCol]: scopeDevice } : scopeRequest ? { WorkRequestEntityId: scopeRequest } : station && station !== '*' ? { [p.stationColumn]: station } : {}
  const ready = scoped || !!station
  const stateDef = p.states.find((x) => x.value === gridState) ?? p.states[0]
  const t0 = useMemo(() => performance.now(), [gridState, station, scopeDevice, scopeRequest]) // eslint-disable-line react-hooks/exhaustive-deps
  const rowsQ = useViewAll(schema, view, { [p.stateColumn]: gridState, ...scopeFilters }, p.orderBy, ready)
  const badgeQ = useViewAll(schema, view, { [p.stateColumn]: stateDef.badgeFrom ?? '', ...scopeFilters }, undefined, ready && !!stateDef.badgeFrom)
  const rows = rowsQ.data ?? []
  const badged = useMemo(() => new Set((badgeQ.data ?? []).map((r) => String(r[deviceCol]).toLowerCase())), [badgeQ.data, deviceCol])
  const [ms, setMs] = useState<number | null>(null)
  useEffect(() => { if (rowsQ.isSuccess) setMs(Math.round(performance.now() - t0)) }, [rowsQ.isSuccess, rowsQ.dataUpdatedAt, t0])
  const reload = () => qc.invalidateQueries({ queryKey: ['view', schema, view] })

  // ---- the view's columns for the chooser
  const catalogQ = useQuery({ queryKey: ['catalog'], queryFn: () => getJson<{ views: { schema: string; name: string; columns: { name?: string; Name?: string }[] }[] }>('/api/v1/catalog'), staleTime: 10 * 60_000 })
  const lead = p.leadColumns.map((c) => c.key); const hidden = new Set(p.hiddenColumns ?? [])
  const allColumns = useMemo(() => {
    const v = catalogQ.data?.views.find((x) => x.schema === schema && x.name === view)
    return (v ? v.columns.map((x) => String(x.name || x.Name)) : lead.concat(p.defaultColumns)).filter((k) => !hidden.has(k) && !lead.includes(k))
  }, [catalogQ.data]) // eslint-disable-line react-hooks/exhaustive-deps

  // ---- filters: the text box over every shown column, and filters by field (round 5 B2)
  const context = p.textFilterColumns ?? []
  const visible = useMemo(() => {
    const f = filter.trim().toLowerCase(); const keys = lead.concat(chosen, context)
    return rows.filter((r) => (!f || keys.some((k) => r[k] != null && String(r[k]).toLowerCase().includes(f)))
      && filters.every((x) => cellText(col(x.key), r).toLowerCase().includes(x.value.toLowerCase())))
  }, [rows, filter, filters, chosen]) // eslint-disable-line react-hooks/exhaustive-deps

  // ---- the grouped grid: the group carries the context, so the row shows the other half
  const g = groupings.find((x) => x.key === grouping) ?? groupings[0]
  const columns = useMemo<Column<Row>[]>(() => {
    const ctx = g.showInstead ?? []
    return lead.concat(station === '*' && !scopeDevice ? ['StationName'] : [], ctx, chosen.filter((k) => !lead.includes(k) && !ctx.includes(k)))
      .map((k) => { const c = col(k); return { key: k, label: labelOf(c), csv: (r: Row) => cellText(c, r),
        render: k === deviceCol.replace('EntityId', 'Name') && stateDef.badgeFrom ? (r: Row) => <>{cellText(c, r)}{badged.has(String(r[deviceCol]).toLowerCase()) && <Pill tone="warn" title={`A ${stateDef.badgeFrom!.toLowerCase()} change on this device — see the ${stateDef.badgeFrom} tab`}>{stateDef.badgeLabel ?? stateDef.badgeFrom}</Pill>}</>
          : (r: Row) => cellText(c, r) } })
  }, [g, station, scopeDevice, chosen, stateDef, badged]) // eslint-disable-line react-hooks/exhaustive-deps
  const groupBy = g.key === 'none' ? null : (r: Row) => s(r[g.key]) || g.empty || '(none)'
  const groupCount = useMemo(() => (groupBy ? new Set(visible.map(groupBy)).size : 1), [visible, groupBy])
  const toggleGroup = (gk: string) => setOpen((o) => { const n = new Set(o); if (n.has(gk)) n.delete(gk); else n.add(gk); return n })

  // ---- the commands (round 4 §3: the legacy right-click menu), from the definition
  const ctx = { navigate, can, raise: ({ command, row }: { command: Command; row: Row }) => setRaise(raiseOptsFor(command, row)) }
  const commands = p.commands?.length ? (r: Row): MenuItem[] => p.commands!.map((c) => ({ label: c.label, disabled: !commandEnabled(c, r, can), run: () => runCommand(c, r, ctx) })) : undefined

  const status: ReactNode = rowsQ.isError ? <Status bad>Could not load: {(rowsQ.error as Error).message}</Status>
    : !ready ? <Status>Choose a location on the left — or the whole estate at the foot of the list.</Status>
    : rowsQ.isPending ? <Status>Loading {stateDef.label} settings…</Status>
    : <Status>{rows.length} {stateDef.label.toLowerCase()} settings record(s){ms != null ? ` · ${ms} ms` : ''}{scopeDevice ? ' · one device' : scopeRequest ? ' · one change request' : station === '*' ? ' · every location' : ` · ${stationName ?? 'one location'}`}</Status>

  const csv = () => downloadCsv(`${screen.key.toLowerCase()}-${gridState.toLowerCase()}-${new Date().toISOString().slice(0, 10)}.csv`, visible,
    context.map((k) => ({ key: k, label: labelOf(col(k)) })).concat(columns))
  const report = () => { if (!p.report) return; if (!station || station === '*') { alert('Choose one location first: the report is per location.'); return } window.open(fill(p.report, { [p.stationColumn]: station, [p.stateColumn]: gridState }), '_blank', 'noopener') }

  return (
    <div className="flex gap-4">
      {locationsHidden
        ? <aside className="no-print shrink-0"><Button kind="mini" onClick={toggleLocations} title="show the locations">›</Button></aside>
        : (
        <aside className="no-print w-60 shrink-0">
          <Panel title="Locations" actions={<Button kind="mini" onClick={toggleLocations} title="hide the locations">‹</Button>}>
            <input className={`${inputClass} mb-2 w-full`} placeholder="filter locations…" value={stationFilter} onChange={(e) => setStationFilter(e.target.value)} />
            <ul className="max-h-[70vh] overflow-y-auto text-sm">
              {stationRows.map((x) => { const id = String(x.EntityId); const sel = id.toLowerCase() === station.toLowerCase()
                return <li key={id}><button type="button" onClick={() => choose(id)} className={`block w-full truncate rounded px-2 py-1 text-left ${sel ? 'bg-slate-800 text-sky-300' : 'text-slate-300 hover:bg-slate-800/60'}`}>{String(x.Name)}</button></li> })}
              <li className="mt-2 border-t border-slate-800 pt-2"><button type="button" onClick={() => choose('*')} className={`block w-full rounded px-2 py-1 text-left ${station === '*' ? 'bg-slate-800 text-sky-300' : 'text-slate-400 hover:bg-slate-800/60'}`}>Whole estate (every location)</button></li>
            </ul>
            <Status>{stationsQ.isPending ? 'Loading…' : `${stationRows.length} of ${stations.length} location(s)`}</Status>
          </Panel>
        </aside>
      )}
      <div className="min-w-0 flex-1 space-y-3">
        <div className="no-print flex flex-wrap items-center gap-2">
          <Tabs tabs={p.states.map((x) => ({ key: x.value, label: x.label }))} value={gridState} onChange={chooseState} />
          {groupings.length > 1 && <Field label="Group by" className="ml-2"><select className={inputClass} value={grouping} onChange={(e) => { setGrouping(e.target.value); setOpen(new Set()); store(store_('grouping'), e.target.value) }}>
            {groupings.map((x) => <option key={x.key} value={x.key}>{x.label}</option>)}</select></Field>}
          <input className={`${inputClass} w-56`} placeholder="filter the rows…" value={filter} onChange={(e) => setFilter(e.target.value)} />
          <Button kind="mini" onClick={() => setShowFilter(!showFilter)}>Filter by field</Button>
          <Button kind="mini" onClick={() => setShowColumns(!showColumns)}>Columns</Button>
          <Button kind="mini" onClick={csv}>Export CSV</Button>
          {p.report && <Button kind="mini" onClick={report}>Location report</Button>}
          <Button kind="mini" onClick={reload}>Refresh</Button>
        </div>
        {showFilter && <AddFilter keys={lead.concat(context, chosen)} labelOf={(k) => labelOf(col(k))} onAdd={(f) => { setFilters([...filters, f]); setShowFilter(false) }} />}
        {filters.length > 0 && (
          <div className="flex flex-wrap gap-1">{filters.map((x, i) => <Pill key={i} tone="accent">{labelOf(col(x.key))} contains “{x.value}” <button type="button" className="ml-1" title="remove" onClick={() => setFilters(filters.filter((_, j) => j !== i))}>×</button></Pill>)}</div>
        )}
        {showColumns && <ColumnChooser all={allColumns} labels={p.labels ?? {}} chosen={chosen} onChange={setChosen} defaults={p.defaultColumns} />}
        {raise && <RaiseRequest o={raise} onClose={() => setRaise(null)} />}
        {status}
        <DataGrid rows={visible} columns={columns} rowKey={(r) => s(r[rowKey])} groupBy={groupBy} openGroups={open} onToggleGroup={toggleGroup}
          expandedKey={expanded} onRowClick={(r) => setExpanded(expanded === s(r[rowKey]) ? null : s(r[rowKey]))}
          /* #190: double-click opens the record (the row stays unfolded, so Back returns to it open — #189) */
          onRowDoubleClick={(r) => { if (p.rowOpen) { setExpanded(s(r[rowKey])); runCommand(p.rowOpen, r, ctx) } }} detail={p.card ? (r) => <Card r={r} card={p.card!} can={can} ctx={ctx} rowKey={rowKey} /> : undefined} menu={commands}
          emptyText={ready ? 'No records for this choice.' : 'Choose a location.'} />
        {ready && rowsQ.isSuccess && <Status>{visible.length} row(s) in {groupCount} group(s) of {rows.length} · open a group to see its records; click a record to unfold it, double-click to open it, right-click for its commands</Status>}
      </div>
    </div>
  )
}

function AddFilter({ keys, labelOf: lab, onAdd }: { keys: string[]; labelOf: (k: string) => string; onAdd: (f: FieldFilter) => void }) {
  const [key, setKey] = useState(keys[0]); const [value, setValue] = useState('')
  return (
    <form className="flex flex-wrap items-end gap-2 rounded border border-slate-700 bg-slate-950 p-2" onSubmit={(e) => { e.preventDefault(); if (value.trim()) onAdd({ key, value: value.trim() }) }}>
      <Field label="Field"><select className={inputClass} value={key} onChange={(e) => setKey(e.target.value)}>{keys.map((k) => <option key={k} value={k}>{lab(k)}</option>)}</select></Field>
      <Field label="Contains"><input className={inputClass} value={value} onChange={(e) => setValue(e.target.value)} autoFocus /></Field>
      <Button type="submit" kind="primary">Apply</Button>
      <Status>Rows are kept when the field contains the text; several filters all apply.</Status>
    </form>
  )
}

/** The card under a row (round 5 B1 C): the definition's facts, its links, and the settings text as filed. */
function Card({ r, card, can, ctx, rowKey }: { r: Row; card: NonNullable<SettingsBookParams['card']>; can: (c: string) => boolean; ctx: Parameters<typeof runCommand>[2]; rowKey: string }) {
  const id = s(r[rowKey])
  const textQ = useQuery({ queryKey: ['settingsText', id], queryFn: () => settingsText(id), staleTime: 5 * 60_000, enabled: card.textFrom === 'revisionFile' })
  return (
    <div className="space-y-2">
      {card.facts && <Facts pairs={card.facts.map((c) => [labelOf(c), cellText(c, r)])} />}
      {card.links && <div className="flex gap-3 text-sm">{card.links.filter((c) => commandEnabled(c, r, can)).map((c) => <a key={c.label} className="text-sky-300 underline" href="#" onClick={(e) => { e.preventDefault(); runCommand(c, r, ctx) }}>{c.label}</a>)}</div>}
      {card.textFrom === 'revisionFile' && (
        <pre className="max-h-96 overflow-auto rounded border border-slate-800 bg-slate-950 p-2 text-xs whitespace-pre-wrap">
          {textQ.isPending ? 'loading the settings text…' : textQ.isError ? 'The settings text could not be read: ' + (textQ.error as Error).message : textQ.data ? textQ.data.text : 'No settings file is filed for this revision.'}
        </pre>
      )}
    </div>
  )
}
