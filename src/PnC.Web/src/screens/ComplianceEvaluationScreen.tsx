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

const triggerWords = (t: unknown) => ({ Scheduled: 'hourly pass', FactChanged: 'after a change', RuleApproved: 'after a rule was approved', Manual: 'by hand' } as Record<string, string>)[s(t)] ?? s(t)
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
      <Status>A device's Compliance tab reads the platform's standing verdict (the last Effective pass over it, its reason and its reads) and shows when it was made. Writes made in SQL directly, and rulings in the fact catalogue itself, leave no request — the hourly pass covers those.</Status>
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
      setMsg({ text: `Done: ${r.rules} rule(s) over ${r.subjects} subject(s) — ${r.opened} opened, ${r.closed} closed, ${r.unchanged} unchanged, ${r.unknown} unknown, ${r.errors} error(s).${r.ruleErrors.length ? ' Rules that could not be evaluated: ' + r.ruleErrors.join('; ') : ''}` })
      qc.invalidateQueries({ queryKey: ['view', 'compliance'] })
    } catch (e) { setMsg({ text: e instanceof ApiError ? `${e.status} ${e.message}` : String(e), bad: true }) } finally { setBusy(false) }
  }
  return (
    <Panel title="Run the pass now" actions={<Button kind="primary" disabled={busy || !can('Obligation.Modify')} title={can('Obligation.Modify') ? 'every effective rule over every candidate device, as the hourly pass does' : 'needs Obligation.Modify'} onClick={() => void run()}>{busy ? 'Running…' : 'Run the pass now'}</Button>}>
      <Status>The platform evaluates on its own: within seconds of a change a rule reads, and every hour. Run it by hand only after a rule changed in a way the queue did not see.</Status>
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
    <Panel title={`Requests · ${q.isPending ? '…' : `${pending} pending`}`}>
      {q.isError && <Status bad>The requests could not be read: {(q.error as Error).message}</Status>}
      {!q.isPending && !rows.length && <Status>No request yet — none of the facts the rules read has changed through the platform since this was built.</Status>}
      {rows.length > 0 && (
        <table className="w-full text-sm">
          <thead><tr className="border-b border-slate-700 text-left text-xs uppercase tracking-wide text-slate-400">
            <th className="py-1 pr-2">Requested</th><th className="py-1 pr-2">About</th><th className="py-1 pr-2">Changed by</th><th className="py-1 pr-2">Who</th><th className="py-1">Answered</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={s(r.RequestId)} className="border-b border-slate-800 align-top">
                <td className="py-1 pr-2 text-xs text-slate-400">{fmtWhen(r.RequestedAt)}</td>
                <td className="py-1 pr-2 text-slate-200">{s(r.SubjectName) || s(r.SubjectEntityId)} <span className="text-xs text-slate-500">{s(r.SubjectKind).toLowerCase()}</span></td>
                <td className="py-1 pr-2 text-xs text-slate-300">{s(r.Reason)}</td>
                <td className="py-1 pr-2 text-xs text-slate-400">{s(r.RequestedByName)}</td>
                <td className="py-1 text-xs">
                  {r.IsPending === true ? <Pill tone="warn">pending</Pill>
                    : <><Pill tone="good">served</Pill> <span className="text-slate-400">{fmtWhen(r.ProcessedAt)} · {s(r.DevicesFound)} device(s){r.RunTrigger ? ` · ${triggerWords(r.RunTrigger)}` : ''}{r.InstancesOpened != null ? ` · ${s(r.InstancesOpened)} opened, ${s(r.InstancesClosed)} closed` : ''}</span></>}
                </td>
              </tr>))}
          </tbody>
        </table>)}
      <Status>The last 100. A request names what changed and the procedure that changed it; the worker groups everything pending into one pass.</Status>
    </Panel>
  )
}

function Passes() {
  const q = useQuery({ queryKey: ['view', 'compliance', 'vRuleEvaluationRun', 'last30'], queryFn: async () => (await view('compliance', 'vRuleEvaluationRun', { Mode: 'Effective' }, { orderBy: '-StartedAt', take: 30 })).rows, refetchInterval: 5000 })
  const rows = q.data ?? []
  return (
    <Panel title="Passes">
      {q.isError && <Status bad>The passes could not be read: {(q.error as Error).message}</Status>}
      {rows.length > 0 && (
        <table className="w-full text-sm">
          <thead><tr className="border-b border-slate-700 text-left text-xs uppercase tracking-wide text-slate-400">
            <th className="py-1 pr-2">Started</th><th className="py-1 pr-2">Trigger</th><th className="py-1 pr-2">Took</th><th className="py-1 pr-2">Subjects</th><th className="py-1 pr-2">Opened · closed · unchanged</th><th className="py-1">Notes</th></tr></thead>
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
      <Status>The last 30 Effective passes. "Subjects" counts rule × subject evaluations; a rule a pass could not evaluate is named in its notes, and it is the rule that is wrong, not any device.</Status>
    </Panel>
  )
}
