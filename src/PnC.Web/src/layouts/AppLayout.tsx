// The frame every screen sits in: a collapsible sidebar with grouped navigation (Dev_Final's layout), the signed-in
// person top right, the health line in the footer. The navigation is built from the screen definitions the person may
// open (#165: GET /api/v1/screens, grouped by each screen's menu.group); the plain pages not yet ported stay as links.
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router'
import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { useHealth, useMe, useScrollMemory } from '@/lib/hooks'
import { devUser } from '@/lib/api'
import { useScreens, screenPath } from '@/lib/screens'

function useStored(key: string, initial: boolean) {
  const [v, setV] = useState<boolean>(() => { try { const s = localStorage.getItem(key); return s === null ? initial : s === 'true' } catch { return initial } })
  useEffect(() => { try { localStorage.setItem(key, String(v)) } catch { /* no storage */ } }, [key, v])
  return [v, () => setV(!v)] as const
}

interface Item { to: string; label: string; external?: boolean }
interface Group { key: string; label: string; items: Item[]; match: string[] }
// the plain pages still to be ported, under the group each belongs to
const PAGES: Group[] = [
  { key: 'Settings book', label: 'Settings book', match: [], items: [{ to: '/report.html', label: 'Location report', external: true }] },
  // #170: Schemes and Primary assets are defined screens now; #173: Locations is one too — the legacy tree stays beside it until the page covers it
  { key: 'Assets and schemes', label: 'Assets and schemes', match: [], items: [{ to: '/floc.html', label: 'Locations (legacy tree)', external: true }] },
  // #185: the definition-driven groups an owner expects to find on the left ("I was expecting to see a Templates tab") sit
  // before Administration; a group is placed by its position in this list, and one not listed here is appended last
  { key: 'Templates', label: 'Templates', match: [], items: [] },
  { key: 'Compliance', label: 'Compliance', match: [], items: [] },
  { key: 'Administration', label: 'Administration', match: [], items: [{ to: '/grants.html', label: 'Grants', external: true }, { to: '/definitions.html', label: 'Definitions', external: true }] },
]

/**
 * #188: Back on every screen. The owner, 2026-09-18: "a Back button on every screen that takes the user back to a previous
 * screen. This occurs a lot in actual usage." One button in the bar every screen shares, the router's own history
 * (react-router keeps its index in history.state.idx), disabled at the first screen of the session. The screens' own
 * Close buttons stay: Close means "done with this", Back means "the screen before".
 */
function BackButton() {
  const navigate = useNavigate(); useLocation()   // re-render on every navigation so the index is re-read
  const idx = (window.history.state as { idx?: number } | null)?.idx
  const canBack = idx == null ? window.history.length > 1 : idx > 0
  return (
    <button type="button" disabled={!canBack} onClick={() => navigate(-1)} title={canBack ? 'Back to the screen before this one' : 'There is no screen to go back to'}
      className="rounded border border-slate-700 px-2 py-0.5 text-xs text-slate-300 hover:border-slate-500 hover:text-slate-100 disabled:cursor-default disabled:opacity-40">‹ Back</button>
  )
}

function GroupHeader({ label, open, onToggle }: { label: string; open: boolean; onToggle: () => void }) {
  return (
    <button type="button" onClick={onToggle} className="flex w-full items-center justify-between px-3 pt-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-slate-500 hover:text-slate-300">
      {label}<span aria-hidden="true">{open ? '▾' : '▸'}</span>
    </button>
  )
}
function NavItem({ it, collapsed }: { it: Item; collapsed: boolean }) {
  const cls = (active: boolean) => `block truncate rounded px-3 py-1.5 text-sm ${active ? 'bg-slate-800 text-sky-300' : 'text-slate-400 hover:bg-slate-800/60 hover:text-slate-200'}`
  if (it.external) return <a href={it.to} className={cls(false)} title={collapsed ? it.label : undefined}>{collapsed ? it.label[0] : it.label}<span className="ml-1 text-[10px] text-slate-600">{collapsed ? '' : 'page'}</span></a>
  return <NavLink to={it.to} className={({ isActive }) => cls(isActive)} title={collapsed ? it.label : undefined}>{collapsed ? it.label[0] : it.label}</NavLink>
}

