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
import { useTemplateDefs, saveAssetCharacteristic, addFirstWinding } from '@/components/CharacteristicsPanel'
import { SchemeSourceActions, sourceRoleLabel } from '@/components/SchemeSourceActions'
import { Panel, Pill, Tabs, Status, Button, inputClass } from '@/components/ui/ui'
import { DataGrid, type Column } from '@/components/ui/data-grid'
import { useRelayWord, parseMask, formatMask, isMaskText, ownerOf, supervisionLine, type RelayWord, type RelayElement } from '@/lib/relayWord'
import type { ReactNode } from 'react'

export interface Template { definitionEntityId: string; versionRowId: string; key: string; name: string; rows: Row[]; ansi: Map<string, string> }

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
    return { definitionEntityId: def, versionRowId: s(ver.RowId), key: s(d?.DefinitionKey), name: s(d?.Name), rows, ansi }
  } })
}

const isRatio = (r: Row) => /^(CTR|PTR|SPTR)/i.test(s(r.SettingCode)) || /^ratio$/i.test(s(r.Unit ?? r.UnitCode)) || /current and potential inputs|transformer ratio/i.test(s(r.Category))   // #211: a ratio setting is an analog input
const rangeText = (r: Row) => (r.MinValue == null && r.MaxValue == null ? '' : `${r.MinValue ?? '…'} – ${r.MaxValue ?? '…'}`)


/** What the relay can take (#211, the owner: "have the application recognize the capabilities of the device being applied
 * and tailor these questions based on those capabilities"): a settings template carries one ratio setting per analog
 * input — the SEL-221F's CTR, PTR, SPTR are one current, one voltage and one sync input; an SEL-551's CTR and CTRN two
 * current inputs. Recognised by code (CTR*, PTR*, SPTR*), unit (ratio) or the ratio category, grouped by kind in template
 * order. A model with no template has no known capability and the question stays plain; nothing is invented for it. */
export const inputKindOf = (x: Row) => (s(x.AnsiCode) === '25' || /^(SPTR|PTRS)|sync/i.test(s(x.SettingCode) + ' ' + s(x.Name)) ? 'SyncVoltage' : /^CT|current/i.test(s(x.SettingCode) + ' ' + s(x.Name)) ? 'Current' : 'Voltage')
export function deviceInputs(rows: Row[]): Record<string, Row[]> {
  const by: Record<string, Row[]> = { Current: [], Voltage: [], SyncVoltage: [] }
  for (const x of rows.filter(isRatio)) by[inputKindOf(x)].push(x)
  return by
}
const KIND_LABEL: Record<string, string> = { Current: 'current', Voltage: 'voltage', SyncVoltage: 'sync voltage' }
const KIND_CODE: Record<string, string> = { Current: 'Current', Voltage: 'Voltage', SyncVoltage: 'Sync voltage' }

/** The Analog inputs tab (#200, reshaped by #205 — owner, 2026-09-20: "the analog inputs tab should only contain information
 * on the CTs and PTs which are feeding the protections and not device specific settings"; #208: grouped by the scheme's
 * ANALOG INPUTS — the relay-side endpoints the transformers feed; two or more CTs on one current input are PARALLELED;
 * #211: READ FIRST, EDIT ON PURPOSE — the owner: "Data input is still too confusing"; the badge-style buttons "are very
 * confusing as I don't know whether they are simply information tags, buttons, status"). View mode is information only:
 * the inputs, their transformers, ratios, phases, placement, notes, and status pills. Edit inputs turns on an Actions
 * column of plain labelled buttons and the add forms; Done returns to view. Each scheme input of a kind is matched to the
 * relay's i-th ratio setting of that kind ("Current 1 · CTR") and judged as one against it: matches when every paralleled
 * ratio equals the setting, "paralleled ratios differ" when the CTs on an input disagree (arithmetic, not a standard's
 * claim), differs otherwise; an input beyond the relay's count is flagged so and can be removed when empty. */
