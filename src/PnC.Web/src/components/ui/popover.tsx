// #235 (2026-09-23): a floatover — a small panel that opens beside its trigger on hover or keyboard focus, stays open while the
// pointer is over it (so a link inside it can be clicked), pins open on a click, and closes on Escape, a click elsewhere, or when
// the pointer leaves both. Drawn over the page (a portal), kept inside the window, positioned as the context menu is.
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'

export function Popover({ trigger, label, children, width = 460 }: { trigger: ReactNode; label: string; children: ReactNode; width?: number }) {
  const btn = useRef<HTMLButtonElement>(null); const box = useRef<HTMLDivElement>(null)
  const [open, setOpen] = useState(false); const [pinned, setPinned] = useState(false)
  const [pos, setPos] = useState({ left: 0, top: 0 })
  const leaveTimer = useRef<number | null>(null)
  const show = () => { if (leaveTimer.current) window.clearTimeout(leaveTimer.current); setOpen(true) }
  const hideSoon = () => { if (pinned) return; if (leaveTimer.current) window.clearTimeout(leaveTimer.current); leaveTimer.current = window.setTimeout(() => setOpen(false), 200) }
  const close = () => { setOpen(false); setPinned(false) }
  useEffect(() => {
    if (!open) return
    const b = btn.current?.getBoundingClientRect(); const el = box.current
    if (b && el) {
      const w = el.offsetWidth, h = el.offsetHeight
      const below = b.bottom + 6 + h < window.innerHeight
      setPos({ left: Math.max(8, Math.min(b.left, window.innerWidth - w - 8)), top: below ? b.bottom + 6 : Math.max(8, b.top - h - 6) })
    }
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') close() }
    const onDown = (e: MouseEvent) => { const t = e.target as Node; if (!box.current?.contains(t) && !btn.current?.contains(t)) close() }
    document.addEventListener('keydown', onKey); document.addEventListener('mousedown', onDown)
    return () => { document.removeEventListener('keydown', onKey); document.removeEventListener('mousedown', onDown) }
  }, [open])
  return (
    <>
      <button ref={btn} type="button" aria-label={label} aria-expanded={open} title={label}
        onMouseEnter={show} onMouseLeave={hideSoon} onFocus={show} onBlur={hideSoon}
        onClick={(e) => { e.stopPropagation(); setPinned(!pinned); setOpen(true) }}
        className="ml-1 rounded px-1 text-xs text-sky-300 hover:bg-slate-800 focus:outline focus:outline-1 focus:outline-sky-400">{trigger}</button>
      {open && createPortal(
        // style is set through the CSSOM (element.style), which the content-security policy allows (see context-menu.tsx)
        <div ref={box} role="dialog" aria-label={label} onMouseEnter={show} onMouseLeave={hideSoon} onClick={(e) => e.stopPropagation()}
          className="fixed z-50 max-h-[70vh] overflow-y-auto rounded border border-slate-700 bg-slate-900 p-3 text-sm text-slate-200 shadow-xl shadow-black/50"
          style={{ left: pos.left, top: pos.top, width }}>
          {children}
        </div>, document.body)}
    </>
  )
}
