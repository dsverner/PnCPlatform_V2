// #171 (2026-09-16): the Compliance tab of a settings record — what this device is, what it inherits from the station and
// from the primary asset its scheme protects, the obligations standing against it, and the platform's standing verdict on
// every rule. Plain React (the #167 rule). Nothing here decides an obligation: the rules and the formulas are definitions
// and the evaluator is the only thing that reads them. #214 (the owner, 2026-09-20: "Should the evaluation be an automatic
// function of what is presently known about the system?"): it is — this tab reads what the platform decided
// (compliance.vDeviceVerdict, vDeviceEvaluation), when and why, and has no button. A change that a rule reads leaves an
// evaluation request; the worker answers within seconds; the hourly pass is the catch-all (Compliance › Evaluation).
import { Fragment, useState } from 'react'
import { statusWords, useNodeTypeName } from '@/lib/labels'
import { useQuery } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { fmtDate, fmtWhen, s, view, viewAll, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Status, type Tone } from '@/components/ui/ui'
import { CLASSIFICATION_KINDS, ClassificationPanel, DEVICE_KINDS, NodeLink, kindApplies, useClassificationKindRef, useClassifications, type DerivedNote } from './PrimaryAssetScreen'

/** One fact read, as the evaluator records it on a verdict (compliance.SubjectVerdict.ReadsJson) and on an obligation. */
export interface FactRead { name: string; params: string | null; value: string }
const readsOf = (v: Row): FactRead[] => { try { return (JSON.parse(s(v.ReadsJson) || '[]') as FactRead[]) ?? [] } catch { return [] } }

/** The PRC-023 loadability working, in the order the calculation goes (the Program.Formula seeds of #171). */
const PRC023_READS: [string, string][] = [
  ['device.functions', 'elements in service at the position'],                    // #197
  ['device.functions.note', 'load-responsive under PRC-023-6 Attachment A'],      // #197
  ['asset.formula.prc023_zset', 'zone 3 reach along the line angle'],
  ['asset.formula.prc023_line_angle', 'line angle'],
  ['asset.formula.prc023_z30', 'impedance at 30°'],
  ['asset.formula.prc023_trip_current', 'trip current at 0.85 pu'],
  ['asset.formula.prc023_load_current', 'lowest load-responsive trip current'],
  ['asset.formula.prc023_criterion', 'criterion'],
]

/** #238 (the owner, 2026-09-25): what the evaluator read, named as a P&C person names it. The stored reason and reads stay
 * exactly as the evaluator wrote them (the audit trail); only the screen puts them in words. The names are the facts seen
 * in verdicts and obligations on DEV (33, listed from compliance.SubjectVerdict and ObligationInstanceFact); a fact not
 * named here shows its own name, so a gap is visible rather than guessed. */
