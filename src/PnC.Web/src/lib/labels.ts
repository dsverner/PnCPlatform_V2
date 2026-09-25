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

/** #238: the status words the schema's CHECK lists allow (asset: Planned/InService/OutOfService/Retired; scheme: Designed/
 * Commissioned/InService/Retired; obligation: Open/Satisfied/NotApplicable/Superseded) as a person says them. A value not
 * listed is split at its capitals ("SomeNewState" → "Some new state") rather than shown run together. */
const STATUS_WORDS: Record<string, string> = {
  Planned: 'Planned', InService: 'In service', OutOfService: 'Out of service', Retired: 'Retired', Designed: 'Designed',
  Commissioned: 'Commissioned', Open: 'Open', Satisfied: 'Satisfied', NotApplicable: 'Not applicable', Superseded: 'Superseded',
}
export const statusWords = (code: unknown) => STATUS_WORDS[s(code)] ?? splitWords(s(code))
export const splitWords = (code: string) => code.replace(/([a-z])([A-Z])/g, '$1 $2').replace(/^(.)(.*)$/, (_, a: string, b: string) => a + b.toLowerCase())

/** #238: what a scheme member is (scheme.AddSchemeMember's MemberKind). */
const MEMBER_KIND_WORDS: Record<string, string> = { ProtectionFunction: 'Protection function', Asset: 'Asset', Channel: 'Channel', Connection: 'Connection', Device: 'Relay', Node: 'Location' }
export const memberKindWords = (code: unknown) => MEMBER_KIND_WORDS[s(code)] ?? splitWords(s(code))

/** #238: a scheme member role by its name (ref.vSchemeMemberRole.Name: "CT source" for CtSource). */
export function useMemberRoleName() {
  const q = useViewAll('ref', 'vSchemeMemberRole', {}, 'Name')
  const byCode = new Map((q.data ?? []).map((t) => [s(t.MemberRoleCode), s(t.Name)]))
  return (code: unknown) => byCode.get(s(code)) || s(code)
}