export function AnalogInputs({ r, revision, canEditAssets = false, canEditScheme = false }: { r: Row; revision: string; canEditAssets?: boolean; canEditScheme?: boolean }) {
  const navigate = useNavigate(); const qc = useQueryClient()
  const tq = useTemplate(s(r.ModelId) || null)
  const parsedQ = useViewAll('document', 'vParsedSettingNamed', { ConfigurationFileRevisionRowId: revision }, 'DisplayOrder')
  const values = useMemo(() => new Map((parsedQ.data ?? []).map((p) => [s(p.SettingCode), p])), [parsedQ.data])
  const hasScheme = !!r.SchemeEntityId; const schemeId = s(r.SchemeEntityId); const schemeName = s(r.SchemeName) || 'the scheme'
  const deviceName = s(r.ModelName).replace(/\s*\(legacy label [^)]*\)\s*$/i, '').trim() || s(r.ModelCode) || 'this relay'   // the short model name (owner, 2026-09-20): the legacy label stays in the record's header
  const sourcesQ = useViewAll('scheme', 'vSchemeSource', { SchemeEntityId: schemeId }, 'AssetName', hasScheme)
  const inputsQ = useViewAll('scheme', 'vSchemeInput', { SchemeEntityId: schemeId }, 'InputCode', hasScheme)
  const sources = sourcesQ.data ?? []; const inputs = useMemo(() => sortInputs(inputsQ.data ?? []), [inputsQ.data])
  const capability = tq.data ? deviceInputs(tq.data.rows) : null
  const settingOf = (x: Row) => { const v = values.get(s(x.SettingCode)); return v ? Number(s(v.RawValue ?? v.DisplayValue)) : NaN }
  const [editing, setEditing] = useState(false); const [addTo, setAddTo] = useState<Row | null>(null); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const refresh = () => { qc.invalidateQueries({ queryKey: ['view', 'scheme'] }); qc.invalidateQueries({ queryKey: ['view', 'asset'] }) }
  const canEdit = canEditAssets && canEditScheme
  // the relay's setting an input feeds: the i-th of its kind, in template order
  const settingFor = (input: Row) => { if (!capability) return null; const kind = s(input.InputKind); const i = inputs.filter((x) => s(x.InputKind) === kind).findIndex((x) => s(x.EntityId) === s(input.EntityId)); return capability[kind]?.[i] ?? null }
  const beyond = (input: Row) => !!capability && settingFor(input) === null
  const judge = (input: Row, mine: Row[]) => {
    const x = settingFor(input); if (!x) return null
    const setting = settingOf(x); const nums = [...new Set(mine.map((m) => (m.Ratio == null ? NaN : Number(m.Ratio))).filter((n) => Number.isFinite(n)))]
    const verdict = !mine.length ? { text: 'nothing named', tone: 'warn' as const }
      : !nums.length ? { text: 'ratio not recorded', tone: 'warn' as const }
      : nums.length > 1 ? { text: `paralleled ratios differ — ${mine.map((m) => `${s(m.AssetName)} ${s(m.RatioInUse) || '?'}`).join(', ')}`, tone: 'bad' as const }
      : !Number.isFinite(setting) ? { text: `${s(x.SettingCode)} not set`, tone: 'warn' as const }
      : Math.abs(nums[0] - setting) <= Math.max(0.005 * nums[0], 0.01) ? { text: 'matches', tone: 'good' as const }
      : { text: `differs — ${s(x.SettingCode)} is ${setting}`, tone: 'bad' as const }
    return { code: s(x.SettingCode), verdict }
  }
  const removeInput = async (input: Row) => {
    setBusy(true); setMsg(null)
    try { await proc('scheme', 'AnalogInput_SoftDelete', { EntityId: input.EntityId }); setMsg({ text: `${s(input.InputCode)} removed.` }); refresh() }
    catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  const orphans = sources.filter((x) => !x.AnalogInputEntityId)
  const unfed = capability ? (['Current', 'Voltage', 'SyncVoltage'] as const).flatMap((k) => capability[k].slice(inputs.filter((i) => s(i.InputKind) === k && Number(i.SourceCount ?? 0) > 0).length)) : []
  return (
    <Panel title={`Feeding this protection · ${sources.length ? `${sources.length} transformer${sources.length === 1 ? '' : 's'} on ${inputs.length} input${inputs.length === 1 ? '' : 's'}` : 'none named'}`}
      actions={hasScheme && canEdit ? <Button kind={editing ? 'primary' : 'default'} onClick={() => { setEditing(!editing); setAddTo(null) }}>{editing ? 'Done' : 'Edit inputs'}</Button> : undefined}>
      {!hasScheme && <Status>This record is in no scheme, so nothing names the transformers that feed it.</Status>}
      {hasScheme && (sourcesQ.isPending || inputsQ.isPending) && <Status>Reading the scheme's inputs…</Status>}
      {hasScheme && !sourcesQ.isPending && !inputsQ.isPending && !sources.length && !inputs.length && <Status>{schemeName} names no CT or VT source yet.{canEdit ? ' Edit inputs to add one.' : ''}</Status>}
      {capability && <Status>{deviceName} takes {capability.Current.length} current input{capability.Current.length === 1 ? '' : 's'}{capability.Current.length ? ` (${capability.Current.map((x) => s(x.SettingCode)).join(', ')})` : ''}, {capability.Voltage.length} voltage{capability.Voltage.length ? ` (${capability.Voltage.map((x) => s(x.SettingCode)).join(', ')})` : ''} and {capability.SyncVoltage.length} sync voltage{capability.SyncVoltage.length ? ` (${capability.SyncVoltage.map((x) => s(x.SettingCode)).join(', ')})` : ''} — read from its settings template.</Status>}
      {inputs.length > 0 && (
        <div className="space-y-3 text-sm">
          {inputs.map((input) => {
            const mine = sources.filter((x) => s(x.AnalogInputEntityId).toLowerCase() === s(input.EntityId).toLowerCase())
            const verdict = judge(input, mine); const parallel = mine.length >= 2; const over = beyond(input); const setting = settingFor(input)
            return (
              <div key={s(input.EntityId)} className={`rounded border p-2 ${over ? 'border-amber-900' : 'border-slate-800'}`}>
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-semibold text-slate-100">{s(input.InputCode)}</span>
                  {setting && <span className="text-xs text-slate-400">· {s(setting.SettingCode)}</span>}
                  <span className="text-xs text-slate-500">{mine.length ? `${mine.length} ${mine.length === 1 ? 'transformer' : (input.InputKind === 'Current' ? 'CTs' : 'transformers')}` : 'nothing named yet'}</span>
                  {parallel && <Pill tone="accent" title="two or more CTs feed this one input: they are connected in parallel before the relay">in parallel</Pill>}
                  {verdict && <span className="flex items-center gap-1 text-slate-400">· feeds {verdict.code} <Pill tone={verdict.verdict.tone}>{verdict.verdict.text}</Pill></span>}
                  {over && <Pill tone="warn" title="the relay's settings template has no ratio setting for this input">beyond this relay's inputs — {deviceName} has {capability![s(input.InputKind)].length} {KIND_LABEL[s(input.InputKind)]}{capability![s(input.InputKind)].length ? ` (${capability![s(input.InputKind)].map((x) => s(x.SettingCode)).join(', ')})` : ''}</Pill>}
                  {!!input.Notes && <span className="text-xs text-slate-300">— {s(input.Notes)}</span>}
                </div>
                {mine.length > 0 && (
                  <table className="mt-1 w-full table-fixed text-sm">
                    {/* fixed widths so the columns line up from one input to the next (owner, 2026-09-20) */}
                    <colgroup><col className="w-[28%]" /><col className="w-[14%]" /><col className="w-[16%]" /><col className={editing ? 'w-[18%]' : 'w-[42%]'} />{editing && <col className="w-[24%]" />}</colgroup>
                    <thead><tr className="text-left text-xs uppercase tracking-wide text-slate-500"><th className="py-1 pr-2 font-normal">Transformer</th><th className="py-1 pr-2 font-normal">Ratio</th><th className="py-1 pr-2 font-normal">Status</th><th className="py-1 pr-2 font-normal">Note</th>{editing && <th className="py-1 font-normal">Actions</th>}</tr></thead>
                    <tbody>
                      {mine.map((src) => {
                        const ratio = src.Ratio == null ? NaN : Number(src.Ratio); const path = screenPath('INSTRUMENT_TRANSFORMER', s(src.AssetEntityId))
                        return (
                          <tr key={s(src.MemberEntityId)} className="border-t border-slate-800 align-top">
                            <td className="py-1 pr-2"><a className="text-sky-300 underline" href={path} onClick={(e) => { e.preventDefault(); navigate(path) }}>{s(src.AssetName)}</a>{src.WindingCode ? <span className="text-slate-200"> · {s(src.WindingCode)}</span> : <span className="text-xs text-amber-300" title="which secondary winding feeds this input is not recorded"> · winding not said</span>} <span className="text-xs text-slate-500">{s(src.AssetTypeCode)}{src.Phases != null ? ` · ${s(src.Phases) === '1' ? 'single-phase' : `${s(src.Phases)}-phase`}` : ''}</span></td>
                            <td className="py-1 pr-2 text-slate-300">{s(src.RatioInUse) ? `${s(src.RatioInUse)}${Number.isFinite(ratio) ? ` = ${ratio}` : ' (not readable)'}` : 'not recorded'}</td>
                            <td className="py-1 pr-2"><span className="flex flex-wrap gap-1">{src.IsPlaced === false && <Pill tone="neutral" title="nothing says where it stands yet — place it from its page">not placed</Pill>}{src.IsInService === false ? <Pill tone="warn">not in service</Pill> : <Pill tone="good">in service</Pill>}</span></td>
                            <td className="py-1 pr-2 text-xs text-slate-300">{s(src.Notes) || <span className="text-slate-600">—</span>}</td>
                            {editing && <td className="py-1"><SchemeSourceActions x={src} canModify={canEditScheme} canRemove={canEditScheme} onChanged={refresh} /></td>}
                          </tr>)
                      })}
                    </tbody>
                  </table>)}
                {editing && (
                  <div className="mt-2 flex flex-wrap items-center gap-2 border-t border-slate-800 pt-2 text-xs">
                    <span className="uppercase tracking-wide text-slate-500">Actions on {s(input.InputCode)}</span>
                    {input.InputKind === 'Current' && !over && <Button kind="mini" disabled={busy} onClick={() => setAddTo(addTo && s(addTo.EntityId) === s(input.EntityId) ? null : input)}>{parallel ? 'Add another paralleled CT' : mine.length ? 'Add a paralleled CT' : 'Add a CT'}</Button>}
                    {!mine.length && <Button kind="mini" disabled={busy} onClick={() => void removeInput(input)}>Remove this input</Button>}
                    {mine.length > 0 && over && <span className="text-slate-500">move its transformers off it (Remove from scheme) and it can be removed</span>}
                  </div>)}
                {editing && addTo && s(addTo.EntityId) === s(input.EntityId) && <AddSourceForm schemeEntityId={schemeId} schemeName={schemeName} inputs={inputs} sources={sources} capability={capability} deviceName={deviceName} fixedInput={input} onDone={() => { setAddTo(null); refresh() }} />}
              </div>)
          })}
        </div>)}
      {orphans.length > 0 && <Status bad>{orphans.length} source{orphans.length === 1 ? ' has' : 's have'} no analog input yet ({orphans.map((x) => s(x.AssetName)).join(', ')}) — the next deploy's catch-up gives them one.</Status>}
      {hasScheme && !inputsQ.isPending && unfed.length > 0 && (
        <ul className="mt-2 space-y-1 border-t border-slate-800 pt-2 text-sm">
          {unfed.map((x) => <li key={s(x.SettingCode)} className="text-slate-500"><span className="text-slate-300">{s(x.SettingCode)}</span> — no {KIND_LABEL[inputKindOf(x)]} input with a transformer on it feeds this setting yet{canEdit ? (editing ? '; add one below' : '; Edit inputs to add one') : ''}.</li>)}
        </ul>)}
      {editing && <AddSourceForm schemeEntityId={schemeId} schemeName={schemeName} inputs={inputs} sources={sources} capability={capability} deviceName={deviceName} onDone={refresh} />}
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      {tq.isPending && <Status>Reading the template…</Status>}
      {!tq.isPending && !tq.data && <Status>No settings template for this model, so what {deviceName} can take is not known; the inputs are shown as the scheme has them.</Status>}
    </Panel>
  )
}

/** Inputs in reading order: the current inputs by number, then voltage, then sync voltage. */
function sortInputs(rows: Row[]): Row[] {
  const rank = (x: Row) => (x.InputKind === 'Current' ? 0 : x.InputKind === 'Voltage' ? 1 : 2)
  const num = (x: Row) => Number((s(x.InputCode).match(/(\d+)$/) ?? [])[1] ?? 0)
  return [...rows].sort((a, b) => rank(a) - rank(b) || num(a) - num(b) || s(a.InputCode).localeCompare(s(b.InputCode)))
}
/** The next free code of a kind for a scheme: "Current n", "Voltage n", "Sync voltage n". */
const nextCode = (inputs: Row[], kind: string) => `${KIND_CODE[kind]} ${Math.max(0, ...inputs.filter((i) => s(i.InputKind) === kind).map((i) => Number((s(i.InputCode).match(/(\d+)$/) ?? [])[1] ?? 0))) + 1}`

/** #206/#208/#211: a transformer feeding this protection that the platform does not have — made here (asset.Asset_Add, its
 * nameplate ratio and phases) unplaced, and named the scheme's source on an analog input. WHERE it lands is decided by what
 * the relay can take (the owner, 2026-09-20): a relay with one input of the kind and that input already fed parallels the
 * set in with no question (the SEL-221F: "one possible CT input"); a relay with more inputs than the scheme has asks one
 * plain choice — paralleled into an existing input, or a separate input, named by the relay setting it would feed; a
 * model with no template asks the same choice without the names, paralleled the default. Placement is the transformer
 * page's (a yard, #202). */
function AddSourceForm({ schemeEntityId, schemeName, inputs, sources, capability, deviceName, fixedInput, onDone }: { schemeEntityId: string; schemeName: string; inputs: Row[]; sources: Row[]; capability: Record<string, Row[]> | null; deviceName: string; fixedInput?: Row; onDone: () => void }) {
  const typesQ = useViewAll('ref', 'vAssetType', {}, 'Name')
  const types = (typesQ.data ?? []).filter((t) => (fixedInput ? ['CT'] : ['CT', 'VT', 'COUPLING_CAPACITOR_VT', 'CCPD']).includes(s(t.AssetTypeCode)))
  const [type, setType] = useState('CT'); const [role, setRole] = useState('CtSource'); const [phases, setPhases] = useState('3')
  const [ratio, setRatio] = useState(''); const [name, setName] = useState(''); const [note, setNote] = useState(''); const [target, setTarget] = useState<string>('')   // an input id, or 'new'
  const [busy, setBusy] = useState(false); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const chosen = types.find((t) => s(t.AssetTypeCode) === type)
  const defsQ = useTemplateDefs(s(chosen?.DefaultTemplateDefinitionEntityId))
  const roles = type === 'CT' ? ['CtSource'] : ['VtSource', 'SyncVtSource']
  const kind = role === 'CtSource' ? 'Current' : role === 'VtSource' ? 'Voltage' : 'SyncVoltage'
  const existing = inputs.filter((i) => s(i.InputKind) === kind)
  const namesOn = (i: Row) => sources.filter((x) => s(x.AnalogInputEntityId).toLowerCase() === s(i.EntityId).toLowerCase()).map((x) => s(x.AssetName)).join(', ')
  const canTake = capability ? capability[kind].length : null                 // how many inputs of the kind the relay has; null = unknown
  const separateAllowed = canTake === null || existing.length < canTake     // a separate input only when the relay has one to spare
  const nextSetting = capability ? capability[kind][existing.length] : null
  // the choice, decided by the relay: fixed input → that; no input yet → a new one; one input and none to spare → paralleled, said; else asked
  const decided = fixedInput ? s(fixedInput.EntityId) : !existing.length ? 'new' : !separateAllowed && existing.length === 1 ? s(existing[0].EntityId) : ''
  const effective = decided || target || (existing.length ? s(existing[0].EntityId) : 'new')
  const explain = fixedInput ? `Paralleled into ${s(fixedInput.InputCode)}${namesOn(fixedInput) ? ` with ${namesOn(fixedInput)}` : ''}.`
    : !existing.length ? `The first ${KIND_LABEL[kind]} input of ${schemeName} — ${nextCode(inputs, kind)}${nextSetting ? ` (${deviceName}'s ${s(nextSetting.SettingCode)})` : ''}.`
    : decided ? `${deviceName} has one ${KIND_LABEL[kind]} input${capability ? ` (${capability[kind].map((x) => s(x.SettingCode)).join(', ')})` : ''}: this set is paralleled into ${s(existing[0].InputCode)}${namesOn(existing[0]) ? ` with ${namesOn(existing[0])}` : ''}.` : ''
  const pickType = (code: string) => { setType(code); const rs = code === 'CT' ? ['CtSource'] : ['VtSource', 'SyncVtSource']; const nr = rs.includes(role) ? role : rs[0]; setRole(nr); if (code === 'CCPD' || (code !== 'CT' && nr === 'SyncVtSource')) setPhases('1'); setTarget('') }   // #207: the S&C potential device is single-phase
  const pickRole = (x: string) => { setRole(x); if (x === 'SyncVtSource') setPhases('1'); setTarget('') }
  const suggested = `${schemeName} ${type === 'CT' ? 'CTs' : role === 'SyncVtSource' ? 'sync PT' : 'PTs'}${ratio.trim() ? ' ' + ratio.trim() : ''}`
  const make = async () => {
    if (!chosen) return
    setBusy(true); setMsg(null)
    let assetId = ''
    try {
      let inputId = effective
      if (inputId === 'new') { const made = await proc('scheme', 'AnalogInput_Add', { SchemeEntityId: schemeEntityId, InputCode: nextCode(inputs, kind), InputKind: kind }); inputId = s(made.EntityId) }
      const a = await proc('asset', 'Asset_Add', { AssetTypeCode: type, Name: (name.trim() || suggested), Status: 'InService' })
      assetId = s(a.EntityId)
      const defs = defsQ.data ?? []
      const pdef = defs.find((d) => s(d.CharacteristicKey) === 'Phases')
      if (phases && pdef) await saveAssetCharacteristic(assetId, pdef, phases)
      const windingId = await addFirstWinding(assetId, ratio, role === 'SyncVtSource' ? 'Sync' : 'Protection')   // #212: the ratio is the winding's
      await proc('scheme', 'AddSchemeMember', { SchemeEntityId: schemeEntityId, MemberKind: 'Asset', MemberEntityId: assetId, MemberRoleCode: role, IsInService: true, Notes: note.trim() || null, AnalogInputEntityId: inputId, WindingEntityId: windingId })
      const where = inputs.find((i) => s(i.EntityId) === inputId)
      setMsg({ text: `${name.trim() || suggested} now feeds ${schemeName} on ${where ? s(where.InputCode) : nextCode(inputs, kind)}; it is not placed yet — place it from its page.` })
      setRatio(''); setName(''); setNote(''); setTarget(''); onDone()
    } catch (e) {
      const why = e instanceof ApiError ? e.message : String(e)
      setMsg({ text: assetId ? `${name.trim() || suggested} was created but not finished: ${why} — open it from the Instrument transformers list.` : why, bad: true })
    } finally { setBusy(false) }
  }
  return (
    <div className={`${fixedInput ? 'mt-2 pl-3' : 'mt-2 border-t border-slate-800 pt-2'} space-y-2 text-sm`}>
      {!fixedInput && <div className="text-xs uppercase tracking-wide text-slate-500">Add a transformer feeding this protection</div>}
      <div className="flex flex-wrap items-end gap-2">
        {fixedInput && <span className="text-xs text-slate-400">A CT paralleled into {s(fixedInput.InputCode)}:</span>}
        <label className="flex flex-col gap-1 text-xs text-slate-400">Type
          <select className={`${inputClass} w-52`} value={type} disabled={busy || typesQ.isPending || !!fixedInput} onChange={(e) => pickType(e.target.value)}>
            {types.map((t) => <option key={s(t.AssetTypeCode)} value={s(t.AssetTypeCode)}>{s(t.Name)}</option>)}
          </select></label>
        {roles.length > 1 && <label className="flex flex-col gap-1 text-xs text-slate-400">Feeds as
          <select className={`${inputClass} w-36`} value={role} disabled={busy} onChange={(e) => pickRole(e.target.value)}>{roles.map((x) => <option key={x} value={x}>{sourceRoleLabel(x)}</option>)}</select></label>}
        <label className="flex flex-col gap-1 text-xs text-slate-400">Phases
          <select className={`${inputClass} w-20`} value={phases} disabled={busy} onChange={(e) => setPhases(e.target.value)}><option value="3">3</option><option value="1">1</option></select></label>
        <label className="flex flex-col gap-1 text-xs text-slate-400">Ratio in use
          <input className={`${inputClass} w-28`} value={ratio} disabled={busy} placeholder="1200:5" onChange={(e) => setRatio(e.target.value)} /></label>
        <label className="flex flex-col gap-1 text-xs text-slate-400">Name
          <input className={`${inputClass} w-64`} value={name} disabled={busy} placeholder={suggested} onChange={(e) => setName(e.target.value)} /></label>
        <label className="flex flex-col gap-1 text-xs text-slate-400">Connection note (optional)
          <input className={`${inputClass} w-64`} value={note} disabled={busy} placeholder={fixedInput ? 'e.g. the E2103-TC4 breaker side' : 'e.g. secondary winding S2'} onChange={(e) => setNote(e.target.value)} /></label>
      </div>
      {explain ? <div className="text-xs text-slate-300">{explain}</div> : (
        <div className="flex flex-col gap-1 text-xs text-slate-300">
          <span className="text-slate-500">Where does it connect?{canTake !== null ? ` ${deviceName} has ${canTake} ${KIND_LABEL[kind]} input${canTake === 1 ? '' : 's'} (${capability![kind].map((x) => s(x.SettingCode)).join(', ')}); ${schemeName} uses ${existing.length}.` : ` What ${deviceName} can take is not known (no settings template).`}</span>
          {existing.map((i) => <label key={s(i.EntityId)} className="flex items-center gap-2"><input type="radio" name="target" checked={effective === s(i.EntityId)} disabled={busy} onChange={() => setTarget(s(i.EntityId))} /> Paralleled into {s(i.InputCode)}{namesOn(i) ? ` with ${namesOn(i)}` : ''}</label>)}
          {separateAllowed && <label className="flex items-center gap-2"><input type="radio" name="target" checked={effective === 'new'} disabled={busy} onChange={() => setTarget('new')} /> A separate input — {nextCode(inputs, kind)}{nextSetting ? ` (${deviceName}'s ${s(nextSetting.SettingCode)})` : ''}</label>}
        </div>)}
      <div><Button kind="primary" disabled={busy || !chosen} onClick={() => void make()}>{fixedInput || (decided && decided !== 'new') || (!decided && effective !== 'new') ? 'Create and parallel it in' : 'Create and name as source'}</Button></div>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </div>
  )
}

/** The settings grid: the template rows given, each with the revision's value or "not set"; a value edits in place when the
 * revision is outstanding (#168 increment 2: process.SetParsedSetting reads it as the parser would — type, range, closed
 * list — closes the prior row in valid time and audits the change; the platform writes the settings file from these rows
 * at the settings step). */
function SettingsGrid({ rows: given, values, revision, editable = false, deviceId = '', relayWord = null, quiet = false }: { rows: Row[]; values: Map<string, Row>; revision: string; editable?: boolean; deviceId?: string; relayWord?: RelayWord | null; quiet?: boolean }) {
  const rows: (Row & { _v?: Row })[] = given.map((r) => ({ ...r, _v: values.get(s(r.SettingCode)) }))
  const qc = useQueryClient()
  const [edits, setEdits] = useState<Record<string, string>>({})
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  // #215: a mask row (Format mask3) unfolds to its bits — read, or the editor when the revision is outstanding. The owner
  // (2026-09-21) reached for the row's arrow before the button, so the arrow (and the row) is the one way in; no button.
  const [open, setOpen] = useState<string | null>(null)
  const isMask = (r: Row) => r.Format === 'mask3' && !!relayWord
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
        if (isMask(r)) return r._v && was ? <span className="font-mono text-slate-100">{was}</span> : <span className="text-slate-500">not set</span>
        if (editable) return <input className="w-32 rounded border border-slate-700 bg-slate-950 px-2 py-0.5 text-sm text-slate-100" value={edits[code] ?? was} placeholder="not set" aria-label={`${code} value`}
          onChange={(e) => setEdits((x) => ({ ...x, [code]: e.target.value }))} onBlur={() => void save(code, was)} onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }} />
        return r._v ? <span className={r._v.RangeCheck === 'OutOfRange' ? 'font-semibold text-amber-300' : 'text-slate-100'}>{was}</span> : <span className="text-slate-500">not set</span> },
      csv: (r) => (r._v ? s(r._v.RawValue ?? r._v.DisplayValue) : '') },
    { key: 'UnitCode', label: 'Unit', render: (r) => s(r.UnitCode) + (r.Base ? ` (${s(r.Base).toLowerCase()})` : '') },
    { key: '_range', label: 'Range', render: (r) => rangeText(r), csv: (r) => rangeText(r) },
    { key: '_flag', label: '', render: (r) => (r._v?.RangeCheck === 'OutOfRange' ? <Pill tone="bad" title={s(r._v.RangeCheckNote)}>out of range</Pill> : null), csv: (r) => s(r._v?.RangeCheck) },
    // #215 follow-up (the owner, 2026-09-21): a mask row says what THAT mask is for (its purpose from the Relay Word definition, one sentence
    // per mask), not the template's one sentence repeated ten times
    { key: 'Description', label: 'Comments', render: (r) => <span className="text-xs text-slate-400">{isMask(r) && relayWord!.masks[s(r.SettingCode)] ? relayWord!.masks[s(r.SettingCode)].purpose : s(r.Description).replace(/^§ /, '')}</span> },
  ]
  return (
    <>
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      {editable && !quiet && <Status>Outstanding revision: a value saves when you leave the field (audited as your change). The platform writes the settings file from these values when the settings step of the change commits.</Status>}
      <div className="mt-2"><DataGrid rows={rows} columns={cols} rowKey={(r) => s(r.SettingCode)} emptyText="No settings in this group."
        expandedKey={open} canExpand={isMask} onRowClick={(r) => { if (isMask(r)) setOpen(open === s(r.SettingCode) ? null : s(r.SettingCode)) }}
        detail={(r) => (open && s(r.SettingCode) === open && relayWord
          ? <MaskBits relayWord={relayWord} code={open} value={r._v ? s(r._v.RawValue ?? r._v.DisplayValue) : ''} editing={editable}
              onSave={async (v) => { await proc('process', 'SetParsedSetting', { ConfigurationFileRevisionRowId: revision, DeviceEntityId: deviceId, SettingCode: open, RawValue: v })
                setMsg({ text: `${open} saved as ${v}.` }); setOpen(null)
                qc.invalidateQueries({ queryKey: ['view', 'document', 'vParsedSettingNamed'] }); qc.invalidateQueries({ queryKey: ['rendered', revision] }) }}
              onClose={() => setOpen(null)} />
          : null)} /></div>
    </>
  )
}

