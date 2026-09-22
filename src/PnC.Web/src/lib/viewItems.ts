// #226: what this person sees on a screen. Resolved by the database in three layers — the screen's own default, then
// the default for each role they hold (the widest wins), then their own choice — so the page only has to read it.
// Hiding is a preference and never a permission: an item hidden here is one click from being back, and nothing the
// person may not see ever depends on it.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { proc, viewAll, type Row } from './api'

export interface ViewItem {
  screenKey: string
  itemKey: string
  name: string
  description: string
  kind: string
  order: number
  isAlways: boolean
  isShown: boolean
  /** which layer answered: the person's own choice, a role they hold, or the screen's own default */
  source: 'mine' | 'role' | 'screen'
}

const toItem = (r: Row): ViewItem => ({
  screenKey: String(r.ScreenKey ?? ''),
  itemKey: String(r.ItemKey ?? ''),
  name: String(r.Name ?? ''),
  description: String(r.Description ?? ''),
  kind: String(r.ItemKind ?? 'Tab'),
  order: Number(r.DisplayOrder ?? 0),
  isAlways: r.IsAlways === true || r.IsAlways === 1,
  isShown: r.IsShown === true || r.IsShown === 1,
  source: (String(r.Source ?? 'screen') as ViewItem['source']),
})

/** Every part of one screen this person may show or hide, in order, with the answer already worked out. */
export function useViewItems(screenKey: string | undefined) {
  return useQuery({
    queryKey: ['viewItems', screenKey ?? ''],
    enabled: !!screenKey,
    staleTime: 5 * 60_000,
    queryFn: async () => (await viewAll('config', 'vMyViewItem', { ScreenKey: screenKey! }, 'DisplayOrder')).map(toItem),
  })
}

/** Show or hide one part of one screen, for me. `shown` of null goes back to what my roles give me. */
export function useSetViewItem(screenKey: string | undefined) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (v: { itemKey: string; shown: boolean | null }) =>
      proc('config', 'SetViewItem', { ScreenKey: screenKey ?? '', ItemKey: v.itemKey, IsShown: v.shown }),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['viewItems'] })
      // the same answer is read a second way on the preferences screen; both go stale together
      void qc.invalidateQueries({ queryKey: ['view', 'config', 'vMyViewItem'] })
    },
  })
}

/** The keys a screen should show, given the resolved items; an empty list means the screen has no items declared. */
export const shownKeys = (items: ViewItem[] | undefined) => (items ?? []).filter((i) => i.isShown).map((i) => i.itemKey)
