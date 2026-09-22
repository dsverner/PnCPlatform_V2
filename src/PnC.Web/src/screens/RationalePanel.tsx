// #219 (2026-09-21): the record's Rationale tab — the structured rationale, one section per protective element. The owner: the
// engineer enters the values and the rationale once; the application makes the settings values, the settings file and the Word
// document. What the tab shows comes from GET /api/v1/rationale/{revision} (RationaleEngine): the template's inputs by section,
// the element map (outputs, what supervises the element — the manual's logic), the line and the plant facts resolved (and the
// ones missing), the stored inputs, the last result. Apply (an outstanding revision only) posts the inputs; the settings appear
// on the Settings tab; rationale.docx opens in Word (#218). A revision that is no longer outstanding shows its frozen result.
import { useEffect, useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { getJson, postJson, s, viewAll, type Row } from '@/lib/api'
import { screenPath } from '@/lib/screens'
import { Panel, Button, Status, inputClass } from '@/components/ui/ui'
import { openFile, downloadFile } from '@/lib/files'
import { supervisionLine, type RelayElement, type RelayGroup } from '@/lib/relayWord'

interface Input { key: string; section: string; name: string; dataType: string; unit: string | null; default: string | null; description: string; columns?: string[] }
interface Section { key: string; kind: string; title: string; statement: string; settings: { code: string; exprText: string }[] }
interface Loaded {
  revisionRowId: string; gridState: string; revisionStatus: string
  device: { entityId: string; name: string; station: string; model: string }
  template: { definitionEntityId: string; versionRowId: string; key: string; name: string; inputs: Input[]; sections: Section[]; sources: string[] } | null
  map: { elements: RelayElement[]; groups: RelayGroup[] } | null
  line: { EntityId: string; Name: string; VoltageClassCode: string; NearStation: string; RemoteStation: string; Terminals: number } | null
  lineSource: string; facts: Record<string, string | number | null>; missing: string[]; commissioned: string[]
  rationale: { revisionRowId: string; status: string } | null
  inputs: Record<string, string | null>; files: Row[]; lastResult: Result | null
}
interface Result {
  appliedAt: string; appliedBy: string; sections: { key: string; kind: string; title: string; used: boolean; statement: string; supervision: string; settings: { code: string; value: string | null; unknown?: string }[]; values: Record<string, string | null> }[]
  masks: Record<string, { value: string; bits: string[]; from: string }>; settingsWritten: { code: string; value: string }[]; rangeChecks: Record<string, string>; unknown: string[]; tables?: Record<string, string[][]>
}

const yes = (v: string | null | undefined) => v === 'Y' || v === 'y' || v === 'true' || v === '1'

export function RationalePanel({ revision, editable }: { revision: string; editable: boolean }) {
  const qc = useQueryClient(); const navigate = useNavigate()
  const [line, setLine] = useState<string>('')
  const q = useQuery({ queryKey: ['rationale', revision, line], staleTime: 15_000, queryFn: () => getJson<Loaded>(`/api/v1/rationale/${revision}${line ? `?line=${line}` : ''}`) })
  const linesQ = useViewAllLines(editable)
  const [inputs, setInputs] = useState<Record<string, string>>({})
  const [table, setTable] = useState<string[][]>([])
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null); const [busy, setBusy] = useState(false)
  const d = q.data
  useEffect(() => {
    if (!d) return
    const next: Record<string, string> = {}
    for (const [k, v] of Object.entries(d.inputs ?? {})) if (v !== null && v !== undefined) next[k] = String(v)
    setInputs(next)
    setTable((d.lastResult?.tables?.FaultStudy as string[][] | undefined) ?? [])
  }, [d])
  const elements = useMemo(() => new Map((d?.map?.elements ?? []).map((e) => [e.key, e])), [d])
  const last = d?.lastResult ?? null
  const preview = (sec: Section) => {
    const lastSec = last?.sections.find((x) => x.key === sec.key)
    return sec.statement.replace(/\{([^}]+)\}/g, (_m, name: string) => {
      if (name === 'supervision') { const e = elements.get(sec.key); return e ? supervisionLine(e) : '' }
      if (name === 'note') return inputs['Note_' + sec.key] ?? ''
      if (name.startsWith('input.')) return inputs[name.slice(6)] ?? '…'
      if (name.startsWith('setting.')) { const w = lastSec?.settings.find((x) => x.code === name.slice(8)); return w?.value ?? '…' }
      if (name.startsWith('value.')) return lastSec?.values?.[name.slice(6)] ?? '…'
      const f = d?.facts?.[name]; return f === null || f === undefined ? '…' : String(f)
    }).replace(/\s+/g, ' ').trim()
  }
  if (q.isPending) return <Status>Loading the rationale…</Status>
  if (q.isError) return <Status bad>Could not load the rationale: {(q.error as Error).message}</Status>
  if (!d?.template) return <Panel title="Rationale"><Status>No rationale template exists for this relay model yet. An administrator sets one up before settings can be worked out here.</Status></Panel>
  const apply = async () => {
    setBusy(true); setMsg(null)
    try {
      const body: Record<string, unknown> = { inputs: { ...inputs, FaultStudy: table.filter((r) => r.some((c) => c.trim())) } }
      if (line) body.lineAssetEntityId = line
      const r = await postJson<Result>(`/api/v1/rationale/${revision}/apply`, body)
      setMsg({ text: `Applied: ${r.settingsWritten.length} setting(s) written${r.unknown.length ? `; ${r.unknown.length} could not be worked out` : ''}${Object.keys(r.rangeChecks).length ? `; range: ${Object.entries(r.rangeChecks).map(([k, v]) => `${k} ${v}`).join(', ')}` : ''}.` })
      qc.invalidateQueries({ queryKey: ['rationale', revision] }); qc.invalidateQueries({ queryKey: ['view', 'document'] }); qc.invalidateQueries({ queryKey: ['rendered', revision] })
    } catch (e) { setMsg({ text: e instanceof Error ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const docx = [...d.files].reverse().find((f) => /^rationale.*\.docx$/i.test(s(f.FileName)))   // the newest: the names are stamped
  // the file's own id and name are ours; the buttons say what the engineer gets
  const openDocx = () => { if (docx) void openFile(s(docx.RowId), s(docx.FileName), s(docx.MimeType)).catch((e) => setMsg({ text: String(e), bad: true })) }
  const saveDocx = () => { if (docx) void downloadFile(s(docx.RowId), s(docx.FileName)).catch((e) => setMsg({ text: String(e), bad: true })) }
  const lineFacts = ['line.R1', 'line.X1', 'line.R0', 'line.X0', 'line.LengthMiles']   // the charging is optional (an input stands in)
  const missingLine = lineFacts.filter((f) => d.missing.includes(f))
  return (
    <div className="space-y-3">
      <Panel title={`Rationale · ${d.template.name}`} actions={<>
        {docx && <Button onClick={openDocx}>Open in Word</Button>}
        {docx && <Button onClick={saveDocx}>Save the document</Button>}
        {editable && <Button onClick={() => void apply()} disabled={busy}>{busy ? 'Applying…' : last ? 'Apply again' : 'Apply'}</Button>}
      </>}>
        {msg && <Status bad={msg.bad}>{msg.text}</Status>}
        {!editable && <Status>This revision is no longer outstanding, so its rationale is fixed{last ? ` — applied ${s(last.appliedAt).slice(0, 16).replace('T', ' ')} by ${last.appliedBy}` : ', and none was applied'}.</Status>}
        {last && editable && <Status>Last applied {s(last.appliedAt).slice(0, 16).replace('T', ' ')} by {last.appliedBy}; the settings written are on the Settings tab. Change an input and apply again.</Status>}
        <div className="mt-2 grid gap-2 md:grid-cols-2">
          <div>
            <div className="text-sm font-semibold text-slate-100">The line</div>
            {d.line
              ? <div className="text-sm text-slate-300">{d.line.Name} · {d.line.VoltageClassCode || '—'} · {d.line.NearStation || '?'} → <b>{d.line.RemoteStation || '?'}</b> <span className="text-xs text-slate-400">({d.lineSource === 'scheme' ? 'the scheme protects it' : d.lineSource === 'stored' ? 'picked earlier' : 'picked'})</span>
                  {' '}<button type="button" className="text-xs text-sky-300 underline" onClick={() => navigate(screenPath('PRIMARY_ASSET', d.line!.EntityId))}>open the line</button></div>
              : <Status>No scheme names the line this relay protects. Pick it here.</Status>}
            {editable && <select className={inputClass + ' mt-1'} value={line || d.line?.EntityId || ''} onChange={(e) => setLine(e.target.value)}>
              <option value="">— pick a line —</option>
              {(linesQ.data ?? []).map((l) => <option key={s(l.EntityId)} value={s(l.EntityId)}>{s(l.Name)}{l.VoltageClassCode ? ` · ${s(l.VoltageClassCode)}` : ''}</option>)}
            </select>}
            {d.line && missingLine.length > 0 && <Status bad>The line carries no {missingLine.map((m) => m.slice(5)).join(', ')} yet — record it on the line (its Impedance panel), then apply.</Status>}
          </div>
          <div>
            <div className="text-sm font-semibold text-slate-100">Plant facts</div>
            <div className="grid grid-cols-2 gap-x-3 text-sm text-slate-300">
              {Object.entries(d.facts).map(([k, v]) => <div key={k}><span className="text-xs text-slate-400">{k}</span> {v === null ? '—' : String(v)}</div>)}
            </div>
          </div>
        </div>
      </Panel>
      {d.template.sections.map((sec) => {
        const el = elements.get(sec.key); const ins = d.template!.inputs.filter((i) => i.section === sec.key && i.dataType !== 'Reference')
        const lastSec = last?.sections.find((x) => x.key === sec.key)
        const used = sec.kind !== 'element' || !ins.some((i) => i.key === 'Used_' + sec.key) || yes(inputs['Used_' + sec.key] ?? 'Y')
        return (
          <Panel key={sec.key} title={`${sec.kind === 'element' ? '' : sec.kind === 'shared' ? 'Shared · ' : ''}${sec.title}`}>
            {el && <div className="text-xs text-slate-400">Capability {el.capability}{el.outputs.length ? ` · outputs ${el.outputs.join(', ')}` : ''} · sets {el.settings.join(', ') || 'no setting'}{d.commissioned.length ? (d.commissioned.includes(el.capability) ? ' · commissioned at this position' : ' · not commissioned at this position') : ''}</div>}
            {el && supervisionLine(el) && <div className="text-xs text-slate-400">{supervisionLine(el)}</div>}
            <div className="mt-2 grid gap-2 md:grid-cols-3">
              {ins.map((i) => i.dataType === 'Table'
                ? <div key={i.key} className="md:col-span-3">
                    <label className="text-xs text-slate-400">{i.name}</label>
                    <table className="mt-1 w-full text-sm"><thead><tr>{(i.columns ?? []).map((c) => <th key={c} className="text-left text-xs text-slate-400">{c}</th>)}{editable && <th />}</tr></thead>
                      <tbody>{table.map((row, ri) => <tr key={ri}>{(i.columns ?? []).map((_c, ci) => <td key={ci}><input className={inputClass} value={row[ci] ?? ''} disabled={!editable} onChange={(e) => setTable((t) => t.map((r, k) => (k === ri ? r.map((c, j) => (j === ci ? e.target.value : c)) : r)))} /></td>)}
                        {editable && <td><button type="button" className="text-xs text-slate-400 underline" onClick={() => setTable((t) => t.filter((_r, k) => k !== ri))}>remove</button></td>}</tr>)}</tbody></table>
                    {editable && <button type="button" className="mt-1 text-xs text-sky-300 underline" onClick={() => setTable((t) => [...t, (i.columns ?? []).map(() => '')])}>add a row</button>}
                    <div className="text-xs text-slate-500">{i.description}</div>
                  </div>
                : <label key={i.key} className="block text-sm" title={i.description}>
                    <span className="text-xs text-slate-400">{i.name}{i.unit ? ` (${i.unit})` : ''}</span>
                    {i.dataType === 'Boolean'
                      ? <select className={inputClass} value={inputs[i.key] ?? ''} disabled={!editable} onChange={(e) => setInputs((x) => ({ ...x, [i.key]: e.target.value }))}><option value="">—</option><option value="Y">Yes</option><option value="N">No</option></select>
                      : <input className={inputClass} type={i.dataType === 'Decimal' || i.dataType === 'Integer' ? 'number' : 'text'} step="any" value={inputs[i.key] ?? ''} disabled={!editable} placeholder={i.default ?? ''} onChange={(e) => setInputs((x) => ({ ...x, [i.key]: e.target.value }))} />}
                  </label>)}
            </div>
            <div className="mt-2 text-sm text-slate-200">{used ? (lastSec && !editable ? lastSec.statement : preview(sec)) : 'Not in use at this position.'}</div>
            {lastSec && lastSec.settings.length > 0 && <div className="mt-1 font-mono text-xs text-slate-400">{lastSec.settings.map((w) => `${w.code} = ${w.value ?? `? (${w.unknown ?? 'not worked out'})`}`).join('    ')}</div>}
            {sec.settings.length > 0 && !lastSec && <div className="mt-1 text-xs text-slate-500">Writes {sec.settings.map((w) => w.code).join(', ')} on apply.</div>}
          </Panel>
        )
      })}
      {last && Object.keys(last.masks).length > 0 && <Panel title="Derived masks">
        <table className="text-sm"><thead><tr><th className="text-left text-xs text-slate-400 pr-3">Mask</th><th className="text-left text-xs text-slate-400 pr-3">Hex</th><th className="text-left text-xs text-slate-400 pr-3">Bits</th><th className="text-left text-xs text-slate-400">From</th></tr></thead>
          <tbody>{Object.entries(last.masks).map(([m, v]) => <tr key={m}><td className="pr-3 font-mono">{m}</td><td className="pr-3 font-mono">{v.value}</td><td className="pr-3">{v.bits.join(' ')}</td><td>{v.from}</td></tr>)}</tbody></table>
      </Panel>}
      <Status>Sources: {d.template.sources.join(' · ')}. Each default is a starting value taken from the old rationales; change any of them. The statements and the settings are written when you apply. The document follows these sections in this order.</Status>
    </div>
  )
}

function useViewAllLines(enabled: boolean) {
  return useQuery({ queryKey: ['view', 'asset', 'lines'], enabled, staleTime: 60_000, queryFn: () => viewAll('asset', 'vAsset', { AssetTypeCode: 'Line' }, 'Name', 1000) })
}
