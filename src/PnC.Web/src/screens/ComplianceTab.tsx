// #171 (2026-09-16): the Compliance tab of a settings record — what this device is, what it inherits from the station and
// from the primary asset its scheme protects, the obligations standing against it, and the platform's standing verdict on
// every rule. Plain React (the #167 rule). Nothing here decides an obligation: the rules and the formulas are definitions
// and the evaluator is the only thing that reads them. #214 (the owner, 2026-09-20: "Should the evaluation be an automatic
// function of what is presently known about the system?"): it is — this tab reads what the platform decided
// (compliance.vDeviceVerdict, vDeviceEvaluation), when and why, and has no button. A change that a rule reads leaves an
// evaluation request; the worker answers within seconds; the hourly pass is the catch-all (Compliance › Evaluation).
import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { fmtDate, fmtWhen, s, view, viewAll, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Status, type Tone } from '@/components/ui/ui'
import { ClassificationPanel, DEVICE_KINDS, NodeLink, kindApplies, useClassificationKindRef, useClassifications, type DerivedNote } from './PrimaryAssetScreen'

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

const statusTone = (v: unknown): Tone => {
  const x = s(v)
  if (x === 'Satisfied') return 'good'
  if (x === 'Open') return 'warn'
  if (x === 'Exception') return 'accent'
  return 'neutral'
}
const resultTone = (v: string): Tone => (v === 'true' ? 'good' : v === 'false' ? 'neutral' : v === 'unknown' ? 'warn' : 'bad')
/** The pass that last looked, in words (compliance.RuleEvaluationRun.Trigger). */
const triggerWords = (t: unknown) => ({ Scheduled: 'the hourly pass', FactChanged: 'after a change', RuleApproved: 'after a rule was approved', Manual: 'run by hand' } as Record<string, string>)[s(t)] ?? s(t)

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
  if (derived?.Error) return { label: `could not be evaluated: ${s(derived.Error)}`, reason: s(derived.Error) }
  if (current) return { reason: derived ? s(derived.Reason) : undefined }   // a derived row stands; its reason is the pass's
  if (derived && !derived.Result) return { label: `undetermined — ${s(derived.Reason)}` }
  return { label: `not yet evaluated — the platform evaluates within seconds of a change and every hour. The inputs: ${besCyberAssetInputs(r, protectedAssets)}.` }
}

/** The facts the derivation reads, stated as facts and nothing more (the technology and each protected element's BES status). */
function besCyberAssetInputs(r: Row, protectedAssets: Row[] | undefined): string {
  const tech = s(r.Technology)                                    // document.vSettingsRecord carries the model's Technology
  const parts = [tech ? `${tech.toLowerCase()}-based` : 'the technology is not recorded']
  if (!r.SchemeEntityId) parts.push('the device is in no scheme, so nothing protected is known')
  else if (!protectedAssets) parts.push('what it protects is still loading')
  else if (!protectedAssets.length) parts.push('the scheme protects nothing that is recorded yet')
  else parts.push(...protectedAssets.map((a) => `${s(a.Name)} is ${a.BesStatus ? s(a.BesStatus) : 'of no recorded BES status'}`))
  return parts.join('; ')
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
        <ClassificationPanel title="This device" subjectKind="Asset" subjectEntityId={device} editable={can('Asset.Modify')} kinds={DEVICE_KINDS}
          reasons={{ BesCyberAsset: besCyberAssetNote(r, protectsQ.data, bca, bcaDerived) }}
          note="Whether the device is a BES Cyber Asset is derived, not judged (the owner, 2026-09-17): a microprocessor-based device protecting a BES element is one, so it is stated here with its basis and no control. External routable connectivity is recorded by hand until a network-analysis module can determine it. The impact rating is the location's, beside it." />
        <Inherited r={r} bca={s(bca?.ClassificationValue)} />
      </div>
      <ElementsInService r={r} />
      <Obligations r={r} verdicts={verdicts} />
      <Standing device={device} verdicts={verdicts} pending={verdictsQ.isPending} />
    </div>
  )
}

