// #227 (2026-09-22): a change request brought over from the old program, shown and finished the way the old program did it.
// The owner, on CR 9617635: the legacy request "still showing all of the procedure states … none of the procedure is going
// to be followed for the legacy WR." The old program's change-request window (prog_frmRelaySettingChangeStatus) kept a
// status, a date and notes per track, set by hand, and "Complete Request" refused while any track was still in progress.
// The software track is not here: the owner, 2026-09-22, "never seriously used … declared as completed or NA in all cases
// just so that the work request could be completed" — its old status stays in the request's notes.
import { useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { ApiError, proc, s, type Row } from '@/lib/api'
import { legacyFree } from '@/lib/legacy'
import { Panel, Pill, stateTone, Button, Field, Status, inputClass } from '@/components/ui/ui'

type TrackStatus = 'InProgress' | 'Complete' | 'NotNeeded'
const STATUS_WORDS: Record<TrackStatus, string> = { InProgress: 'In progress', Complete: 'Complete', NotNeeded: 'Not needed' }
const TRACKS = [
  { code: 'Documentation', label: 'Documentation', status: 'DocumentationTrackStatus', date: 'DocumentationTrackDate', note: 'DocumentationTrackNote' },
  { code: 'Database', label: 'Settings database', status: 'DatabaseTrackStatus', date: 'DatabaseTrackDate', note: 'DatabaseTrackNote' },
] as const

const refused = (e: unknown) => (e instanceof ApiError ? e.message : (e as Error).message)
const dayOf = (v: unknown) => (v ? String(v).slice(0, 10) : '')
const isDone = (v: unknown) => v === 'Complete' || v === 'NotNeeded'

export function LegacyRequest({ head, can, onChanged }: { head: Row; can: (c: string) => boolean; onChanged: () => void }) {
  const qc = useQueryClient()
  const id = s(head.WorkRequestEntityId)
  const open = !['Closed', 'Cancelled'].includes(s(head.RequestState))
  const mayEdit = open && can('WorkRequest.Modify')
  const bothDone = TRACKS.every((t) => isDone(head[t.status]))
  const relay = legacyFree(head.EquipmentName) || 'the relay'
  const isDelete = s(head.WorkTypeKey) === 'SETTINGS_DELETE'
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const [confirming, setConfirming] = useState(false)
  const [withdrawing, setWithdrawing] = useState(false)
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)

  const after = () => {
    onChanged()
    // the settings book and the record screens read the same revisions; they are stale once a request finishes
    void qc.invalidateQueries({ queryKey: ['view', 'document', 'vSettingsRecord'] })
    void qc.invalidateQueries({ queryKey: ['view', 'work', 'vChangeRequestStatus'] })
    // the Items grid's "Replaces" column reads each relay's revisions under its own key
    void qc.invalidateQueries({ queryKey: ['deviceRevisions'] })
  }
  const complete = async () => {
    setBusy(true); setMsg(null)
    try {
      await proc('work', 'CompleteLegacyRequest', { WorkRequestEntityId: id })
      setMsg({ text: isDelete ? `Finished. The settings of ${relay} are archived and nothing is in service in their place.` : `Finished. The new settings of ${relay} are in service and the ones they replace are archived.` })
      setConfirming(false); after()
    } catch (e) { setMsg({ text: 'Not finished: ' + refused(e), bad: true }) } finally { setBusy(false) }
  }
  const withdraw = async () => {
    setBusy(true); setMsg(null)
    try {
      await proc('work', 'WithdrawLegacyRequest', { WorkRequestEntityId: id, Reason: reason.trim() })
      setMsg({ text: `Withdrawn. The settings in service on ${relay} are unchanged.` })
      setWithdrawing(false); setReason(''); after()
    } catch (e) { setMsg({ text: 'Not withdrawn: ' + refused(e), bad: true }) } finally { setBusy(false) }
  }

  return (
    <Panel title="What is left to do">
      <div className="mb-2 text-sm text-slate-400">
        This change was raised in the old program. It is finished the way the old program finished it: set each track, then finish the request.
      </div>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      <div className="grid gap-3 md:grid-cols-2">
        {TRACKS.map((t) => <Track key={t.code} requestId={id} code={t.code} label={t.label} status={s(head[t.status]) as TrackStatus} date={dayOf(head[t.date])} note={s(head[t.note])} mayEdit={mayEdit} onSaved={after} />)}
      </div>
      {open && (
        <div className="mt-3 space-y-2">
          {!confirming && !withdrawing && (
            <div className="flex flex-wrap items-center gap-2">
              <Button kind="primary" disabled={!mayEdit || !bothDone || busy} onClick={() => setConfirming(true)}>Finish the request</Button>
              <Button kind="danger" disabled={!mayEdit || busy} onClick={() => setWithdrawing(true)}>Withdraw the request</Button>
              {!bothDone && <span className="text-xs text-slate-400">Both tracks must be Complete or Not needed before the request can be finished.</span>}
            </div>
          )}
          {confirming && (
            <div className="rounded border border-sky-800 bg-sky-950/30 p-2 text-sm">
              <div className="text-slate-200">
                {isDelete
                  ? `The settings in service on ${relay} will be archived, and nothing will be in service in their place.`
                  : `The outstanding settings will go in service on ${relay}, and the settings in service now will be archived.`}
              </div>
              <div className="mt-2 flex gap-2">
                <Button kind="primary" disabled={busy} onClick={() => void complete()}>Finish it</Button>
                <Button disabled={busy} onClick={() => setConfirming(false)}>Not yet</Button>
              </div>
            </div>
          )}
          {withdrawing && (
            <form className="flex flex-wrap items-end gap-2 rounded border border-red-900 bg-red-950/20 p-2" onSubmit={(e) => { e.preventDefault(); if (reason.trim()) void withdraw() }}>
              <Field label="Why is it withdrawn? (required)"><input className={`${inputClass} w-96`} value={reason} onChange={(e) => setReason(e.target.value)} autoFocus /></Field>
              <Button type="submit" kind="danger" disabled={busy || !reason.trim()}>Withdraw it</Button>
              <Button disabled={busy} onClick={() => { setWithdrawing(false); setReason('') }}>Never mind</Button>
              <span className="w-full text-xs text-slate-400">The outstanding settings are set aside and stay in the relay's history. The settings in service are not changed.</span>
            </form>
          )}
        </div>
      )}
    </Panel>
  )
}

