// The one grid: columns with labels and renderers, optional grouping with collapsed groups and counts (progressive
// disclosure, round 4), a row that unfolds to a detail panel, a row context menu (right-click, Shift+F10, ⋯), sorting by
// a column, a column chooser and CSV export. Every list screen uses it.
import { Fragment, useMemo, useState, type ReactNode, type MouseEvent } from 'react'
import { Button } from './ui'
import { useContextMenu, type MenuItem } from './context-menu'
import { s } from '@/lib/api'

export interface Column<T> { key: string; label: string; render?: (r: T) => ReactNode; csv?: (r: T) => string; width?: string }
export interface GridProps<T> {
  rows: T[]
  columns: Column<T>[]
  rowKey: (r: T) => string
  groupBy?: ((r: T) => string) | null
  openGroups?: Set<string>
  onToggleGroup?: (g: string) => void
  expandedKey?: string | null
  onRowClick?: (r: T) => void
  onRowDoubleClick?: (r: T) => void   // #190: the owner's "double click the description" — opens the row's record
  detail?: (r: T) => ReactNode
  menu?: (r: T) => MenuItem[]
  emptyText?: string
}

export function DataGrid<T>({ rows, columns, rowKey, groupBy, openGroups, onToggleGroup, expandedKey, onRowClick, onRowDoubleClick, detail, menu, emptyText = 'Nothing to show.' }: GridProps<T>) {
  const cm = useContextMenu()
  const groups = useMemo(() => {
    const m = new Map<string, T[]>()
    if (!groupBy) { m.set('', rows); return m }
    for (const r of rows) { const g = groupBy(r); if (!m.has(g)) m.set(g, []); m.get(g)!.push(r) }
    return new Map([...m.entries()].sort((a, b) => a[0].localeCompare(b[0])))
  }, [rows, groupBy])
  const openMenu = (r: T, e: MouseEvent) => { if (!menu) return; e.preventDefault(); e.stopPropagation(); cm.open(menu(r), e.clientX, e.clientY) }
  const cols = columns.length + (detail ? 1 : 0) + (menu ? 1 : 0)
  return (
    <div className="overflow-auto">
      {cm.menu}
      <table className="grid-table">
        <thead><tr>{detail && <th className="w-6" />}{columns.map((c) => <th key={c.key} className={c.width}>{c.label}</th>)}{menu && <th className="w-8 no-print" />}</tr></thead>
        <tbody>
          {rows.length === 0 && <tr><td colSpan={cols} className="py-6 text-center text-slate-500">{emptyText}</td></tr>}
          {[...groups.entries()].map(([g, list]) => {
            const open = !groupBy || (openGroups?.has(g) ?? false)
            return (
              <Fragment key={g || '·'}>
                {groupBy && (
                  <tr className="group"><td colSpan={cols}>
                    <button type="button" aria-expanded={open} onClick={() => onToggleGroup?.(g)} className="flex w-full items-center justify-between px-2 py-1.5 text-left text-sm font-semibold text-slate-200 hover:bg-slate-800/60">
                      <span><span className="mr-2 text-slate-500">{open ? '▾' : '▸'}</span>{g}</span>
                      <span className="text-xs font-normal text-slate-500">{list.length} {list.length === 1 ? 'record' : 'records'}</span>
                    </button>
                  </td></tr>
                )}
                {open && list.map((r) => {
                  const k = rowKey(r); const expanded = expandedKey === k
                  return (
                    <Fragment key={k}>
                      <tr className={`row ${expanded ? 'selected' : ''} ${onRowClick ? 'cursor-pointer' : ''}`} tabIndex={0}
                        onClick={() => onRowClick?.(r)} onDoubleClick={() => onRowDoubleClick?.(r)} onContextMenu={(e) => openMenu(r, e)}
                        onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onRowClick?.(r) } else if (e.shiftKey && e.key === 'F10' && menu) { e.preventDefault(); const rc = (e.currentTarget as HTMLElement).getBoundingClientRect(); cm.open(menu(r), rc.left + 24, rc.bottom) } }}>
                        {detail && <td className="text-slate-500">{expanded ? '▾' : '▸'}</td>}
                        {columns.map((c) => <td key={c.key}>{c.render ? c.render(r) : s((r as Record<string, unknown>)[c.key])}</td>)}
                        {menu && <td className="no-print"><Button kind="mini" title="Commands (right-click or Shift+F10 also)" onClick={(e) => { e.stopPropagation(); const rc = (e.currentTarget as HTMLElement).getBoundingClientRect(); cm.open(menu(r), rc.left, rc.bottom) }}>⋯</Button></td>}
                      </tr>
                      {expanded && detail && <tr className="row selected"><td colSpan={cols} className="whitespace-normal p-3 pl-8">{detail(r)}</td></tr>}
                    </Fragment>
                  )
                })}
              </Fragment>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

/** Rows as a CSV file the browser saves. */
export function downloadCsv<T>(name: string, rows: T[], columns: Column<T>[]) {
  const q = (v: unknown) => { const t = v == null ? '' : String(v); return /[",\n\r]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t }
  const lines = [columns.map((c) => q(c.label)).join(',')]
  for (const r of rows) lines.push(columns.map((c) => q(c.csv ? c.csv(r) : (r as Record<string, unknown>)[c.key])).join(','))
  const blob = new Blob(['﻿' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' })
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); a.remove()
  setTimeout(() => URL.revokeObjectURL(a.href), 1000)
}

/** The column chooser: which of the view's columns the grid shows, kept in this browser. */
export function useChosenColumns(storageKey: string, defaults: string[]) {
  const [chosen, setChosen] = useState<string[]>(() => { try { const c = JSON.parse(localStorage.getItem(storageKey) || 'null'); return Array.isArray(c) && c.length ? c : defaults } catch { return defaults } })
  const set = (cols: string[]) => { setChosen(cols); try { localStorage.setItem(storageKey, JSON.stringify(cols)) } catch { /* lasts the page */ } }
  return [chosen, set] as const
}
export function ColumnChooser({ all, labels, chosen, onChange, defaults }: { all: string[]; labels: Record<string, string>; chosen: string[]; onChange: (c: string[]) => void; defaults: string[] }) {
  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-1 rounded border border-slate-700 bg-slate-950 p-2 text-xs">
      {all.map((c) => (
        <label key={c} className="inline-flex items-center gap-1 text-slate-300">
          <input type="checkbox" checked={chosen.includes(c)} onChange={(e) => onChange(all.filter((k) => (k === c ? e.target.checked : chosen.includes(k))))} />{labels[c] || c}
        </label>
      ))}
      <Button kind="mini" onClick={() => onChange(defaults)}>Default columns</Button>
    </div>
  )
}