/** #215: a logic mask's bits, from the relay's Relay Word (the Program.RelayWord definition seeded from the manual). Read: the
 * three rows of eight with the ticked bits named. Edit (the owner: "an editor to assist the user in selecting the appropriate
 * bits"): tick boxes with each bit's meaning, the row's hex as it changes, a hex field kept in step, the mask's purpose and
 * typical bits from the manual, a red line when a bit the manual says never to mask is ticked; Save writes the filed shape
 * ("F0 A4 00") through process.SetParsedSetting like any other value. Row 3 bit 2 is named with its -3/-4 variant. */
function MaskBits({ relayWord, code, value, editing, onSave, onClose }: { relayWord: RelayWord; code: string; value: string; editing: boolean; onSave: (v: string) => Promise<void>; onClose: () => void }) {
  const rows = relayWord.rows; const nRows = rows.length; const nBits = rows[0]?.length ?? 8
  const mask = relayWord.masks[code]
  const readable = isMaskText(value, nRows)
  const [on, setOn] = useState<boolean[]>(() => parseMask(value, nRows, nBits))
  const [hex, setHex] = useState<string>(() => (value ? formatMask(parseMask(value, nRows, nBits), nRows, nBits) : ''))
  const [busy, setBusy] = useState(false); const [err, setErr] = useState<string | null>(null)
  const variantAt = (ri: number, bi: number) => relayWord.variants.find((v) => v.row === ri + 1 && v.bit === bi + 1)
  const label = (ri: number, bi: number) => { const b = rows[ri][bi]; const v = variantAt(ri, bi); return v ? `${b.code} (${v.code} on the ${v.models})` : b.code }
  const toggle = (i: number) => { const next = on.slice(); next[i] = !next[i]; setOn(next); setHex(formatMask(next, nRows, nBits)) }
  const typeHex = (text: string) => { setHex(text); if (isMaskText(text, nRows)) setOn(parseMask(text, nRows, nBits)) }
  const neverOn = (mask?.never ?? []).filter((c) => rows.some((row, ri) => row.some((b, bi) => b.code === c && on[ri * nBits + bi])))
  const save = async () => {
    if (!isMaskText(hex, nRows)) { setErr(`Enter ${nRows} hex bytes (as ${relayWord.masks[code]?.example ?? '00 00 00'}).`); return }
    setBusy(true); setErr(null)
    try { await onSave(formatMask(parseMask(hex, nRows, nBits), nRows, nBits)) } catch (e) { setErr(e instanceof ApiError ? e.message : String(e)) } finally { setBusy(false) }
  }
  return (
    <div className="space-y-2 p-2 text-sm">
      {!readable && <Status bad>The filed value “{value}” is not {nRows} hex bytes; the bits below read it as far as they can. Saving replaces it.</Status>}
      <div>
        <table className="w-auto text-xs">
          <tbody>
            {rows.map((row, ri) => (
              <tr key={ri} className="align-top">
                <td className="pr-2 text-slate-500">Row {ri + 1}</td>
                {row.map((b, bi) => { const i = ri * nBits + bi; const isOn = on[i]; const never = editing && (mask?.never ?? []).includes(b.code)
                  return (
                    <td key={b.code} className="px-1 pb-1">
                      <label className={`flex flex-col items-center gap-0.5 rounded border px-1.5 py-1 ${isOn ? 'border-sky-700 bg-sky-900/30 text-sky-100' : 'border-slate-800 text-slate-400'} ${never && isOn ? 'border-red-700' : ''}`} title={`${label(ri, bi)} — ${b.meaning} (${b.cite})`}>
                        {editing ? <input type="checkbox" checked={isOn} disabled={busy} onChange={() => toggle(i)} aria-label={`${code} ${b.code}`} /> : <span className="font-mono">{isOn ? '1' : '0'}</span>}
                        <span className="font-mono">{b.code}</span>
                      </label>
                    </td>) })}
                <td className="pl-2 font-mono text-slate-200">{formatMask(on, nRows, nBits).split(' ')[ri]}</td>
              </tr>))}
          </tbody>
        </table>
        {/* the owner, 2026-09-21: the manual's recommendations (typical bits, cautions, testing bits) are not shown here for now — they
            stay in the definition for a later step; the mask's purpose is on its row, the never-bit warning remains */}
      </div>
      {neverOn.length > 0 && <Status bad>{mask?.neverNote || `The manual says never to mask ${neverOn.join(', ')} into ${code}.`} ({mask?.cite})</Status>}
      {editing && (
        <div className="flex flex-wrap items-center gap-2">
          <label className="flex items-center gap-2 text-xs text-slate-400">Hex<input className={`${inputClass} w-28 font-mono`} value={hex} disabled={busy} placeholder={mask?.example ?? '00 00 00'} onChange={(e) => typeHex(e.target.value)} aria-label={`${code} hex`} /></label>
          <Button kind="primary" disabled={busy} onClick={() => void save()}>{busy ? 'Saving…' : 'Save'}</Button>
          <Button disabled={busy} onClick={onClose}>Cancel</Button>
          {err && <Status bad>{err}</Status>}
        </div>)}
    </div>
  )
}

