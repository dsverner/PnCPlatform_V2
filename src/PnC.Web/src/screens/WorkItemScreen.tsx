// Screen kind "workItem" (#165): one work request as the legacy change-request window showed it — the stage bar over
// the request workflow's states, the header, the notes, the completion tracks side by side, the items grid, the
// transitions as buttons — but rendered from the procedure instance's block tree and the workflow document, so any
// procedure an administrator writes gets the same screen. The definition says which header view and facts, which
// blocks are the tracks, which items to list.
import { useMemo, useState, type ReactNode } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ApiError, fmtWhen, s, view as readView, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type WorkItemParams, type Screen, type Command, splitView, cellText, labelOf, runCommand, commandEnabled, screenPath } from '@/lib/screens'
import { procedureInstance, evaluate, releaseHold, workflowDocumentOf, transition, type BlockNode, type ProcedureInstance } from '@/lib/process'
import { Panel, Pill, stateTone, Button, Facts, StageBar, Status, Field, inputClass } from '@/components/ui/ui'
import { DataGrid, type Column } from '@/components/ui/data-grid'
import { RaiseRequest, type RaiseOpts } from '@/components/actions/RaiseRequest'
import { raiseOptsFor } from './ListScreen'
import { legacyFree } from '@/lib/legacy'
import { LegacyRequest } from '@/components/LegacyRequest'

// #227: the request's state as a P&C person says it, not the workflow's codes
const REQUEST_WORDS: Record<string, string> = { Raised: 'raised', InProgress: 'in progress', Closed: 'finished', Cancelled: 'withdrawn' }
const WORK_WORDS: Record<string, string> = { Running: 'under way', Held: 'on hold', Completed: 'done', Cancelled: 'stopped', Pending: 'not started' }
// #227: a request from the old program has none of these — no package, no outage window, no raised date
const NOT_IN_THE_OLD_PROGRAM = new Set(['PriorityCode', 'OutageWindowStartAt', 'OutageWindowEndAt', 'ReturnToServiceAt', 'LifecycleState', 'DeviceCount', 'RequestStartedAt'])

