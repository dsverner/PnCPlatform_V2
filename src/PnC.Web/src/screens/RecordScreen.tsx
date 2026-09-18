// Screen kind "record" (#165, written as plain code for the settings record — the rule of 2026-09-15: a one-off screen is
// React with its constants, not a parameter grammar). The legacy flat window's content in the platform's names: the
// device, where it is, the dates and state, the classification and instrument-transformer characteristics (editable
// while the revision is a draft — the direct save with audit of #163), the notes, the parsed settings, the settings text
// as filed, the files and records, and Compare with another revision of the same device. What the platform does not
// model is said so, never invented.
import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate, useLocation } from 'react-router'
import { ApiError, fmtDate, fmtWhen, s, view, viewAll, proc, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { legacyFree, legacyDetail } from '@/lib/legacy'
import { settingsText } from '@/lib/actions'
import { type RecordParams, type Screen, splitView, screenPath } from '@/lib/screens'
import { Panel, Pill, stateTone, Button, Facts, Status, Field, Tabs, inputClass } from '@/components/ui/ui'
import { DataGrid, type Column } from '@/components/ui/data-grid'
import DeviceSettings, { useTemplate, isRatio } from './DeviceSettings'
import ComplianceTab, { useProtectedAssets } from './ComplianceTab'
import { NodeLink } from './PrimaryAssetScreen'

const CHARACTERISTIC_SCHEMA = 'SETTINGS_RECORD'   // CharacteristicSchema.RecordTemplate seeded for the settings record (#167)

export default function RecordScreen({ params: p, id }: { screen: Screen; params: RecordParams; id?: string }) {
  const [schema, vw] = splitView(p.view); const navigate = useNavigate(); const loc = useLocation(); const can = useCan()
  const rowQ = useViewAll(schema, vw, { [p.key]: id ?? '' }, undefined, !!id)
  const r = rowQ.data?.[0]
  const revision = s(r?.RevisionRowId || id)
  const parsedQ = useViewAll('document', 'vParsedSettingNamed', { ConfigurationFileRevisionRowId: revision }, 'SettingCode', !!r)
  const textQ = useQuery({ queryKey: ['settingsText', revision], queryFn: () => settingsText(revision), enabled: !!r, staleTime: 5 * 60_000 })
  const revisionsQ = useViewAll(schema, vw, { DeviceEntityId: s(r?.DeviceEntityId) }, '-CalculatedAt', !!r?.DeviceEntityId)
  const others = useMemo(() => (revisionsQ.data ?? []).filter((x) => x.RevisionRowId !== revision), [revisionsQ.data, revision])
  const templateQ = useTemplate(s(r?.ModelId) || null); const template = templateQ.data ?? null
  const [compareWith, setCompareWith] = useState('')
  const compareId = compareWith || s(others[0]?.RevisionRowId)   // #compare in the address: the newest other revision until one is chosen
  // owner, 2026-09-16: the settings, the classification, the notes, the text as filed, the files and Compare are each a tab of their
  // own — nothing sits under the settings tabs whatever tab is chosen (it read as part of the settings and confused)
  const [section, setSection] = useState(loc.hash === '#compare' ? 'compare' : loc.hash === '#files' ? 'files' : 'settings')
  if (!id) return <Status bad>No revision in the address.</Status>
  if (rowQ.isPending) return <Status>Loading the record…</Status>
  if (rowQ.isError) return <Status bad>Could not load: {(rowQ.error as Error).message}</Status>
  if (!r) return <Status bad>No settings record with that revision is readable by you.</Status>
  const parsed = parsedQ.data ?? []
  const back = () => (r.StationNodeEntityId ? navigate(screenPath('SETTINGS_BOOK') + `?StationNodeEntityId=${r.StationNodeEntityId}&GridState=${r.GridState}`) : navigate(screenPath('SETTINGS_BOOK')))
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2"><h1 className="text-lg font-semibold text-slate-100">{legacyFree(r.DeviceName)} — rev {s(r.RevisionLabel) || '?'}</h1><Pill tone={stateTone(r.GridState)}>{s(r.GridState)}</Pill></div>
        <div className="flex flex-wrap gap-2">
          {!!r.WorkRequestEntityId && <Button onClick={() => navigate(screenPath('WORK_ITEM', s(r.WorkRequestEntityId)))}>Change request</Button>}
          <Button disabled={!others.length} title={others.length ? undefined : 'This device has no other revision'} onClick={() => { setSection('compare'); if (!compareWith && others[0]) setCompareWith(s(others[0].RevisionRowId)) }}>Compare</Button>
          <Button onClick={() => setSection('files')}>Documentation</Button>
          <Button onClick={back}>Close</Button>
        </div>
      </header>
      <Status>Revision {s(r.RevisionStatus)} · lifecycle {s(r.LifecycleState) || '—'} · {s(r.FileKind)} {s(r.ParseStatus)}</Status>
      <div className="grid gap-3 lg:grid-cols-3">
        <Panel title="Device"><Facts cols={1} pairs={[['Device', legacyFree(r.DeviceName)], ['Model', <span><a className="text-sky-300 underline" href={screenPath('DEVICE_TEMPLATE', s(r.ModelId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('DEVICE_TEMPLATE', s(r.ModelId))) }} title="the device template for this model (#184)">{s(r.ModelCode)}</a>{r.ModelName ? ' — ' + s(r.ModelName) : ''}</span>], ['Manufacturer', s(r.ManufacturerName)], ['Technology', s(r.Technology)], ['Software version', s(r.FirmwareVersion)], ['Serial number', s(r.SerialNumber)], ['Voltage', s(r.VoltageClassCode)], ['Functions', s(r.Functions || r.PositionName)],
          /* #187: what the sheet is drawn from — the owner could not tell whether the relay "had a template applied" */
          ['Template', r.TemplateKey ? <span><a className="text-sky-300 underline" href={screenPath('DEVICE_TEMPLATE', s(r.ModelId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('DEVICE_TEMPLATE', s(r.ModelId))) }}>{s(r.TemplateKey)} v{s(r.TemplateVersion)}</a> <span className="text-slate-500">through the model</span></span> : <span className="text-slate-500">no template for this model yet</span>]]} /></Panel>
        <Panel title="Where"><Facts cols={1} pairs={[['Location', <NodeLink id={s(r.BuildingNodeEntityId)} name={s(r.BuildingName)} />],
          ['Scheme', r.SchemeEntityId ? <a className="text-sky-300 underline" href={screenPath('SCHEME', s(r.SchemeEntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('SCHEME', s(r.SchemeEntityId))) }}>{s(r.SchemeName)}</a> : s(r.SchemeName)],
          ['Protects', <Protects schemeEntityId={s(r.SchemeEntityId)} />], ['Equipment', s(r.PanelName)], ['Position', s(r.PositionName)],
          /* #187: placed and FLOC are two facts — a relay can be installed at a position that has no tag yet */
          ['Placed', r.PositionNodeEntityId
            ? <span>Installed at <NodeLink id={s(r.PositionNodeEntityId)} name={s(r.PositionName)} />{r.PanelName ? <>, {s(r.PanelName)}</> : null}{r.PlacedFrom ? ` since ${fmtDate(r.PlacedFrom)}` : ''}</span>
            : <span className="text-slate-500">not placed — no position holds this device</span>],
          ['FLOC', r.Floc ? <code className="rounded bg-slate-800 px-1 font-mono text-xs text-slate-200">{s(r.Floc)}</code> : <FlocMissing r={r} />]]} /></Panel>
        <Panel title="Dates and state"><Facts cols={1} pairs={[['Calculated', fmtWhen(r.CalculatedAt) + (r.CalculatedByDisplayName ? ' by ' + r.CalculatedByDisplayName : '')], ['Verified', fmtWhen(r.VerifiedAt)], ['In service', r.InServiceFrom ? fmtWhen(r.InServiceFrom) + (r.InServiceTo ? ' – ' + fmtWhen(r.InServiceTo) : ' – now') : 'not in service'], ['Change request', legacyFree(r.WorkRequestTitle)], ['Action type', s(r.WorkTypeKey)], ['Lifecycle', s(r.LifecycleState)], ['Revision', s(r.RevisionLabel) + ' · ' + s(r.RevisionStatus)]]} /></Panel>
      </div>
      <Tabs value={section} onChange={setSection} tabs={[{ key: 'settings', label: 'Settings' }, { key: 'classification', label: 'Classification' }, { key: 'compliance', label: 'Compliance' }, { key: 'notes', label: 'Notes' }, { key: 'text', label: 'Text as filed' }, { key: 'files', label: 'Files and records' }, ...(others.length ? [{ key: 'compare', label: 'Compare' }] : [])]} />
      {section === 'settings' && (template
        /* #168: the template's view of the device — functions, inputs, settings by function — when the model has one */
        ? <DeviceSettings r={r} revision={revision} filedText={textQ.data?.text ?? null} editable={r.GridState === 'Outstanding' && can('ConfigurationFile.Modify')} />
        : <Panel title={parsed.length ? `Settings · ${parsed.length} parsed from the ${s(r.FileKind)} file` : r.FileKind === 'NativeSettings' ? 'Settings · the native (vendor) file is stored as is; no reader exists for it yet (#113)' : 'Settings · no parsed settings; the text as filed is the record'}>
            {parsed.length > 0 ? <DataGrid rows={parsed} columns={PARSED_COLS} rowKey={(x) => s(x.SettingCode) + '|' + s(x.GroupNumber)} /> : <Status>No settings template for this model yet; the text as filed is the record.</Status>}
          </Panel>)}
      {/* an outstanding record is editable (owner, 2026-09-15); in service or archived is the record */}
      {section === 'classification' && <Characteristics r={r} revision={revision} editable={r.GridState === 'Outstanding' && can('Record.Modify')} hideGroups={template?.rows.some(isRatio) ? ['Instrument transformers'] : []} />}
      {/* #171: what the device is, what it inherits from the station and the protected asset, its obligations and the evaluator's working */}
      {section === 'compliance' && <ComplianceTab r={r} />}
      {section === 'notes' && <Notes r={r} revision={revision} />}
      {section === 'text' && (
        <Panel title="Settings text as filed">
          <h3 className="mt-1 text-xs font-semibold uppercase tracking-wide text-slate-400">{textQ.data ? textQ.data.name : 'file'}</h3>
          <pre className="mt-1 max-h-[32rem] overflow-auto rounded border border-slate-800 bg-slate-950 p-2 text-xs whitespace-pre-wrap">{textQ.isPending ? 'loading…' : textQ.isError ? 'The settings text could not be read: ' + (textQ.error as Error).message : textQ.data ? textQ.data.text : 'No settings file is filed for this revision.'}</pre>
        </Panel>
      )}
      {section === 'compare' && others.length > 0 && (
        <Panel title="Compare" actions={<Field label="With"><select className={inputClass} value={compareId} onChange={(e) => setCompareWith(e.target.value)}>{others.map((x) => <option key={s(x.RevisionRowId)} value={s(x.RevisionRowId)}>rev {s(x.RevisionLabel) || '?'} · {s(x.GridState)} · calculated {fmtDate(x.CalculatedAt)}{x.WorkRequestTitle ? ' · ' + legacyFree(x.WorkRequestTitle) : ''}</option>)}</select></Field>}>
          {compareId && <Compare mine={parsed} mineText={textQ.data?.text ?? ''} mineLabel={s(r.RevisionLabel)} other={others.find((x) => s(x.RevisionRowId) === compareId)!} />}
        </Panel>
      )}
      {section === 'files' && <FilesPanel r={r} revision={revision} />}
    </div>
  )
}

