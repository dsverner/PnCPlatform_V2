// The shared parts every screen is built from (the comprehensibility rule: one convention applied widely). Written in
// dark-theme classes; the light theme is the palette swap in index.css. No inline style anywhere — the CSP forbids it.
import type { ReactNode, ButtonHTMLAttributes } from 'react'

export function Panel({ title, actions, children, className = '' }: { title?: ReactNode; actions?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`rounded border border-slate-700 bg-slate-900 ${className}`}>
      {(title || actions) && (
        <header className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-700 px-3 py-2">
          <h2 className="text-sm font-semibold text-slate-200">{title}</h2>
          {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
        </header>
      )}
      <div className="p-3">{children}</div>
    </section>
  )
}

export type Tone = 'neutral' | 'good' | 'warn' | 'bad' | 'accent'
const tones: Record<Tone, string> = {
  neutral: 'bg-slate-800 text-slate-300 border-slate-700',
  good: 'bg-emerald-900/50 text-emerald-300 border-emerald-800',
  warn: 'bg-amber-900/50 text-amber-300 border-amber-800',
  bad: 'bg-red-900/50 text-red-300 border-red-800',
  accent: 'bg-sky-900/50 text-sky-300 border-sky-800',
}
export function Pill({ tone = 'neutral', children, title }: { tone?: Tone; children: ReactNode; title?: string }) {
  return <span title={title} className={`inline-block rounded-full border px-2 py-0.5 text-xs font-medium ${tones[tone]}`}>{children}</span>
}
export function stateTone(state: unknown): Tone {
  const v = String(state ?? '')
  if (v === 'Active' || v === 'Closed' || v === 'InService' || v === 'Complete') return 'good'
  if (v === 'Outstanding' || v === 'InProgress' || v === 'In Progress' || v === 'Raised') return 'warn'
  if (v === 'Cancelled' || v === 'Withdrawn') return 'bad'
  return 'neutral'
}

export function Button({ kind = 'default', className = '', ...rest }: ButtonHTMLAttributes<HTMLButtonElement> & { kind?: 'default' | 'primary' | 'mini' | 'danger' }) {
  const base = 'rounded border text-sm transition-colors disabled:cursor-not-allowed disabled:opacity-40 focus-visible:outline focus-visible:outline-2 focus-visible:outline-sky-500'
  const k = kind === 'primary' ? 'border-sky-700 bg-sky-800 px-3 py-1.5 text-sky-100 hover:bg-sky-700'
    : kind === 'danger' ? 'border-red-800 bg-red-900/40 px-3 py-1.5 text-red-200 hover:bg-red-900/70'
    : kind === 'mini' ? 'border-slate-700 bg-slate-800 px-2 py-0.5 text-xs text-slate-200 hover:border-sky-600'
    : 'border-slate-700 bg-slate-800 px-3 py-1.5 text-slate-200 hover:border-sky-600'
  return <button type="button" className={`${base} ${k} ${className}`} {...rest} />
}

/** Label/value pairs in columns, as the legacy record window laid its fields out. */
export function Facts({ pairs, cols = 3 }: { pairs: [ReactNode, ReactNode][]; cols?: 1 | 2 | 3 }) {
  const grid = cols === 3 ? 'md:grid-cols-3' : cols === 2 ? 'md:grid-cols-2' : ''
  return (
    <dl className={`grid grid-cols-1 gap-x-6 gap-y-1 text-sm ${grid}`}>
      {pairs.map(([k, v], i) => (
        <div key={i} className="grid grid-cols-[9rem_1fr] gap-2">
          <dt className="text-slate-400">{k}</dt>
          <dd className="min-w-0 break-words text-slate-200">{v == null || v === '' ? <span className="text-slate-500">—</span> : v}</dd>
        </div>
      ))}
    </dl>
  )
}

export function Tabs<T extends string>({ tabs, value, onChange }: { tabs: { key: T; label: ReactNode }[]; value: T; onChange: (k: T) => void }) {
  return (
    <div role="tablist" className="flex flex-wrap gap-1 border-b border-slate-700">
      {tabs.map((t) => (
        <button key={t.key} role="tab" type="button" aria-selected={t.key === value} onClick={() => onChange(t.key)}
          className={`-mb-px border-b-2 px-3 py-1.5 text-sm ${t.key === value ? 'border-sky-400 text-sky-300' : 'border-transparent text-slate-400 hover:text-slate-200'}`}>{t.label}</button>
      ))}
    </div>
  )
}

/** The workflow's states in order with the current one marked — read from a definition, never a list in code. */
export function StageBar({ stages, current }: { stages: { code: string; name: string; cancellation?: boolean }[]; current?: string | null }) {
  let passed = true
  return (
    <ol className="flex flex-wrap" aria-label="Stage">
      {stages.filter((s) => !s.cancellation || s.code === current).map((s, i) => {
        const isCurrent = s.code === current; const done = passed && !isCurrent; if (isCurrent) passed = false
        return (
          <li key={s.code} className={`border px-3 py-1 text-xs first:rounded-l last:rounded-r -ml-px first:ml-0 ${isCurrent ? 'border-sky-600 bg-sky-800 font-semibold text-sky-100' : done ? 'border-emerald-800 bg-emerald-900/40 text-emerald-200' : 'border-slate-700 bg-slate-900 text-slate-400'}`}>
            <span className="mr-1 opacity-60">{i + 1}</span>{s.name}
          </li>
        )
      })}
    </ol>
  )
}

export function Status({ children, bad }: { children: ReactNode; bad?: boolean }) {
  return <p className={`text-xs ${bad ? 'text-red-300' : 'text-slate-400'}`}>{children}</p>
}

export function Field({ label, children, className = '' }: { label: ReactNode; children: ReactNode; className?: string }) {
  return <label className={`flex flex-col gap-1 text-xs text-slate-400 ${className}`}>{label}{children}</label>
}
export const inputClass = 'rounded border border-slate-700 bg-slate-950 px-2 py-1 text-sm text-slate-200 focus:border-sky-500 focus:outline-none'