export default function WorkItemScreen({ screen, params: p, id }: { screen: Screen; params: WorkItemParams; id?: string }) {
  const [schema, view] = splitView(p.headerView); const qc = useQueryClient(); const can = useCan(); const navigate = useNavigate()
  const headQ = useViewAll(schema, view, { [p.headerKey]: id ?? '' }, undefined, !!id)
  const head = headQ.data?.[0]
  const wfId = head ? s(head.RequestWorkflowInstanceEntityId) : ''
  const instId = head ? s(head.ProcedureInstanceEntityId) : ''
  const wfQ = useQuery({ queryKey: ['workflowDoc', wfId], queryFn: () => workflowDocumentOf(wfId), enabled: !!wfId, staleTime: 5 * 60_000 })
  const instQ = useQuery({ queryKey: ['procedureInstance', instId], queryFn: () => procedureInstance(instId), enabled: !!instId, staleTime: 15_000 })
  const [itemsSchema, itemsView] = p.items ? splitView(p.items.view) : ['', '']
  const itemsQ = useViewAll(itemsSchema, itemsView, { [p.items?.key ?? '']: id ?? '' }, undefined, !!p.items && !!id)
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const [reasonFor, setReasonFor] = useState<string | null>(null); const [reason, setReason] = useState('')
  const [raise, setRaise] = useState<RaiseOpts | null>(null)
  const reload = () => { qc.invalidateQueries({ queryKey: ['view', schema, view] }); qc.invalidateQueries({ queryKey: ['procedureInstance', instId] }); qc.invalidateQueries({ queryKey: ['workflowDoc', wfId] }) }
  // the names of the members a foreach iterates (devices): from the items grid where it has them, else the asset view, one read per member
  const memberIds = useMemo(() => [...new Set((instQ.data?.blocks ?? []).map((b) => b.memberSubjectEntityId).filter((x): x is string => !!x))].sort(), [instQ.data])
  const namesQ = useQuery({ queryKey: ['memberNames', memberIds], enabled: memberIds.length > 0, staleTime: 10 * 60_000,
    queryFn: async () => { const out: [string, string][] = []; for (const id of memberIds) { const r = (await readView('asset', 'vAsset', { EntityId: id }, { take: 1 })).rows[0]; if (r) out.push([id.toLowerCase(), legacyFree(r.Name)]) } return out } })
  const memberNames = useMemo(() => { const m = new Map<string, string>(namesQ.data ?? []); for (const r of itemsQ.data ?? []) if (r.DeviceEntityId) m.set(String(r.DeviceEntityId).toLowerCase(), legacyFree(r.DeviceName)); return m }, [itemsQ.data, namesQ.data])

  if (!id) return <Status bad>The address names no change request.</Status>
  if (headQ.isPending) return <Status>Loading the change request…</Status>
  if (headQ.isError) return <Status bad>Could not load: {(headQ.error as Error).message}</Status>
  if (!head) return <Status bad>You may not read that change request, or it does not exist.</Status>

  const current = s(head.RequestState) || null
  const legacy = head.FromOldProgram === true || head.FromOldProgram === 1
  const doc = wfQ.data?.document
  const transitions = doc && !legacy ? doc.transitions.filter((t) => t.from === current).filter((t, i, a) => a.findIndex((x) => x.name === t.name) === i) : []
  const fire = async (name: string, why?: string) => {
    if (!wfId) { setMsg({ text: 'This change request has no stages, so it cannot be moved on.', bad: true }); return }
    try { const x = await transition(wfId, name, why); setMsg({ text: `${name} → ${x.toState}.` }); setReasonFor(null); setReason(''); reload() }
    catch (e) { setMsg({ text: `${name} refused: ${e instanceof ApiError ? e.status + ' ' : ''}${(e as Error).message}`, bad: true }) }
  }
  const ctx = { navigate, can, raise: ({ command, row }: { command: Command; row: Row }) => setRaise(raiseOptsFor(command, row)), transition: (name: string, requiresReason?: boolean) => (requiresReason ? setReasonFor(name) : fire(name)) }
  const title = p.title ? cellText({ key: p.title, format: 'legacyFree' }, head) : legacyFree(head.Title)

  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-lg font-semibold text-slate-100">{title || screen.name}</h1>
        <div className="flex flex-wrap items-center gap-2">
          {transitions.map((t) => <Button key={t.name} kind={t.to === 'Cancelled' ? 'danger' : 'primary'} disabled={!can('WorkRequest.Modify')} onClick={() => (t.requiresReason ? setReasonFor(t.name) : fire(t.name))}>{t.name}</Button>)}
          {(p.commands ?? []).map((c) => <Button key={c.label} disabled={!commandEnabled(c, head, can)} onClick={() => runCommand(c, head, ctx)}>{c.label}</Button>)}
          <Button kind="mini" onClick={reload}>Refresh</Button>
        </div>
      </header>
      {reasonFor && (
        <form className="flex flex-wrap items-end gap-2 rounded border border-slate-700 bg-slate-950 p-2" onSubmit={(e) => { e.preventDefault(); if (reason.trim()) fire(reasonFor, reason.trim()) }}>
          <Field label={`${reasonFor} — the reason (one is required)`}><input className={`${inputClass} w-96`} value={reason} onChange={(e) => setReason(e.target.value)} autoFocus /></Field>
          <Button type="submit" kind="primary">{reasonFor}</Button><Button onClick={() => setReasonFor(null)}>Never mind</Button>
        </form>
      )}
      <Status bad={msg?.bad}>{msg?.text ?? (legacy
        ? `Raised in the old program; the request is ${REQUEST_WORDS[current ?? ''] ?? 'open'}.`
        : `The request is ${REQUEST_WORDS[current ?? ''] ?? 'not started'}.${head.ProcedureState ? ` The work is ${WORK_WORDS[s(head.ProcedureState)] ?? s(head.ProcedureState).toLowerCase()}.` : ''}${head.LifecycleState ? ` The settings package is ${s(head.LifecycleState).toLowerCase()}.` : ''}`)}</Status>
      {doc ? <StageBar stages={doc.states} current={current} /> : wfQ.isError ? <Status>You may not see the stages of this request.</Status> : null}
      {raise && <RaiseRequest o={raise} onClose={() => setRaise(null)} />}
      <div className="grid gap-3 lg:grid-cols-[2fr_1fr]">
        <Panel title="Request"><Facts cols={2} pairs={p.headerFacts.filter((c) => !legacy || !NOT_IN_THE_OLD_PROGRAM.has(c.key)).map((c) => [labelOf(c),
          legacy && c.key === 'RequestedAt' && !head.RequestedAt ? 'not recorded in the old program' : cellText(c, head)])} /></Panel>
        {/* #227: the old program kept the requester as a name, which the request's header now shows; the same words are not repeated here */}
        {p.notes && <Panel title="Notes"><Facts cols={1} pairs={p.notes.filter((c) => !(legacy && c.key === 'Description' && /^Requested by /.test(s(head.Description)))).map((c) => [labelOf(c), cellText(c, head)])} /></Panel>}
      </div>
      {legacy ? <LegacyRequest head={head} can={can} onChanged={reload} />
        : instId ? (instQ.isPending ? <Status>Loading the procedure…</Status> : instQ.isError ? <Status bad>The procedure could not be read: {(instQ.error as Error).message}</Status>
        : <Tracks inst={instQ.data} p={p} memberNames={memberNames} can={can} onChanged={reload} navigate={navigate} />)
        : <Status>No procedure has been started for this request{current === 'Raised' ? ' — use Start, above' : ''}.</Status>}
      {p.produced && instQ.data && Object.keys(instQ.data.produced).length > 0 && (
        <Panel title="What this produced"><Facts cols={3} pairs={p.produced.filter((x) => instQ.data.produced[x.name]).map((x) => [x.label, x.screen ? <a className="text-sky-300 underline" href="#" onClick={(e) => { e.preventDefault(); navigate(screenPath(x.screen!, instQ.data.produced[x.name])) }}>{instQ.data.produced[x.name]}</a> : instQ.data.produced[x.name]])} /></Panel>
      )}
      {p.items && <Items p={p} rows={itemsQ.data ?? []} pending={itemsQ.isPending} ctx={ctx} can={can} />}
    </div>
  )
}

