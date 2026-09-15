// The "Request change" / "New setting" form (round 4 §3): the effective work types to choose from, a title, optional
// read-only context lines (location, scheme), then Raise and start → the request page.
import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { ApiError } from '@/lib/api'
import { workTypes, raiseAndStart } from '@/lib/actions'
import { Panel, Button, Field, inputClass, Status } from '@/components/ui/ui'

export interface RaiseOpts { heading: string; title: string; scopeKind: 'Asset' | 'Node'; scopeEntityId: string; defaultType: string; workflowKey?: string; before?: [string, string][]; note?: string }

export function RaiseRequest({ o, onClose }: { o: RaiseOpts; onClose: () => void }) {
  const typesQ = useQuery({ queryKey: ['workTypes'], queryFn: workTypes, staleTime: 5 * 60_000 })
  const [title, setTitle] = useState(o.title); const [type, setType] = useState(''); const [busy, setBusy] = useState(false); const [err, setErr] = useState('')
  useEffect(() => { setTitle(o.title); setType('') }, [o])
  const types = typesQ.data ?? []
  const chosen = type || types.find((t) => t.key === o.defaultType)?.versionRowId || types[0]?.versionRowId || ''
  const go = async () => {
    setBusy(true); setErr('')
    try { const id = await raiseAndStart({ workTypeVersionRowId: chosen, title: title.trim(), scopeKind: o.scopeKind, scopeEntityId: o.scopeEntityId, workflowKey: o.workflowKey }); location.href = '/request.html?id=' + id }
    catch (e) { setErr('Refused: ' + (e instanceof ApiError ? e.status + ' ' : '') + (e as Error).message); setBusy(false) }
  }
  return (
    <Panel title={o.heading} actions={<Button kind="mini" onClick={onClose}>Close</Button>}>
      <Status>{o.note || 'A new work request; starting it runs the settings-change procedure.'}</Status>
      <div className="mt-2 flex flex-wrap items-end gap-3">
        {(o.before || []).map(([k, v]) => <Field key={k} label={k}><input className={inputClass} readOnly value={v} size={Math.max(12, Math.min(40, v.length + 2))} /></Field>)}
        <Field label="Action type">
          <select className={inputClass} value={chosen} onChange={(e) => setType(e.target.value)}>
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
