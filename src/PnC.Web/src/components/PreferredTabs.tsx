// #226: a tab strip that shows the parts of the screen this person keeps, with a way to change that. The owner,
// 2026-09-22, on the record screen growing to eleven tabs: "I would not, purposely, block access to those screens from
// anyone … they should be default hidden or shown depending upon the group that they are in, and more precisely,
// possibly by the individual … the ability to customize on a user level would be a very powerful feature."
//
// Hiding is a preference, never a permission. Nothing here decides what a person may see — the database does that, the
// same way for everyone. A part hidden here is one click from being back, and a link straight to a hidden part still
// opens it, with a line offering to keep it.
import { useState } from 'react'
import type { ReactNode } from 'react'
import { Button, Tabs } from '@/components/ui/ui'
import { useSetViewItem, useViewItems, type ViewItem } from '@/lib/viewItems'
import { useCan } from '@/lib/hooks'

export interface TabSpec<T extends string> { key: T; label: ReactNode }

const sourceWords: Record<ViewItem['source'], string> = {
  mine: 'your choice',
  role: 'your role',
  screen: 'the usual',
}

/**
 * The strip. `tabs` is every part the screen can show and knows the data for; the person's preferences decide which of
 * them appear. A part the screen did not offer (no data for it on this record) never appears whatever the preference
 * says, and a part not in the catalogue yet is always shown, so a new tab is visible before it is declared.
 */
export function PreferredTabs<T extends string>({ screenKey, tabs, value, onChange }: { screenKey: string; tabs: TabSpec<T>[]; value: T; onChange: (k: T) => void }) {
  const itemsQ = useViewItems(screenKey)
  const setItem = useSetViewItem(screenKey)
  // a read-only account keeps the screen as its group has it: choosing is a write, and read-only never writes
  const canChoose = useCan()('ViewItem.Modify')
  const [open, setOpen] = useState(false)
  const items = itemsQ.data ?? []
  const byKey = new Map(items.map((i) => [i.itemKey, i]))
  // while the preferences are still being read, show the screen as it is: no tab flickers away and back
  const keep = (t: TabSpec<T>) => { const i = byKey.get(t.key); return !i || i.isShown }
  const landedOnHidden = !keep({ key: value } as TabSpec<T>)
  const shown = tabs.filter((t) => keep(t) || t.key === value)
  // the chooser lists the parts this screen actually offers, in the catalogue's order
  const choices = items.filter((i) => tabs.some((t) => t.key === i.itemKey))
  const current = byKey.get(value)

  return (
    <div>
      <Tabs
        tabs={shown} value={value} onChange={onChange}
        extra={canChoose && choices.length > 0 && (
          <Button kind="mini" onClick={() => setOpen(!open)} aria-expanded={open}>Choose what you see</Button>
        )}
      />
      {canChoose && landedOnHidden && current && (
        <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-slate-400">
          <span>{current.name} is one you normally keep hidden.</span>
          <Button kind="mini" disabled={setItem.isPending} onClick={() => setItem.mutate({ itemKey: current.itemKey, shown: true })}>Keep it</Button>
        </div>
      )}
      {open && (
        <div className="mt-2 rounded border border-slate-700 bg-slate-900 p-3">
          <div className="mb-2 text-xs text-slate-400">
            Tick what you want on this screen. It is yours alone, it follows you to any computer, and nothing here
            changes what you are allowed to open.
          </div>
          <ul className="grid grid-cols-1 gap-x-6 gap-y-1 sm:grid-cols-2">
            {choices.map((i) => (
              <li key={i.itemKey} className="flex items-center gap-2 text-sm">
                <input
                  id={`vi-${screenKey}-${i.itemKey}`} type="checkbox" className="accent-sky-500"
                  checked={i.isShown} disabled={i.isAlways || setItem.isPending}
                  onChange={(e) => setItem.mutate({ itemKey: i.itemKey, shown: e.target.checked })}
                />
                <label htmlFor={`vi-${screenKey}-${i.itemKey}`} className="text-slate-200">{i.name}</label>
                <span className="text-xs text-slate-500">{i.isAlways ? 'always' : sourceWords[i.source]}</span>
                {i.source === 'mine' && (
                  <button type="button" className="text-xs text-sky-400 hover:text-sky-300" disabled={setItem.isPending}
                    onClick={() => setItem.mutate({ itemKey: i.itemKey, shown: null })}>undo</button>
                )}
              </li>
            ))}
          </ul>
          {setItem.isError && <div className="mt-2 text-xs text-red-300">Not saved: {(setItem.error as Error).message}</div>}
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <Button kind="mini" disabled={setItem.isPending || !choices.some((i) => i.source === 'mine')}
              onClick={() => { for (const i of choices) if (i.source === 'mine') setItem.mutate({ itemKey: i.itemKey, shown: null }) }}>
              Back to the usual
            </Button>
            <Button kind="mini" onClick={() => setOpen(false)}>Close</Button>
          </div>
        </div>
      )}
    </div>
  )
}
