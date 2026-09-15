// The legacy's popup menu: opened by right-click, Shift+F10 or the ⋯ button on a row; a command the person may not run
// is greyed, not hidden. One menu on the page at a time; Escape or a click elsewhere closes it.
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'

export interface MenuItem { label: ReactNode; run: () => void; disabled?: boolean; title?: string }

export function useContextMenu() {
  const [state, setState] = useState<{ x: number; y: number; items: MenuItem[] } | null>(null)
  const open = (items: MenuItem[], x: number, y: number) => setState({ x, y, items })
  const close = () => setState(null)
  const menu = state ? <ContextMenu items={state.items} x={state.x} y={state.y} onClose={close} /> : null
  return { open, close, menu }
}

export function ContextMenu({ items, x, y, onClose }: { items: MenuItem[]; x: number; y: number; onClose: () => void }) {
  const ref = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState({ left: x, top: y })
  useEffect(() => {
    const el = ref.current; if (!el) return
    const w = el.offsetWidth, h = el.offsetHeight
    setPos({ left: Math.max(4, Math.min(x, window.innerWidth - w - 8)), top: Math.max(4, Math.min(y, window.innerHeight - h - 8)) })
    const first = el.querySelector<HTMLButtonElement>('button:not(:disabled)'); first?.focus()
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    const onClick = (e: MouseEvent) => { if (!el.contains(e.target as Node)) onClose() }
    document.addEventListener('keydown', onKey); document.addEventListener('mousedown', onClick)
    return () => { document.removeEventListener('keydown', onKey); document.removeEventListener('mousedown', onClick) }
  }, [x, y, onClose])
  // React applies `style` through the CSSOM (element.style.left = …), which the content-security policy allows; only
  // markup style attributes and <style> elements are inline style. Nothing else in the app positions by coordinates.
  return createPortal(
    <div ref={ref} role="menu" className="fixed z-50 min-w-44 rounded border border-slate-700 bg-slate-900 p-1 shadow-xl shadow-black/50" style={{ left: pos.left, top: pos.top }}>
      {items.map((it, i) => (
        <button key={i} type="button" role="menuitem" disabled={it.disabled} title={it.title}
          onClick={(e) => { e.stopPropagation(); onClose(); it.run() }}
          className="block w-full rounded px-3 py-1.5 text-left text-sm text-slate-200 hover:bg-slate-800 focus:bg-slate-800 focus:outline-none disabled:cursor-not-allowed disabled:opacity-40">{it.label}</button>
      ))}
    </div>, document.body)
}
