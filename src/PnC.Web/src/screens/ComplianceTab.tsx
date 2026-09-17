// #171 (2026-09-16): the Compliance tab of a settings record — what this device is, what it inherits from the station and
// from the primary asset its scheme protects, the obligations standing against it, and the evaluator's own working.
// Plain React (the #167 rule). Nothing here decides an obligation: the rules and the formulas are definitions and the
// evaluator (POST /api/v1/compliance/evaluate) is the only thing that reads them — this screen shows what it read.
import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ApiError, fmtDate, fmtWhen, postJson, s, view, viewAll, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Status, type Tone } from '@/components/ui/ui'
import { ClassificationPanel, DEVICE_KINDS } from './PrimaryAssetScreen'

/** The evaluator's report (src/PnC.Api/Engine/ComplianceEvaluator.cs, serialised camelCase). */
export interface FactRead { name: string; params: string | null; value: string }
export interface Verdict {
  ruleKey: string; ruleName: string; ruleVersionRowId: string; requirementEntityId: string | null
  subjectKind: string; subjectEntityId: string; subjectName: string
  result: 'true' | 'false' | 'unknown' | 'error'; error: string | null; unknowns: string[]; reads: FactRead[]
  instanceRowId: string | null; action: 'open' | 'close' | 'unchanged' | 'none'; evidenceNote: string | null
  requirementNumber: string | null; standardCode: string | null; standardVersion: string | null
}
export interface EvaluationReport {
  at: string; mode: string; rules: number; subjects: number; opened: number; closed: number; unchanged: number
  unknown: number; errors: number; verdicts: Verdict[]; ruleErrors: string[]; runId: string
}

/** The PRC-023 loadability working, in the order the calculation goes (the Program.Formula seeds of #171). */
const PRC023_READS: [string, string][] = [
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
        BusName: term?.BusName, BusNpcc: term?.BusNpcc, HasTerminal: !!term, BesStatus: valueOf('BesStatus'), Prc023: valueOf('Prc023') })
    }
    return out
  } })
}

/** The station's CIP-002 impact rating (recorded on the station node, #171 — every BES Cyber Asset at it inherits it). */
export function useStationCip(stationEntityId: string) {
  return useViewAll('asset', 'vClassification', { SubjectKind: 'Node', SubjectEntityId: stationEntityId, ClassificationKindCode: 'CipImpactRating' }, undefined, !!stationEntityId)
}

export default function ComplianceTab({ r }: { r: Row }) {
  const can = useCan()
  const device = s(r.DeviceEntityId)
  const [report, setReport] = useState<EvaluationReport | null>(null)
  return (
    <div className="space-y-3">
      <div className="grid gap-3 lg:grid-cols-2">
        <ClassificationPanel title="This device" subjectKind="Asset" subjectEntityId={device} editable={can('Asset.Modify')} kinds={DEVICE_KINDS}
          note="Recorded on the device itself: whether it is a BES Cyber Asset and whether it has external routable connectivity. The CIP-002 procedure derives these in a later phase; the impact rating is the station's, beside it." />
        <Inherited r={r} />
      </div>
      <Obligations r={r} report={report} />
      <Evaluate device={device} report={report} setReport={setReport} />
    </div>
  )
}

