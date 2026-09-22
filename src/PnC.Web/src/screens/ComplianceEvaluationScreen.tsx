// #214 (2026-09-20): how the platform keeps compliance evaluated — the Compliance area's Evaluation screen. The owner, on a
// device's "Evaluate now" button: "Should the evaluation be an automatic function of what is presently known about the
// system?" It is. A write that changes a fact the rules read leaves a request (compliance.EvaluationRequest); the worker
// takes the pending requests within seconds and runs one Effective pass over the devices affected; the hourly pass is the
// catch-all. This screen shows the requests (what changed, who, served by which pass), the passes (trigger, duration, what
// they opened and closed, the rules they could not evaluate) and the one hand-run, for after a rule changes. Plain React
// (#167); the COMPLIANCE_EVALUATION definition names compliance.vEvaluationQueue and pages/Screen.tsx dispatches it here.
import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ApiError, fmtWhen, postJson, s, view } from '@/lib/api'
import { useCan } from '@/lib/hooks'
import { type Screen } from '@/lib/screens'
import { Panel, Pill, Button, Status } from '@/components/ui/ui'

const triggerWords = (t: unknown) => ({ Scheduled: 'the hourly check', FactChanged: 'after a change', RuleApproved: 'after a rule changed', Manual: 'by hand' } as Record<string, string>)[s(t)] ?? s(t)
const seconds = (a: unknown, b: unknown) => (a && b ? `${Math.max(0, Math.round((new Date(s(b)).getTime() - new Date(s(a)).getTime()) / 1000))} s` : '—')

export default function ComplianceEvaluationScreen({ screen }: { screen: Screen }) {
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-lg font-semibold text-slate-100">{screen.name}</h1>
      </header>
      <RunNow />
      <Requests />
      <Passes />
      <Status>A relay's Compliance tab shows the last check on it: what was decided, why, and when. A change made outside the application is picked up by the hourly check.</Status>
    </div>
  )
}

/** The one hand-run: every effective rule over every candidate, now (Obligation.Modify) — for after a rule, formula or
 * derivation changed in a way that left no request (the approval of one does leave a request). */
function RunNow() {
  const can = useCan(); const qc = useQueryClient()
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const run = async () => {
    setBusy(true); setMsg(null)
    try {
      const r = await postJson<{ rules: number; subjects: number; opened: number; closed: number; unchanged: number; unknown: number; errors: number; ruleErrors: string[]; runId: string }>('/api/v1/compliance/evaluate', { mode: 'Effective' })
      setMsg({ text: `Done: ${r.rules} rule(s) over ${r.subjects} device(s) — ${r.opened} opened, ${r.closed} closed, ${r.unchanged} unchanged, ${r.unknown} undecided, ${r.errors} error(s).${r.ruleErrors.length ? ' Rules that could not be checked: ' + r.ruleErrors.join('; ') : ''}` })
      qc.invalidateQueries({ queryKey: ['view', 'compliance'] })
    } catch (e) { setMsg({ text: e instanceof ApiError ? `${e.status} ${e.message}` : String(e), bad: true }) } finally { setBusy(false) }
  }
  return (
    <Panel title="Check everything now" actions={<Button kind="primary" disabled={busy || !can('Obligation.Modify')} title={can('Obligation.Modify') ? 'Checks every rule against every device, as the hourly check does' : 'You may not run the compliance check.'} onClick={() => void run()}>{busy ? 'Checking…' : 'Check everything now'}</Button>}>
      <Status>Compliance is checked on its own: within seconds of a change, and every hour. Run it by hand only after a rule changed outside the application.</Status>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </Panel>
  )
}

