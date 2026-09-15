import { useQuery } from '@tanstack/react-query'
import { me, health, viewAll, type Row } from './api'

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