/** The block tree as tracks: the parallel block's branches side by side (the legacy's three tracks), the other stages as rows. */
function Tracks({ inst, p, memberNames, can, onChanged, navigate }: { inst: ProcedureInstance; p: WorkItemParams; memberNames: Map<string, string>; can: (c: string) => boolean; onChanged: () => void; navigate: (path: string) => void }) {
  const [msg, setMsg] = useState<string | null>(null); const [holdReason, setHoldReason] = useState<Record<string, string>>({})
  const byParent = useMemo(() => { const m = new Map<string | null, BlockNode[]>(); for (const b of inst.blocks) { if (!m.has(b.parent)) m.set(b.parent, []); m.get(b.parent)!.push(b) } return m }, [inst.blocks])
  const root = inst.blocks.find((b) => b.parent === null)
  if (!root) return <Status>This procedure has no steps yet.</Status>
  const top = byParent.get(root.blockInstanceEntityId) ?? []
  const parallel = p.tracks === 'branches' ? (p.tracksOf ? inst.blocks.find((b) => b.path === p.tracksOf && b.kind === 'parallel') : inst.blocks.find((b) => b.kind === 'parallel')) : undefined
  const branches = parallel ? byParent.get(parallel.blockInstanceEntityId) ?? [] : []
  const stepsUnder = (b: BlockNode): BlockNode[] => { const out: BlockNode[] = []; const walk = (x: BlockNode) => { if (x.step) out.push(x); for (const c of byParent.get(x.blockInstanceEntityId) ?? []) walk(c) }; walk(b); return out }
  const shown = (steps: BlockNode[]) => (p.showSteps === 'open' ? steps.filter((x) => !['Committed', 'Skipped', 'Varied'].includes(x.step!.state)) : steps)
  const member = (b: BlockNode) => (b.memberSubjectEntityId ? memberNames.get(b.memberSubjectEntityId.toLowerCase()) ?? b.memberSubjectEntityId.slice(0, 8) : null)
  const trackStatus = (b: BlockNode) => (b.state === 'Completed' ? 'Complete' : b.state === 'Skipped' && b.outcome === 'NotApplicable' ? 'NA' : b.state === 'Running' || b.state === 'Held' ? 'In progress' : b.state === 'Cancelled' ? 'Cancelled' : 'Not started')
  const release = async (b: BlockNode) => { const why = (holdReason[b.blockInstanceEntityId] ?? '').trim(); if (!why) { setMsg('Give a reason before releasing this hold.'); return }
    try { await releaseHold(b.blockInstanceEntityId, why); setMsg(`${b.title ?? 'The hold'} released.`); onChanged() } catch (e) { setMsg(`Could not release it: ${(e as Error).message}`) } }
  const reevaluate = async () => { try { const r = await evaluate(inst.procedureInstanceEntityId); setMsg(`${r.changes} step(s) moved on${r.completed ? '; the procedure is complete' : ''}${r.notes.length ? ' · ' + r.notes.join('; ') : ''}`); onChanged() } catch (e) { setMsg(`Could not move it on: ${(e as Error).message}`) } }
  const StepRow = ({ b }: { b: BlockNode }) => (
    <li className="flex flex-wrap items-center justify-between gap-2 py-1 text-sm">
      <span><a className="text-sky-300 underline" href="#" onClick={(e) => { e.preventDefault(); navigate(screenPath('STEP', b.step!.stepInstanceEntityId)) }}>{b.title ?? b.step!.stepId}</a>{member(b) && <span className="ml-2 text-xs text-slate-400">{member(b)}</span>}</span>
      <span className="flex items-center gap-2 text-xs text-slate-400"><Pill tone={stateTone(b.step!.state === 'Committed' ? 'Complete' : b.step!.state === 'Ready' || b.step!.state === 'Active' ? 'InProgress' : b.step!.state)}>{b.step!.state}{b.step!.outcome ? ' · ' + b.step!.outcome : ''}</Pill>{b.step!.committedAt && fmtWhen(b.step!.committedAt)}{b.step!.dueAt && !b.step!.committedAt && `due ${fmtWhen(b.step!.dueAt)}`}</span>
    </li>
  )
  const Block = ({ b }: { b: BlockNode }): ReactNode => {
    const steps = shown(stepsUnder(b))
    return (
      <div className="rounded border border-slate-800 bg-slate-950/60 p-2">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <span className="text-sm font-medium text-slate-200">{b.title ?? b.path.split('/').pop()}{b.iterationKey && <span className="ml-2 text-xs text-slate-400">{member(b) ?? b.iterationKey}</span>}</span>
          <Pill tone={stateTone(trackStatus(b) === 'Complete' ? 'Complete' : trackStatus(b) === 'In progress' ? 'InProgress' : trackStatus(b))}>{trackStatus(b)}{b.completedAt ? ' · ' + fmtWhen(b.completedAt) : ''}</Pill>
        </div>
        {b.kind === 'hold' && b.state === 'Held' && (
          <div className="mt-1 flex flex-wrap items-end gap-2"><Field label="Why release this hold?"><input className={inputClass} value={holdReason[b.blockInstanceEntityId] ?? ''} onChange={(e) => setHoldReason({ ...holdReason, [b.blockInstanceEntityId]: e.target.value })} /></Field><Button kind="mini" disabled={!can('WorkRequest.Modify')} onClick={() => release(b)}>Release hold</Button></div>
        )}
        {steps.length > 0 && <ul className="mt-1 divide-y divide-slate-800">{steps.map((x) => <StepRow key={x.blockInstanceEntityId} b={x} />)}</ul>}
      </div>
    )
  }
  return (
    // #165: the procedure key is the definition's, not the user's — the state and outcome are what a person reads
    <Panel title={`The procedure · ${inst.state}${inst.outcome ? ' — ' + inst.outcome : ''}`} actions={<Button kind="mini" disabled={!can('WorkRequest.Modify')} onClick={reevaluate} title="Starts any step whose turn it is now, and closes the procedure when the last step is done.">Move it on</Button>}>
      {msg && <Status>{msg}</Status>}
      {branches.length > 0 && (
        <div className="mb-3 grid gap-3" style={{ gridTemplateColumns: `repeat(${Math.min(branches.length, 4)}, minmax(0, 1fr))` }}>
          {branches.map((b) => <Block key={b.blockInstanceEntityId} b={b} />)}
        </div>
      )}
      <div className="space-y-2">
        {top.filter((b) => b !== parallel).map((b) => <Block key={b.blockInstanceEntityId} b={b} />)}
      </div>
    </Panel>
  )
}