/** The settings by function: a tab per category in the template's order, every template row of the category with the
 * revision's value or "not set". The ratio settings (CTR, PTR, SPTR) are a category like any other — #205 brought them back
 * from the Analog inputs tab, which now holds the transformers that feed them. */
/** #219 (the owner, 2026-09-21): within a tab the settings are grouped by PROTECTIVE ELEMENT — "Zone 1, Zone 2 etc. with all
 * appropriate settings"; overcurrent "broken up into phase, ground" — in the element map's order, each with its outputs and what
 * supervises it (the manual's own logic). A relay whose Relay Word carries no map shows the tab as one grid, as before. Nothing hidden (#183). */
function ElementGroups({ rows, values, revision, editable, deviceId, relayWord }: { rows: Row[]; values: Map<string, Row>; revision: string; editable: boolean; deviceId: string; relayWord: RelayWord | null }) {
  const map = relayWord?.elements?.length ? relayWord : null
  if (!map) return <SettingsGrid rows={rows} values={values} revision={revision} editable={editable} deviceId={deviceId} relayWord={relayWord} />
  const order: { key: string; name: string; element: RelayElement | null }[] = [...(map.elements ?? []).map((e) => ({ key: e.key, name: e.name, element: e })), ...(map.groups ?? []).map((g) => ({ key: g.key, name: g.name, element: null as RelayElement | null }))]
  const groups = order.map((o) => ({ ...o, rows: rows.filter((r) => ownerOf(map, s(r.SettingCode))?.key === o.key) })).filter((g) => g.rows.length > 0)
  const placed = new Set(groups.flatMap((g) => g.rows.map((r) => s(r.SettingCode))))
  const rest = rows.filter((r) => !placed.has(s(r.SettingCode)))
  return (
    <div className="space-y-3">
      {groups.map((g, gi) => (
        <div key={g.key}>
          <div className="mt-2 flex flex-wrap items-baseline gap-2">
            <span className="text-sm font-semibold text-slate-100">{g.name}</span>
            {g.element && g.element.outputs.length > 0 && <span className="text-xs text-slate-400">outputs {g.element.outputs.join(', ')}</span>}
          </div>
          {g.element && supervisionLine(g.element) && <div className="text-xs text-slate-400">{supervisionLine(g.element)}</div>}
          <SettingsGrid rows={g.rows} values={values} revision={revision} editable={editable} deviceId={deviceId} relayWord={relayWord} quiet={gi > 0} />
        </div>
      ))}
      {rest.length > 0 && <div><div className="mt-2 text-sm font-semibold text-slate-100">Other</div><SettingsGrid rows={rest} values={values} revision={revision} editable={editable} deviceId={deviceId} relayWord={relayWord} quiet={groups.length > 0} /></div>}
    </div>
  )
}

