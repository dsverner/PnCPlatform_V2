// #210 (2026-09-20): the reference lists the forms draw from, kept by the people who may. The owner, on a stray voltage
// class in a transformer's list (#209): "can the user delete it from the list since it is incorrect and should not show
// up as an option?" — until now no screen could. Voltage classes first: the active ones in display order, each corrected
// in place (nominal kV, transmission, order — the code is the key and cannot change: add the right one and retire the
// wrong one), retired with a second click, and added; a retired code added again is reinstated. The writes are the
// reference procedures the API already exposes under the Definition class (api-permissions.json: ref → Definition):
// ref.VoltageClass_Upsert (Definition.Modify — PCEngineer, Administrator) and ref.VoltageClass_Deactivate
// (Definition.Archive — Administrator). Plain React (#167); the REFERENCE_DATA definition names ref.vVoltageClass and
// pages/Screen.tsx dispatches it here. The next lists (asset types, units) are panels beside this one when they come.
import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { ApiError, proc, s, view, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type ListParams, type Screen } from '@/lib/screens'
import { Panel, Pill, Button, Status, inputClass } from '@/components/ui/ui'

export default function ReferenceDataScreen({ screen }: { screen: Screen; params: ListParams; id?: string }) {
  const can = useCan()
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-lg font-semibold text-slate-100">{screen.name}</h1>
      </header>
      <VoltageClasses canModify={can('Definition.Modify')} canRetire={can('Definition.Archive')} />
    </div>
  )
}

