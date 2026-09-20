// #168: a device's settings by function — the settings template's view of a revision. The template (the model's
// Transform.SettingsParse definition, Effective version) gives every setting its name, functional group (the manual's own
// heading), unit, range, closed list and order; the revision's parsed rows give the values as filed. What the relay does
// is the template's ANSI codes; its inputs are the ratio settings the template carries. Nothing here is per model in
// code: a template for another relay draws the same way.
import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { getText, proc, view, viewAll, s, ApiError, type Row } from '@/lib/api'
import { useViewAll } from '@/lib/hooks'
import { screenPath } from '@/lib/screens'
import { Panel, Pill, Tabs, Status, Button } from '@/components/ui/ui'
import { DataGrid, type Column } from '@/components/ui/data-grid'

export interface Template { definitionEntityId: string; versionRowId: string; name: string; rows: Row[]; ansi: Map<string, string> }

/** The settings template bound to a model (the firmware row that carries a parse transform), with its Effective rows. */
export function useTemplate(modelId: string | null | undefined) {
  return useQuery({ queryKey: ['settingsTemplate', modelId], enabled: !!modelId, staleTime: 10 * 60_000, queryFn: async (): Promise<Template | null> => {
    const fv = (await view('ref', 'vFirmwareVersion', { ModelId: modelId! }, { take: 50 })).rows.filter((x) => x.ParseTransformDefinitionEntityId)
    const bound = fv.find((x) => x.VersionString === 'n/a') ?? fv[0]; if (!bound) return null
    const def = s(bound.ParseTransformDefinitionEntityId)
    const ver = (await view('config', 'vDefinitionVersion', { DefinitionEntityId: def, Status: 'Effective' }, { take: 5 })).rows[0]; if (!ver) return null
    const d = (await view('config', 'vDefinition', { EntityId: def }, { take: 1 })).rows[0]
    const rows = await viewAll('config', 'vSettingDefinition', { DefinitionVersionRowId: s(ver.RowId) }, 'DisplayOrder')
    const codes = [...new Set(rows.map((r) => s(r.AnsiCode)).filter(Boolean))]
    const ansi = new Map<string, string>()
    for (const c of codes) { const a = (await view('ref', 'vAnsiFunction', { AnsiCode: c }, { take: 1 })).rows[0]; if (a) ansi.set(c, s(a.Name)) }
    return { definitionEntityId: def, versionRowId: s(ver.RowId), name: s(d?.Name), rows, ansi }
  } })
}

const isRatio = (r: Row) => /current and potential inputs|transformer ratio/i.test(s(r.Category))
const rangeText = (r: Row) => (r.MinValue == null && r.MaxValue == null ? '' : `${r.MinValue ?? '…'} – ${r.MaxValue ?? '…'}`)


/** The Analog inputs tab (#200, reshaped by #205 — owner, 2026-09-20: "the analog inputs tab should only contain information
 * on the CTs and PTs which are feeding the protections and not device specific settings"): the instrument transformers the
 * scheme names as its CT and VT sources (scheme.vSchemeSource, #201), each with its ratio, whether it is in service, and
 * which of the relay's ratio settings it feeds and whether the two agree (to half a percent). The relay's ratio settings
 * themselves (CTR, PTR, SPTR on an SEL-221F) are read and edited in the settings book like every other setting; here a
 * setting is only named and judged. A ratio setting with no source of its kind named is said so, not judged. */