/** A tab beside the template's categories that is not a settings category (#216 follow-up: the relay's Hardware). */
export interface ExtraTab { key: string; label: string; render: () => ReactNode }

export function SettingsByFunction({ template, parsed, parseStatus, parseError, revision, filedText, editable = false, deviceId = '', extraTabs = [], showListing = true }: { template: Template; parsed: Row[]; parseStatus: string; parseError: string; revision: string; filedText: string | null; editable?: boolean; deviceId?: string; extraTabs?: ExtraTab[]; showListing?: boolean }) {
  const values = useMemo(() => new Map(parsed.map((p) => [s(p.SettingCode), p])), [parsed])
  const bookRows = template.rows
  const rwQ = useRelayWord(template.key)   // #215: the relay's Relay Word, when a definition names this template
  const categories = useMemo(() => { const seen: string[] = []; for (const r of bookRows) { const c = s(r.Category) || 'Settings'; if (!seen.includes(c)) seen.push(c) } return seen }, [bookRows])
  const [tab, setTab] = useState(categories[0] ?? '')
  const current = tab || categories[0] || ''
  const rows = bookRows.filter((r) => (s(r.Category) || 'Settings') === current)
  const unmatched = parseError && /not in the template: ([^;]+)/.exec(parseError)?.[1]
  return (
    <Panel title={`Settings · ${template.name}`} actions={<>{parseStatus && <Pill tone={parseStatus === 'Parsed' ? 'good' : parseStatus === 'Partial' ? 'warn' : 'neutral'}>{parseStatus}</Pill>}
      {parsed.length > 0 && <a className="text-xs text-sky-300 underline" href={`/api/v1/settings/${revision}/rendered`} target="_blank" rel="noopener">the settings file as the platform writes it</a>}</>}>
      {unmatched && <Status bad>Names in the filed text that the template does not know: {unmatched}</Status>}
      <Tabs tabs={[...categories.map((c) => ({ key: c, label: c.length > 42 ? c.slice(0, 40) + '…' : c })), ...extraTabs.map((x) => ({ key: x.key, label: x.label }))]} value={current} onChange={setTab} />
      {extraTabs.find((x) => x.key === current)
        ? extraTabs.find((x) => x.key === current)!.render()   // the owner, 2026-09-21: "hardware should really be another tab in the settings section"
        : <ElementGroups rows={rows} values={values} revision={revision} editable={editable} deviceId={deviceId} relayWord={rwQ.data ?? null} />}
      {showListing && <RelayListingAndFile template={template} parsed={parsed} revision={revision} filedText={filedText} />}
    </Panel>
  )
}

