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
    try { const x = await fn(); setBad(false); setMsg(`${what} → done${x && x.advanced ? ' · ' + x.advanced : ''}.`); onDone() }
    catch (e) { setBad(true); setMsg(`${what} → ${e instanceof ApiError ? e.status + ' ' : ''}${(e as Error).message}`) }
  }
  return (
    <Panel title={`Set verified date — ${legacyFree(r.DeviceName)}${r.WorkRequestTitle ? ' (' + legacyFree(r.WorkRequestTitle) + ')' : ''}`} actions={<Button kind="mini" onClick={onClose}>Close</Button>}>
      <Status>The return-to-service step is {String(r.RtsStepState)}. Pick the date the settings were verified in the field, then claim, have a second person witness from their own session, and check in — or commit now for today.</Status>
      <div className="mt-2 flex flex-wrap items-end gap-2">
        <Field label="Verified on"><input type="date" className={inputClass} value={at} onChange={(e) => setAt(e.target.value)} /></Field>
        <Field label="Verified by (account)"><input className={inputClass} value={by} onChange={(e) => setBy(e.target.value)} /></Field>
        <Button onClick={() => call('Claim', () => step.claim(id))}>1. Claim</Button>
        <Button onClick={() => call('Witness', () => step.witness(id))}>2. Witness (as the second person)</Button>
        <Button onClick={() => call('Check-in', () => step.checkin(id, by.trim(), new Date(at + 'T12:00:00').toISOString()))}>3. Check in that date</Button>
        <Button kind="primary" onClick={() => call('Commit', () => step.commit(id))}>Commit now (today)</Button>
      </div>
      {msg && <Status bad={bad}>{msg}</Status>}
    </Panel>
  )
}