const KIND_LABEL: Record<string, string> = Object.fromEntries(CLASSIFICATION_KINDS.map((k) => [k.code, k.label]))
const kindLabel = (code: string) => KIND_LABEL[code] ?? code
const RATING_WORDS: Record<string, string> = { FifteenMinute: '15-minute rating', FourHour: '4-hour rating', PracticalLimitation: 'practical limitation' }
const FACT_WORDS: Record<string, string> = {
  'device.technology': 'Technology', 'asset.voltage_class': 'Voltage class', 'device.protects.name': 'Protected element',
  'device.protects.terminal.voltage': 'Voltage at the protected terminal', 'device.functions.note': 'Why each element is or is not load-responsive',
  'cadence.anchor': 'Period start', 'cadence.due': 'Due', 'record.occurred_at': 'Record date', 'record.last': 'Last record',
  'person.employer': 'Employer', 'person.authorisations': 'Authorisations',
}
export function factLabel(name: string, params?: string | null): string {
  const inline = /^(.*?)(\[.*\])$/.exec(name)                    // an obligation fact carries its parameters in its name
  if (inline && !params) return factLabel(inline[1], inline[2])
  const p = s(params).replace(/^\[|\]$/g, '')
  if (name === 'device.functions') return /load_responsive/.test(p) ? 'Load-responsive elements in service' : 'Elements in service'
  if (name === 'device.protects.rating') { const k = /kind='?([A-Za-z]+)/.exec(p)?.[1] ?? ''; return `Protected element's ${RATING_WORDS[k] ?? (k || 'rating')}` }
  if (FACT_WORDS[name]) return FACT_WORDS[name]
  const prc = PRC023_READS.find(([n]) => n === name); if (prc) return prc[1][0].toUpperCase() + prc[1].slice(1)
  let m: RegExpExecArray | null
  if ((m = /^device\.classification\.(\w+)$/.exec(name))) return `${kindLabel(m[1])} (this relay)`
  if ((m = /^device\.protects\.bus\.classification\.(\w+)$/.exec(name))) return `${kindLabel(m[1])} of the bus at the protected end`
  if ((m = /^device\.protects\.classification\.(\w+)$/.exec(name))) return `${kindLabel(m[1])} of the protected element`
  if ((m = /^device\.location\.classification\.(\w+)$/.exec(name))) return `${kindLabel(m[1])} of the building`
  if ((m = /^device\.station\.classification\.(\w+)$/.exec(name))) return `${kindLabel(m[1])} of the station`
  if ((m = /^device\.settings\.(.+)$/.exec(name))) return `Setting ${m[1]}`
  return name
}
/** A value as read: "unknown" is what the evaluator writes for a fact nobody has recorded; "{}" is an empty set. */
export const factValue = (v: unknown) => { const x = s(v); return x === 'unknown' ? 'not recorded' : x === '{}' ? 'none' : x.replace(/@Primary\b/g, ' primary').replace(/@Secondary\b/g, ' secondary') }
const readLine = (x: FactRead) => `${factLabel(x.name, x.params)}: ${factValue(x.value)}`

/** A standing verdict's reason in words (ComplianceEvaluator.Reasons writes "undetermined — not known: <facts>" and "it
 * read <fact> = <value>; …"; those are rebuilt from the fact names and reads; a reason already in words is shown as is). */
function reasonWords(v: Row): string {
  const r = s(v.Reason)
  const unknown = /^undetermined(?: — not known)?:\s*(.*)$/.exec(r)
  if (unknown) return 'Not known yet: ' + unknown[1].split(',').map((n) => n.trim()).filter(Boolean).map((n) => factLabel(n)).join('; ')
  if (r.startsWith('it read ')) {
    const reads = readsOf(v).filter((x) => x.name !== 'device.functions.note').slice(0, 3)
    return reads.length ? 'Read ' + reads.map(readLine).join('; ') : r
  }
  if (r === 'no case matched') { const reads = readsOf(v); return reads.length ? 'worked out from ' + reads.map(readLine).join('; ') : 'none of its cases applies' }
  return r
}

const statusTone = (v: unknown): Tone => {
  const x = s(v)
  if (x === 'Satisfied') return 'good'
  if (x === 'Open') return 'warn'
  if (x === 'Exception') return 'accent'
  return 'neutral'
}
const resultTone = (v: string): Tone => (v === 'true' ? 'good' : v === 'false' ? 'neutral' : v === 'unknown' ? 'warn' : 'bad')
/** Why the last check happened, in words (compliance.RuleEvaluationRun.Trigger). */
const triggerWords = (t: unknown) => ({ Scheduled: 'in the hourly check', FactChanged: 'after a change', RuleApproved: 'after a rule changed', Manual: 'run by hand' } as Record<string, string>)[s(t)] ?? s(t)

/** What the device's scheme protects, with each primary asset's applicability classifications and the bus at the end it
 * protects from. Lifted out of RecordScreen so the Where panel and this tab ask the same question once (#171). */
export function useProtectedAssets(schemeEntityId: string) {
  return useQuery({ queryKey: ['schemeProtectsNamed', schemeEntityId], enabled: !!schemeEntityId, staleTime: 60_000, queryFn: async () => {
    const links = await viewAll('scheme', 'vSchemeProtects', { SchemeEntityId: schemeEntityId })
    const out: Row[] = []
    for (const l of links) {
      const a = (await view('asset', 'vPrimaryAsset', { EntityId: s(l.PrimaryAssetEntityId) }, { take: 1 })).rows[0]; if (!a) continue
      // the end this scheme protects from, and the bus there: the NPCC A-10 declaration is the bus's (the owner, 2026-09-16)
      const term = l.AssetTerminalEntityId ? (await view('asset', 'vAssetTerminalDetail', { TerminalEntityId: s(l.AssetTerminalEntityId) }, { take: 1 })).rows[0] : null
      const cls = (await view('asset', 'vClassification', { SubjectKind: 'Asset', SubjectEntityId: s(a.EntityId) }, { take: 50 })).rows
      const valueOf = (code: string) => cls.find((c) => s(c.ClassificationKindCode) === code)?.ClassificationValue ?? null
      out.push({ ...a, ZoneRole: l.ZoneRole, TerminalNo: term?.TerminalNo, TerminalStation: term?.StationName, TerminalStationId: term?.StationNodeEntityId,
        BusName: term?.BusName, BusNpcc: term?.BusNpcc, HasTerminal: !!term, BesStatus: valueOf('BesStatus'), Prc023: valueOf('Prc023'),
        Npcc: valueOf('NpccBulkPowerSystem') })   // #196: the element's own A-10 declaration, entered by hand for now; the bus's stands in when it has none
    }
    return out
  } })
}

/** #237 (the owner, 2026-09-25: the Protects line had "all of the various information sections … stuck together"): what
 * a scheme protects, one bullet per primary asset, each fact on its own labelled line. Shared by the record's Placement
 * panel and the Compliance tab. #173: a classification that does not apply to the asset's type is not shown (a bus has
 * no PRC-023 line); #196: the element's own NPCC declaration rules over the bus's. */
export function ProtectedAssetList({ schemeEntityId }: { schemeEntityId: string }) {
  const navigate = useNavigate()
  const q = useProtectedAssets(schemeEntityId)
  const kindRefQ = useClassificationKindRef()
  const kindRef = (code: string) => (kindRefQ.data ?? []).find((k) => s(k.ClassificationKindCode) === code)
  const link = (screen: string, id: string, label: string) => (
    <a className="text-sky-300 underline" href={screenPath(screen, id)} onClick={(e) => { e.preventDefault(); navigate(screenPath(screen, id)) }}>{label}</a>)
  if (!schemeEntityId) return <span className="text-slate-500">this relay is in no scheme, so what it protects is not known</span>
  if (q.isPending) return <span className="text-slate-500">…</span>
  const rows = q.data ?? []
  if (!rows.length) return <span className="text-slate-500">the scheme has nothing recorded that it protects</span>
  const notRecorded = <span className="text-slate-500">not recorded</span>
  return (
    <ul className="list-disc space-y-2 pl-5 marker:text-slate-600">{rows.map((a) => {
      const type = s(a.AssetTypeName).toLowerCase() || 'element'
      const kinds = ([['BesStatus', 'BES status', a.BesStatus], ['Prc023', 'PRC-023', a.Prc023]] as [string, string, unknown][])
        .filter(([code]) => kindApplies(kindRef(code), s(a.AssetTypeCode)))
      return (
        <li key={s(a.EntityId)}>
          <span className="font-medium">{link('PRIMARY_ASSET', s(a.EntityId), s(a.Name))}</span>
          <span className="ml-2 text-xs text-slate-500">{s(a.AssetTypeName)}{a.ZoneRole !== 'Primary' ? ` (${s(a.ZoneRole).toLowerCase()} zone)` : ''}</span>
          <dl className="mt-1 grid grid-cols-[9rem_1fr] gap-x-2 gap-y-0.5 text-xs">
            {kinds.map(([code, label, value]) => <Fragment key={code}><dt className="text-slate-500">{label}</dt><dd className="text-slate-300">{value ? s(value) : notRecorded}</dd></Fragment>)}
            {!kinds.length && <><dt className="text-slate-500">BES / PRC-023</dt><dd className="text-slate-500">does not apply to a {type}</dd></>}
            {a.Npcc ? <><dt className="text-slate-500">NPCC (the {type}'s own)</dt><dd className="text-sky-300">{s(a.Npcc)}</dd></> : null}
            <dt className="text-slate-500">Protected from</dt>
            <dd className="text-slate-300">{a.HasTerminal
              ? <>terminal {s(a.TerminalNo)} at {a.TerminalStationId ? link('LOCATION', s(a.TerminalStationId), s(a.TerminalStation)) : s(a.TerminalStation)}</>
              : <span className="text-slate-500">no end is named, so no bus NPCC is taken</span>}</dd>
            {a.HasTerminal ? <>
              <dt className="text-slate-500">Bus at that end</dt>
              <dd className="text-slate-300">{a.BusName ? s(a.BusName) : <span className="text-slate-500">no bus linked</span>}</dd>
              {a.BusName ? <><dt className="text-slate-500">Bus NPCC</dt><dd className="text-slate-300">{s(a.BusNpcc) || notRecorded}{a.Npcc ? <span className="text-slate-500"> — the {type}'s own declaration rules</span> : null}</dd></> : null}
            </> : null}
          </dl>
        </li>) })}
    </ul>)
}

/** The CIP-002 impact rating the rules actually read: the nearest classified ancestor-or-self of the device's placement
 * node, not the station's (#173, the owner 2026-09-17 — "the classification … of building that the device is in"; the
 * engine walks ParentEntityId in location.fNearestClassified). location.vNode.Path is that same chain for a screen: the
 * ancestors' ids in order, the node's own excluded (#94), so this is three reads — the placement node, every Node-subject
 * CipImpactRating (8 rows on DEV today), and the node that carries the winner. The deepest wins: a rating on the building
 * beats the station's. PositionNodeEntityId comes from document.vSettingsRecord; without it the installed placement is read. */
export function useLocationCip(positionNodeEntityId: string, deviceEntityId: string) {
  return useQuery({ queryKey: ['locationCip', positionNodeEntityId, deviceEntityId], enabled: !!(positionNodeEntityId || deviceEntityId), staleTime: 60_000, queryFn: async () => {
    let nodeId = positionNodeEntityId
    if (!nodeId) nodeId = s((await view('asset', 'vPlacement', { AssetEntityId: deviceEntityId, PlacementKind: 'Installed' }, { take: 1 })).rows[0]?.NodeEntityId)
    if (!nodeId) return null
    const node = (await view('location', 'vNode', { EntityId: nodeId }, { take: 1 })).rows[0]
    if (!node) return null
    const cls = await viewAll('asset', 'vClassification', { SubjectKind: 'Node', ClassificationKindCode: 'CipImpactRating' })
    const byNode = new Map(cls.map((c) => [s(c.SubjectEntityId).toLowerCase(), c]))
    const chain = [...s(node.Path).split('/').map((x) => x.trim()).filter(Boolean), s(node.EntityId)]
    for (let i = chain.length - 1; i >= 0; i--) {
      const c = byNode.get(chain[i].toLowerCase())
      if (!c) continue
      const carrier = chain[i].toLowerCase() === s(node.EntityId).toLowerCase() ? node : (await view('location', 'vNode', { EntityId: chain[i] }, { take: 1 })).rows[0]
      return { value: s(c.ClassificationValue), at: c.DeterminedAt, nodeId: chain[i], nodeName: s(carrier?.Name), nodeType: s(carrier?.NodeTypeCode) }
    }
    return { value: '', at: null, nodeId: '', nodeName: '', nodeType: '' }
  } })
}

/** The BES Cyber Asset line (#173). The value is the platform's, written by a derivation the evaluator runs — so until a
 * derived row exists this says only that no pass has run and lists the inputs as facts; it never announces the verdict
 * itself. #214: the derivation's standing verdict (compliance.vDeviceVerdict, VerdictKind Derivation) carries its reason. */
function besCyberAssetNote(r: Row, protectedAssets: Row[] | undefined, current: Row | undefined, derived: Row | undefined): DerivedNote {
  if (derived?.Error) return { label: `could not be worked out: ${s(derived.Error)}`, reason: s(derived.Error) }
  // a derived row stands; its reason is what the pass read (#238: the facts in words, not the case's formula text)
  if (current) return { reason: derived ? (readsOf(derived).map(readLine).join('; ') || reasonWords(derived)) : undefined }
  if (derived && !derived.Result) return { label: `not decided — ${reasonWords(derived)}` }
  return { label: <>not decided yet. This is checked within seconds of a change, and every hour. What is known so far:
    <ul className="mt-0.5 list-disc pl-5">{besCyberAssetInputs(r, protectedAssets).map((p) => <li key={p}>{p}</li>)}</ul></> }
}

/** The facts the derivation reads, stated as facts and nothing more (the technology and each protected element's BES status). */
function besCyberAssetInputs(r: Row, protectedAssets: Row[] | undefined): string[] {
  const tech = s(r.Technology)                                    // document.vSettingsRecord carries the model's Technology
  const parts = [tech ? `Technology: ${tech.toLowerCase()}` : 'the technology is not recorded']
  if (!r.SchemeEntityId) parts.push('this relay is in no scheme, so what it protects is not known')
  else if (!protectedAssets) parts.push('what it protects is still loading')
  else if (!protectedAssets.length) parts.push('the scheme has nothing recorded that it protects')
  else parts.push(...protectedAssets.map((a) => `${s(a.Name)} is ${a.BesStatus ? s(a.BesStatus) : 'of no recorded BES status'}`))
  return parts
}

export default function ComplianceTab({ r }: { r: Row }) {
  const can = useCan()
  const device = s(r.DeviceEntityId)
  const protectsQ = useProtectedAssets(s(r.SchemeEntityId))     // shared by query key with the Inherited panel below
  const clsQ = useClassifications('Asset', device)              // shared by query key with the panel's own read
  const verdictsQ = useViewAll('compliance', 'vDeviceVerdict', { DeviceEntityId: device }, 'RuleKey', !!device)   // #214: the standing verdicts
  const verdicts = verdictsQ.data ?? []
  const bca = (clsQ.data ?? []).find((c) => s(c.ClassificationKindCode) === 'BesCyberAsset')
  const bcaDerived = verdicts.find((v) => s(v.VerdictKind) === 'Derivation' && s(v.DerivationKind) === 'BesCyberAsset')
  return (
    <div className="space-y-3">
      <div className="grid gap-3 lg:grid-cols-2">
        {/* #173 (2026-09-17): the BES Cyber Asset line is derived, not chosen, so the panel offers no control for it */}
        <ClassificationPanel title="This device" subjectKind="Asset" subjectEntityId={device} editable={can('Asset.Modify')} kinds={DEVICE_KINDS}
          reasons={{ BesCyberAsset: besCyberAssetNote(r, protectsQ.data, bca, bcaDerived) }}
          note="A microprocessor relay that protects a BES element is a BES Cyber Asset. That is worked out here, not chosen, so there is nothing to set. External routable connectivity is entered by hand. The impact rating comes from the building, shown beside this." />
        <Inherited r={r} bca={s(bca?.ClassificationValue)} />
      </div>
      <ElementsInService r={r} />
      <Standards r={r} verdicts={verdicts} pending={verdictsQ.isPending} />
    </div>
  )
}

/** What the device inherits: the location's CIP impact rating, and the protected primary asset's BES / PRC-023 and the bus's NPCC.
 * #173: a classification that does not apply to the protected asset's type is not shown at all — a bus has no PRC-023 line. */
function Inherited({ r, bca }: { r: Row; bca: string }) {
  const cipQ = useLocationCip(s(r.PositionNodeEntityId), s(r.DeviceEntityId))
  const nodeTypeName = useNodeTypeName()
  const cip = cipQ.data
  return (
    <Panel title="Inherited">
      <dl className="space-y-2 text-sm">
        <div className="grid grid-cols-[13rem_1fr] items-start gap-2">
          <dt className="text-slate-400">CIP impact rating</dt>
          <dd className="min-w-0">
            {/* #196 follow-up (owner, 2026-09-19): the rating is the device's only when the device is a BES Cyber Asset; the
                MCGG22's page read "Medium" though it is electromechanical — the building's rating shown as if it were the relay's */}
            {cipQ.isPending ? <span className="text-slate-500">…</span>
              : !cip ? <span className="text-slate-500">this relay is not placed anywhere, so it takes no rating</span>
              : !cip.value ? <span className="text-slate-500">no building above this position carries a rating</span>
              : bca === 'Not BCA' ? <span className="text-slate-300">Not applicable — not a cyber asset. <span className="text-slate-500">The building <NodeLink id={cip.nodeId} name={cip.nodeName} /> is rated {cip.value}; that applies to the cyber assets it houses, not to this relay.</span></span>
              : <><Pill tone={cip.value === 'High' ? 'bad' : cip.value === 'Medium' ? 'warn' : 'neutral'}>{cip.value}</Pill>
                  <span className="ml-2">— {bca === 'BCA' ? 'a BES Cyber Asset in' : 'the rating of'} <NodeLink id={cip.nodeId} name={cip.nodeName} /> <span className="text-xs text-slate-500">({nodeTypeName(cip.nodeType).toLowerCase()}{cip.at ? ', rated ' + fmtWhen(cip.at) : ''})</span>
                  {bca === 'BCA' ? null : <div className="text-xs text-slate-500">Whether this relay is a BES Cyber Asset is not decided yet.</div>}</span></>}
            <div className="text-xs text-slate-600">CIP-002: this is the building's rating. Every BES Cyber Asset in it takes that rating. Whether this relay is one is worked out above.</div>{/* #173, #195 */}
          </dd>
        </div>
        <div className="grid grid-cols-[13rem_1fr] items-start gap-2">
          <dt className="text-slate-400">Protected primary asset</dt>
          <dd className="min-w-0">
            <ProtectedAssetList schemeEntityId={s(r.SchemeEntityId)} />
            <div className="text-xs text-slate-600">What applies comes from the primary asset and its bus. The relay takes it from what it protects.</div>
          </dd>
        </div>
      </dl>
    </Panel>
  )
}

/** #197 (owner, 2026-09-19): the elements in service at the device's position (scheme.CommissionedFunction, one row per
 * enabled element, #181), each with its PRC-023-6 Attachment A ruling — read from scheme.vPositionFunction, which judges a
 * legacy string such as 50/51N by its numbers (ref.fAnsiLoadResponsive). PRC-023 R1's applicability turns on this list: the
 * rule reads these same rows as device.functions[load_responsive='true']. */
function ElementsInService({ r }: { r: Row }) {
  const pos = s(r.PositionNodeEntityId)
  const q = useViewAll('scheme', 'vPositionFunction', { PositionNodeEntityId: pos }, 'AnsiCode', !!pos)
  const rows = q.data ?? []
  return (
    <Panel title={`Elements in service · ${pos && q.isPending ? '…' : rows.length}`}>
      {!pos && <Status>This record names no position, so the elements in service are not known. Set the position on the record.</Status>}
      {pos && !q.isPending && !rows.length && <Status>No element is in service at this position. PRC-023 cannot apply until one is recorded.</Status>}
      {rows.length > 0 && (
        <table className="w-full text-sm">
          <thead><tr className="border-b border-slate-700 text-left text-xs uppercase tracking-wide text-slate-400">
            <th className="py-1 pr-2">Element</th><th className="py-1 pr-2">Load-responsive</th><th className="py-1">Basis (PRC-023-6 Attachment A)</th></tr></thead>
          <tbody>
            {rows.map((f) => { const lr = f.LoadResponsive
              return (
                <tr key={s(f.RowId)} className="border-b border-slate-800 align-top">
                  <td className="py-1 pr-2 text-slate-200">{s(f.AnsiCode)}{f.IsPrincipal ? <span className="ml-1 text-xs text-slate-500">principal</span> : null}
                    <div className="text-xs text-slate-500">{s(f.AnsiName) !== s(f.AnsiCode) ? s(f.AnsiName) : ''}{f.BaseCodes && s(f.BaseCodes) !== s(f.AnsiCode) ? ` · read as ${s(f.BaseCodes)}` : ''}</div></td>
                  <td className="py-1 pr-2"><Pill tone={lr === true ? 'good' : lr === false ? 'neutral' : 'warn'}>{lr === true ? 'yes' : lr === false ? 'no' : 'not ruled'}</Pill></td>
                  <td className="py-1 text-xs text-slate-400">{s(f.LoadResponsiveBasis)}</td>
                </tr>) })}
          </tbody>
        </table>)}
      <Status>PRC-023-6 applies to “load-responsive phase protection systems as described in Attachment A” at the terminals of its circuits (4.1). An element nobody has ruled on leaves the standard undecided here, never inapplicable.</Status>
    </Panel>
  )
}

/** #214 follow-up (the owner, 2026-09-20: "agreed on your one list suggestion"): ONE list per rule, in standard order. A rule
 * that applies carries its obligation on the row — status, period, the facts read when it opened (compliance.vObligationSubject:
 * Open and Satisfied; NotApplicable and Superseded are history); an undetermined rule says what is not known; an error is shown
 * (it is not a decision that the rule does not bind). The rules that do not apply sit behind one closed line at the bottom with
 * their reasons (#197, the owner: "there must be a reason" — kept, not spread). The verdicts are the platform's standing
 * decision (compliance.vDeviceVerdict, vDeviceEvaluation); nothing here runs anything. */
function Standards({ r, verdicts, pending }: { r: Row; verdicts: Row[]; pending: boolean }) {
  const device = s(r.DeviceEntityId)
  const evalQ = useViewAll('compliance', 'vDeviceEvaluation', { DeviceEntityId: device }, undefined, !!device)
  const obQ = useViewAll('compliance', 'vObligationSubject', { SubjectEntityId: device }, 'RequirementNumber', !!device)
  const ev = (evalQ.data ?? [])[0]
  const obligations = obQ.data ?? []
  const byRule = new Map(obligations.map((o) => [s(o.RuleDefinitionKey), o]))
  const rules = verdicts.filter((v) => s(v.VerdictKind) === 'Rule')
  const sortKey = (v: Row) => `${s(v.StandardCode)} ${s(v.RequirementNumber)} ${s(v.RuleKey)}`
  const binding = rules.filter((v) => s(v.Result) !== 'false').sort((x, y) => sortKey(x).localeCompare(sortKey(y)))
  const notBinding = rules.filter((v) => s(v.Result) === 'false').sort((x, y) => sortKey(x).localeCompare(sortKey(y)))
  // an obligation whose rule has no standing verdict yet (the platform has not evaluated the device since #214) still shows
  const orphans = obligations.filter((o) => !rules.some((v) => s(v.RuleKey) === s(o.RuleDefinitionKey)))
  const [open, setOpen] = useState<string | null>(null)
  const [showWhy, setShowWhy] = useState(false)
  const busy = pending || evalQ.isPending || obQ.isPending
  const count = binding.length + orphans.length
  return (
    <Panel title={`Standards · ${busy ? '…' : count}`}>
      {obQ.isError && <Status bad>This list could not be read: {(obQ.error as Error).message}</Status>}
      {!busy && (ev
        ? <Status>{fmtWhen(ev.LastEvaluatedAt)} — last checked {triggerWords(ev.LastTrigger)} · {s(ev.RulesEvaluated)} rule(s).</Status>
        : <Status>Not checked yet. A relay is checked within seconds of a change, and every hour. There is nothing to press.</Status>)}
      {!busy && !count && !!rules.length && <Status>No standard applies to this relay, and none is undecided.</Status>}
      {count > 0 && (
        <table className="w-full text-sm">
          <thead><tr className="border-b border-slate-700 text-left text-xs uppercase tracking-wide text-slate-400">
            <th className="py-1 pr-2">Standard</th><th className="py-1 pr-2">Requirement</th><th className="py-1 pr-2">Rule</th>
            <th className="py-1 pr-2">Status</th><th className="py-1 pr-2">Period</th><th className="py-1">What was read</th></tr></thead>
          <tbody>
            {binding.map((v) => { const key = s(v.RuleKey); const o = byRule.get(key); const result = s(v.Result); const id = o ? s(o.RowId) : 'v:' + key
              return (
                <tr key={key} className="border-b border-slate-800 align-top">
                  <td className="py-1 pr-2 text-slate-200">{s(v.StandardCode)}<div className="text-xs text-slate-500">{s(v.StandardVersion)}</div></td>
                  <td className="py-1 pr-2 text-slate-200">{s(v.RequirementNumber)}<div className="text-xs text-slate-500">{s(v.RequirementTitle)}</div></td>
                  <td className="py-1 pr-2 text-slate-200">{s(v.RuleName)}
                    {result === 'unknown' && <div className="text-xs text-amber-300">{reasonWords(v)}</div>}
                    {result === 'error' && <div className="text-xs text-red-300">{s(v.Reason)}</div>}
                    {!!v.EvidenceNote && <div className="text-xs text-slate-500">Evidence: {s(v.EvidenceNote)}</div>}</td>
                  <td className="py-1 pr-2">
                    {o ? <Pill tone={statusTone(o.Status)}>{statusWords(o.Status)}</Pill>
                      : result === 'true' ? <Pill tone="warn" title="This requirement applies to the relay. It joins the list at the next check.">applies</Pill>
                      : <Pill tone={resultTone(result)}>{result === 'unknown' ? 'not decided' : 'error'}</Pill>}
                    <div className="text-xs text-slate-600">since {fmtWhen(v.SinceAt)}</div>
                  </td>
                  <td className="py-1 pr-2 text-xs text-slate-400">{o ? <>{fmtDate(o.PeriodStartAt)}{o.PeriodEndAt ? ' – ' + fmtDate(o.PeriodEndAt) : ' – open'}</> : '—'}</td>
                  <td className="py-1">
                    <Button kind="mini" onClick={() => setOpen(open === id ? null : id)}>{open === id ? 'hide' : 'show'}</Button>
                    {open === id && (o ? <ObligationFacts instanceRowId={s(o.RowId)} /> : <VerdictReads v={v} />)}
                    {open === id && <Working v={v} />}
                  </td>
                </tr>) })}
            {orphans.map((o) => { const id = s(o.RowId)
              return (
                <tr key={id} className="border-b border-slate-800 align-top">
                  <td className="py-1 pr-2 text-slate-200">{s(o.StandardCode)}<div className="text-xs text-slate-500">{s(o.StandardVersion)}</div></td>
                  <td className="py-1 pr-2 text-slate-200">{s(o.RequirementNumber)}{o.SubRequirement ? '.' + s(o.SubRequirement) : ''}<div className="text-xs text-slate-500">{s(o.RequirementTitle)}</div></td>
                  <td className="py-1 pr-2 text-slate-200">{s(o.RuleName)}</td>
                  <td className="py-1 pr-2"><Pill tone={statusTone(o.Status)}>{statusWords(o.Status)}</Pill></td>
                  <td className="py-1 pr-2 text-xs text-slate-400">{fmtDate(o.PeriodStartAt)}{o.PeriodEndAt ? ' – ' + fmtDate(o.PeriodEndAt) : ' – open'}</td>
                  <td className="py-1"><Button kind="mini" onClick={() => setOpen(open === id ? null : id)}>{open === id ? 'hide' : 'show'}</Button>{open === id && <ObligationFacts instanceRowId={id} />}</td>
                </tr>) })}
          </tbody>
        </table>)}
      {!!notBinding.length && (
        <div className="mt-2 text-xs">
          <span className="text-slate-500">{notBinding.length} standard{notBinding.length === 1 ? '' : 's'} do{notBinding.length === 1 ? 'es' : ''} not apply to this relay</span>
          <Button kind="mini" className="ml-2" onClick={() => setShowWhy(!showWhy)}>{showWhy ? 'hide why' : 'show why'}</Button>
          {showWhy && (
            <ul className="mt-1 space-y-0.5">
              {notBinding.map((v) => <li key={'why' + s(v.RuleKey)}><span className="text-slate-300">{ruleTitle(v)}</span> <span className="text-slate-400">— {reasonWords(v)}</span> <span className="text-slate-600">since {fmtWhen(v.SinceAt)}</span></li>)}
            </ul>)}
        </div>)}
    </Panel>
  )
}

const ruleTitle = (v: Row) => (v.StandardCode ? `${s(v.StandardCode)} ${s(v.StandardVersion)} ${s(v.RequirementNumber)}`.replace(/\s+/g, ' ').trim() : s(v.RuleName))

/** The reads the standing verdict was decided on (compliance.SubjectVerdict.ReadsJson) — shown when no obligation row carries them. */
function VerdictReads({ v }: { v: Row }) {
  const reads = readsOf(v).filter((x) => !PRC023_READS.some(([n]) => n === x.name))
  if (!reads.length) return <div className="mt-1 text-xs text-slate-500">Nothing was read for this rule.</div>
  return (
    <ul className="mt-1 space-y-0.5 text-xs">
      {reads.map((x, i) => <li key={x.name + i}><span className="text-slate-400">{factLabel(x.name, x.params)}:</span> <span className="text-slate-100">{factValue(x.value)}</span></li>)}
    </ul>
  )
}

/** The PRC-023 loadability working, from the recorded reads, when the verdict carries them (#171). */
function Working({ v }: { v: Row }) {
  const byName = new Map(readsOf(v).map((x) => [x.name, x]))
  const working = PRC023_READS.filter(([n]) => byName.has(n))
  if (!working.length) return null
  return (
    <div className="mt-1">
      <div className="text-xs font-semibold uppercase tracking-wide text-slate-400">The loadability working</div>
      <ul className="mt-0.5 space-y-0.5 text-xs">
        {working.map(([name, label]) => <li key={name}><span className="text-slate-400">{label}:</span> <span className="text-slate-100">{factValue(byName.get(name)!.value)}</span></li>)}
      </ul>
      <div className="mt-0.5 text-xs text-slate-600">The steady-state self-polarised circle. The memory-polarised expansion is not modelled. 50H is taken as a tripping element; its MTU/MTO mask is not decoded.</div>{/* #171 */}
    </div>
  )
}


function ObligationFacts({ instanceRowId }: { instanceRowId: string }) {
  const q = useViewAll('compliance', 'vObligationInstanceFact', { ObligationInstanceRowId: instanceRowId }, 'FactName')
  const rows = q.data ?? []
  if (q.isPending) return <div className="mt-1 text-xs text-slate-500">…</div>
  if (!rows.length) return <div className="mt-1 text-xs text-slate-500">Nothing was recorded against this requirement.</div>
  return (
    <ul className="mt-1 space-y-0.5 text-xs">
      {rows.map((f) => <li key={s(f.ObligationInstanceFactId)}><span className="text-slate-400">{factLabel(s(f.FactName))}:</span> <span className="text-slate-200">{factValue(f.ValueAsRead)}</span></li>)}
    </ul>
  )
}
