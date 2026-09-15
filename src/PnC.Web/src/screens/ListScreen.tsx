// Screen kind "list" (#165): a grid over a view with counters, filters by column, a text filter, CSV, a row that opens
// something and row commands — the requests queue is one definition of it.
import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router'
import { useQueryClient } from '@tanstack/react-query'
import { s, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type ListParams, type Screen, type Command, splitView, cellText, labelOf, whenHolds, runCommand, commandEnabled } from '@/lib/screens'
import { Pill, stateTone, Button, Field, inputClass, Status } from '@/components/ui/ui'
import { DataGrid, downloadCsv, type Column } from '@/components/ui/data-grid'
import type { MenuItem } from '@/components/ui/context-menu'
import { RaiseRequest, type RaiseOpts } from '@/components/actions/RaiseRequest'
import { legacyFree } from '@/lib/legacy'

export function raiseOptsFor(cmd: Command, r: Row): RaiseOpts | null {
  if (!cmd.scopeColumn || !cmd.scopeKind || !r[cmd.scopeColumn]) return null
  const subject = cmd.titleFrom ? legacyFree(r[cmd.titleFrom]) : ''
  return { heading: `${cmd.label} — ${subject}`, title: `${cmd.label} — ${subject}`, scopeKind: cmd.scopeKind, scopeEntityId: s(r[cmd.scopeColumn]), defaultType: cmd.workType ?? 'SETTINGS_CHANGE', workflowKey: cmd.workflowKey }
}

export default function ListScreen({ screen, params: p }: { screen: Screen; params: ListParams }) {
  const [schema, view] = splitView(p.view); const qc = useQueryClient(); const navigate = useNavigate(); const can = useCan()
  const q = useViewAll(schema, view, p.fixedFilters ?? {}, p.orderBy)
  const rows = q.data ?? []
  const [choice, setChoice] = useState<Record<string, number>>(() => Object.fromEntries((p.filters ?? []).map((f) => [f.column, Math.max(0, (f.options ?? []).findIndex((o) => o.default))])))
  const [filter, setFilter] = useState(''); const [raise, setRaise] = useState<RaiseOpts | null>(null)
  const distinct = useMemo(() => Object.fromEntries((p.filters ?? []).filter((f) => !f.options).map((f) => [f.column, [...new Set(rows.map((r) => s(r[f.column])).filter(Boolean))].sort()])), [rows, p.filters])
  const visible = useMemo(() => {
    const f = filter.trim().toLowerCase(); const keys = p.textFilterColumns ?? p.columns.map((c) => c.key)
    return rows.filter((r) => (p.filters ?? []).every((fl) => {
      const i = choice[fl.column] ?? 0
      if (fl.options) { const want = fl.options[i]?.value; if (want === undefined || want === null) return true; return whenHolds({ [fl.column]: want }, r) }
      const want = distinct[fl.column]?.[i - 1]; return i === 0 || s(r[fl.column]) === want
    }) && (!f || keys.some((k) => r[k] != null && String(r[k]).toLowerCase().includes(f))))
  }, [rows, filter, choice, p, distinct])
  const now = new Date()
  const inMonth = (d: unknown) => !!d && new Date(String(d)).getFullYear() === now.getFullYear() && new Date(String(d)).getMonth() === now.getMonth()
  const columns: Column<Row>[] = p.columns.map((c) => ({ key: c.key, label: labelOf(c), csv: (r) => cellText(c, r),
    render: c.format === 'state' ? (r) => <Pill tone={stateTone(r[c.key])}>{cellText(c, r) || 'not started'}</Pill>
      : p.rowOpen && c === p.columns[0] ? (r) => <a className="text-sky-300 underline" href="#" onClick={(e) => { e.preventDefault(); e.stopPropagation(); runCommand(p.rowOpen!, r, ctx) }}>{cellText(c, r) || '(untitled)'}</a>
      : (r) => cellText(c, r) }))
  const ctx = { navigate, can, raise: ({ command, row }: { command: Command; row: Row }) => setRaise(raiseOptsFor(command, row)) }
  const menu = p.commands?.length ? (r: Row): MenuItem[] => p.commands!.map((c) => ({ label: c.label, disabled: !commandEnabled(c, r, can), run: () => runCommand(c, r, ctx) })) : undefined
  return (
    <div className="space-y-3">
      {p.counters && (
        <div className="flex flex-wrap gap-2">
          {p.counters.map((c) => <div key={c.label} className="min-w-28 rounded border border-slate-700 bg-slate-900 px-3 py-2">
            <div className="text-2xl font-semibold tabular-nums text-slate-100">{rows.filter((r) => whenHolds(c.when, r) && (!c.thisMonth || inMonth(r[c.thisMonth]))).length}</div><div className="text-xs text-slate-400">{c.label}</div></div>)}
        </div>
      )}
      <div className="no-print flex flex-wrap items-end gap-2">
        {(p.filters ?? []).map((f) => (
          <Field key={f.column} label={f.label}>
            <select className={inputClass} value={choice[f.column] ?? 0} onChange={(e) => setChoice({ ...choice, [f.column]: Number(e.target.value) })}>
              {f.options ? f.options.map((o, i) => <option key={i} value={i}>{o.label}</option>) : [<option key="all" value={0}>Every {f.label.toLowerCase()}</option>, ...(distinct[f.column] ?? []).map((v, i) => <option key={v} value={i + 1}>{v}</option>)]}
            </select>
          </Field>
        ))}
        <input className={`${inputClass} w-56`} placeholder="filter…" value={filter} onChange={(e) => setFilter(e.target.value)} />
        <Button kind="mini" onClick={() => downloadCsv(`${screen.key.toLowerCase()}-${new Date().toISOString().slice(0, 10)}.csv`, visible, columns)}>Export CSV</Button>
        <Button kind="mini" onClick={() => qc.invalidateQueries({ queryKey: ['view', schema, view] })}>Refresh</Button>
      </div>
      {raise && <RaiseRequest o={raise} onClose={() => setRaise(null)} />}
      {q.isError ? <Status bad>Could not load: {(q.error as Error).message}</Status> : <Status>{q.isPending ? 'Loading…' : `${visible.length} shown of ${rows.length}`}</Status>}
      <DataGrid rows={visible} columns={columns} rowKey={(r) => s(r[p.rowKey ?? p.columns[0].key])} menu={menu}
        onRowClick={p.rowOpen ? (r) => runCommand(p.rowOpen!, r, ctx) : undefined} emptyText={q.isPending ? 'Loading…' : 'Nothing for this choice.'} />
    </div>
  )
}
