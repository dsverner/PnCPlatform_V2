// #226 (2026-09-22): what people see. The owner, on the record screen growing to eleven tabs: "I would not, purposely,
// block access to those screens from anyone. I do think that, in general, they should be default hidden or shown
// depending upon the group that they are in, and more precisely, possibly by the individual … the ability to customize
// on a user level would be a very powerful feature"; and "the ability to edit at all levels need to be built in as well."
//
// Two panels, in the order they matter to whoever is looking. Yours first: every part of every screen, what you see now
// and where that answer came from, changed here or on the screen itself. Then, for an administrator, what each group
// starts people with — which changes nobody who has already chosen for themselves.
//
// Hiding is a preference and never a permission. Nothing on this screen grants or refuses anything; the parts a person
// may not open are refused by the database whatever is ticked here. Plain React (#167); the VIEW_PREFERENCES definition
// names config.vViewItem and pages/Screen.tsx dispatches it here.
import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { ApiError, proc, s, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { useScreens, type Screen } from '@/lib/screens'
import { Panel, Button, Status } from '@/components/ui/ui'

const yes = (v: unknown) => v === true || v === 1 || v === '1'

/** A refused save is shown, never swallowed: the tick snaps back on the next read and the reason is said out loud. */
const refusal = (e: unknown) => 'Not saved: ' + (e instanceof ApiError ? e.message : (e as Error).message)

/** A screen's own name, so no key of ours is put in front of a person. */
function useScreenName() {
  const q = useScreens()
  return (key: string) => q.data?.find((x) => x.key === key)?.name ?? key
}

export default function ViewPreferencesScreen({ screen }: { screen: Screen }) {
  const can = useCan()
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-lg font-semibold text-slate-100">{screen.name}</h1>
      </header>
      <Status>
        A part of a screen you have turned off is still one click away, and nothing here changes what you are allowed to
        open. Your own choices follow you to any computer you sign in on.
      </Status>
      <Mine canChoose={can('ViewItem.Modify')} />
      {can('ViewItem.Administer') && <GroupDefaults />}
    </div>
  )
}