/** #170: what the device's scheme protects, with the primary assets' applicability classifications — the device inherits them (the owner, 2026-09-16). */
function Protects({ schemeEntityId }: { schemeEntityId: string }) {
  const navigate = useNavigate()
  const q = useProtectedAssets(schemeEntityId)   // #171: one lookup, shared with the Compliance tab
  if (!schemeEntityId) return <span className="text-slate-500">—</span>
  if (q.isPending) return <span className="text-slate-500">…</span>
  const rows = q.data ?? []
  if (!rows.length) return <span className="text-slate-500">not recorded on the scheme yet</span>
  return <span>{rows.map((a, i) => <span key={s(a.EntityId)}>{i > 0 ? '; ' : ''}<a className="text-sky-300 underline" href={screenPath('PRIMARY_ASSET', s(a.EntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('PRIMARY_ASSET', s(a.EntityId))) }}>{s(a.Name)}</a> <span className="text-xs text-slate-500">{s(a.AssetTypeName).toLowerCase()}{a.ZoneRole !== 'Primary' ? ' · ' + s(a.ZoneRole).toLowerCase() : ''}{a.Classifications ? ' · ' + s(a.Classifications) : ' · no classification recorded'}{a.HasTerminal ? ` · from terminal ${s(a.TerminalNo)} ${s(a.TerminalStation)}: ` + (a.BusName ? `bus ${s(a.BusName)} NPCC ${s(a.BusNpcc) || 'not recorded'}` : 'no bus linked') : ''}</span></span>)}</span>
}

