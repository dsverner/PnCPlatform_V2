// The "Request change" / "New setting" form (round 4 §3): the effective work types to choose from, a title, optional
// read-only context lines (location, scheme), then Raise and start → the request page.
import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { screenPath } from '@/lib/screens'
import { ApiError } from '@/lib/api'
import { workTypes, raiseAndStart } from '@/lib/actions'
import { useViewAll } from '@/lib/hooks'
import { s } from '@/lib/api'
import { Panel, Button, Field, inputClass, Status } from '@/components/ui/ui'

export interface RaiseOpts { heading: string; title: string; scopeKind: 'Asset' | 'Node'; scopeEntityId: string; defaultType: string; workflowKey?: string; before?: [string, string][]; note?: string }

const legacyName = (v: unknown) => s(v).replace(/\s*\[\d+\]\s*$/, '')   // the device's name without the legacy record number

export function RaiseRequest({ o, onClose }: { o: RaiseOpts; onClose: () => void }) {
  const typesQ = useQuery({ queryKey: ['workTypes'], queryFn: workTypes, staleTime: 5 * 60_000 }); const navigate = useNavigate()
  const [title, setTitle] = useState(o.title); const [type, setType] = useState(''); const [busy, setBusy] = useState(false); const [err, setErr] = useState('')
  useEffect(() => { setTitle(o.title); setType(''); setSecond(false) }, [o])
  const types = typesQ.data ?? []
  // #191: a device that already has an open change request. The owner, 2026-09-18: the person first looks at the existing
  // request and decides to join it, or starts a second that takes the first's current settings as its starting point and
  // can only complete after the first. Read from the settings book's own view; nothing is raised until one is chosen.
  const openQ = useViewAll('document', 'vSettingsRecord', { DeviceEntityId: o.scopeEntityId, GridState: 'Outstanding' }, '-RowSeq', o.scopeKind === 'Asset')
  const open = o.scopeKind === 'Asset' ? (openQ.data ?? []).filter((x) => x.WorkRequestEntityId) : []
  const [second, setSecond] = useState(false)
  const mustChoose = open.length > 0 && !second
  const chosen = type || types.find((t) => t.key === o.defaultType)?.versionRowId || types[0]?.versionRowId || ''
  const go = async () => {
    setBusy(true); setErr('')
    const wt = types.find((t) => t.versionRowId === chosen)
    try { const id = await raiseAndStart({ workTypeVersionRowId: chosen, title: title.trim(), scopeKind: o.scopeKind, scopeEntityId: o.scopeEntityId, workflowKey: wt?.workflowKey ?? o.workflowKey }); navigate(screenPath('WORK_ITEM', id)) }
    catch (e) { setErr('Refused: ' + (e instanceof ApiError ? e.status + ' ' : '') + (e as Error).message); setBusy(false) }
  }
  return (
    <Panel title={o.heading} actions={<Button kind="mini" onClick={onClose}>Close</Button>}>
      <Status>{o.note || 'A new change request. Starting it runs the settings-change procedure.'}</Status>
      {open.length > 0 && (
        <div className="mt-2 rounded border border-amber-700/60 bg-amber-950/30 p-2 text-sm">
          <div className="text-amber-200">{legacyName(open[0].DeviceName)} already has an open change request{open.length > 1 ? 's' : ''}:</div>
          <ul className="mt-1 space-y-1">
            {open.map((x) => <li key={s(x.RevisionRowId)} className="text-slate-200">{s(x.WorkRequestTitle)} <span className="text-slate-500">— rev {s(x.RevisionLabel)}, {s(x.RevisionStatus)}{x.ProcedureState ? `, procedure ${s(x.ProcedureState)}` : ''}</span></li>)}
          </ul>
          {!second
            ? <div className="mt-2 flex flex-wrap items-center gap-2">
                <Button kind="primary" onClick={() => navigate(screenPath('WORK_ITEM', s(open[0].WorkRequestEntityId)))}>Open it — join that request</Button>
                <Button onClick={() => setSecond(true)}>Raise a second, based on it</Button>
                <span className="text-xs text-slate-500">Join it, and your edits and steps there are in your own name. A second request starts from that request's settings as they stand, and cannot go in service before it does.</span>
              </div>
            : <div className="mt-2 text-xs text-slate-400">A second request: its draft starts from “{s(open[0].WorkRequestTitle)}” as it stands now, and cannot go in service before that request does.</div>}
        </div>)}
      <div className="mt-2 flex flex-wrap items-end gap-3" hidden={mustChoose}>
        {(o.before || []).map(([k, v]) => <Field key={k} label={k}><input className={inputClass} readOnly value={v} size={Math.max(12, Math.min(40, v.length + 2))} /></Field>)}
        <Field label="Action type">
          <select className={inputClass} value={chosen} onChange={(e) => setType(e.target.value)}>
            {/* the workflow key beside the name is ours, not the engineer's */}
            {types.map((t) => <option key={t.versionRowId} value={t.versionRowId}>{t.key} — {t.name}</option>)}
          </select>
        </Field>
        <Field label="Title"><input className={inputClass} size={50} value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
        <Button kind="primary" disabled={busy || !chosen || !title.trim()} onClick={go}>Raise and start</Button>
      </div>
      {err && <Status bad>{err}</Status>}
    </Panel>
  )
}
