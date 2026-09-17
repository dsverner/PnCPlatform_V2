// #176 (2026-09-17): the two choosers the attach screens need, shared because both screens ask the same question of the
// asset registry.
//
// The one thing to know before reading: a filter named with a trailing `~` searches a text column for the value
// ANYWHERE inside it (Data/SqlSession.cs, QueryViewAsync). `Name~=3445` finds the relay whose recorded name is
// "SEL-221F 3445 Z1-3", which is the only way a chooser is usable — nobody knows an asset's recorded name exactly.
// Everything else the dispatcher takes is still an equality filter. The search runs on the server with a take, because
// the registry holds about 7 000 assets and pulling the set into the browser is what the estate's size rules out; the
// typing is debounced so a person keying a relay number issues one request, not six.
//
// Two relays can carry the same name (the migration found several), so the model is shown beside it; the model comes
// from ref.vModel, a reference catalogue read once and shared through the query cache, never a lookup per row.
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { useQuery } from '@tanstack/react-query'
import { s, view, type Row } from '@/lib/api'
import { useViewAll } from '@/lib/hooks'
import { Status, inputClass } from './ui/ui'

/** A value that settles: `ms` after the last keystroke. */
export function useDebounced<T>(value: T, ms = 300): T {
  const [v, setV] = useState(value)
  useEffect(() => { const t = window.setTimeout(() => setV(value), ms); return () => window.clearTimeout(t) }, [value, ms])
  return v
}

/** ref.vModel by ModelId — ModelCode, ModelName, Technology, DeviceCategory, AssetTypeCode. One read for every chooser. */
export function useModels() {
  const q = useViewAll('ref', 'vModel', {}, 'ModelCode')
  const byId = new Map((q.data ?? []).map((m) => [s(m.ModelId).toLowerCase(), m]))
  return { byId, isPending: q.isPending }
}

/** "SEL-421 · Numerical" — what distinguishes two assets of the same name. Empty when the asset has no model. */
export function modelLabel(m: Row | undefined): string {
  if (!m) return ''
  return [s(m.ModelCode) || s(m.ModelName), s(m.Technology)].filter(Boolean).join(' · ')
}

/**
 * Choose one asset by its name (asset.vAsset: EntityId, Name, AssetTypeCode, Status, ModelId). The picked asset is the
 * caller's state, so the caller can keep it, clear it, or show what else is true of it.
 */
export function AssetPicker({ value, onChange, label = 'Device', placeholder = 'any part of the name, e.g. 3445', note, disabled, autoFocusKey }: {
  value: Row | null
  onChange: (r: Row | null) => void
  label?: ReactNode
  placeholder?: string
  note?: ReactNode
  disabled?: boolean
  /** changing this string returns the cursor to the search box — how a run of entries keeps its place */
  autoFocusKey?: string
}) {
  const [term, setTerm] = useState('')
  const settled = useDebounced(term.trim(), 300)
  const { byId } = useModels()
  const box = useRef<HTMLInputElement>(null)
  const firstRun = useRef(true)
  const hits = useQuery({
    queryKey: ['assetByName', settled],
    enabled: settled.length > 0 && !value,
    staleTime: 30_000,
    queryFn: async () => (await view('asset', 'vAsset', { 'Name~': settled }, { take: 50, orderBy: 'Name' })).rows,
  })
  // a run of entries: after each successful add the caller bumps this key, the box empties and the cursor comes back
  // here. Never on the first render — a page that opens should not take the cursor away from the person.
  useEffect(() => {
    if (firstRun.current) { firstRun.current = false; return }
    if (!autoFocusKey) return
    setTerm(''); box.current?.focus()
  }, [autoFocusKey])
  if (value) return (
    <div className="flex flex-col gap-1 text-xs text-slate-400">{label}
      <div className="flex items-center gap-2">
        <span className="rounded border border-sky-800 bg-sky-900/40 px-2 py-1 text-sm text-sky-100">{s(value.Name)}</span>
        <span className="text-xs text-slate-500">{modelLabel(byId.get(s(value.ModelId).toLowerCase())) || s(value.AssetTypeCode)}</span>
        <button type="button" className="text-xs text-slate-400 underline" disabled={disabled} onClick={() => { onChange(null); setTerm('') }}>change</button>
      </div>
    </div>)
  const rows = hits.data ?? []
  return (
    <div className="flex flex-col gap-1 text-xs text-slate-400">{label}
      <input ref={box} className={`${inputClass} w-64`} value={term} disabled={disabled} placeholder={placeholder}
        onChange={(e) => setTerm(e.target.value)} />
      {note && <Status>{note}</Status>}
      {settled.length > 0 && hits.isPending && <Status>looking…</Status>}
      {hits.isError && <Status bad>Could not search the registry: {(hits.error as Error).message}</Status>}
      {settled.length > 0 && !hits.isPending && !rows.length && (
        <Status bad>No asset's name contains “{settled}”.</Status>)}
      {rows.length > 0 && (
        <ul className="max-h-40 space-y-0.5 overflow-auto rounded border border-slate-800 p-1">
          {rows.map((a) => (
            <li key={s(a.EntityId)}>
              <button type="button" disabled={disabled} onClick={() => onChange(a)}
                className="w-full rounded px-1 py-0.5 text-left text-sm text-slate-200 hover:bg-slate-800">
                {s(a.Name)}
                <span className="ml-2 text-xs text-slate-500">{modelLabel(byId.get(s(a.ModelId).toLowerCase())) || s(a.AssetTypeCode)}</span>
                <span className="ml-2 text-xs text-slate-600">{s(a.Status)}</span>
              </button>
            </li>))}
        </ul>)}
      {rows.length > 1 && <Status>{rows.length}{rows.length === 50 ? '+' : ''} assets match — the model tells two of the same name apart.</Status>}
    </div>)
}