/** What the device inherits: the station's CIP impact rating, and the protected primary asset's BES / PRC-023 and the bus's NPCC. */
function Inherited({ r }: { r: Row }) {
  const navigate = useNavigate()
  const stationId = s(r.StationNodeEntityId)
  const cipQ = useStationCip(stationId)
  const protectsQ = useProtectedAssets(s(r.SchemeEntityId))
  const cip = cipQ.data?.[0]
  const link = (screen: string, id: string, label: string) => (
    <a className="text-sky-300 underline" href={screenPath(screen, id)} onClick={(e) => { e.preventDefault(); navigate(screenPath(screen, id)) }}>{label}</a>)
  const rows = protectsQ.data ?? []
  return (
    <Panel title="Inherited">
      <dl className="space-y-2 text-sm">
        <div className="grid grid-cols-[13rem_1fr] items-start gap-2">
          <dt className="text-slate-400">Station CIP impact rating</dt>
          <dd className="min-w-0">
            {stationId ? <>{cipQ.isPending ? <span className="text-slate-500">…</span> : cip ? <Pill tone={s(cip.ClassificationValue) === 'High' ? 'bad' : s(cip.ClassificationValue) === 'Medium' ? 'warn' : 'neutral'}>{s(cip.ClassificationValue)}</Pill> : <span className="text-slate-500">not recorded</span>}
              <span className="ml-2">{link('STATION', stationId, s(r.StationName) || 'the station')}</span></>
              : <span className="text-slate-500">no station for this device</span>}
            <div className="text-xs text-slate-600">CIP-002: recorded on the station; every BES Cyber Asset at it inherits it.</div>
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
                      BES status: {a.BesStatus ? s(a.BesStatus) : <span className="text-slate-500">not recorded</span>} · PRC-023: {a.Prc023 ? s(a.Prc023) : <span className="text-slate-500">not recorded</span>}
                    </div>
                    <div className="ml-3 text-xs text-slate-400">
                      {a.HasTerminal ? <>from terminal {s(a.TerminalNo)} · {a.TerminalStationId ? link('STATION', s(a.TerminalStationId), s(a.TerminalStation)) : s(a.TerminalStation)} · {a.BusName ? <>bus {s(a.BusName)} — NPCC {s(a.BusNpcc) || 'not recorded'}</> : 'no bus linked at that end'}</>
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

/** The obligations standing against this device. compliance.vObligationSubject carries Open and Satisfied only — an
 * obligation that is NotApplicable or Superseded is history and is not in the view (its own comment says so). */
function Obligations({ r, report }: { r: Row; report: EvaluationReport | null }) {
  const device = s(r.DeviceEntityId)
  const q = useViewAll('compliance', 'vObligationSubject', { SubjectEntityId: device }, 'RequirementNumber', !!device)
  const [open, setOpen] = useState<string | null>(null)
  const rows = q.data ?? []
  const noteFor = (key: string) => report?.verdicts.find((v) => v.ruleKey === key)?.evidenceNote ?? null
  return (
    <Panel title={`Obligations · ${q.isPending ? '…' : rows.length}`}>
      {q.isError && <Status bad>The obligations could not be read: {(q.error as Error).message}</Status>}
      {!q.isPending && !rows.length && <Status>No obligation stands against this device. Evaluate now (below) shows what the rules decide and why.</Status>}
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

/** Evaluate now: a Preview writes nothing and returns the verdicts with everything the rules read; Commit runs the same
 * pass as Effective, which opens and closes the obligation instances and records the facts read. */
function Evaluate({ device, report, setReport }: { device: string; report: EvaluationReport | null; setReport: (r: EvaluationReport | null) => void }) {
  const qc = useQueryClient(); const can = useCan()
  const [busy, setBusy] = useState(''); const [err, setErr] = useState<string | null>(null)
  const run = async (mode: 'Preview' | 'Effective') => {
    setBusy(mode); setErr(null)
    try {
      const rep = await postJson<EvaluationReport>('/api/v1/compliance/evaluate', { subjectKind: 'Device', subjectEntityId: device, mode })
      setReport(rep)
      if (mode === 'Effective') { qc.invalidateQueries({ queryKey: ['view', 'compliance', 'vObligationSubject'] }); qc.invalidateQueries({ queryKey: ['view', 'compliance', 'vObligationInstanceFact'] }) }
    } catch (e) { setErr(e instanceof ApiError ? `${e.status} ${e.message}` : String(e)) } finally { setBusy('') }
  }
  return (
    <Panel title="Evaluate now" actions={
      <div className="flex gap-2">
        <Button kind="primary" disabled={!device || !!busy} onClick={() => void run('Preview')}>{busy === 'Preview' ? 'Evaluating…' : 'Evaluate now'}</Button>
        <Button disabled={!device || !!busy || !report} title={can('Obligation.Modify') ? 'open and close the obligations this preview decided' : 'the API refuses this without Obligation.Modify'} onClick={() => void run('Effective')}>{busy === 'Effective' ? 'Committing…' : 'Commit'}</Button>
      </div>}>
      {err && <Status bad>{err}</Status>}
      {!report && !err && <Status>A preview evaluates every effective rule against this device and writes nothing. Commit runs the same pass for real (Obligation.Modify).</Status>}
      {report && (
        <div className="space-y-2 text-sm">
          <Status>{report.mode} · {fmtWhen(report.at)} · {report.rules} rule(s) over {report.subjects} subject(s) — {report.opened} opened, {report.closed} closed, {report.unchanged} unchanged, {report.unknown} unknown, {report.errors} error(s). Run {s(report.runId).slice(0, 8)}.</Status>
          {report.ruleErrors.length > 0 && <div className="rounded border border-red-800 bg-red-900/30 p-2 text-xs text-red-200"><div className="font-semibold">Rules that could not be evaluated</div><ul className="mt-1 space-y-0.5">{report.ruleErrors.map((e, i) => <li key={i}>{e}</li>)}</ul></div>}
          {!report.verdicts.length && <Status>No rule applies to this device.</Status>}
          <ul className="space-y-2">{report.verdicts.map((v, i) => <li key={v.ruleKey + i}><VerdictCard v={v} /></li>)}</ul>
        </div>)}
    </Panel>
  )
}

function VerdictCard({ v }: { v: Verdict }) {
  const [open, setOpen] = useState(false)
  const reads = v.reads ?? []
  const byName = new Map(reads.map((x) => [x.name, x]))
  const working = PRC023_READS.filter(([n]) => byName.has(n))
  const others = reads.filter((x) => !PRC023_READS.some(([n]) => n === x.name))
  return (
    <div className="rounded border border-slate-800 bg-slate-950 p-2">
      <div className="flex flex-wrap items-center gap-2">
        <Pill tone={resultTone(v.result)}>{v.result}</Pill>
        <span className="text-slate-200">{v.ruleName}</span>
        <span className="text-xs text-slate-500">{v.ruleKey}{v.standardCode ? ` · ${v.standardCode} ${v.standardVersion ?? ''} ${v.requirementNumber ?? ''}` : ''} · {v.action}</span>
        <Button kind="mini" onClick={() => setOpen(!open)}>{open ? 'hide the reads' : `${reads.length} read(s)`}</Button>
      </div>
      {v.error && <div className="mt-1 text-xs text-red-300">{v.error}</div>}
      {(v.unknowns ?? []).length > 0 && <div className="mt-1 text-xs text-amber-300">unknown: {v.unknowns.join(', ')}</div>}
      {v.evidenceNote && <div className="mt-1 text-xs text-slate-500">evidence: {v.evidenceNote}</div>}
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