export function AnalogInputs({ r, revision }: { r: Row; revision: string }) {
  const navigate = useNavigate()
  const tq = useTemplate(s(r.ModelId) || null)
  const parsedQ = useViewAll('document', 'vParsedSettingNamed', { ConfigurationFileRevisionRowId: revision }, 'DisplayOrder')
  const values = useMemo(() => new Map((parsedQ.data ?? []).map((p) => [s(p.SettingCode), p])), [parsedQ.data])
  const hasScheme = !!r.SchemeEntityId; const schemeName = s(r.SchemeName) || 'the scheme'
  const sourcesQ = useViewAll('scheme', 'vSchemeSource', { SchemeEntityId: s(r.SchemeEntityId) }, 'AssetName', hasScheme)
  const sources = sourcesQ.data ?? []
  const ratios = (tq.data?.rows ?? []).filter(isRatio)
  const isCurrent = (x: Row) => /^CT|current/i.test(s(x.SettingCode) + ' ' + s(x.Name))
  const roleOf = (x: Row) => (isCurrent(x) ? 'CtSource' : 'VtSource')
  const settingOf = (x: Row) => { const v = values.get(s(x.SettingCode)); return v ? Number(s(v.RawValue ?? v.DisplayValue)) : NaN }
  // the relay's ratio settings a transformer of this role feeds, each with a verdict against the nameplate ratio
  const feeds = (src: Row) => ratios.filter((x) => roleOf(x) === s(src.MemberRoleCode)).map((x) => {
    const setting = settingOf(x); const ratio = src.Ratio == null ? NaN : Number(src.Ratio)
    const verdict = !Number.isFinite(ratio) ? { text: 'ratio not readable', tone: 'warn' as const }
      : !Number.isFinite(setting) ? { text: `${s(x.SettingCode)} not set`, tone: 'warn' as const }
      : Math.abs(ratio - setting) <= Math.max(0.005 * ratio, 0.01) ? { text: 'matches', tone: 'good' as const }
      : { text: `differs — ${s(x.SettingCode)} is ${setting}`, tone: 'bad' as const }
    return { code: s(x.SettingCode), verdict }
  })
  const unfed = ratios.filter((x) => !sources.some((src) => s(src.MemberRoleCode) === roleOf(x)))
  return (
    <Panel title={`Feeding this protection · ${sources.length ? `${sources.length} transformer${sources.length === 1 ? '' : 's'}` : 'none named'}`}>
      {!hasScheme && <Status>This record is in no scheme, so nothing names the transformers that feed it.</Status>}
      {hasScheme && sourcesQ.isPending && <Status>Reading the scheme's sources…</Status>}
      {hasScheme && !sourcesQ.isPending && !sources.length && <Status>{schemeName} names no CT or VT source yet. Name a transformer as its source from the transformer's page (Instrument transformers in the nav).</Status>}
      {sources.length > 0 && (
        <ul className="space-y-1 text-sm">
          {sources.map((src) => {
            const ratio = src.Ratio == null ? NaN : Number(src.Ratio); const path = screenPath('INSTRUMENT_TRANSFORMER', s(src.AssetEntityId)); const fed = feeds(src)
            return (
              <li key={s(src.MemberEntityId)} className="flex flex-wrap items-center gap-2">
                <a className="text-sky-300 underline" href={path} onClick={(e) => { e.preventDefault(); navigate(path) }}>{s(src.AssetName)}</a>
                <span className="text-xs text-slate-500">{s(src.AssetTypeCode)} · {src.MemberRoleCode === 'CtSource' ? 'CT source' : 'VT source'}</span>
                <span className="text-slate-400">{s(src.RatioInUse) ? `${s(src.RatioInUse)}${Number.isFinite(ratio) ? ` = ${ratio}` : ' (ratio not read)'}` : 'no ratio recorded'}</span>
                {src.IsInService === false && <Pill tone="warn">not in service</Pill>}
                {fed.map((f) => <span key={f.code} className="flex items-center gap-1 text-slate-400">· feeds {f.code} <Pill tone={f.verdict.tone}>{f.verdict.text}</Pill></span>)}
                {tq.data && !fed.length && <span className="text-xs text-slate-500">· the template carries no {src.MemberRoleCode === 'CtSource' ? 'current' : 'voltage'} ratio setting for it to feed</span>}
              </li>)
          })}
        </ul>)}
      {hasScheme && !sourcesQ.isPending && unfed.length > 0 && (
        <ul className="mt-2 space-y-1 border-t border-slate-800 pt-2 text-sm">
          {unfed.map((x) => <li key={s(x.SettingCode)} className="text-slate-500"><span className="text-slate-300">{s(x.SettingCode)}</span> — {schemeName} names no {isCurrent(x) ? 'CT' : 'VT'} source; name it from the transformer's page.</li>)}
        </ul>)}
      {tq.isPending && <Status>Reading the template…</Status>}
      {!tq.isPending && !tq.data && <Status>No settings template for this model, so which setting each transformer feeds is not known.</Status>}
    </Panel>
  )
}

/** The settings grid: the template rows given, each with the revision's value or "not set"; a value edits in place when the
 * revision is outstanding (#168 increment 2: process.SetParsedSetting reads it as the parser would — type, range, closed
 * list — closes the prior row in valid time and audits the change; the platform writes the settings file from these rows
 * at the settings step). */
function SettingsGrid({ rows: given, values, revision, editable = false, deviceId = '' }: { rows: Row[]; values: Map<string, Row>; revision: string; editable?: boolean; deviceId?: string }) {
  const rows: (Row & { _v?: Row })[] = given.map((r) => ({ ...r, _v: values.get(s(r.SettingCode)) }))
  const qc = useQueryClient()
  const [edits, setEdits] = useState<Record<string, string>>({})
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const save = async (code: string, was: string) => {
    const v = edits[code]; if (v === undefined || v === was) return
    try {
      await proc('process', 'SetParsedSetting', { ConfigurationFileRevisionRowId: revision, DeviceEntityId: deviceId, SettingCode: code, RawValue: v })
      setMsg({ text: `${code} saved${v === '' ? ' (unset)' : ''}.` })
      setEdits((e) => { const n = { ...e }; delete n[code]; return n })
      qc.invalidateQueries({ queryKey: ['view', 'document', 'vParsedSettingNamed'] }); qc.invalidateQueries({ queryKey: ['rendered', revision] })
    } catch (err) { setMsg({ text: err instanceof ApiError ? err.message : String(err), bad: true }) }
  }
  const cols: Column<Row & { _v?: Row }>[] = [
    { key: 'Name', label: 'Setting', render: (r) => <span>{s(r.Name)} <span className="text-xs text-slate-500">{s(r.SettingCode)}</span></span> },
    { key: '_value', label: 'Value', render: (r) => {
        const was = r._v ? s(r._v.RawValue ?? r._v.DisplayValue) : ''; const code = s(r.SettingCode)
        if (editable) return <input className="w-32 rounded border border-slate-700 bg-slate-950 px-2 py-0.5 text-sm text-slate-100" value={edits[code] ?? was} placeholder="not set" aria-label={`${code} value`}
          onChange={(e) => setEdits((x) => ({ ...x, [code]: e.target.value }))} onBlur={() => void save(code, was)} onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }} />
        return r._v ? <span className={r._v.RangeCheck === 'OutOfRange' ? 'font-semibold text-amber-300' : 'text-slate-100'}>{was}</span> : <span className="text-slate-500">not set</span> },
      csv: (r) => (r._v ? s(r._v.RawValue ?? r._v.DisplayValue) : '') },
    { key: 'UnitCode', label: 'Unit', render: (r) => s(r.UnitCode) + (r.Base ? ` (${s(r.Base).toLowerCase()})` : '') },
    { key: '_range', label: 'Range', render: (r) => rangeText(r), csv: (r) => rangeText(r) },
    { key: '_flag', label: '', render: (r) => (r._v?.RangeCheck === 'OutOfRange' ? <Pill tone="bad" title={s(r._v.RangeCheckNote)}>out of range</Pill> : null), csv: (r) => s(r._v?.RangeCheck) },
    { key: 'Description', label: 'The manual says', render: (r) => <span className="text-xs text-slate-400">{s(r.Description).replace(/^§ /, '')}</span> },
  ]
  return (
    <>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      {editable && <Status>Outstanding revision: a value saves when you leave the field (audited as your change). The platform writes the settings file from these values when the settings step of the change commits.</Status>}
      <div className="mt-2"><DataGrid rows={rows} columns={cols} rowKey={(r) => s(r.SettingCode)} emptyText="No settings in this group." /></div>
    </>
  )
}

/** The settings by function: a tab per category in the template's order, every template row of the category with the
 * revision's value or "not set". The ratio settings (CTR, PTR, SPTR) are a category like any other — #205 brought them back
 * from the Analog inputs tab, which now holds the transformers that feed them. */
export function SettingsByFunction({ template, parsed, parseStatus, parseError, revision, filedText, editable = false, deviceId = '' }: { template: Template; parsed: Row[]; parseStatus: string; parseError: string; revision: string; filedText: string | null; editable?: boolean; deviceId?: string }) {
  const values = useMemo(() => new Map(parsed.map((p) => [s(p.SettingCode), p])), [parsed])
  const bookRows = template.rows
  const categories = useMemo(() => { const seen: string[] = []; for (const r of bookRows) { const c = s(r.Category) || 'Settings'; if (!seen.includes(c)) seen.push(c) } return seen }, [bookRows])
  const [tab, setTab] = useState(categories[0] ?? '')
  const current = tab || categories[0] || ''
  const rows = bookRows.filter((r) => (s(r.Category) || 'Settings') === current)
  const renderedQ = useQuery({ queryKey: ['rendered', revision], queryFn: () => getText(`/api/v1/settings/${revision}/rendered`), staleTime: 60_000, enabled: parsed.length > 0 })
  const unmatched = parseError && /not in the template: ([^;]+)/.exec(parseError)?.[1]
  return (
    <Panel title={`Settings · ${template.name}`} actions={<>{parseStatus && <Pill tone={parseStatus === 'Parsed' ? 'good' : parseStatus === 'Partial' ? 'warn' : 'neutral'}>{parseStatus}</Pill>}
      {parsed.length > 0 && <a className="text-xs text-sky-300 underline" href={`/api/v1/settings/${revision}/rendered`} target="_blank" rel="noopener">the settings file as the platform writes it</a>}</>}>
      {unmatched && <Status bad>Names in the filed text that the template does not know: {unmatched}</Status>}
      <Tabs tabs={categories.map((c) => ({ key: c, label: c.length > 42 ? c.slice(0, 40) + '…' : c }))} value={current} onChange={setTab} />
      <SettingsGrid rows={rows} values={values} revision={revision} editable={editable} deviceId={deviceId} />
      <details className="mt-3">
        <summary className="cursor-pointer text-xs font-semibold uppercase tracking-wide text-slate-400">Relay listing and the file</summary>
        <div className="mt-2 grid gap-3 lg:grid-cols-2">
          <div><h4 className="text-xs text-slate-500">Listing (the template's order, as the relay lists it)</h4><pre className="mt-1 overflow-auto rounded border border-slate-800 bg-slate-950 p-2 text-xs">{listing(template.rows, values)}</pre></div>
          <div><h4 className="text-xs text-slate-500">The file the platform writes{renderedQ.data != null && filedText != null ? (renderedQ.data === filedText ? ' — identical to the file as filed' : ' — differs from the file as filed (order or spelling; the values are what was parsed)') : ''}</h4>
            <pre className="mt-1 max-h-64 overflow-auto rounded border border-slate-800 bg-slate-950 p-2 text-xs whitespace-pre-wrap">{renderedQ.isPending ? '…' : renderedQ.isError ? 'not available' : renderedQ.data}</pre></div>
        </div>
      </details>
    </Panel>
  )
}

/** A SHOWSET-like listing: five "CODE =value" cells per line in the template's order; the masks on their own lines. */
function listing(rows: Row[], values: Map<string, Row>): string {
  const cell = (r: Row) => { const v = values.get(s(r.SettingCode)); return (s(r.SettingCode).padEnd(5) + '=' + (v ? s(v.RawValue ?? v.DisplayValue) : '')).padEnd(15) }
  const main = rows.filter((r) => r.Format !== 'mask3' && s(r.SettingCode) !== 'ID'); const masks = rows.filter((r) => r.Format === 'mask3')
  const lines: string[] = []
  for (let i = 0; i < main.length; i += 5) lines.push(main.slice(i, i + 5).map(cell).join('').trimEnd())
  if (masks.length) { lines.push(''); lines.push('Logic settings:'); lines.push(masks.map((r) => s(r.SettingCode).padEnd(5)).join('')); lines.push(masks.map((r) => { const v = values.get(s(r.SettingCode)); return (v ? s(v.RawValue ?? v.DisplayValue) : '').padEnd(5) }).join('').trimEnd()) }
  return lines.join('\n')
}

/** Everything the template gives a record's Settings tab: the settings by function. Falls back to the plain parsed grid when the model has no template.
 * The function chips (2026-09-18) and the Inputs panel (#200) that sat above the book are gone: the owner wanted neither there. */
export default function DeviceSettings({ r, revision, filedText, editable = false }: { r: Row; revision: string; filedText: string | null; editable?: boolean }) {
  const tq = useTemplate(s(r.ModelId) || null)
  const parsedQ = useViewAll('document', 'vParsedSettingNamed', { ConfigurationFileRevisionRowId: revision }, 'DisplayOrder')
  const parsed = parsedQ.data ?? []
  if (tq.isPending) return <Status>Loading the template…</Status>
  if (!tq.data) return null
  return (
    <>
      <SettingsByFunction template={tq.data} parsed={parsed} parseStatus={s(r.ParseStatus)} parseError={s(r.ParseError)} revision={revision} filedText={filedText} editable={editable} deviceId={s(r.DeviceEntityId)} />
    </>
  )
}
/**
 * #192: the draft's basis, above the settings — the thing the engineer must act on before the check, the approval, the
 * issue and the baseline will pass. Reads process.BasisDrift (then / theirs now / mine per setting). No drift: one quiet
 * line. Drift: the rows, a theirs/mine choice on each conflict, and Re-base (process.RebaseDraft), disabled until every
 * conflict is decided. Nothing is merged silently; each applied value is an audited edit.
 */
export function BasisPanel({ r, revision, editable }: { r: Row; revision: string; editable: boolean }) {
  const qc = useQueryClient()
  const [decisions, setDecisions] = useState<Record<string, 'mine' | 'theirs'>>({})
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const q = useQuery({ queryKey: ['basisDrift', revision], enabled: !!revision, staleTime: 15_000, queryFn: () => proc<{ results?: Row[][] }>('process', 'BasisDrift', { RevisionRowId: revision, DeviceEntityId: s(r.DeviceEntityId) }) })
  const rows = q.data?.results?.[0] ?? []; const head = q.data?.results?.[1]?.[0]
  const drift = rows.filter((x) => ['take', 'agree', 'conflict'].includes(s(x.Outcome)))
  const conflicts = drift.filter((x) => s(x.Outcome) === 'conflict')
  const undecided = conflicts.filter((x) => !decisions[s(x.SettingCode)])
  if (q.isPending) return null
  if (q.isError) return <Status bad>Could not read the basis: {(q.error as Error).message}</Status>
  const title = s(head?.BasisTitle) || 'the request it is based on'
  if (!drift.length) return <Status>Based on {title} — unchanged since this draft was taken{head?.HasFrozenBasis ? '' : ' (no frozen basis yet; the first re-base takes one)'}.</Status>
  const rebase = async () => {
    setBusy(true); setMsg(null)
    try {
      const out = await proc<Row>('process', 'RebaseDraft', { RevisionRowId: revision, DeviceEntityId: s(r.DeviceEntityId), Decisions: JSON.stringify(decisions) })
      setMsg({ text: `Re-based: ${s(out.Applied)} value(s) taken from ${title}, ${s(out.Kept)} kept as yours.` }); setDecisions({})
      qc.invalidateQueries({ queryKey: ['basisDrift', revision] }); qc.invalidateQueries({ queryKey: ['view', 'document'] }); qc.invalidateQueries({ queryKey: ['settingsText', revision] })
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  return (
    <Panel title={`${title} has changed since this draft was taken · ${drift.length} setting${drift.length === 1 ? '' : 's'}`} className="border-amber-700/60">
      <Status>{head?.HasFrozenBasis ? 'Then is the basis as it stood when this draft was taken; theirs is the basis now; mine is this draft.' : 'This draft was taken before the basis was frozen, so every difference between the basis now and this draft is shown as a conflict to decide once; the re-base then freezes the basis.'} The check, the approval, the issue and the baseline refuse this draft until it is re-based.</Status>
      <table className="mt-2 w-full text-sm">
        <thead><tr className="text-left text-xs uppercase tracking-wide text-slate-500"><th className="py-1">Setting</th><th>Then</th><th>Theirs now</th><th>Mine</th><th>Outcome</th></tr></thead>
        <tbody>
          {drift.map((x) => { const code = s(x.SettingCode); const o = s(x.Outcome)
            return (
              <tr key={code + '|' + s(x.GroupNumber)} className="border-t border-slate-800">
                <td className="py-1">{s(x.SettingName) || code} <span className="text-xs text-slate-500">{code}{x.GroupNumber && s(x.GroupNumber) !== '1' ? ` · group ${s(x.GroupNumber)}` : ''}</span></td>
                <td className="font-mono text-slate-400">{s(x.ThenValue) || '—'}</td><td className="font-mono">{s(x.NowValue) || '—'}</td><td className="font-mono">{s(x.MineValue) || '—'}</td>
                <td>{o === 'take' ? <span className="text-sky-300">theirs will apply</span> : o === 'agree' ? <span className="text-slate-400">both changed to the same value</span>
                  : <span className="flex flex-wrap items-center gap-2 text-amber-200">conflict
                      <label className="flex items-center gap-1 text-xs text-slate-300"><input type="radio" name={`d-${code}`} disabled={!editable || busy} checked={decisions[code] === 'theirs'} onChange={() => setDecisions({ ...decisions, [code]: 'theirs' })} /> theirs</label>
                      <label className="flex items-center gap-1 text-xs text-slate-300"><input type="radio" name={`d-${code}`} disabled={!editable || busy} checked={decisions[code] === 'mine'} onChange={() => setDecisions({ ...decisions, [code]: 'mine' })} /> mine</label>
                    </span>}</td>
              </tr>) })}
        </tbody>
      </table>
      <div className="mt-2 flex flex-wrap items-center gap-2">
        <Button kind="primary" disabled={!editable || busy || undecided.length > 0} title={undecided.length ? `decide ${undecided.map((x) => s(x.SettingCode)).join(', ')} first` : undefined} onClick={() => void rebase()}>Re-base — apply their changes</Button>
        {!editable && <span className="text-xs text-slate-500">re-basing needs ConfigurationFile.Modify on an outstanding record</span>}
        {undecided.length > 0 && editable && <span className="text-xs text-slate-500">{undecided.length} conflict{undecided.length === 1 ? '' : 's'} to decide</span>}
      </div>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </Panel>
  )
}

export { isRatio }
