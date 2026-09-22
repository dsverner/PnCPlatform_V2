// Set Verified Date (round 4): the witnessed return-to-service commit (#114) or the check-in of a field capture (#115),
// with the date picked first. Item 5 of the build order replaces this with the direct in-service date write.
import { useState } from 'react'
import { ApiError, type Row } from '@/lib/api'
import { step } from '@/lib/actions'
import { useMe } from '@/lib/hooks'
import { legacyFree } from '@/lib/legacy'
import { Panel, Button, Field, inputClass, Status } from '@/components/ui/ui'

export function VerifiedDate({ r, onClose, onDone }: { r: Row; onClose: () => void; onDone: () => void }) {
  const meQ = useMe()
  const [at, setAt] = useState(new Date().toISOString().slice(0, 10)); const [by, setBy] = useState(meQ.data?.user.userPrincipalName ?? '')
  const [msg, setMsg] = useState(''); const [bad, setBad] = useState(false)
  const id = String(r.RtsStepInstanceEntityId)
  const call = async (what: string, fn: () => Promise<Row>) => {
    try { const x = await fn(); setBad(false); setMsg(`${what}.${x && x.advanced ? ' · ' + x.advanced : ''}`); onDone() }
    catch (e) { setBad(true); setMsg(`Refused: ${e instanceof ApiError ? e.status + ' ' : ''}${(e as Error).message}`) }
  }
  return (
    <Panel title={`Set verified date — ${legacyFree(r.DeviceName)}${r.WorkRequestTitle ? ' (' + legacyFree(r.WorkRequestTitle) + ')' : ''}`} actions={<Button kind="mini" onClick={onClose}>Close</Button>}>
      <Status>Pick the date the settings were verified in the field. Take the step, have a second person witness it from their own sign-in, then record the date. Or sign it off now, for today.</Status>
      <div className="mt-2 flex flex-wrap items-end gap-2">
        <Field label="Verified on"><input type="date" className={inputClass} value={at} onChange={(e) => setAt(e.target.value)} /></Field>
        <Field label="Verified by (account)"><input className={inputClass} value={by} onChange={(e) => setBy(e.target.value)} /></Field>
        <Button onClick={() => call('The step is yours', () => step.claim(id))}>1. Take it on</Button>
        <Button onClick={() => call('Witnessed', () => step.witness(id))}>2. Witness it — the second person</Button>
        <Button onClick={() => call('The date is recorded', () => step.checkin(id, by.trim(), new Date(at + 'T12:00:00').toISOString()))}>3. Record that date</Button>
        <Button kind="primary" onClick={() => call('Signed off for today', () => step.commit(id))}>Sign off now, for today</Button>
      </div>
      {msg && <Status bad={bad}>{msg}</Status>}
    </Panel>
  )
}