function Track({ requestId, code, label, status, date, note, mayEdit, onSaved }: { requestId: string; code: string; label: string; status: TrackStatus | ''; date: string; note: string; mayEdit: boolean; onSaved: () => void }) {
  const [st, setSt] = useState<TrackStatus | ''>(status)
  const [dt, setDt] = useState(date)
  const [nt, setNt] = useState(note)
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
  // a save elsewhere (or a refresh) brings new values; the fields follow them
  useEffect(() => { setSt(status); setDt(date); setNt(note) }, [status, date, note])
  const changed = st !== status || dt !== date || nt !== note
  const save = async () => {
    if (!st) return
    setBusy(true); setErr('')
    try {
      await proc('work', 'SetRequestTrack', { WorkRequestEntityId: requestId, TrackCode: code, Status: st, TrackDate: dt || null, Note: nt.trim() || null })
      onSaved()
    } catch (e) { setErr('Not saved: ' + refused(e)) } finally { setBusy(false) }
  }
  return (
    <div className="rounded border border-slate-800 bg-slate-950/60 p-2">
      <div className="flex items-center justify-between gap-2">
        <span className="text-sm font-medium text-slate-200">{label}</span>
        <Pill tone={stateTone(status === 'Complete' ? 'Complete' : status === 'InProgress' ? 'InProgress' : status === 'NotNeeded' ? 'NA' : 'NotStarted')}>{status ? STATUS_WORDS[status] : 'Not set'}</Pill>
      </div>
      <div className="mt-2 flex flex-wrap items-end gap-2">
        <Field label="Status">
          <select className={inputClass} value={st} disabled={!mayEdit || busy} onChange={(e) => setSt(e.target.value as TrackStatus)}>
            {!st && <option value="">—</option>}
            {(Object.keys(STATUS_WORDS) as TrackStatus[]).map((k) => <option key={k} value={k}>{STATUS_WORDS[k]}</option>)}
          </select>
        </Field>
        <Field label="Date"><input type="date" className={inputClass} value={dt} disabled={!mayEdit || busy} onChange={(e) => setDt(e.target.value)} /></Field>
      </div>
      <Field label="Notes"><textarea className={`${inputClass} mt-1 w-full`} rows={2} value={nt} disabled={!mayEdit || busy} onChange={(e) => setNt(e.target.value)} /></Field>
      {mayEdit && <div className="mt-1"><Button kind="mini" disabled={!changed || !st || busy} onClick={() => void save()}>Save</Button></div>}
      {err && <Status bad>{err}</Status>}
    </div>
  )
}