export default function AppLayout({ children }: { children?: ReactNode }) {
  const meQ = useMe(); const healthQ = useHealth(); const loc = useLocation(); const screensQ = useScreens()
  const [collapsed, toggleCollapsed] = useStored('pnc.sidebar.collapsed', false)
  useScrollMemory()   // #189: each history entry keeps its scroll position
  const groups = useMemo<Group[]>(() => {
    const byGroup = new Map<string, Group>()
    for (const g of PAGES) byGroup.set(g.key, { ...g, items: [] })
    for (const sc of [...(screensQ.data ?? [])].filter((x) => x.menu).sort((a, b) => (a.menu!.order ?? 0) - (b.menu!.order ?? 0))) {
      const key = sc.menu!.group
      if (!byGroup.has(key)) byGroup.set(key, { key, label: key, match: [], items: [] })
      const g = byGroup.get(key)!; g.items.push({ to: screenPath(sc.key), label: sc.menu!.label }); g.match.push(screenPath(sc.key))
    }
    for (const g of PAGES) byGroup.get(g.key)!.items.push(...g.items)
    return [...byGroup.values()].filter((g) => g.items.length)
  }, [screensQ.data])
  const who = meQ.data ? 'signed in as ' + (meQ.data.person.displayName || meQ.data.user.userPrincipalName) + (devUser() ? ' (development)' : '') : meQ.isError ? 'not signed in' : '…'
  return (
    <div className="flex h-screen overflow-hidden">   {/* the owner, 2026-09-20: the nav and the header stay; only the content pane scrolls */}
      <aside className={`flex shrink-0 flex-col border-r border-slate-800 bg-slate-900 ${collapsed ? 'w-14' : 'w-56'}`}>
        <div className="flex items-center justify-between px-3 py-3">
          <NavLink to="/" className="truncate text-sm font-semibold text-slate-100">{collapsed ? 'P&C' : 'P&C Platform'}</NavLink>
          <button type="button" onClick={toggleCollapsed} className="text-slate-500 hover:text-slate-200" aria-label={collapsed ? 'Expand the menu' : 'Collapse the menu'}>{collapsed ? '›' : '‹'}</button>
        </div>
        <nav className="flex-1 overflow-y-auto pb-4">
          {groups.map((g) => <NavGroup key={g.key} g={g} collapsed={collapsed} path={loc.pathname} />)}
          {screensQ.isError && <p className="px-3 py-2 text-xs text-red-300">The menu could not be loaded. Refresh the page.</p>}
        </nav>
        <footer className="border-t border-slate-800 px-3 py-2 text-[11px] text-slate-500">
          {healthQ.data ? `${healthQ.data.environment} · ${healthQ.data.release}` : '…'}
        </footer>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between border-b border-slate-800 bg-slate-900/60 px-4 py-2 text-xs text-slate-400"><BackButton />{who}</header>
        <main className="min-w-0 flex-1 overflow-y-auto p-4">{children ?? <Outlet />}</main>
      </div>
    </div>
  )
}
function NavGroup({ g, collapsed, path }: { g: Group; collapsed: boolean; path: string }) {
  const [open, toggle] = useStored('pnc.sidebar.' + g.key, true)
  const active = g.match.some((m) => path.startsWith(m))
  return (
    <div>
      {!collapsed && <GroupHeader label={g.label} open={open || active} onToggle={toggle} />}
      {(open || active || collapsed) && <div className="px-1">{g.items.map((it) => <NavItem key={it.to} it={it} collapsed={collapsed} />)}</div>}
    </div>
  )
}