function Items({ p, rows, pending, ctx, can }: { p: WorkItemParams; rows: Row[]; pending: boolean; ctx: Parameters<typeof runCommand>[2]; can: (c: string) => boolean }) {
  // #164: the revision this item replaced — the device's revision whose in-service period ended when this one began (the legacy
  // A that became the P), else the device's latest earlier revision; one read per device
  const devices = useMemo(() => [...new Set(rows.map((r) => s(r.DeviceEntityId)).filter(Boolean))].sort(), [rows])
  const histQ = useQuery({ queryKey: ['deviceRevisions', devices], enabled: devices.length > 0, staleTime: 60_000,
    queryFn: async () => { const out: Record<string, Row[]> = {}; for (const d of devices) out[d] = (await readView('document', 'vSettingsRecord', { DeviceEntityId: d }, { take: 200 })).rows; return out } })
  const replaced = (r: Row): string => {
    const list = (histQ.data?.[s(r.DeviceEntityId)] ?? []).filter((x) => x.RevisionRowId !== r.RevisionRowId)
    const byEnd = r.InServiceFrom ? list.find((x) => x.InServiceTo && String(x.InServiceTo) === String(r.InServiceFrom)) : undefined
    const earlier = list.filter((x) => x.CalculatedAt && r.CalculatedAt && String(x.CalculatedAt) < String(r.CalculatedAt)).sort((a, b) => String(b.CalculatedAt).localeCompare(String(a.CalculatedAt)))[0]
    const x = byEnd ?? earlier; return x ? `rev ${s(x.RevisionLabel)} (${s(x.GridState).toLowerCase()})` : '—'
  }
  const cols: Column<Row>[] = [
    ...p.items!.columns.map((c): Column<Row> => ({ key: c.key, label: labelOf(c), render: (r) => (c.format === 'state' ? <Pill tone={stateTone(r[c.key])}>{cellText(c, r)}</Pill> : cellText(c, r)), csv: (r) => cellText(c, r) })),
    { key: '_replaces', label: 'Replaces', render: (r) => replaced(r), csv: (r) => replaced(r) },
  ]
  const open = p.items!.rowOpen
  return (
    <Panel title={`Items · ${pending ? '…' : rows.length}`}>
      <DataGrid rows={rows} columns={cols} rowKey={(r) => s(r[p.items!.key === 'WorkRequestEntityId' ? 'RevisionRowId' : p.items!.key])} onRowClick={open ? (r) => { if (commandEnabled(open, r, can)) runCommand(open, r, ctx) } : undefined} emptyText={pending ? 'Loading…' : 'Nothing is listed on this request yet.'} />
    </Panel>
  )
}