const PARSED_COLS: Column<Row>[] = [
  { key: 'SettingCode', label: 'Setting' }, { key: 'SettingName', label: 'Name' }, { key: 'GroupNumber', label: 'Group' }, { key: 'DisplayValue', label: 'Value' }, { key: 'UnitCode', label: 'Unit' },
  { key: 'MinValue', label: 'Min' }, { key: 'MaxValue', label: 'Max' }, { key: 'RangeCheck', label: 'Range' }, { key: 'RangeCheckNote', label: 'Note' },
]

/** The classification and instrument-transformer fields (the columnless legacy fields, characteristics by the owner's ruling of
 * 2026-09-15): the schema's definitions by display group; a migrated record's values read from its summary until the values are
 * migrated; a draft revision's values saved directly (document.CharacteristicValue_Add/_Revise, audited). */
function Characteristics({ r, revision, editable, hideGroups = [] }: { r: Row; revision: string; editable: boolean; hideGroups?: string[] }) {
  const qc = useQueryClient()
  const defsQ = useQuery({ queryKey: ['characteristicSchema', CHARACTERISTIC_SCHEMA], staleTime: 10 * 60_000, queryFn: async () => {
    const d = (await view('config', 'vDefinition', { DefinitionKind: 'CharacteristicSchema.RecordTemplate', DefinitionKey: CHARACTERISTIC_SCHEMA }, { take: 1 })).rows[0]; if (!d) return []
    const v = (await view('config', 'vDefinitionVersion', { DefinitionEntityId: s(d.EntityId), Status: 'Effective' }, { take: 5 })).rows[0]; if (!v) return []
    return (await viewAll('config', 'vCharacteristicDefinition', { DefinitionVersionRowId: s(v.RowId) }, 'DisplayOrder'))
  } })
  const valuesQ = useViewAll('document', 'vCharacteristicValue', { HostRevisionRowId: revision })
  const recQ = useViewAll('record', 'vRecord', { WorkRequestEntityId: s(r.WorkRequestEntityId), RecordKindCode: 'ConfigurationFileRevision' }, undefined, !!r.WorkRequestEntityId)
  const migrated = useMemo(() => { const recs = recQ.data ?? []; const rec = recs.find((x) => s(x.SecondSubjectEntityId).toLowerCase() === revision.toLowerCase()) || (recs.length === 1 ? recs[0] : null); return rec ? legacyDetail(rec.Summary) : { notes: [], mp: [], it: [] } }, [recQ.data, revision])
  const [edits, setEdits] = useState<Record<string, string>>({}); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const defs = defsQ.data ?? []; const values = valuesQ.data ?? []
  const valueOf = (d: Row) => { const v = values.find((x) => s(x.CharacteristicDefinitionRowId).toLowerCase() === s(d.RowId).toLowerCase()); if (!v) return null; return v.TextValue ?? v.DecimalValue ?? v.IntegerValue ?? v.BooleanValue ?? v.DateTimeValue ?? v.ReferenceEntityId }
  const legacyValue = (d: Row) => migrated.mp.concat(migrated.it).find(([label]) => label.toLowerCase() === s(d.Name).toLowerCase())?.[1]
  const groups = useMemo(() => { const m = new Map<string, Row[]>(); for (const d of defs) { const g = s(d.DisplayGroup) || 'Characteristics'; if (!m.has(g)) m.set(g, []); m.get(g)!.push(d) } return m }, [defs])
  const save = async (d: Row) => {
    const text = (edits[s(d.RowId)] ?? '').trim(); if (!text) return
    const existing = values.find((x) => s(x.CharacteristicDefinitionRowId).toLowerCase() === s(d.RowId).toLowerCase())
    const typed: Row = { HostRevisionRowId: revision, CharacteristicDefinitionRowId: d.RowId }
    if (d.DataType === 'Integer') typed.IntegerValue = Number(text); else if (d.DataType === 'Decimal') typed.DecimalValue = Number(text); else if (d.DataType === 'Boolean') typed.BooleanValue = /^(1|true|yes)$/i.test(text); else typed.TextValue = text
    try {
      if (existing) await proc('document', 'CharacteristicValue_Revise', { EntityId: existing.EntityId, ...typed }); else await proc('document', 'CharacteristicValue_Add', typed)
      setMsg({ text: `${s(d.Name)} saved.` }); setEdits({ ...edits, [s(d.RowId)]: '' }); qc.invalidateQueries({ queryKey: ['view', 'document', 'vCharacteristicValue'] })
    } catch (e) { setMsg({ text: `${s(d.Name)}: ${e instanceof ApiError ? e.status + ' ' : ''}${(e as Error).message}`, bad: true }) }
  }
  if (defsQ.isPending) return <Status>Loading the characteristics…</Status>
  if (!defs.length) {
    const mp = migrated.mp.concat(migrated.it)
    return <Panel title="Classification and instrument transformers"><Facts pairs={mp.length ? mp : [['Class · use · responsibility', 'not recorded'], ['CT / PT ratios', 'not recorded']]} /><Status>No characteristic schema {CHARACTERISTIC_SCHEMA} is Effective; the migrated values are shown from the record.</Status></Panel>
  }
  return (
    <div className="grid gap-3 lg:grid-cols-2">
      {[...groups.entries()].filter(([g]) => !hideGroups.includes(g)).map(([g, list]) => (
        <Panel key={g} title={g}>
          <dl className="grid grid-cols-1 gap-x-6 gap-y-1 text-sm">
            {list.map((d) => { const v = valueOf(d); const lv = legacyValue(d); const key = s(d.RowId)
              return (
                <div key={key} className="grid grid-cols-[11rem_1fr] items-center gap-2">
                  <dt className="text-slate-400">{s(d.Name)}{d.UnitCode ? <span className="text-slate-600"> ({s(d.UnitCode)})</span> : ''}</dt>
                  <dd className="min-w-0">
                    {editable ? <div className="flex gap-1"><input className={`${inputClass} w-full`} placeholder={v != null ? s(v) : lv ? `${lv} (migrated)` : ''} value={edits[key] ?? ''} onChange={(e) => setEdits({ ...edits, [key]: e.target.value })} onBlur={() => save(d)} onKeyDown={(e) => { if (e.key === 'Enter') save(d) }} /></div>
                      : <span className={v == null && !lv ? 'text-slate-500' : 'text-slate-200'}>{v != null ? s(v) : lv ? <>{lv} <span className="text-xs text-slate-500">(migrated)</span></> : '—'}</span>}
                  </dd>
                </div>) })}
          </dl>
        </Panel>
      ))}
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
      {editable && <Status>Draft revision: a value saves when you leave the field (audited as your change).</Status>}
    </div>
  )
}

