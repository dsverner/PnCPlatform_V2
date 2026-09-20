// #206 (2026-09-20): what a person does to one scheme-source membership (a transformer feeding a scheme as CT, VT or
// sync-VT source) — the same three actions on the transformer's page (its Feeds panel) and on the record's Analog inputs
// tab: in service on/off, the connection note ("two CTs paralleled", "secondary winding S2 — 2103 A-PROT on S1"), and
// remove from the scheme. The owner: the client "use[s] a breaker and a half scheme with two CTs paralleled before being
// brought into the device. There is no way for the application to determine this and will need to be corrected by the
// user by adding another set of instrument transformers, indicating a parallel connection etc." Writes:
// scheme.SchemeMember_Revise (the whole row, audited) and scheme.SchemeMember_SoftDelete; both Scheme.Modify / .Archive.
import { useState } from 'react'
import { ApiError, proc, s, type Row } from '@/lib/api'
import { Button, Status, inputClass } from '@/components/ui/ui'

export const SOURCE_ROLE_LABEL: Record<string, string> = { CtSource: 'CT source', VtSource: 'VT source', SyncVtSource: 'Sync VT source' }
export const sourceRoleLabel = (code: unknown) => SOURCE_ROLE_LABEL[s(code)] ?? s(code)

/** The membership row as scheme.vSchemeSource gives it (MemberEntityId, SchemeEntityId, AssetEntityId, MemberRoleCode, IsInService, Notes). */
export function SchemeSourceActions({ x, canModify, canRemove, onChanged }: { x: Row; canModify: boolean; canRemove: boolean; onChanged: () => void }) {
  const [note, setNote] = useState<string | null>(null)
  const [confirm, setConfirm] = useState(false)
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const revise = async (patch: { IsInService?: boolean; Notes?: string | null }) => {
    setBusy(true); setMsg(null)
    try {
      await proc('scheme', 'SchemeMember_Revise', { EntityId: x.MemberEntityId, SchemeEntityId: x.SchemeEntityId, MemberKind: 'Asset', MemberEntityId: x.AssetEntityId, MemberRoleCode: x.MemberRoleCode,
        IsInService: patch.IsInService ?? x.IsInService !== false, Notes: patch.Notes === undefined ? (x.Notes ?? null) : patch.Notes })
      setNote(null); onChanged()
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const remove = async () => {
    setBusy(true); setMsg(null)
    try { await proc('scheme', 'SchemeMember_SoftDelete', { EntityId: x.MemberEntityId }); setConfirm(false); onChanged() }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  if (!canModify && !canRemove) return null
  return (
    <span className="flex flex-wrap items-center gap-1 text-xs">
      {canModify && <Button kind="mini" disabled={busy} title={x.IsInService === false ? 'mark this source in service' : 'mark this source not in service (it stays named)'} onClick={() => void revise({ IsInService: x.IsInService === false })}>{x.IsInService === false ? 'In service' : 'Not in service'}</Button>}
      {canModify && note === null && <Button kind="mini" disabled={busy} title="how this transformer is connected to the scheme: paralleled, which secondary winding, shared with which protection" onClick={() => setNote(s(x.Notes))}>{x.Notes ? 'Connection…' : 'Connection note'}</Button>}
      {canModify && note !== null && (
        <span className="flex items-center gap-1">
          <input className={`${inputClass} w-72`} value={note} disabled={busy} placeholder="e.g. two CTs paralleled; secondary winding S2" onChange={(e) => setNote(e.target.value)} />
          <Button kind="mini" disabled={busy} onClick={() => void revise({ Notes: note.trim() || null })}>Save</Button>
          <Button kind="mini" disabled={busy} onClick={() => setNote(null)}>Cancel</Button>
        </span>)}
      {canRemove && !confirm && <Button kind="mini" disabled={busy} title="the scheme no longer names this transformer as a source (the transformer itself stays)" onClick={() => setConfirm(true)}>Remove from scheme</Button>}
      {canRemove && confirm && <span className="flex items-center gap-1"><span className="text-slate-400">remove it as this scheme's source?</span><Button kind="mini" disabled={busy} onClick={() => void remove()}>Yes, remove</Button><Button kind="mini" disabled={busy} onClick={() => setConfirm(false)}>No</Button></span>}
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </span>
  )
}