/** Every part of every screen as it stands for me, and where that answer comes from. */
function Mine({ canChoose }: { canChoose: boolean }) {
  const qc = useQueryClient()
  const screenName = useScreenName()
  const q = useViewAll('config', 'vMyViewItem', {}, 'DisplayOrder')
  const [err, setErr] = useState('')
  const rows = q.data ?? []
  const set = async (r: Row, shown: boolean | null) => {
    setErr('')
    try {
      await proc('config', 'SetViewItem', { ScreenKey: s(r.ScreenKey), ItemKey: s(r.ItemKey), IsShown: shown })
    } catch (e) { setErr(refusal(e)) }
    await qc.invalidateQueries({ queryKey: ['view', 'config', 'vMyViewItem'] })
    await qc.invalidateQueries({ queryKey: ['viewItems'] })
  }
  const chosen = rows.filter((r) => s(r.Source) === 'mine')
  // one at a time, so a refusal part way through is seen and the rest still go
  const clearAll = async () => { for (const r of chosen) await set(r, null) }
  const screens = [...new Set(rows.map((r) => s(r.ScreenKey)))]
  return (
    <Panel title="Yours" actions={canChoose && chosen.length > 0 && <Button kind="mini" onClick={() => void clearAll()}>Back to the usual</Button>}>
      {q.isPending && <Status>Loading…</Status>}
      {q.isError && <Status bad>These could not be read: {(q.error as Error).message}</Status>}
      {!q.isPending && !q.isError && rows.length === 0 && <Status>No screen offers a choice yet.</Status>}
      {err && <Status bad>{err}</Status>}
      {!canChoose && <Status>A read-only account sees each screen as its group has it; nothing here can be changed from it.</Status>}
      {screens.map((sk) => (
        <div key={sk} className="mb-3">
          <h3 className="mb-1 text-sm font-semibold text-slate-300">{screenName(sk)}</h3>
          <table className="w-full text-sm">
            <thead><tr className="text-left text-xs uppercase tracking-wide text-slate-500"><th className="w-8" /><th>Part</th><th>What it shows</th><th className="w-28">From</th><th className="w-20" /></tr></thead>
            <tbody>
              {rows.filter((r) => s(r.ScreenKey) === sk).map((r) => (
                <tr key={s(r.ItemKey)} className="border-t border-slate-800">
                  <td className="py-1">
                    <input
                      type="checkbox" className="accent-sky-500" aria-label={s(r.Name)}
                      checked={yes(r.IsShown)} disabled={yes(r.IsAlways) || !canChoose}
                      onChange={(e) => void set(r, e.target.checked)}
                    />
                  </td>
                  <td className="py-1 text-slate-200">{s(r.Name)}</td>
                  <td className="py-1 text-slate-400">{s(r.Description)}</td>
                  <td className="py-1 text-slate-500">{yes(r.IsAlways) ? 'always on' : s(r.Source) === 'mine' ? 'your choice' : s(r.Source) === 'role' ? 'your role' : 'the usual'}</td>
                  <td className="py-1">
                    {canChoose && s(r.Source) === 'mine' && <Button kind="mini" onClick={() => void set(r, null)}>Undo</Button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}
    </Panel>
  )
}

/** What each group starts people with. An administrator's panel: it never touches anyone's own choices. */
function GroupDefaults() {
  const qc = useQueryClient()
  const screenName = useScreenName()
  const [err, setErr] = useState('')
  const itemsQ = useViewAll('config', 'vViewItem', {}, 'DisplayOrder')
  const rolesQ = useViewAll('security', 'vRole', {}, 'RoleCode')
  const defaultsQ = useViewAll('config', 'vRoleViewItem', {})
  const items = itemsQ.data ?? []
  // the groups people are actually put in; the mechanics (a step's assignee, a placement override) are not shapes to set
  const roles = (rolesQ.data ?? []).filter((r) => !['Assignee', 'PlacementOverride'].includes(s(r.RoleCode)))
  const standing = new Map((defaultsQ.data ?? []).map((d) => [`${s(d.RoleCode)}|${s(d.ScreenKey)}|${s(d.ItemKey)}`, yes(d.IsShown)]))
  const set = async (role: string, r: Row, shown: boolean) => {
    setErr('')
    try {
      await proc('config', 'SetRoleViewItem', { RoleCode: role, ScreenKey: s(r.ScreenKey), ItemKey: s(r.ItemKey), IsShown: shown })
    } catch (e) { setErr(refusal(e)) }
    await qc.invalidateQueries({ queryKey: ['view', 'config', 'vRoleViewItem'] })
    await qc.invalidateQueries({ queryKey: ['view', 'config', 'vMyViewItem'] })
    await qc.invalidateQueries({ queryKey: ['viewItems'] })
  }
  const screens = [...new Set(items.map((r) => s(r.ScreenKey)))]
  return (
    <Panel title="What each group starts with">
      <Status>
        This is the shape someone sees before they change anything. Change it and people who have already chosen for
        themselves keep their own choice.
      </Status>
      {err && <Status bad>{err}</Status>}
      {screens.map((sk) => (
        <div key={sk} className="mt-3 overflow-x-auto">
          <h3 className="mb-1 text-sm font-semibold text-slate-300">{screenName(sk)}</h3>
          <table className="text-sm">
            <thead>
              <tr className="text-left text-xs uppercase tracking-wide text-slate-500">
                <th className="pr-4">Part</th>
                {roles.map((role) => <th key={s(role.RoleCode)} className="px-2">{s(role.Name) || s(role.RoleCode)}</th>)}
              </tr>
            </thead>
            <tbody>
              {items.filter((r) => s(r.ScreenKey) === sk).map((r) => (
                <tr key={s(r.ItemKey)} className="border-t border-slate-800">
                  <td className="py-1 pr-4 text-slate-200">{s(r.Name)}{yes(r.IsAlways) && <span className="ml-2 text-xs text-slate-500">always on</span>}</td>
                  {roles.map((role) => {
                    const key = `${s(role.RoleCode)}|${s(r.ScreenKey)}|${s(r.ItemKey)}`
                    const on = standing.has(key) ? standing.get(key)! : yes(r.ShownByDefault)
                    return (
                      <td key={key} className="px-2 py-1">
                        <input
                          type="checkbox" className="accent-sky-500"
                          aria-label={`${s(r.Name)} for ${s(role.Name) || s(role.RoleCode)}`}
                          checked={yes(r.IsAlways) || on} disabled={yes(r.IsAlways)}
                          onChange={(e) => void set(s(role.RoleCode), r, e.target.checked)}
                        />
                      </td>
                    )
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}
    </Panel>
  )
}