function Notes({ r, revision }: { r: Row; revision: string }) {
  const recQ = useViewAll('record', 'vRecord', { WorkRequestEntityId: s(r.WorkRequestEntityId), RecordKindCode: 'ConfigurationFileRevision' }, undefined, !!r.WorkRequestEntityId)
  const revQ = useViewAll('document', 'vRevision', { RowId: revision })
  const docQ = useViewAll('document', 'vDocument', { EntityId: s(r.DocumentEntityId) }, undefined, !!r.DocumentEntityId)
  const pairs: [string, string][] = []
  const recs = recQ.data ?? []; const rec = recs.find((x) => s(x.SecondSubjectEntityId).toLowerCase() === revision.toLowerCase()) || (recs.length === 1 ? recs[0] : null)
  if (rec) pairs.push(...legacyDetail(rec.Summary).notes)
  const rv = revQ.data?.[0]; if (rv) for (const k of ['ChangeNote', 'Notes', 'Description']) if (rv[k]) pairs.push([`Revision ${k.toLowerCase()}`, legacyFree(rv[k])])
  const d = docQ.data?.[0]; if (d) for (const k of ['Notes', 'Description']) if (d[k]) pairs.push([`Document ${k.toLowerCase()}`, legacyFree(d[k])])
  return <Panel title="Notes"><Facts cols={1} pairs={pairs.length ? pairs : [['Notes', 'none recorded']]} /></Panel>
}

