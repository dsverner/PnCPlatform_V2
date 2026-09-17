// Screens from definitions (#165). A screen definition (Program.Screen, docs/design/screen.schema.json) names one of the
// screen kinds written in code and binds it to its data, columns, commands and procedure. This module is the shared
// half: the definition types, the list of screens the person may open, the cell formatters, the equality `when`, and the
// command runner every kind uses. Nothing here knows a procedure.
import { useQuery } from '@tanstack/react-query'
import { getJson, fmtDate, fmtWhen, s, type Row } from './api'
import { legacyFree } from './legacy'

export type Format = 'text' | 'date' | 'when' | 'number' | 'state' | 'legacyFree'
export interface ColumnDef { key: string; label?: string; format?: Format; fallback?: string }
export type When = Record<string, string | boolean | number | null | string[]>
export interface Command {
  label: string; action: 'openScreen' | 'raiseRequest' | 'transition' | 'openStep' | 'url'
  screen?: string; param?: string; query?: Record<string, string>
  workflowKey?: string; workType?: string; scopeKind?: 'Asset' | 'Node'; scopeColumn?: string; titleFrom?: string
  transition?: string; requiresReason?: boolean; url?: string; when?: When; permission?: string
}
export interface SettingsBookParams {
  view: string; stationsView?: string; stationsNodeType?: string; stationColumn: string; stateColumn: string
  states: { value: string; label: string; badgeFrom?: string; badgeLabel?: string }[]
  deviceColumn?: string; rowKey?: string; orderBy?: string
  groupings?: { key: string; label: string; empty?: string; showInstead?: string[] }[]
  leadColumns: ColumnDef[]; defaultColumns: string[]; labels?: Record<string, string>; formats?: Record<string, Format>
  hiddenColumns?: string[]; textFilterColumns?: string[]
  card?: { facts?: ColumnDef[]; textFrom?: 'revisionFile'; links?: Command[] }
  commands?: Command[]; report?: string
}
export interface ListParams {
  view: string; fixedFilters?: Record<string, string>; orderBy?: string; rowKey?: string; columns: ColumnDef[]; textFilterColumns?: string[]
  filters?: { column: string; label: string; options?: { label: string; value?: string | null | string[]; default?: boolean }[] }[]
  counters?: { label: string; when: When; thisMonth?: string }[]
  rowOpen?: Command; commands?: Command[]
}
export interface WorkItemParams {
  headerView: string; headerKey: string; headerFacts: ColumnDef[]; title?: string; notes?: ColumnDef[]
  tracks?: 'auto' | 'branches'; tracksOf?: string; showSteps?: 'all' | 'open'
  produced?: { name: string; label: string; screen?: string }[]
  items?: { view: string; key: string; columns: ColumnDef[]; rowOpen?: Command }
  commands?: Command[]
}
export interface StepParams { help?: Record<string, string>; refViews?: Record<string, { view: string; label: string; filters?: Record<string, string> }> }
export interface RecordParams {
  view: string; key: string; title?: string; facts?: ColumnDef[]
  characteristics?: { schemaKey: string; hostColumn?: string; editableWhen?: When }
  textFrom?: 'revisionFile'; parsed?: boolean; files?: boolean
  history?: { byColumn: string; columns?: ColumnDef[] }; commands?: Command[]
}
export interface Screen {
  key: string; name: string; description?: string; versionRowId: string; versionNumber: number
  menu?: { group: string; label: string; order?: number }; permission?: string
  screenKind: 'settingsBook' | 'list' | 'workItem' | 'step' | 'record'
  params: SettingsBookParams | ListParams | WorkItemParams | StepParams | RecordParams
}

/** The Effective screens this person may open (the API filters by each screen's permission). */
export function useScreens() {
  return useQuery({ queryKey: ['screens'], queryFn: () => getJson<{ screens: Screen[] }>('/api/v1/screens').then((r) => r.screens), staleTime: 10 * 60_000 })
}

/** Split a view name "schema.vName" for the dispatcher. */
export function splitView(view: string): [string, string] { const i = view.indexOf('.'); return [view.slice(0, i), view.slice(i + 1)] }

/** A cell's text by format; `fallback` fills an empty value from another column. */
export function cellText(c: ColumnDef, r: Row): string {
  let v = r[c.key]; if ((v == null || v === '') && c.fallback) v = r[c.fallback]
  switch (c.format) {
    case 'date': return fmtDate(v)
    case 'when': return fmtWhen(v)
    case 'legacyFree': return legacyFree(v)
    case 'number': return v == null ? '' : String(v)
    default: return s(v)
  }
}
export const labelOf = (c: ColumnDef) => c.label ?? c.key

/** Every entry must hold: the column equals the value, or is one of the values; ["*"] means "not empty". */
export function whenHolds(when: When | undefined, r: Row): boolean {
  if (!when) return true
  return Object.entries(when).every(([k, want]) => {
    const v = r[k]
    if (Array.isArray(want)) return want.includes('*') ? v != null && v !== '' : v != null && want.includes(String(v))
    if (want === null) return v == null || v === ''
    return v != null && String(v) === String(want)
  })
}

/** {Column} placeholders filled from the row, URL-encoded. */
export function fill(template: string, r: Row): string {
  return template.replace(/\{([A-Za-z0-9_]+)\}/g, (_, k) => encodeURIComponent(s(r[k])))
}

/** The screen path for a key and an optional id. */
export const screenPath = (key: string, id?: string | null, query?: Record<string, string>) => {
  const q = query && Object.keys(query).length ? '?' + new URLSearchParams(query).toString() : ''
  return `/s/${key}${id ? '/' + encodeURIComponent(id) : ''}${q}`
}

export interface CommandContext {
  navigate: (path: string) => void
  can: (code: string) => boolean
  raise: (o: { command: Command; row: Row }) => void
  transition?: (name: string, requiresReason?: boolean) => void
}
export function commandEnabled(cmd: Command, r: Row, can: (c: string) => boolean): boolean {
  if (cmd.permission && !can(cmd.permission)) return false
  return whenHolds(cmd.when, r)
}
/** Run a command for a row: navigation is the router's, the rest is handed to the screen's context. */
export function runCommand(cmd: Command, r: Row, ctx: CommandContext) {
  switch (cmd.action) {
    case 'url': if (cmd.url) location.href = fill(cmd.url, r); return
    case 'openScreen': {
      if (!cmd.screen) return
      const q: Record<string, string> = {}; for (const [k, col] of Object.entries(cmd.query ?? {})) if (r[col] != null) q[k] = s(r[col])
      ctx.navigate(screenPath(cmd.screen, cmd.param ? s(r[cmd.param]) : null, q)); return
    }
    case 'openStep': if (cmd.param && r[cmd.param]) ctx.navigate(screenPath('STEP', s(r[cmd.param]))); return
    case 'raiseRequest': ctx.raise({ command: cmd, row: r }); return
    case 'transition': if (cmd.transition) ctx.transition?.(cmd.transition, cmd.requiresReason); return
  }
}
