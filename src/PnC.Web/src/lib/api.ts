// The platform's API as the front end sees it (docs/design/API.md). Two shapes serve everything: a view read
// `GET /api/v1/<schema>/<view>?<Column>=<value>&orderBy=&skip=&take=` (equality filters only; the read scope is the
// database's) and a procedure call `POST /api/v1/<schema>/<procedure>` with the parameters as the JSON body. Plus the
// hand-written endpoints: /health, /api/v1/me, the process engine (/api/v1/process/...), definitions, files.
// DEV act-as identity: the X-PnC-Dev-User header from localStorage (decision #85), the same key the plain pages used,
// so a person signed in on one is signed in on the other.

export class ApiError extends Error {
  status: number
  code?: string
  body: unknown
  constructor(status: number, message: string, code?: string, body?: unknown) {
    super(message); this.name = 'ApiError'; this.status = status; this.code = code; this.body = body
  }
}

export function devUser(): string | null { try { return localStorage.getItem('pnc.devUser') } catch { return null } }
export function setDevUser(v: string | null) { try { if (v) localStorage.setItem('pnc.devUser', v); else localStorage.removeItem('pnc.devUser') } catch { /* no storage */ } }

function headers(json: boolean): Record<string, string> {
  const h: Record<string, string> = { Accept: 'application/json' }
  if (json) h['Content-Type'] = 'application/json'
  const u = devUser(); if (u) h['X-PnC-Dev-User'] = u
  return h
}

async function call<T>(method: string, url: string, body?: unknown): Promise<T> {
  const r = await fetch(url, { method, headers: headers(body !== undefined), body: body === undefined ? undefined : JSON.stringify(body) })
  const data = await r.json().catch(() => null)
  if (!r.ok) throw new ApiError(r.status, (data && (data.detail || data.title)) || r.statusText, data && data.code, data)
  return data as T
}

export const getJson = <T = unknown>(url: string) => call<T>('GET', url)
export const postJson = <T = unknown>(url: string, body: unknown = {}) => call<T>('POST', url, body)

export async function getText(url: string): Promise<string> {
  const r = await fetch(url, { headers: headers(false) })
  if (!r.ok) { const d = await r.json().catch(() => null); throw new ApiError(r.status, (d && d.detail) || r.statusText, d && d.code, d) }
  return r.text()
}

export type Row = Record<string, unknown>
export interface ViewPage { view: string; skip: number; take: number; scope: string; rows: Row[] }

/** One page of a view. `filters` are equality filters on the view's columns; `orderBy` "Col" or "-Col". */
export function view(schema: string, name: string, filters: Record<string, string | null | undefined> = {}, opts: { orderBy?: string; skip?: number; take?: number } = {}) {
  const p = new URLSearchParams()
  for (const [k, v] of Object.entries(filters)) if (v !== undefined && v !== null && v !== '') p.set(k, String(v))
  if (opts.orderBy) p.set('orderBy', opts.orderBy)
  p.set('take', String(opts.take ?? 500)); p.set('skip', String(opts.skip ?? 0))
  return getJson<ViewPage>(`/api/v1/${schema}/${name}?${p.toString()}`)
}

/** Every row of a view: the dispatcher answers at most Api:MaxTake per call, so page on skip until a short page. */
export async function viewAll(schema: string, name: string, filters: Record<string, string | null | undefined> = {}, orderBy?: string, max?: number): Promise<Row[]> {
  const rows: Row[] = []; const take = 5000; let skip = 0
  for (;;) {
    const page = await view(schema, name, filters, { orderBy, skip, take })
    rows.push(...page.rows)
    if (page.rows.length < take || (max && rows.length >= max)) break
    skip += take
  }
  return rows
}

/** A procedure call: the body's keys are the procedure's parameters (ActorId and MigrationRunId are never accepted). */
export const proc = <T = Row>(schema: string, name: string, body: Row) => postJson<T>(`/api/v1/${schema}/${name}`, body)

export interface Me { user: { userPrincipalName: string; entityId?: string }; person: { displayName?: string; entityId?: string }; permissions: string[]; grants?: unknown[] }
export const me = () => getJson<Me>('/api/v1/me')
export interface Health { environment: string; release: string; database: string; catalogLoadedAt: string }
export const health = () => getJson<Health>('/health')

export const fmtDate = (v: unknown) => (v ? new Date(String(v)).toLocaleDateString() : '')
export const fmtWhen = (v: unknown) => (v ? new Date(String(v)).toLocaleString() : '')
export const s = (v: unknown) => (v == null ? '' : String(v))
