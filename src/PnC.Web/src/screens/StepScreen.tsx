// Screen kind "step" (#165): one step of any procedure, drawn from its definition — instruction, the capture fields by
// type, the evidence the step requires, its outcomes, its sign-off — and the acts a person performs on it: claim,
// release, take over, witness (a second person, from their own session), save the draft (the direct save with audit),
// commit, or check in a field capture. The engine decides everything; the API refuses in its own words.
import { useEffect, useMemo, useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ApiError, fmtWhen, s, type Row } from '@/lib/api'
import { useCan, useMe, useViewAll } from '@/lib/hooks'
import { type StepParams, type Screen, splitView, screenPath } from '@/lib/screens'
import { stepInstance, stepCall, fileToEvidence, type CaptureSpec, type Evidence, type CommitResult } from '@/lib/process'
import { Panel, Pill, stateTone, Button, Facts, Status, Field, inputClass } from '@/components/ui/ui'

type Values = Record<string, unknown>

export default function StepScreen({ params: p, id }: { screen: Screen; params: StepParams; id?: string }) {
  const qc = useQueryClient(); const can = useCan(); const meQ = useMe(); const navigate = useNavigate()
  const q = useQuery({ queryKey: ['stepInstance', id], queryFn: () => stepInstance(id!), enabled: !!id, staleTime: 5_000 })
  const st = q.data; const def = st?.definition
  const [values, setValues] = useState<Values>({}); const [loadedFor, setLoadedFor] = useState<string | null>(null)
  const [files, setFiles] = useState<Record<string, File[]>>({}); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const [busy, setBusy] = useState(false); const [result, setResult] = useState<CommitResult | null>(null)
  const [takeoverReason, setTakeoverReason] = useState(''); const [field, setField] = useState(false)
  const [capturedBy, setCapturedBy] = useState(''); const [capturedAt, setCapturedAt] = useState(() => new Date(Date.now() - new Date().getTimezoneOffset() * 60_000).toISOString().slice(0, 16))
  const saveTimer = useRef<number | null>(null); const [saved, setSaved] = useState<string | null>(null)
  useEffect(() => { if (st && loadedFor !== st.stepInstanceEntityId + (st.draftModifiedAt ?? '')) { setValues(st.draft ?? {}); setLoadedFor(st.stepInstanceEntityId + (st.draftModifiedAt ?? '')) } }, [st, loadedFor])
  const reload = () => qc.invalidateQueries({ queryKey: ['stepInstance', id] })
  const editable = !!st && st.state === 'Active' && st.isClaimant
  const canAct = can('Record.Modify')

  // the draft: saved on a pause in typing while the person holds the claim (SaveDraft renews the lease)
  const change = (k: string, v: unknown) => {
    const next = { ...values, [k]: v }; setValues(next)
    if (!editable || !st) return
    if (saveTimer.current) window.clearTimeout(saveTimer.current)
    saveTimer.current = window.setTimeout(async () => { try { await stepCall.draft(st.stepInstanceEntityId, next); setSaved(new Date().toLocaleTimeString()) } catch (e) { setMsg({ text: 'Draft not saved: ' + (e as Error).message, bad: true }) } }, 800)
  }
  const act = async (what: string, fn: () => Promise<unknown>) => {
    setBusy(true); setMsg(null)
    try { await fn(); setMsg({ text: `${what} — done.` }); reload() } catch (e) { setMsg({ text: `${what} refused: ${e instanceof ApiError ? e.status + ' ' : ''}${(e as Error).message}`, bad: true }) }
    setBusy(false)
  }
  const commit = async (outcome: string) => {
    if (!st) return
    setBusy(true); setMsg(null)
    try {
      const evidence: Evidence[] = []
      for (const [kind, list] of Object.entries(files)) for (const f of list) evidence.push(await fileToEvidence(f, kind))
      const capture = normalise(values, def?.capture ?? {})
      const r = field
        ? await stepCall.checkin(st.stepInstanceEntityId, { outcome, capture, evidence, capturedBy: capturedBy.trim(), capturedAt: new Date(capturedAt).toISOString() })
        : await stepCall.commit(st.stepInstanceEntityId, { outcome, capture, evidence })
      setResult(r); setMsg({ text: `Committed as ${r.outcome}${r.advanced ? ' · ' + r.advanced : ''}${r.branchOutcome ? ' · branch ' + r.branchOutcome : ''}${r.instance.completed ? ' · the procedure is complete' : ''}.` }); reload()
    } catch (e) { setMsg({ text: `Commit refused: ${e instanceof ApiError ? e.status + ' ' : ''}${(e as Error).message}`, bad: true }) }
    setBusy(false)
  }

  if (!id) return <Status bad>No step id in the address.</Status>
  if (q.isPending) return <Status>Loading the step…</Status>
  if (q.isError) return <Status bad>Could not load: {(q.error as Error).message}</Status>
  if (!st || !def) return <Status bad>No step with that id is readable by you.</Status>
  const evidenceKinds = def.evidence?.kinds ?? []
  const outcomes = def.outcomes?.length ? def.outcomes : ['Done']
  const back = st.workRequestEntityId ? screenPath('WORK_ITEM', st.workRequestEntityId) : null
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-lg font-semibold text-slate-100">{def.title}</h1>
          <p className="text-xs text-slate-400">{st.procedureKey} · {st.blockPath}{st.memberSubjectEntityId ? ` · ${st.memberSubjectKind} ${st.memberSubjectEntityId}` : ''}{back && <> · <a className="text-sky-300 underline" href="#" onClick={(e) => { e.preventDefault(); navigate(back) }}>the work item</a></>}</p>
        </div>
        <Pill tone={stateTone(st.state === 'Committed' ? 'Complete' : st.state === 'Ready' || st.state === 'Active' ? 'InProgress' : st.state)}>{st.state}{st.outcome ? ' · ' + st.outcome : ''}</Pill>
      </header>
      {def.instruction && <p className="rounded border border-slate-800 bg-slate-900 p-3 text-sm text-slate-200">{def.instruction}</p>}
      <Facts cols={3} pairs={[['Role', `${def.roleCode ?? def.role}${st.assignedRoleCode && st.assignedRoleCode !== def.roleCode ? ' (' + st.assignedRoleCode + ')' : ''}`],
        ['Claimed', st.claimedByDisplayName ? `${st.claimedByDisplayName}${st.isClaimant ? ' (you)' : ''} until ${fmtWhen(st.claimExpiresAt)}` : '—'],
        ['Sign-off', def.signoff ? `${def.signoff.action ?? ''}${def.signoff.witness ? ' · witnessed' : ''}` : '—'],
        ['Witness', st.witnessedByDisplayName ?? (def.signoff?.witness ? 'not yet' : '—')], ['Record', def.record?.kind ?? '—'], ['Advances', def.advances ? `${def.advances.workflow} · ${def.advances.transition}` : '—'],
        ['Due', st.dueAt ? fmtWhen(st.dueAt) : '—'], ['Committed', st.committedAt ? fmtWhen(st.committedAt) : '—'], ['Held', st.heldReason ?? '—']]} />
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      {result?.recordEntityId && <Status>Record {result.recordEntityId}{result.producedEntityId ? ` · produced ${result.producedEntityId}` : ''}</Status>}

      {st.state !== 'Committed' && st.state !== 'Skipped' && (
        <div className="no-print flex flex-wrap items-end gap-2">
          {st.state === 'Ready' && <Button kind="primary" disabled={busy || !canAct} onClick={() => act('Claim', () => stepCall.claim(st.stepInstanceEntityId))}>Claim</Button>}
          {st.state === 'Active' && st.isClaimant && <Button disabled={busy} onClick={() => act('Release', () => stepCall.release(st.stepInstanceEntityId))}>Release</Button>}
          {st.state === 'Active' && !st.isClaimant && canAct && (
            <><Field label="Take over — the reason"><input className={inputClass} value={takeoverReason} onChange={(e) => setTakeoverReason(e.target.value)} /></Field>
              <Button disabled={busy || !takeoverReason.trim()} onClick={() => act('Take over', () => stepCall.takeover(st.stepInstanceEntityId, takeoverReason.trim()))}>Take over</Button></>
          )}
          {st.state === 'Active' && def.signoff?.witness && !st.isClaimant && canAct && <Button disabled={busy} title="A second person, from their own session, attests to this step" onClick={() => act('Witness', () => stepCall.witness(st.stepInstanceEntityId))}>Witness</Button>}
        </div>
      )}

      {def.capture && Object.keys(def.capture).length > 0 && (
        <Panel title="Capture" actions={saved && <span className="text-xs text-slate-500">draft saved {saved}</span>}>
          <div className="grid gap-3 md:grid-cols-2">
            {Object.entries(def.capture).map(([k, spec]) => <CaptureField key={k} name={k} spec={spec} value={values[k]} onChange={(v) => change(k, v)} disabled={!editable} help={p.help?.[k]} refView={spec.refKind ? p.refViews?.[spec.refKind] : undefined} subject={st.subjectEntityId} />)}
          </div>
          {!editable && st.state !== 'Committed' && <Status>Claim the step to fill it in.</Status>}
        </Panel>
      )}
      {def.evidence && st.state !== 'Committed' && (
        <Panel title={`Evidence${def.evidence.required ? ' (required' + (def.evidence.min ? `, at least ${def.evidence.min}` : '') + ')' : ''}`}>
          <div className="grid gap-3 md:grid-cols-2">
            {(evidenceKinds.length ? evidenceKinds : ['Attachment']).map((kind) => (
              <Field key={kind} label={kind}><input type="file" multiple disabled={!editable} className="text-sm text-slate-300" onChange={(e) => setFiles({ ...files, [kind]: Array.from(e.target.files ?? []) })} /></Field>
            ))}
          </div>
          <Status>Files travel with the commit; the first file of a settings or readback step is the configuration file itself.</Status>
        </Panel>
      )}
      {editable && (
        <Panel title="Commit">
          <label className="mb-2 flex items-center gap-2 text-sm text-slate-300"><input type="checkbox" checked={field} onChange={(e) => { setField(e.target.checked); if (e.target.checked && !capturedBy) setCapturedBy(meQ.data?.user.userPrincipalName ?? '') }} />Captured in the field by someone else, checked in now (the act is theirs; the acceptance is yours)</label>
          {field && <div className="mb-2 flex flex-wrap items-end gap-2"><Field label="Captured by (account)"><input className={inputClass} value={capturedBy} onChange={(e) => setCapturedBy(e.target.value)} /></Field><Field label="Captured at"><input type="datetime-local" className={inputClass} value={capturedAt} onChange={(e) => setCapturedAt(e.target.value)} /></Field></div>}
          <div className="flex flex-wrap gap-2">{outcomes.map((o) => <Button key={o} kind="primary" disabled={busy || (field && !capturedBy.trim())} onClick={() => commit(o)}>{outcomes.length === 1 && o === 'Done' ? (field ? 'Check in' : 'Commit') : `${field ? 'Check in' : 'Commit'} as ${o}`}</Button>)}</div>
          {def.signoff?.witness && <Status>This step is witnessed: a second person must press Witness from their own session before the commit, within fifteen minutes.</Status>}
        </Panel>
      )}
      {st.state === 'Committed' && st.draft && Object.keys(st.draft).length > 0 && <Panel title="As committed"><Facts cols={2} pairs={Object.entries(st.draft).map(([k, v]) => [k, Array.isArray(v) ? v.join(', ') : s(v)])} /></Panel>}
    </div>
  )
}

