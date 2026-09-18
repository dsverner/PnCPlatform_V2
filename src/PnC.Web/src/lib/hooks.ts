import { useQuery } from '@tanstack/react-query'
import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { useLocation } from 'react-router'
import { me, health, viewAll, type Row } from './api'

/**
 * #189: every history entry remembers the working state of the screen it shows. The owner, 2026-09-18: Back should
 * "take us to the exact screen (with whatever device we had open before open etc.)" — not "a pristine version". React
 * Router gives each entry a stable `location.key`; state a screen would lose on unmount is written to sessionStorage
 * under `pnc.entry.<key>.<name>` as it changes and read back when the screen mounts on that key again (Back, Forward,
 * a reload of the same entry). Session-scoped — it lasts the tab, not the account — and nothing goes to the server.
 * Note: a `replace` navigation makes a NEW key, so a choice that should survive Back must push, not replace.
 */
const entryKey = (locKey: string, name: string) => `pnc.entry.${locKey}.${name}`
function readEntry(k: string): unknown { try { const v = sessionStorage.getItem(k); return v === null ? undefined : JSON.parse(v) } catch { return undefined } }
function writeEntry(k: string, v: unknown) { try { sessionStorage.setItem(k, JSON.stringify(v)) } catch { /* private window, quota — the page still works */ } }

export function useEntryState<T>(name: string, initial: T | (() => T), codec?: { to: (v: T) => unknown; from: (raw: unknown) => T }): [T, (v: T | ((prev: T) => T)) => void] {
  const key = entryKey(useLocation().key, name)
  const [v, setV] = useState<T>(() => {
    const raw = readEntry(key)
    if (raw !== undefined) return codec ? codec.from(raw) : (raw as T)
    return typeof initial === 'function' ? (initial as () => T)() : initial
  })
  const set = (next: T | ((prev: T) => T)) => setV((prev) => {
    const val = typeof next === 'function' ? (next as (p: T) => T)(prev) : next
    writeEntry(key, codec ? codec.to(val) : val); return val
  })
  return [v, set]
}

/** The scroll position of each entry, kept and restored the same way; the rows arrive after mount, so the restore is
 * tried after paint and again at 300 ms and 1 s. Used once, in the layout. */
export function useScrollMemory() {
  const locKey = useLocation().key
  const timer = useRef<number | null>(null)
  useEffect(() => {
    const onScroll = () => { if (timer.current) window.clearTimeout(timer.current); timer.current = window.setTimeout(() => writeEntry(entryKey(locKey, 'scroll'), window.scrollY), 200) }
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => { window.removeEventListener('scroll', onScroll); if (timer.current) window.clearTimeout(timer.current) }
  }, [locKey])
  useLayoutEffect(() => {
    const y = readEntry(entryKey(locKey, 'scroll'))
    if (typeof y !== 'number' || y <= 0) { window.scrollTo(0, 0); return }
    const go = () => { if (Math.abs(window.scrollY - y) > 2) window.scrollTo(0, y) }
    go(); const t1 = window.setTimeout(go, 300); const t2 = window.setTimeout(go, 1000)
    return () => { window.clearTimeout(t1); window.clearTimeout(t2) }
  }, [locKey])
}

export function useMe() {
  return useQuery({ queryKey: ['me'], queryFn: me, retry: false, staleTime: 5 * 60_000 })
}
export function useHealth() {
  return useQuery({ queryKey: ['health'], queryFn: health, staleTime: 60_000 })
}
/** Every row of a view for the given equality filters; the key is the filters, so the same read is shared. */
export function useViewAll<T extends Row = Row>(schema: string, name: string, filters: Record<string, string | null | undefined> = {}, orderBy?: string, enabled = true) {
  return useQuery({
    queryKey: ['view', schema, name, filters, orderBy],
    queryFn: () => viewAll(schema, name, filters, orderBy) as Promise<T[]>,
    enabled,
    staleTime: 30_000,
  })
}
/** Permission check over /me; false until the identity is known. */
export function useCan() {
  const q = useMe()
  const perms = q.data?.permissions ?? []
  return (code: string) => perms.includes(code)
}