function VoltageClasses({ canModify, canRetire }: { canModify: boolean; canRetire: boolean }) {
  const qc = useQueryClient()
  const q = useViewAll('ref', 'vVoltageClass', {}, 'DisplayOrder')
  const rows = q.data ?? []
  const [edit, setEdit] = useState<Record<string, { NominalKv: string; IsTransmission: boolean; DisplayOrder: string }>>({})
  const [confirm, setConfirm] = useState<string | null>(null); const [carrying, setCarrying] = useState<number | null>(null)
  const [add, setAdd] = useState({ code: '', kv: '', transmission: true, order: '' }); const [adding, setAdding] = useState(false)
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const refresh = () => qc.invalidateQueries({ queryKey: ['view', 'ref', 'vVoltageClass'] })
  // the row's values as the edit boxes start out
  const editFrom = (r: Row) => ({ NominalKv: s(r.NominalKv), IsTransmission: r.IsTransmission === true, DisplayOrder: s(r.DisplayOrder) })
  const upsert = async (code: string, kv: number, transmission: boolean, order: number, said: string) => {
    setBusy(true); setMsg(null)
    try { await proc('ref', 'VoltageClass_Upsert', { VoltageClassCode: code, NominalKv: kv, IsTransmission: transmission, DisplayOrder: order }); setMsg({ text: said }); refresh(); return true }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }); return false } finally { setBusy(false) }
  }
  const save = async (r: Row) => {
    const e = edit[s(r.VoltageClassCode)]; if (!e) return
    const kv = Number(e.NominalKv), order = Number(e.DisplayOrder)
    if (!Number.isFinite(kv) || kv <= 0) { setMsg({ text: 'Nominal kV must be a number above zero.', bad: true }); return }
    if (await upsert(s(r.VoltageClassCode), kv, e.IsTransmission, Number.isFinite(order) ? order : 0, `${s(r.VoltageClassCode)} saved.`)) setEdit((x) => { const n = { ...x }; delete n[s(r.VoltageClassCode)]; return n })
  }
  const startRetire = async (r: Row) => {
    setConfirm(s(r.VoltageClassCode)); setCarrying(null)
    try { const res = await view('asset', 'vAsset', { VoltageClassCode: s(r.VoltageClassCode) }, { take: 1 }) as unknown as { rows: Row[]; total?: number }; setCarrying(res.total ?? res.rows.length) } catch { setCarrying(null) }
  }
  const retire = async (code: string) => {
    setBusy(true); setMsg(null)
    try { await proc('ref', 'VoltageClass_Deactivate', { VoltageClassCode: code }); setMsg({ text: `${code} retired. It leaves every voltage-class list. Equipment that carries it keeps it, shown as retired.` }); setConfirm(null); refresh() }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const create = async () => {
    const code = add.code.trim(); const kv = Number(add.kv); const order = add.order.trim() ? Number(add.order) : Math.max(0, ...rows.map((r) => Number(r.DisplayOrder ?? 0))) + 10
    if (!code) { setMsg({ text: 'A code is needed, such as 500kV.', bad: true }); return }
    if (!Number.isFinite(kv) || kv <= 0) { setMsg({ text: 'Nominal kV must be a number above zero.', bad: true }); return }
    if (await upsert(code, kv, add.transmission, order, `${code} added (${kv} kV). If that code had been retired, it is back in the list with these values.`)) { setAdd({ code: '', kv: '', transmission: true, order: '' }); setAdding(false) }
  }
  return (
    <Panel title={`Voltage classes · ${q.isPending ? '…' : rows.length}`} actions={canModify ? <Button kind="mini" disabled={busy} onClick={() => setAdding(!adding)}>Add a voltage class</Button> : undefined}>
      {q.isError && <Status bad>Could not read the voltage classes: {(q.error as Error).message}</Status>}
      {adding && canModify && (
        <div className="mb-2 flex flex-wrap items-end gap-2 border-b border-slate-800 pb-2 text-sm">
          <label className="flex flex-col gap-1 text-xs text-slate-400">Code<input className={`${inputClass} w-28`} value={add.code} disabled={busy} placeholder="500kV" onChange={(e) => setAdd({ ...add, code: e.target.value })} /></label>
          <label className="flex flex-col gap-1 text-xs text-slate-400">Nominal kV<input className={`${inputClass} w-24`} value={add.kv} disabled={busy} placeholder="500" onChange={(e) => setAdd({ ...add, kv: e.target.value })} /></label>
          <label className="flex items-center gap-1 text-xs text-slate-400"><input type="checkbox" checked={add.transmission} disabled={busy} onChange={(e) => setAdd({ ...add, transmission: e.target.checked })} /> transmission</label>
          <label className="flex flex-col gap-1 text-xs text-slate-400">Order<input className={`${inputClass} w-20`} value={add.order} disabled={busy} placeholder="next" onChange={(e) => setAdd({ ...add, order: e.target.value })} /></label>
          <Button kind="primary" disabled={busy} onClick={() => void create()}>Add</Button>
          <span className="text-xs text-slate-500">A code that was retired comes back with these values.</span>
        </div>)}
      {rows.length > 0 && (
        <table className="w-full text-sm">
          <thead><tr className="border-b border-slate-700 text-left text-xs uppercase tracking-wide text-slate-400">
            <th className="py-1 pr-2">Code</th><th className="py-1 pr-2">Nominal kV</th><th className="py-1 pr-2">Network</th><th className="py-1 pr-2">Order</th><th className="py-1"></th></tr></thead>
          <tbody>
            {rows.map((r) => {
              const code = s(r.VoltageClassCode); const e = edit[code]
              return (
                <tr key={code} className="border-b border-slate-800">
                  <td className="py-1 pr-2 font-semibold text-slate-100">{code}</td>
                  <td className="py-1 pr-2">{e ? <input className={`${inputClass} w-24`} value={e.NominalKv} disabled={busy} onChange={(ev) => setEdit({ ...edit, [code]: { ...e, NominalKv: ev.target.value } })} /> : <span className="text-slate-200">{Number(r.NominalKv)}</span>}</td>
                  <td className="py-1 pr-2">{e ? <label className="flex items-center gap-1 text-xs text-slate-400"><input type="checkbox" checked={e.IsTransmission} disabled={busy} onChange={(ev) => setEdit({ ...edit, [code]: { ...e, IsTransmission: ev.target.checked } })} /> transmission</label> : <Pill tone={r.IsTransmission ? 'accent' : 'neutral'}>{r.IsTransmission ? 'transmission' : 'distribution'}</Pill>}</td>
                  <td className="py-1 pr-2">{e ? <input className={`${inputClass} w-16`} value={e.DisplayOrder} disabled={busy} onChange={(ev) => setEdit({ ...edit, [code]: { ...e, DisplayOrder: ev.target.value } })} /> : <span className="text-slate-400">{s(r.DisplayOrder)}</span>}</td>
                  <td className="py-1">
                    <span className="flex flex-wrap items-center gap-1 text-xs">
                      {canModify && !e && <Button kind="mini" disabled={busy} onClick={() => setEdit({ ...edit, [code]: editFrom(r) })}>Edit</Button>}
                      {canModify && e && <><Button kind="mini" disabled={busy} onClick={() => void save(r)}>Save</Button><Button kind="mini" disabled={busy} onClick={() => setEdit((x) => { const n = { ...x }; delete n[code]; return n })}>Cancel</Button></>}
                      {canRetire && confirm !== code && <Button kind="mini" disabled={busy} title="the class leaves every list; equipment that carries it keeps it" onClick={() => void startRetire(r)}>Retire</Button>}
                      {canRetire && confirm === code && <span className="flex items-center gap-1"><span className="text-slate-400">retire {code}? {carrying === null ? '…' : carrying === 0 ? 'no asset carries it.' : `${carrying} asset${carrying === 1 ? '' : 's'} carry it and keep it.`}</span><Button kind="mini" disabled={busy} onClick={() => void retire(code)}>Yes, retire</Button><Button kind="mini" disabled={busy} onClick={() => setConfirm(null)}>No</Button></span>}
                    </span>
                  </td>
                </tr>)
            })}
          </tbody>
        </table>)}
      {!q.isPending && !rows.length && <Status>No voltage class is in the list. Add one, or the voltage-class boxes on the forms stay empty.</Status>}
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      {/* #210: the writes are ref.VoltageClass_Upsert (Definition.Modify) and ref.VoltageClass_Deactivate (Definition.Archive) */}
      <Status>Every voltage box on the forms offers this list: a transformer's equipment, a primary asset's terminals. A code cannot be renamed. To change one, add the right code and retire the wrong one; equipment keeps a retired code until someone changes it. {canModify ? '' : 'You may not add or correct a voltage class here. '}{canRetire ? '' : 'You may not retire one.'}</Status>
    </Panel>
  )
}
