// #237 (the owner, 2026-09-25): a screen shows a thing's name as a P&C person says it, never its internal code —
// "Device position", not "DevicePosition". The names are reference data (ref.vLocationNodeType.Name), read once and
// shared through the query cache.
import { s } from '@/lib/api'
import { useViewAll } from '@/lib/hooks'

/** The name of a location node type ("Device position" for DevicePosition); the code itself only until the names load. */
export function useNodeTypeName() {
  const q = useViewAll('ref', 'vLocationNodeType', {}, 'Name')
  const byCode = new Map((q.data ?? []).map((t) => [s(t.NodeTypeCode), s(t.Name)]))
  return (code: unknown) => byCode.get(s(code)) || s(code)
}

/** The name of an asset type as ref.vAssetType names it (for COUPLING_CAPACITOR_VT, CT_AUX and the like); the code until they load. */
export function useAssetTypeName() {
  const q = useViewAll('ref', 'vAssetType', {}, 'Name')
  const byCode = new Map((q.data ?? []).map((t) => [s(t.AssetTypeCode), s(t.Name)]))
  return (code: unknown) => byCode.get(s(code)) || s(code)
}