/** Values as the commit sends them: numbers as numbers, dates as instants, sets as arrays, blanks left out. */
function normalise(values: Values, spec: Record<string, CaptureSpec>): Values {
  const out: Values = {}
  for (const [k, v] of Object.entries(values)) {
    const t = spec[k]?.type
    if (v === '' || v == null) continue
    if (t === 'num') { const n = Number(v); if (!Number.isNaN(n)) out[k] = n }
    else if (t === 'date') out[k] = new Date(String(v)).toISOString()
    else if (t === 'set') out[k] = Array.isArray(v) ? v : String(v).split(/[\n,]/).map((x) => x.trim()).filter(Boolean)
    else if (t === 'bool') out[k] = !!v
    else out[k] = v
  }
  return out
}

function CaptureField({ name, spec, value, onChange, disabled, help, refView, subject }: { name: string; spec: CaptureSpec; value: unknown; onChange: (v: unknown) => void; disabled: boolean; help?: string; refView?: { view: string; label: string; filters?: Record<string, string> }; subject: string }) {
  const label = <>{name}{spec.required && <span className="text-amber-300"> *</span>}{spec.unit && <span className="ml-1 text-slate-500">({spec.unit}{spec.base ? ', ' + spec.base : ''})</span>}</>
  const [schema, view] = refView ? splitView(refView.view) : ['', '']
  const filters = useMemo(() => Object.fromEntries(Object.entries(refView?.filters ?? {}).map(([k, v]) => [k, v === '{subject}' ? subject : v])), [refView, subject])
  const optsQ = useViewAll(schema, view, filters, refView?.label, !!refView && (spec.type === 'ref' || spec.type === 'set'))
  const [pick, setPick] = useState('')
  const all = (optsQ.data ?? []) as Row[]
  // a long pick list (every asset, every scheme) narrows by text; what is already chosen always stays listed
  const chosenIds = new Set((Array.isArray(value) ? (value as string[]) : value ? [String(value)] : []).map((x) => x.toLowerCase()))
  const opts = pick.trim() ? all.filter((r) => chosenIds.has(s(r.EntityId).toLowerCase()) || s(r[refView?.label ?? 'Name']).toLowerCase().includes(pick.trim().toLowerCase())) : all
  const finder = refView && all.length > 30 ? <input className={`${inputClass} mb-1 w-full`} placeholder={`find among ${all.length}…`} value={pick} onChange={(e) => setPick(e.target.value)} disabled={disabled} /> : null
  const body = (() => {
    switch (spec.type) {
      case 'bool': return <input type="checkbox" checked={!!value} disabled={disabled} onChange={(e) => onChange(e.target.checked)} />
      case 'num': return <input type="number" step="any" className={inputClass} value={s(value)} disabled={disabled} onChange={(e) => onChange(e.target.value)} />
      case 'date': return <input type="datetime-local" className={inputClass} value={toLocal(value)} disabled={disabled} onChange={(e) => onChange(e.target.value)} />
      case 'text': return spec.allowed?.length
        ? <select className={inputClass} value={s(value)} disabled={disabled} onChange={(e) => onChange(e.target.value)}><option value="">—</option>{spec.allowed.map((a) => <option key={a} value={a}>{a}</option>)}</select>
        : <textarea className={`${inputClass} min-h-16`} value={s(value)} disabled={disabled} onChange={(e) => onChange(e.target.value)} />
      case 'ref': return refView
        ? <>{finder}<select className={inputClass} value={s(value)} disabled={disabled} onChange={(e) => onChange(e.target.value)}><option value="">—</option>{opts.map((r) => <option key={s(r.EntityId)} value={s(r.EntityId)}>{s(r[refView.label])}</option>)}</select></>
        : <input className={inputClass} placeholder={`${spec.refKind ?? 'entity'} id`} value={s(value)} disabled={disabled} onChange={(e) => onChange(e.target.value)} />
      case 'set': { const chosen = Array.isArray(value) ? (value as string[]).map((x) => x.toLowerCase()) : []
        return refView
          ? <>{finder}<select multiple className={`${inputClass} min-h-32`} disabled={disabled} value={chosen} onChange={(e) => onChange(Array.from(e.target.selectedOptions).map((o) => o.value))}>{opts.map((r) => <option key={s(r.EntityId)} value={s(r.EntityId).toLowerCase()}>{s(r[refView.label])}</option>)}</select><span className="text-xs text-slate-500">{chosen.length} chosen · Ctrl-click to add or remove</span></>
          : <textarea className={`${inputClass} min-h-16`} placeholder="one id per line" value={Array.isArray(value) ? (value as string[]).join('\n') : s(value)} disabled={disabled} onChange={(e) => onChange(e.target.value)} /> }
      default: return <input className={inputClass} value={s(value)} disabled={disabled} onChange={(e) => onChange(e.target.value)} />
    }
  })()
  return <Field label={label}>{body}{help && <span className="text-xs text-slate-500">{help}</span>}</Field>
}
function toLocal(v: unknown): string { if (!v) return ''; const d = new Date(String(v)); return Number.isNaN(d.getTime()) ? s(v) : new Date(d.getTime() - d.getTimezoneOffset() * 60_000).toISOString().slice(0, 16) }