/** Compare (round 5 B4): two revisions' parsed settings side by side, or their texts line by line when nothing is parsed. */
function Compare({ mine, mineText, mineLabel, other }: { mine: Row[]; mineText: string; mineLabel: string; other: Row }) {
  const otherId = s(other.RevisionRowId)
  const theirsQ = useViewAll('document', 'vParsedSettingNamed', { ConfigurationFileRevisionRowId: otherId }, 'SettingCode')
  const textQ = useQuery({ queryKey: ['settingsText', otherId], queryFn: () => settingsText(otherId), staleTime: 5 * 60_000, enabled: mine.length === 0 })
  if (theirsQ.isPending) return <Status>Comparing…</Status>
  const theirs = theirsQ.data ?? []; const label = `rev ${s(other.RevisionLabel) || '?'}`
  if (mine.length || theirs.length) {
    const key = (x: Row) => s(x.SettingCode) + '|' + s(x.GroupNumber)
    const m = new Map(mine.map((x) => [key(x), x])), t = new Map(theirs.map((x) => [key(x), x]))
    const rows = [...new Set([...m.keys(), ...t.keys()])].sort().map((k) => { const a = m.get(k), b = t.get(k); const av = a ? s(a.DisplayValue) : null, bv = b ? s(b.DisplayValue) : null; return { k, code: s((a || b)!.SettingCode), name: s((a || b)!.SettingName), group: s((a || b)!.GroupNumber), mine: av, theirs: bv, diff: av !== bv } })
    const n = rows.filter((x) => x.diff).length
    return <><Status>{n} of {rows.length} setting(s) differ between rev {mineLabel || '?'} and {label} (differences highlighted).</Status>
      <DataGrid rows={rows} rowKey={(x) => x.k} columns={[{ key: 'code', label: 'Setting' }, { key: 'name', label: 'Name' }, { key: 'group', label: 'Group' }, { key: 'mine', label: 'This revision', render: (x) => <span className={x.diff ? 'font-semibold text-amber-300' : ''}>{x.mine ?? '—'}</span> }, { key: 'theirs', label, render: (x) => <span className={x.diff ? 'font-semibold text-amber-300' : ''}>{x.theirs ?? '—'}</span> }]} /></>
  }
  if (textQ.isPending) return <Status>Comparing the texts…</Status>
  const a = mineText.split(/\r?\n/), b = (textQ.data?.text ?? '').split(/\r?\n/); const sa = new Set(a), sb = new Set(b)
  const rows = Array.from({ length: Math.max(a.length, b.length) }, (_, i) => ({ i: i + 1, mine: a[i], theirs: b[i], diff: (a[i] != null && !sb.has(a[i])) || (b[i] != null && !sa.has(b[i])) }))
  return <><Status>{rows.filter((x) => x.diff).length} line(s) present in one text and not the other (no parsed settings on either; the texts are compared line by line).</Status>
    <DataGrid rows={rows} rowKey={(x) => String(x.i)} columns={[{ key: 'i', label: 'Line' }, { key: 'mine', label: 'This revision', render: (x) => <span className={x.diff ? 'font-semibold text-amber-300' : ''}>{x.mine ?? ''}</span> }, { key: 'theirs', label, render: (x) => <span className={x.diff ? 'font-semibold text-amber-300' : ''}>{x.theirs ?? ''}</span> }]} /></>
}

