// The settings book (W8, #157–#158; React port, #163). The legacy main window: a location on the left, its settings
// records grouped by functional scheme (collapsed, with counts), a row that unfolds to its card and settings text, the
// state toggle (Active / Outstanding / Archived), the column chooser, filters by field, the right-click commands (Set
// Verified Date, Request Change, New Setting, Compare, Open the record), Export CSV, the location report. No legacy
// field name or record number on screen (owner, 2026-09-14); the text filter still matches them.
import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useSearchParams } from 'react-router'
import { getJson, fmtDate, fmtWhen, s, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { legacyFree } from '@/lib/legacy'
import { settingsText } from '@/lib/actions'
import { Panel, Pill, Button, Facts, Tabs, Field, inputClass, Status } from '@/components/ui/ui'
import { DataGrid, ColumnChooser, downloadCsv, useChosenColumns, type Column } from '@/components/ui/data-grid'
import type { MenuItem } from '@/components/ui/context-menu'
import { RaiseRequest, type RaiseOpts } from '@/components/actions/RaiseRequest'
import { VerifiedDate } from '@/components/actions/VerifiedDate'

const LEAD = ['Functions', 'DeviceName', 'RevisionLabel']
const DEFAULT_COLUMNS = ['ModelCode', 'ManufacturerName', 'FirmwareVersion', 'SerialNumber', 'VoltageClassCode', 'WorkRequestTitle', 'WorkTypeKey', 'CalculatedAt', 'VerifiedAt', 'LifecycleState', 'FileKind']
const LABELS: Record<string, string> = { Functions: 'Functions', DeviceName: 'Device', RevisionLabel: 'Rev', StationName: 'Location', SchemeName: 'Scheme', PanelName: 'Equipment', PositionName: 'Position', ModelCode: 'Model',
  ModelName: 'Model name', ManufacturerName: 'Manufacturer', FirmwareVersion: 'Software version', SerialNumber: 'Serial number', VoltageClassCode: 'Voltage', WorkRequestTitle: 'Change request',
  WorkTypeKey: 'Action type', CalculatedAt: 'Calculated', VerifiedAt: 'Verified', LifecycleState: 'Lifecycle', FileKind: 'File kind', GridState: 'State', StationNumber: 'Station no.',
  ParseStatus: 'Parsed', InServiceFrom: 'In service from', InServiceTo: 'In service to', ReturnToServiceAt: 'Returned to service', CalculatedByDisplayName: 'Calculated by', Technology: 'Technology', AssetStatus: 'Device status' }
const HIDDEN = new Set(['RowSeq', 'RevisionRowId', 'DeviceEntityId', 'LifecycleWorkflowInstanceEntityId', 'DocumentEntityId', 'PackageRevisionRowId', 'PackageSequence', 'WorkRequestEntityId', 'ProcedureInstanceEntityId',
  'RtsStepInstanceEntityId', 'ModelId', 'PositionNodeEntityId', 'PanelNodeEntityId', 'StationNodeEntityId', 'SchemeEntityId', 'InServiceFromQuality'])
const DATES = new Set(['CalculatedAt', 'VerifiedAt', 'InServiceFrom', 'InServiceTo', 'ReturnToServiceAt'])
const CONTEXT = ['SchemeName', 'PanelName', 'StationName', 'PositionName']
type GridState = 'Active' | 'Outstanding' | 'Archived'
type Grouping = 'scheme' | 'panel' | 'none'
interface FieldFilter { key: string; value: string }

const shown = (r: Row) => legacyFree(r.DeviceName)
// the legacy grid's Functions column was the FUNCTIONS text; where it carried no ANSI code the migration kept it as the position's name
const functions = (r: Row) => s(r.Functions || r.PositionName)
const cell = (k: string) => (r: Row): string => (k === 'DeviceName' ? shown(r) : k === 'Functions' ? functions(r) : k === 'WorkRequestTitle' ? legacyFree(r[k]) : DATES.has(k) ? fmtDate(r[k]) : s(r[k]))

function stored(key: string, fallback: string) { try { return localStorage.getItem(key) || fallback } catch { return fallback } }
function store(key: string, v: string) { try { localStorage.setItem(key, v) } catch { /* lasts the page */ } }

export default function SettingsBookPage() {
  const [sp] = useSearchParams(); const qc = useQueryClient(); const can = useCan()
  const scopeDevice = sp.get('DeviceEntityId'); const scopeRequest = sp.get('WorkRequestEntityId')
  const [gridState, setGridState] = useState<GridState>((sp.get('GridState') as GridState) || 'Active')
  const [station, setStation] = useState(() => sp.get('StationNodeEntityId') || (scopeDevice || scopeRequest ? '' : stored('pnc.settings.station', '')))
  const [stationFilter, setStationFilter] = useState('')
  const [grouping, setGrouping] = useState<Grouping>(() => stored('pnc.settings.grouping', 'scheme') as Grouping)
  const [open, setOpen] = useState<Set<string>>(new Set()); const [expanded, setExpanded] = useState<string | null>(null)
  const [filter, setFilter] = useState(''); const [filters, setFilters] = useState<FieldFilter[]>([])
  const [chosen, setChosen] = useChosenColumns('pnc.settings.columns2', DEFAULT_COLUMNS)
  const [showColumns, setShowColumns] = useState(false); const [showFilter, setShowFilter] = useState(false)
  const [action, setAction] = useState<{ kind: 'raise'; o: RaiseOpts } | { kind: 'verify'; r: Row } | null>(null)

  // ---- the location list (legacy: the active location; round 4: a list first, the estate only by an explicit choice)
  const stationsQ = useViewAll('location', 'vNode', { NodeTypeCode: 'Station' }, 'Name')
  const stations = stationsQ.data ?? []
  const stationRows = stations.filter((x) => !stationFilter || String(x.Name).toLowerCase().includes(stationFilter.toLowerCase()))
  const stationName = stations.find((x) => String(x.EntityId).toLowerCase() === station.toLowerCase())?.Name
  const choose = (id: string) => { setStation(id); setOpen(new Set()); setExpanded(null); store('pnc.settings.station', id) }

  // ---- the read: one state, one location; Active also reads Outstanding for the badges (round 5 B5)
  const scoped = !!(scopeDevice || scopeRequest)
  const scopeFilters: Record<string, string | null> = scopeDevice ? { DeviceEntityId: scopeDevice } : scopeRequest ? { WorkRequestEntityId: scopeRequest } : station && station !== '*' ? { StationNodeEntityId: station } : {}
  const ready = scoped || !!station
  const t0 = useMemo(() => performance.now(), [gridState, station, scopeDevice, scopeRequest]) // eslint-disable-line react-hooks/exhaustive-deps
  const rowsQ = useViewAll('document', 'vSettingsRecord', { GridState: gridState, ...scopeFilters }, '-CalculatedAt', ready)
  const outQ = useViewAll('document', 'vSettingsRecord', { GridState: 'Outstanding', ...scopeFilters }, undefined, ready && gridState === 'Active')
  const rows = rowsQ.data ?? []
  const outstanding = useMemo(() => new Set((outQ.data ?? []).map((r) => String(r.DeviceEntityId).toLowerCase())), [outQ.data])
  const [ms, setMs] = useState<number | null>(null)
  useEffect(() => { if (rowsQ.isSuccess) setMs(Math.round(performance.now() - t0)) }, [rowsQ.isSuccess, rowsQ.dataUpdatedAt, t0])
  const reload = () => qc.invalidateQueries({ queryKey: ['view', 'document', 'vSettingsRecord'] })

  // ---- the view's columns for the chooser
  const catalogQ = useQuery({ queryKey: ['catalog'], queryFn: () => getJson<{ views: { schema: string; name: string; columns: { name?: string; Name?: string }[] }[] }>('/api/v1/catalog'), staleTime: 10 * 60_000 })
  const allColumns = useMemo(() => {
    const v = catalogQ.data?.views.find((x) => x.schema === 'document' && x.name === 'vSettingsRecord')
    return (v ? v.columns.map((x) => String(x.name || x.Name)) : LEAD.concat(DEFAULT_COLUMNS)).filter((k) => !HIDDEN.has(k) && !LEAD.includes(k))
  }, [catalogQ.data])

  // ---- filters: the text box over every shown column, and filters by field (round 5 B2)
  const visible = useMemo(() => {
    const f = filter.trim().toLowerCase(); const keys = LEAD.concat(chosen, CONTEXT)
    return rows.filter((r) => (!f || keys.some((k) => r[k] != null && String(r[k]).toLowerCase().includes(f)))
      && filters.every((x) => r[x.key] != null && String(DATES.has(x.key) ? fmtDate(r[x.key]) : r[x.key]).toLowerCase().includes(x.value.toLowerCase())))
  }, [rows, filter, filters, chosen])

  // ---- the grouped grid: the group carries the context, so the row shows the other half
  const columns = useMemo<Column<Row>[]>(() => {
    const ctx = grouping === 'scheme' ? ['PanelName'] : grouping === 'panel' ? ['SchemeName'] : ['SchemeName', 'PanelName']
    return LEAD.concat(station === '*' && !scopeDevice ? ['StationName'] : [], ctx, chosen.filter((k) => !LEAD.includes(k) && !ctx.includes(k)))
      .map((k) => ({ key: k, label: LABELS[k] || k, csv: cell(k),
        render: k === 'DeviceName' ? (r: Row) => <>{shown(r)}{gridState === 'Active' && outstanding.has(String(r.DeviceEntityId).toLowerCase()) && <Pill tone="warn" title="An outstanding change on this device — see the Outstanding tab">outstanding request</Pill>}</> : cell(k) }))
  }, [grouping, station, scopeDevice, chosen, gridState, outstanding])
  const groupBy = grouping === 'scheme' ? (r: Row) => s(r.SchemeName) || '(no scheme yet)' : grouping === 'panel' ? (r: Row) => s(r.PanelName) || '(no equipment)' : null
  const groupCount = useMemo(() => (groupBy ? new Set(visible.map(groupBy)).size : 1), [visible, groupBy])
  const toggleGroup = (g: string) => setOpen((o) => { const n = new Set(o); if (n.has(g)) n.delete(g); else n.add(g); return n })

  // ---- the commands (round 4 §3: the legacy right-click menu)
  const commands = (r: Row): MenuItem[] => {
    const items: MenuItem[] = [{ label: 'Open the record', run: () => { location.href = '/setting.html?revision=' + r.RevisionRowId } }]
    if (r.WorkRequestEntityId) items.push({ label: 'Change request', run: () => { location.href = '/request.html?id=' + r.WorkRequestEntityId } })
    items.push({ label: 'Set verified date', disabled: !(r.RtsStepInstanceEntityId && (r.RtsStepState === 'Ready' || r.RtsStepState === 'Active') && can('Record.Modify')), run: () => setAction({ kind: 'verify', r }) })
    items.push({ label: 'Request change', disabled: !(r.GridState === 'Active' && can('WorkRequest.Modify')),
      run: () => setAction({ kind: 'raise', o: { heading: 'Request change — ' + shown(r), title: 'Settings change — ' + shown(r), scopeKind: 'Asset', scopeEntityId: String(r.DeviceEntityId), defaultType: 'SETTINGS_CHANGE' } }) })
    items.push({ label: 'New setting here', disabled: !(r.PositionNodeEntityId && can('WorkRequest.Modify')),
      run: () => setAction({ kind: 'raise', o: { heading: 'New setting — ' + (s(r.PositionName) || shown(r)), title: 'New setting — ' + (s(r.PositionName) || shown(r)), scopeKind: 'Node', scopeEntityId: String(r.PositionNodeEntityId), defaultType: 'SETTINGS_ADD',
        before: [['Location', s(r.StationName)], ['Scheme', s(r.SchemeName) + (r.PanelName ? ' · ' + r.PanelName : '')]], note: 'A work request on this position, in the same location and scheme; starting it runs the settings-change procedure.' } }) })
    items.push({ label: 'Compare revisions', run: () => { location.href = '/setting.html?revision=' + r.RevisionRowId + '#compare' } })
    return items
  }

  const status: ReactNode = rowsQ.isError ? <Status bad>Could not load: {(rowsQ.error as Error).message}</Status>
    : !ready ? <Status>Choose a location on the left — or the whole estate at the foot of the list.</Status>
    : rowsQ.isPending ? <Status>Loading {gridState} settings…</Status>
    : <Status>{rows.length} {gridState.toLowerCase()} settings record(s){ms != null ? ` · ${ms} ms` : ''}{scopeDevice ? ' · one device' : scopeRequest ? ' · one change request' : station === '*' ? ' · every location' : ` · ${stationName ?? 'one location'}`}</Status>

  const csv = () => downloadCsv(`settings-${gridState.toLowerCase()}-${new Date().toISOString().slice(0, 10)}.csv`, visible,
    [{ key: 'StationName', label: 'Location' }, { key: 'SchemeName', label: 'Scheme' }, { key: 'PanelName', label: 'Equipment' }].concat(columns))
  const print = () => { if (!station || station === '*') { alert('Choose one location first: the report is per location.'); return } window.open(`/report.html?StationNodeEntityId=${encodeURIComponent(station)}&GridState=${encodeURIComponent(gridState)}`, '_blank', 'noopener') }

  return (
    <div className="flex gap-4">
      {!scoped && (
        <aside className="no-print w-60 shrink-0">
          <Panel title="Locations">
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
          <Tabs<GridState> tabs={[{ key: 'Active', label: 'Active' }, { key: 'Outstanding', label: 'Outstanding' }, { key: 'Archived', label: 'Archived' }]} value={gridState} onChange={(k) => { setGridState(k); setExpanded(null) }} />
          <Field label="Group by" className="ml-2"><select className={inputClass} value={grouping} onChange={(e) => { setGrouping(e.target.value as Grouping); setOpen(new Set()); store('pnc.settings.grouping', e.target.value) }}>
            <option value="scheme">Scheme</option><option value="panel">Equipment</option><option value="none">No grouping</option></select></Field>
          <input className={`${inputClass} w-56`} placeholder="filter the rows…" value={filter} onChange={(e) => setFilter(e.target.value)} />
          <Button kind="mini" onClick={() => setShowFilter(!showFilter)}>Filter by field</Button>
          <Button kind="mini" onClick={() => setShowColumns(!showColumns)}>Columns</Button>
          <Button kind="mini" onClick={csv}>Export CSV</Button>
          <Button kind="mini" onClick={print}>Location report</Button>
          <Button kind="mini" onClick={reload}>Refresh</Button>
        </div>
        {showFilter && <AddFilter keys={LEAD.concat(CONTEXT, chosen)} onAdd={(f) => { setFilters([...filters, f]); setShowFilter(false) }} />}
        {filters.length > 0 && (
          <div className="flex flex-wrap gap-1">{filters.map((x, i) => <Pill key={i} tone="accent">{LABELS[x.key] || x.key} contains “{x.value}” <button type="button" className="ml-1" title="remove" onClick={() => setFilters(filters.filter((_, j) => j !== i))}>×</button></Pill>)}</div>
        )}
        {showColumns && <ColumnChooser all={allColumns} labels={LABELS} chosen={chosen} onChange={setChosen} defaults={DEFAULT_COLUMNS} />}
        {action?.kind === 'raise' && <RaiseRequest o={action.o} onClose={() => setAction(null)} />}
        {action?.kind === 'verify' && <VerifiedDate r={action.r} onClose={() => setAction(null)} onDone={reload} />}
        {status}
        <DataGrid rows={visible} columns={columns} rowKey={(r) => String(r.RevisionRowId)} groupBy={groupBy} openGroups={open} onToggleGroup={toggleGroup}
          expandedKey={expanded} onRowClick={(r) => setExpanded(expanded === String(r.RevisionRowId) ? null : String(r.RevisionRowId))} detail={(r) => <Card r={r} />} menu={commands}
          emptyText={ready ? 'No records for this choice.' : 'Choose a location.'} />
        {ready && rowsQ.isSuccess && <Status>{visible.length} row(s) in {groupCount} group(s) of {rows.length} · open a group to see its records; click a record to unfold it</Status>}
      </div>
    </div>
  )
}

function AddFilter({ keys, onAdd }: { keys: string[]; onAdd: (f: FieldFilter) => void }) {
  const [key, setKey] = useState(keys[0]); const [value, setValue] = useState('')
  return (
    <form className="flex flex-wrap items-end gap-2 rounded border border-slate-700 bg-slate-950 p-2" onSubmit={(e) => { e.preventDefault(); if (value.trim()) onAdd({ key, value: value.trim() }) }}>
      <Field label="Field"><select className={inputClass} value={key} onChange={(e) => setKey(e.target.value)}>{keys.map((k) => <option key={k} value={k}>{LABELS[k] || k}</option>)}</select></Field>
      <Field label="Contains"><input className={inputClass} value={value} onChange={(e) => setValue(e.target.value)} autoFocus /></Field>
      <Button type="submit" kind="primary">Apply</Button>
      <Status>Rows are kept when the field contains the text; several filters all apply.</Status>
    </form>
  )
}

/** The card under a row (round 5 B1 C): the record's facts and the settings text as filed. */
function Card({ r }: { r: Row }) {
  const id = String(r.RevisionRowId)
  const textQ = useQuery({ queryKey: ['settingsText', id], queryFn: () => settingsText(id), staleTime: 5 * 60_000 })
  return (
    <div className="space-y-2">
      <Facts pairs={[['Device', shown(r)], ['Model', s(r.ModelCode) + (r.ModelName ? ' — ' + r.ModelName : '')], ['Manufacturer', s(r.ManufacturerName)], ['Software version', s(r.FirmwareVersion)], ['Serial number', s(r.SerialNumber)],
        ['Functions', functions(r)], ['Location', s(r.StationName) + (r.StationNumber ? ' · ' + r.StationNumber : '')], ['Scheme', s(r.SchemeName)], ['Equipment', s(r.PanelName)], ['Position', s(r.PositionName)],
        ['Calculated', fmtWhen(r.CalculatedAt) + (r.CalculatedByDisplayName ? ' by ' + r.CalculatedByDisplayName : '')], ['Verified', fmtWhen(r.VerifiedAt)],
        ['In service', r.InServiceFrom ? fmtDate(r.InServiceFrom) + (r.InServiceTo ? ' – ' + fmtDate(r.InServiceTo) : ' – now') : 'not in service'], ['Change request', legacyFree(r.WorkRequestTitle)], ['Action type', s(r.WorkTypeKey)], ['Lifecycle', s(r.LifecycleState)]]} />
      <div className="flex gap-3 text-sm">
        <a className="text-sky-300 underline" href={'/setting.html?revision=' + id}>Open the record</a>
        {!!r.WorkRequestEntityId && <a className="text-sky-300 underline" href={'/request.html?id=' + r.WorkRequestEntityId}>Change request</a>}
      </div>
      <pre className="max-h-96 overflow-auto rounded border border-slate-800 bg-slate-950 p-2 text-xs whitespace-pre-wrap">
        {textQ.isPending ? 'loading the settings text…' : textQ.isError ? 'The settings text could not be read: ' + (textQ.error as Error).message : textQ.data ? textQ.data.text : 'No settings file is filed for this revision.'}
      </pre>
    </div>
  )
}