function Requests() {
  // the last 100 only: the queue is append-only and grows with every write the rules read
  const q = useQuery({ queryKey: ['view', 'compliance', 'vEvaluationQueue', 'last100'], queryFn: async () => (await view('compliance', 'vEvaluationQueue', {}, { orderBy: '-RequestedAt', take: 100 })).rows, refetchInterval: 5000 })
  const rows = q.data ?? []
  const pending = rows.filter((r) => r.IsPending === true).length
  return (
    <Panel title={`Changes to check · ${q.isPending ? '…' : `${pending} waiting`}`}>
      {q.isError && <Status bad>This list could not be read: {(q.error as Error).message}</Status>}
      {!q.isPending && !rows.length && <Status>Nothing is waiting. No change that a compliance rule reads has been made here yet.</Status>}
      {rows.length > 0 && (
        <table className="w-full text-sm">
          <thead><tr className="border-b border-slate-700 text-left text-xs uppercase tracking-wide text-slate-400">
            <th className="py-1 pr-2">Noticed</th><th className="py-1 pr-2">Relay or asset</th><th className="py-1 pr-2">What changed</th><th className="py-1 pr-2">Who</th><th className="py-1">Checked</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={s(r.RequestId)} className="border-b border-slate-800 align-top">
                <td className="py-1 pr-2 text-xs text-slate-400">{fmtWhen(r.RequestedAt)}</td>
                <td className="py-1 pr-2 text-slate-200">{s(r.SubjectName) || s(r.SubjectEntityId)} <span className="text-xs text-slate-500">{s(r.SubjectKind).toLowerCase()}</span></td>
                <td className="py-1 pr-2 text-xs text-slate-300">{s(r.Reason)}</td>
                <td className="py-1 pr-2 text-xs text-slate-400">{s(r.RequestedByName)}</td>
                <td className="py-1 text-xs">
                  {r.IsPending === true ? <Pill tone="warn">waiting</Pill>
                    : <><Pill tone="good">checked</Pill> <span className="text-slate-400">{fmtWhen(r.ProcessedAt)} · {s(r.DevicesFound)} device(s){r.RunTrigger ? ` · ${triggerWords(r.RunTrigger)}` : ''}{r.InstancesOpened != null ? ` · ${s(r.InstancesOpened)} opened, ${s(r.InstancesClosed)} closed` : ''}</span></>}
                </td>
              </tr>))}
          </tbody>
        </table>)}
      <Status>The last 100 changes. Each one names what changed and who changed it. Everything waiting is checked together, within seconds.</Status>
    </Panel>
  )
}

function Passes() {
  const q = useQuery({ queryKey: ['view', 'compliance', 'vRuleEvaluationRun', 'last30'], queryFn: async () => (await view('compliance', 'vRuleEvaluationRun', { Mode: 'Effective' }, { orderBy: '-StartedAt', take: 30 })).rows, refetchInterval: 5000 })
  const rows = q.data ?? []
  return (
    <Panel title="Checks run">
      {q.isError && <Status bad>This list could not be read: {(q.error as Error).message}</Status>}
      {rows.length > 0 && (
        <table className="w-full text-sm">
          <thead><tr className="border-b border-slate-700 text-left text-xs uppercase tracking-wide text-slate-400">
            <th className="py-1 pr-2">Started</th><th className="py-1 pr-2">Why</th><th className="py-1 pr-2">Took</th><th className="py-1 pr-2">Checks</th><th className="py-1 pr-2">Opened · closed · unchanged</th><th className="py-1">Notes</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={s(r.RunId)} className="border-b border-slate-800 align-top">
                <td className="py-1 pr-2 text-xs text-slate-400">{fmtWhen(r.StartedAt)}</td>
                <td className="py-1 pr-2 text-slate-200">{triggerWords(r.Trigger)}</td>
                <td className="py-1 pr-2 text-xs text-slate-400">{r.CompletedAt ? seconds(r.StartedAt, r.CompletedAt) : <Pill tone="warn">running</Pill>}</td>
                <td className="py-1 pr-2 text-xs text-slate-300">{s(r.SubjectsScoped)}</td>
                <td className="py-1 pr-2 text-xs text-slate-300">{s(r.InstancesOpened)} · {s(r.InstancesClosed)} · {s(r.InstancesUnchanged)}</td>
                <td className="py-1 text-xs text-slate-400">{r.Notes ? <span className={/could not be evaluated/.test(s(r.Notes)) ? 'text-amber-300' : ''}>{s(r.Notes)}</span> : '—'}</td>
              </tr>))}
          </tbody>
        </table>)}
      <Status>The last 30 checks. "Checks" counts one rule against one device. A rule that could not be checked is named in the notes; the rule is wrong, not the device.</Status>
    </Panel>
  )
}
