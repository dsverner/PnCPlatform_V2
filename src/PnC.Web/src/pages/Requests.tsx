// The request queue (W8, #158; round 5 B5): every change request the person may read, from work.vChangeRequestStatus
// (read whole — the view is materialised before paging), counted in the browser: raised, in progress, closed this month,
// cancelled, not started. Filters by state and location; a row opens the request. Nothing here knows a rule.
import { useMemo, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { fmtDate, s, type Row } from '@/lib/api'
import { useViewAll } from '@/lib/hooks'
import { legacyFree } from '@/lib/legacy'
import { Pill, stateTone, Button, Field, inputClass, Status } from '@/components/ui/ui'
import { DataGrid, downloadCsv, type Column } from '@/components/ui/data-grid'

const isOpen = (r: Row) => r.RequestState === 'Raised' || r.RequestState === 'InProgress'
const COLS: Column<Row>[] = [
  { key: 'Title', label: 'Request', render: (r) => <a className="text-sky-300 underline" href={'/request.html?id=' + r.WorkRequestEntityId}>{legacyFree(r.Title) || '(untitled)'}</a>, csv: (r) => legacyFree(r.Title) },
  { key: 'RequestState', label: 'State', render: (r) => <Pill tone={stateTone(r.RequestState)}>{s(r.RequestState) || 'not started'}</Pill>, csv: (r) => s(r.RequestState) },
  { key: 'WorkTypeKey', label: 'Action type' }, { key: 'StationName', label: 'Location' },
  { key: 'EquipmentName', label: 'Relay / equipment', render: (r) => legacyFree(r.EquipmentName || r.ScopeName), csv: (r) => legacyFree(r.EquipmentName || r.ScopeName) },
  { key: 'DeviceCount', label: 'Devices' }, { key: 'RequestedByDisplayName', label: 'Requested by' },
  { key: 'RequestedAt', label: 'Requested', render: (r) => fmtDate(r.RequestedAt), csv: (r) => fmtDate(r.RequestedAt) },
  { key: 'DocumentationStatus', label: 'Documentation' }, { key: 'DatabaseStatus', label: 'Database' }, { key: 'LifecycleState', label: 'Package' },
  { key: 'RequestCompletedAt', label: 'Completed', render: (r) => fmtDate(r.RequestCompletedAt), csv: (r) => fmtDate(r.RequestCompletedAt) },
]

export default function RequestsPage() {
  const qc = useQueryClient()
  const q = useViewAll('work', 'vChangeRequestStatus', {}, '-RequestedAt')
  const rows = q.data ?? []
  const [which, setWhich] = useState('open'); const [station, setStation] = useState(''); const [filter, setFilter] = useState('')
  const stations = useMemo(() => [...new Set(rows.map((r) => s(r.StationName)).filter(Boolean))].sort(), [rows])
  const now = new Date(); const month = (d: unknown) => !!d && new Date(String(d)).getFullYear() === now.getFullYear() && new Date(String(d)).getMonth() === now.getMonth()
  const counters: [string, number, string][] = [
    ['Raised', rows.filter((r) => r.RequestState === 'Raised').length, 'Raised'], ['In progress', rows.filter((r) => r.RequestState === 'InProgress').length, 'InProgress'],
    ['Closed this month', rows.filter((r) => r.RequestState === 'Closed' && month(r.RequestCompletedAt)).length, 'Closed'], ['Cancelled', rows.filter((r) => r.RequestState === 'Cancelled').length, 'Cancelled'],
    ['Not started', rows.filter((r) => !r.RequestState).length, ''],
  ]
  const visible = useMemo(() => { const f = filter.trim().toLowerCase()
    return rows.filter((r) => (which === 'open' ? isOpen(r) : which === '' ? true : s(r.RequestState) === which) && (!station || r.StationName === station)
      && (!f || ['Title', 'ScopeName', 'EquipmentName', 'StationName', 'RequestedByDisplayName', 'WorkTypeKey', 'Description'].some((k) => r[k] && String(r[k]).toLowerCase().includes(f)))) }, [rows, which, station, filter])
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {counters.map(([label, n, w]) => (
          <button key={label} type="button" onClick={() => setWhich(w)} className={`min-w-28 rounded border px-3 py-2 text-left ${which === w ? 'border-sky-600 bg-sky-900/40' : 'border-slate-700 bg-slate-900 hover:border-sky-700'}`}>
            <div className="text-2xl font-semibold tabular-nums text-slate-100">{n}</div><div className="text-xs text-slate-400">{label}</div>
          </button>
        ))}
      </div>
      <div className="no-print flex flex-wrap items-end gap-2">
        <Field label="State"><select className={inputClass} value={which} onChange={(e) => setWhich(e.target.value)}>
          <option value="open">Open (raised or in progress)</option><option value="">Every state</option><option value="Raised">Raised</option><option value="InProgress">In progress</option><option value="Closed">Closed</option><option value="Cancelled">Cancelled</option></select></Field>
        <Field label="Location"><select className={inputClass} value={station} onChange={(e) => setStation(e.target.value)}><option value="">Every location</option>{stations.map((x) => <option key={x} value={x}>{x}</option>)}</select></Field>
        <input className={`${inputClass} w-56`} placeholder="filter…" value={filter} onChange={(e) => setFilter(e.target.value)} />
        <Button kind="mini" onClick={() => downloadCsv(`requests-${new Date().toISOString().slice(0, 10)}.csv`, visible, COLS)}>Export CSV</Button>
        <Button kind="mini" onClick={() => qc.invalidateQueries({ queryKey: ['view', 'work', 'vChangeRequestStatus'] })}>Refresh</Button>
      </div>
      {q.isError ? <Status bad>Could not load: {(q.error as Error).message}</Status> : <Status>{q.isPending ? 'Loading requests…' : `${visible.length} shown of ${rows.length}`}</Status>}
      <DataGrid rows={visible} columns={COLS} rowKey={(r) => String(r.WorkRequestEntityId)} emptyText={q.isPending ? 'Loading…' : 'No requests for this choice.'} />
    </div>
  )
}