/** What the device inherits: the location's CIP impact rating, and the protected primary asset's BES / PRC-023 and the bus's NPCC.
 * #173: a classification that does not apply to the protected asset's type is not shown at all — a bus has no PRC-023 line. */
function Inherited({ r, bca }: { r: Row; bca: string }) {
  const navigate = useNavigate()
  const cipQ = useLocationCip(s(r.PositionNodeEntityId), s(r.DeviceEntityId))
  const protectsQ = useProtectedAssets(s(r.SchemeEntityId))
  const kindRefQ = useClassificationKindRef()
  const kindRef = (code: string) => (kindRefQ.data ?? []).find((k) => s(k.ClassificationKindCode) === code)
  const inherited = (a: Row) => ([['BesStatus', 'BES status', a.BesStatus], ['Prc023', 'PRC-023', a.Prc023]] as [string, string, unknown][])
    .filter(([code]) => kindApplies(kindRef(code), s(a.AssetTypeCode)))
  const cip = cipQ.data
  const link = (screen: string, id: string, label: string) => (
    <a className="text-sky-300 underline" href={screenPath(screen, id)} onClick={(e) => { e.preventDefault(); navigate(screenPath(screen, id)) }}>{label}</a>)
  const rows = protectsQ.data ?? []
  return (
    <Panel title="Inherited">
      <dl className="space-y-2 text-sm">
        <div className="grid grid-cols-[13rem_1fr] items-start gap-2">
          <dt className="text-slate-400">CIP impact rating</dt>
          <dd className="min-w-0">
            {/* #196 follow-up (owner, 2026-09-19): the rating is the device's only when the device is a BES Cyber Asset; the
                MCGG22's page read "Medium" though it is electromechanical — the building's rating shown as if it were the relay's */}
            {cipQ.isPending ? <span className="text-slate-500">…</span>
              : !cip ? <span className="text-slate-500">the device is not placed anywhere, so it inherits no rating</span>
              : !cip.value ? <span className="text-slate-500">no building above this device's position carries a rating</span>
              : bca === 'Not BCA' ? <span className="text-slate-300">Not applicable — not a cyber asset. <span className="text-slate-500">The building <NodeLink id={cip.nodeId} name={cip.nodeName} /> is rated {cip.value}; that applies to the cyber assets it houses, not to this relay.</span></span>
              : <><Pill tone={cip.value === 'High' ? 'bad' : cip.value === 'Medium' ? 'warn' : 'neutral'}>{cip.value}</Pill>
                  <span className="ml-2">— {bca === 'BCA' ? 'a BES Cyber Asset in' : 'the rating of'} <NodeLink id={cip.nodeId} name={cip.nodeName} /> <span className="text-xs text-slate-500">{cip.nodeType}{cip.at ? ' · ' + fmtWhen(cip.at) : ''}{bca === 'BCA' ? '' : ' · cyber status not derived yet'}</span></span></>}
            <div className="text-xs text-slate-600">CIP-002: the building's rating, taken by the BES Cyber Assets it houses (#173, #195); whether this device is one is derived above.</div>
          </dd>
        </div>
        <div className="grid grid-cols-[13rem_1fr] items-start gap-2">
          <dt className="text-slate-400">Protected primary asset</dt>
          <dd className="min-w-0">
            {!r.SchemeEntityId ? <span className="text-slate-500">the device is in no scheme, so nothing protected is known</span>
              : protectsQ.isPending ? <span className="text-slate-500">…</span>
              : !rows.length ? <span className="text-slate-500">the scheme protects nothing that is recorded yet</span>
              : <ul className="space-y-1">{rows.map((a) => (
                  <li key={s(a.EntityId)}>
                    {link('PRIMARY_ASSET', s(a.EntityId), s(a.Name))} <span className="text-xs text-slate-500">{s(a.AssetTypeName).toLowerCase()}{a.ZoneRole !== 'Primary' ? ' · ' + s(a.ZoneRole).toLowerCase() : ''}</span>
                    <div className="ml-3 text-xs text-slate-400">
                      {inherited(a).map(([code, label, value], i) => <span key={code}>{i > 0 ? ' · ' : ''}{label}: {value ? s(value) : <span className="text-slate-500">not recorded</span>}</span>)}
                      {!inherited(a).length && <span className="text-slate-500">no applicability classification applies to a {s(a.AssetTypeName).toLowerCase()}</span>}
                    </div>
                    <div className="ml-3 text-xs text-slate-400">
                      {a.Npcc ? <span className="text-sky-300">NPCC {s(a.Npcc)} — declared on the {s(a.AssetTypeName).toLowerCase() || 'element'} (#196) · </span> : null}
                      {a.HasTerminal ? <>from terminal {s(a.TerminalNo)} · {a.TerminalStationId ? link('LOCATION', s(a.TerminalStationId), s(a.TerminalStation)) : s(a.TerminalStation)} · {a.BusName ? <>bus {s(a.BusName)} — NPCC {s(a.BusNpcc) || 'not recorded'}{a.Npcc ? ' (the element\'s declaration rules)' : ''}</> : 'no bus linked at that end'}</>
                        : <span className="text-slate-500">the protects link names no terminal end, so no bus NPCC is inherited</span>}
                    </div>
                  </li>))}</ul>}
            <div className="text-xs text-slate-600">The applicability comes from the primary asset and its bus (the owner, 2026-09-16); the device inherits it.</div>
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
      {!pos && <Status>The record names no position, so its elements in service are not known.</Status>}
      {pos && !q.isPending && !rows.length && <Status>No element is recorded in service at this position; PRC-023 cannot bind until one is.</Status>}
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
      <Status>PRC-023-6 binds “load-responsive phase protection systems as described in Attachment A” at the terminals of its circuits (4.1). The rule reads this list; an element nobody has ruled leaves the standard undetermined, never inapplicable.</Status>
    </Panel>
  )
}

/** The obligations standing against this device. compliance.vObligationSubject carries Open and Satisfied only — an
 * obligation that is NotApplicable or Superseded is history and is not in the view (its own comment says so). */
function Obligations({ r, verdicts }: { r: Row; verdicts: Row[] }) {
  const device = s(r.DeviceEntityId)
  const q = useViewAll('compliance', 'vObligationSubject', { SubjectEntityId: device }, 'RequirementNumber', !!device)
  const [open, setOpen] = useState<string | null>(null)
  const rows = q.data ?? []
  const noteFor = (key: string) => s(verdicts.find((v) => s(v.RuleKey) === key)?.EvidenceNote) || null
  return (
    <Panel title={`Obligations · ${q.isPending ? '…' : rows.length}`}>
      {q.isError && <Status bad>The obligations could not be read: {(q.error as Error).message}</Status>}
      {!q.isPending && !rows.length && <Status>No obligation stands against this device. Below: what each rule decided about it, and why.</Status>}
      {rows.length > 0 && (
        <table className="w-full text-sm">
          <thead><tr className="border-b border-slate-700 text-left text-xs uppercase tracking-wide text-slate-400">
            <th className="py-1 pr-2">Standard</th><th className="py-1 pr-2">Requirement</th><th className="py-1 pr-2">Rule</th>
            <th className="py-1 pr-2">Status</th><th className="py-1 pr-2">Period</th><th className="py-1">Facts read</th></tr></thead>
          <tbody>
            {rows.map((o) => { const id = s(o.RowId); const note = noteFor(s(o.RuleDefinitionKey))
              return (
                <tr key={id} className="border-b border-slate-800 align-top">
                  <td className="py-1 pr-2 text-slate-200">{s(o.StandardCode)}<div className="text-xs text-slate-500">{s(o.StandardVersion)}</div></td>
                  <td className="py-1 pr-2 text-slate-200">{s(o.RequirementNumber)}{o.SubRequirement ? '.' + s(o.SubRequirement) : ''}<div className="text-xs text-slate-500">{s(o.RequirementTitle)}</div></td>
                  <td className="py-1 pr-2 text-slate-200">{s(o.RuleName)}{note && <div className="text-xs text-slate-500">evidence: {note}</div>}</td>
                  <td className="py-1 pr-2"><Pill tone={statusTone(o.Status)}>{s(o.Status)}</Pill></td>
                  <td className="py-1 pr-2 text-xs text-slate-400">{fmtDate(o.PeriodStartAt)}{o.PeriodEndAt ? ' – ' + fmtDate(o.PeriodEndAt) : ' – open'}</td>
                  <td className="py-1">
                    <Button kind="mini" onClick={() => setOpen(open === id ? null : id)}>{open === id ? 'hide' : 'show'}</Button>
                    {open === id && <ObligationFacts instanceRowId={id} />}
                  </td>
                </tr>) })}
          </tbody>
        </table>)}
      <Status>Open and Satisfied only — compliance.vObligationSubject leaves a NotApplicable or Superseded obligation to the history.</Status>
    </Panel>
  )
}

function ObligationFacts({ instanceRowId }: { instanceRowId: string }) {
  const q = useViewAll('compliance', 'vObligationInstanceFact', { ObligationInstanceRowId: instanceRowId }, 'FactName')
  const rows = q.data ?? []
  if (q.isPending) return <div className="mt-1 text-xs text-slate-500">…</div>
  if (!rows.length) return <div className="mt-1 text-xs text-slate-500">No fact was recorded on this obligation.</div>
  return (
    <ul className="mt-1 space-y-0.5 text-xs">
      {rows.map((f) => <li key={s(f.ObligationInstanceFactId)}><span className="text-slate-400">{s(f.FactName)}</span> <span className="text-slate-200">{s(f.ValueAsRead)}</span></li>)}
    </ul>
  )
}

/** #214: the platform's standing verdict on every rule for this device — read from compliance.vDeviceVerdict (what the last
 * Effective pass decided, its reason and its reads; SinceAt = when that verdict began) and vDeviceEvaluation (when the
 * device was last looked at, and by which pass). The rules that bind (true) and the undetermined ones are listed first;
 * the ones that do not apply in one line each with the reason (#197), their reads opened by the engineer who wants them.
 * An error is shown: it is not a decision that the rule does not bind. Nothing here runs anything. */
function Standing({ device, verdicts, pending }: { device: string; verdicts: Row[]; pending: boolean }) {
  const evalQ = useViewAll('compliance', 'vDeviceEvaluation', { DeviceEntityId: device }, undefined, !!device)
  const ev = (evalQ.data ?? [])[0]
  const rules = verdicts.filter((v) => s(v.VerdictKind) === 'Rule')
  const binding = rules.filter((v) => s(v.Result) !== 'false')
  const notBinding = rules.filter((v) => s(v.Result) === 'false')
  const [showFalse, setShowFalse] = useState(false)
  return (
    <Panel title="Standards and this device">
      {evalQ.isPending || pending ? <Status>…</Status>
        : !ev ? <Status>Not yet evaluated — the platform evaluates a device within seconds of a change that a rule reads, and every hour. Nothing to press.</Status>
        : <Status>Evaluated {fmtWhen(ev.LastEvaluatedAt)} · {triggerWords(ev.LastTrigger)} · {s(ev.RulesEvaluated)} rule(s)</Status>}
      {ev && !rules.length && <Status>No rule was evaluated against this device.</Status>}
      {!!binding.length && <ul className="mt-2 space-y-2">{binding.map((v) => <li key={s(v.RuleKey)}><VerdictCard v={v} /></li>)}</ul>}
      {ev && !binding.length && !!rules.length && <Status>No standard binds this device, and none is undetermined.</Status>}
      {!!notBinding.length && (
        <div className="mt-2 rounded border border-slate-800 bg-slate-950 p-2 text-sm">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-slate-400">{notBinding.length} standard{notBinding.length === 1 ? '' : 's'} do{notBinding.length === 1 ? 'es' : ''} not apply to this device</span>
            <Button kind="mini" onClick={() => setShowFalse(!showFalse)}>{showFalse ? 'hide the reads' : 'show the reads'}</Button>
          </div>
          <ul className="mt-1 space-y-0.5 text-xs">
            {notBinding.map((v) => <li key={'why' + s(v.RuleKey)}><span className="text-slate-200">{ruleTitle(v)}</span> <span className="text-slate-400">— does not apply: {s(v.Reason)}</span> <span className="text-slate-600">since {fmtWhen(v.SinceAt)}</span></li>)}
          </ul>
          {showFalse && <ul className="mt-2 space-y-2">{notBinding.map((v) => <li key={s(v.RuleKey)}><VerdictCard v={v} /></li>)}</ul>}
        </div>)}
    </Panel>
  )
}

const ruleTitle = (v: Row) => (v.StandardCode ? `${s(v.StandardCode)} ${s(v.StandardVersion)} ${s(v.RequirementNumber)}`.replace(/\s+/g, ' ').trim() : s(v.RuleName))

function VerdictCard({ v }: { v: Row }) {
  const [open, setOpen] = useState(false)
  const reads = readsOf(v)
  const byName = new Map(reads.map((x) => [x.name, x]))
  const working = PRC023_READS.filter(([n]) => byName.has(n))
  const others = reads.filter((x) => !PRC023_READS.some(([n]) => n === x.name))
  const result = s(v.Result)
  return (
    <div className="rounded border border-slate-800 bg-slate-950 p-2">
      <div className="flex flex-wrap items-center gap-2">
        <Pill tone={resultTone(result)}>{result === 'true' ? 'applies' : result === 'false' ? 'does not apply' : result === 'unknown' ? 'undetermined' : 'error'}</Pill>
        <span className="text-slate-200">{s(v.RuleName)}</span>
        <span className="text-xs text-slate-500">{s(v.RuleKey)}{v.StandardCode ? ` · ${ruleTitle(v)}` : ''} · v{s(v.VersionNumber)} · since {fmtWhen(v.SinceAt)}</span>
        <Button kind="mini" onClick={() => setOpen(!open)}>{open ? 'hide the reads' : `${reads.length} read(s)`}</Button>
      </div>
      {result !== 'true' && <div className="mt-1 text-xs text-slate-400">{s(v.Reason)}</div>}
      {!!v.Error && <div className="mt-1 text-xs text-red-300">{s(v.Error)}</div>}
      {!!v.EvidenceNote && <div className="mt-1 text-xs text-slate-500">evidence: {s(v.EvidenceNote)}</div>}
      {working.length > 0 && (
        <div className="mt-1">
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-400">The loadability working</div>
          <ul className="mt-0.5 space-y-0.5 text-xs">
            {working.map(([name, label]) => <li key={name}><span className="text-slate-400">{label}</span> <span className="text-slate-100">{byName.get(name)!.value}</span></li>)}
          </ul>
          <div className="mt-0.5 text-xs text-slate-600">The steady-state self-polarised circle; the memory-polarised expansion is not modelled. 50H is treated as a tripping element without decoding its MTU/MTO mask (#171).</div>
        </div>)}
      {open && (
        <ul className="mt-1 space-y-0.5 text-xs">
          {others.length === 0 && <li className="text-slate-500">no other read</li>}
          {others.map((x, i) => <li key={x.name + i}><span className="text-slate-400">{x.name}{x.params ? ` [${x.params}]` : ''}</span> <span className="text-slate-100">{x.value}</span></li>)}
        </ul>)}
    </div>
  )
}