/** The relay's listing and the file the platform writes from these values, beside the file as filed (#168). The owner,
 * 2026-09-21: it belongs with the files — the record mounts it on Files and records; the template screen keeps it under the book. */
export function RelayListingAndFile({ template, parsed, revision, filedText, bare = false }: { template: Template; parsed: Row[]; revision: string; filedText: string | null; bare?: boolean }) {
  const values = useMemo(() => new Map(parsed.map((p) => [s(p.SettingCode), p])), [parsed])
  const renderedQ = useQuery({ queryKey: ['rendered', revision], queryFn: () => getText(`/api/v1/settings/${revision}/rendered`), staleTime: 60_000, enabled: !!revision && parsed.length > 0 })
  const body = (
      <div className="mt-2 grid gap-3 lg:grid-cols-2">
        <div><h4 className="text-xs text-slate-500">Listing (the template's order, as the relay lists it)</h4><pre className="mt-1 overflow-auto rounded border border-slate-800 bg-slate-950 p-2 text-xs">{listing(template.rows, values)}</pre></div>
        <div><h4 className="text-xs text-slate-500">The file the platform writes{renderedQ.data != null && filedText != null ? (renderedQ.data === filedText ? ' — identical to the file as filed' : ' — differs from the file as filed (order or spelling; the values are what was parsed)') : ''}</h4>
          <pre className="mt-1 max-h-64 overflow-auto rounded border border-slate-800 bg-slate-950 p-2 text-xs whitespace-pre-wrap">{!revision || !parsed.length ? 'no revision' : renderedQ.isPending ? '…' : renderedQ.isError ? 'not available' : renderedQ.data}</pre></div>
      </div>)
  if (bare) return body
  return (
    <details className="mt-3">
      <summary className="cursor-pointer text-xs font-semibold uppercase tracking-wide text-slate-400">Relay listing and the file</summary>
      {body}
    </details>
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
      <SettingsByFunction template={tq.data} parsed={parsed} parseStatus={s(r.ParseStatus)} parseError={s(r.ParseError)} revision={revision} filedText={filedText} editable={editable} deviceId={s(r.DeviceEntityId)} showListing={false} />
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