/** The files and records: this revision's files, then every record of the change with its evidence files (a name opens the file — every open is a logged read, #144). */
function FilesPanel({ r, revision }: { r: Row; revision: string }) {
  const q = useQuery({ queryKey: ['recordFiles', revision, s(r.WorkRequestEntityId)], staleTime: 60_000, queryFn: async () => {
    const rows: Row[] = []
    for (const f of (await view('document', 'vFile', { RevisionRowId: revision }, { take: 100 })).rows) rows.push({ what: "this revision's file", kind: f.FileRole, name: f.FileName, mime: f.MimeType, size: f.SizeBytes, sha: f.Sha256, when: f.CreatedAt, fileRowId: f.RowId })
    if (r.WorkRequestEntityId) {
      for (const rec of (await view('record', 'vRecord', { WorkRequestEntityId: s(r.WorkRequestEntityId) }, { take: 200 })).rows) {
        const links = (await view('document', 'vRevisionLink', { SubjectKind: 'Record', SubjectEntityId: s(rec.EntityId) }, { take: 50 })).rows
        if (!links.length) { rows.push({ what: rec.RecordKindCode, kind: rec.OverallResult ?? '', name: rec.RecordKindCode === 'ConfigurationFileRevision' ? "the migrated record's detail — shown in the groups above" : legacyFree(rec.Summary), when: rec.OccurredAt }); continue }
        for (const l of links) {
          const fs = (await view('document', 'vFile', { RevisionRowId: s(l.RevisionRowId) }, { take: 50 })).rows
          if (!fs.length) rows.push({ what: rec.RecordKindCode, kind: l.LinkKind, name: `(revision ${s(l.RevisionRowId).slice(0, 8)})`, when: rec.OccurredAt })
          for (const f of fs) rows.push({ what: rec.RecordKindCode, kind: f.FileRole || l.LinkKind, name: f.FileName, mime: f.MimeType, size: f.SizeBytes, sha: f.Sha256, when: rec.OccurredAt, fileRowId: f.RowId })
        }
      }
    }
    return rows
  } })
  const rows = q.data ?? []
  return (
    <div id="files-panel"><Panel title={`Files and records · ${q.isPending ? '…' : rows.length}`}>
      <DataGrid rows={rows} rowKey={(x, ) => s(x.fileRowId) || s(x.what) + s(x.name) + s(x.when)} columns={[{ key: 'what', label: 'Record' }, { key: 'kind', label: 'Kind' },
        { key: 'name', label: 'File / summary', render: (x) => (x.fileRowId ? <a className="text-sky-300 underline" href={'/api/v1/files/' + x.fileRowId} target="_blank" rel="noopener">{s(x.name)}</a> : s(x.name)) },
        { key: 'mime', label: 'Type' }, { key: 'size', label: 'Bytes' }, { key: 'sha', label: 'SHA-256', render: (x) => (x.sha ? s(x.sha).slice(0, 12) + '…' : '') }, { key: 'when', label: 'When', render: (x) => fmtWhen(x.when) }]} emptyText={q.isPending ? 'Loading…' : 'No files.'} />
      <Status>A file name opens the file (every open is a logged read, #144). The rationale document moves to the file store in a later wave (#159).</Status>
    </Panel></div>
  )
}

/**
 * #187: why there is no FLOC, and where to put that right. The owner, 2026-09-18: "no FLOC" read as "not placed", and the
 * line must take the user "to the proper screen to enter this information". The tag is composed from the codes of the
 * position and every level above it (#175); the levels without one are named here, each a link to its own location
 * page, where the code box is. Read from location.vNode: the position, then its ancestors from Path (one read a level).
 */
function FlocMissing({ r }: { r: Row }) {
  const posId = s(r.PositionNodeEntityId)
  const q = useQuery({ queryKey: ['flocMissing', posId], enabled: !!posId, staleTime: 60_000, queryFn: async () => {
    const pos = (await view('location', 'vNode', { EntityId: posId }, { take: 1 })).rows[0]
    if (!pos) return [] as Row[]
    const ids = s(pos.Path).split('/').map((x) => x.trim()).filter(Boolean)
    const chain: Row[] = []
    for (const id of ids) { const n = (await view('location', 'vNode', { EntityId: id }, { take: 1 })).rows[0]; if (n) chain.push(n) }
    chain.push(pos)
    // location.fComposeFloc: an uncoded node starts a fresh chain below it, so a level above the FIRST coded one (the
    // Owner above "TN") is not missing anything; every uncoded level from there down breaks the tag
    const first = chain.findIndex((n) => !!s(n.Code))
    return chain.slice(first < 0 ? 0 : first).filter((n) => !s(n.Code))
  } })
  if (!posId) return <span className="text-slate-500">no tag — the device is not placed</span>
  if (q.isPending) return <span className="text-slate-500">…</span>
  const missing = q.data ?? []
  if (!missing.length) return <span className="text-slate-500">no tag yet</span>
  return (
    <span className="text-slate-400">no tag yet — no code on {missing.map((n, i) => <span key={s(n.EntityId)}>{i > 0 ? (i === missing.length - 1 ? ' and ' : ', ') : ''}<NodeLink id={s(n.EntityId)} name={`${s(n.Name)} (${s(n.NodeTypeCode)})`} /></span>)}; open one to enter it</span>
  )
}
