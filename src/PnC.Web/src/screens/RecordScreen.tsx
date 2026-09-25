// Screen kind "record" (#165, written as plain code for the settings record — the rule of 2026-09-15: a one-off screen is
// React with its constants, not a parameter grammar). The legacy flat window's content in the platform's names: the
// device, where it is, the dates and state, the classification and instrument-transformer characteristics (editable
// while the revision is a draft — the direct save with audit of #163), the notes, the parsed settings, the settings text
// as filed, the files and records, and the device's History (#220). What the platform does not
// model is said so, never invented.
import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useNavigate, useLocation } from 'react-router'
import { fmtDate, fmtWhen, s, view, type Row } from '@/lib/api'
import { useCan, useEntryState, useViewAll } from '@/lib/hooks'
import { legacyFree, legacyDetail } from '@/lib/legacy'
import { settingsText } from '@/lib/actions'
import { type RecordParams, type Screen, splitView, screenPath } from '@/lib/screens'
import { Panel, Pill, stateTone, Button, Facts, Status } from '@/components/ui/ui'
import { PreferredTabs } from '@/components/PreferredTabs'
import { openFile, downloadFile } from '@/lib/files'
import { RaiseRequest, type RaiseOpts } from '@/components/actions/RaiseRequest'

/** #222: what a person may raise from a relay's record — the settings actions, not the transformer tests. */
const SETTINGS_ACTIONS = ['SETTINGS_CHANGE', 'SETTINGS_ADD', 'SETTINGS_DELETE', 'SETTINGS_VERIFY', 'SETTINGS_CHANGE_SIMPLE']
import { RationalePanel } from '@/screens/RationalePanel'
import { DataGrid, type Column } from '@/components/ui/data-grid'
import DeviceSettings, { useTemplate, AnalogInputs, BasisPanel, RelayListingAndFile } from './DeviceSettings'
import ComplianceTab, { ProtectedAssetList } from './ComplianceTab'
import { useNodeTypeName } from '@/lib/labels'
import { NodeLink } from './PrimaryAssetScreen'
import { ManualPanel } from '@/components/ManualPanel'
import { AssetCharacteristics } from '@/components/CharacteristicsPanel'


export default function RecordScreen({ params: p, id }: { screen: Screen; params: RecordParams; id?: string }) {
  const [schema, vw] = splitView(p.view); const navigate = useNavigate(); const loc = useLocation(); const can = useCan()
  const rowQ = useViewAll(schema, vw, { [p.key]: id ?? '' }, undefined, !!id)
  const r = rowQ.data?.[0]
  const revision = s(r?.RevisionRowId || id)
  const settingsLocked = ['true', '1'].includes(s(r?.SettingsLocked).toLowerCase())   // #231: document.vSettingsRecord.SettingsLocked
  const parsedQ = useViewAll('document', 'vParsedSettingNamed', { ConfigurationFileRevisionRowId: revision }, 'SettingCode', !!r)
  const textQ = useQuery({ queryKey: ['settingsText', revision], queryFn: () => settingsText(revision), enabled: !!r, staleTime: 5 * 60_000 })
  const revisionsQ = useViewAll(schema, vw, { DeviceEntityId: s(r?.DeviceEntityId) }, '-CalculatedAt', !!r?.DeviceEntityId)
  const templateQ = useTemplate(s(r?.ModelId) || null); const template = templateQ.data ?? null
  const [raise, setRaise] = useState<RaiseOpts | null>(null)   // #220: a change is raised from the record itself, as from the settings book's menu
  // #223 (the owner, 2026-09-22): the Rationale tab is where the rationale is written and read for a change worked here.
  // It showed an empty form of formulas on records brought in from the old system, which meant nothing — those changes
  // were designed elsewhere, and the Word rationale they came with is on Files and records. So the tab follows the work:
  // offered on a change raised in the platform, not on one the migration carried over.
  const requestQ = useViewAll('work', 'vWorkRequest', { EntityId: s(r?.WorkRequestEntityId) }, undefined, !!r?.WorkRequestEntityId)
  const fromTheOldSystem = !r?.WorkRequestEntityId || !!requestQ.data?.[0]?.MigrationRunId
  const hasRationaleTab = !requestQ.isPending && !fromTheOldSystem
  // owner, 2026-09-16: the settings, the classification, the notes, the text as filed and the files are each a tab of their
  // own — nothing sits under the settings tabs whatever tab is chosen (it read as part of the settings and confused)
  const [section, setSection] = useEntryState('section', () => loc.hash === '#files' ? 'files' : 'settings')   // #189; #220: Compare is gone (the owner, 2026-09-22)
  if (!id) return <Status bad>No revision in the address.</Status>
  if (rowQ.isPending) return <Status>Loading the record…</Status>
  if (rowQ.isError) return <Status bad>Could not load: {(rowQ.error as Error).message}</Status>
  if (!r) return <Status bad>No settings record with that revision is readable by you.</Status>
  const parsed = parsedQ.data ?? []
  const back = () => (r.StationNodeEntityId ? navigate(screenPath('SETTINGS_BOOK') + `?StationNodeEntityId=${r.StationNodeEntityId}&GridState=${r.GridState}`) : navigate(screenPath('SETTINGS_BOOK')))
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        {/* #188: the owner, 2026-09-18: the title "should really be the name of the protection" — the scheme's name as recorded, the relay beneath */}
        <div className="flex items-center gap-2"><h1 className="text-lg font-semibold text-slate-100">{s(r.SchemeName) || legacyFree(r.DeviceName)}</h1><Pill tone={stateTone(r.GridState)}>{s(r.GridState)}</Pill></div>
        <div className="flex flex-wrap gap-2">
          {/* #220 (the owner, 2026-09-22): the change is raised from the record; the device's changes are on the History tab; Compare is gone */}
          {r.GridState === 'Active' && can('WorkRequest.Modify') && <Button onClick={() => setRaise({ heading: `Raise a change request — ${legacyFree(r.DeviceName)}`, title: `Settings change — ${legacyFree(r.DeviceName)}`, scopeKind: 'Asset', scopeEntityId: s(r.DeviceEntityId), defaultType: 'SETTINGS_CHANGE', workflowKey: 'SETTINGS_CHANGE_REQUEST', offer: SETTINGS_ACTIONS })}>Raise a change request</Button>}
          <Button onClick={() => setSection('history')}>History</Button>
          <Button onClick={() => setSection('files')}>Documentation</Button>
          <Button onClick={back}>Close</Button>
        </div>
      </header>
      {raise && <RaiseRequest o={raise} onClose={() => setRaise(null)} />}
      {/* #237 (the owner, 2026-09-25): facts set out as label and value, not one run of " · " */}
      <dl className="flex flex-wrap gap-x-6 gap-y-1 rounded border border-slate-800 bg-slate-900/60 px-3 py-1.5 text-sm">
        {([['Relay', legacyFree(r.DeviceName)], ['Revision', `${s(r.RevisionLabel) || '?'} (${s(r.RevisionStatus).toLowerCase()})`], ['Lifecycle', s(r.LifecycleState) || '—'],
          ['Settings file', [s(r.FileKind).replace(/([a-z])([A-Z])/g, '$1 $2').toLowerCase(), s(r.ParseStatus).toLowerCase()].filter(Boolean).join(', ') || 'none filed']] as [string, string][]).map(([k, v]) =>
          <div key={k} className="flex gap-1.5"><dt className="text-slate-500">{k}:</dt><dd className="text-slate-200">{v}</dd></div>)}
      </dl>
      {/* #226 (the owner, 2026-09-22): which of these a person keeps is theirs — defaulted by the work they do, changed
          by them, and never a way of blocking anything. The two conditional tabs keep their conditions on top of it. */}
      <PreferredTabs screenKey="SETTINGS_RECORD" value={section} onChange={setSection} tabs={[{ key: 'settings', label: 'Settings' }, ...(hasRationaleTab ? [{ key: 'rationale', label: 'Rationale' }] : []), { key: 'analog', label: 'Analog inputs' }, ...(r.TemplateDefinitionEntityId ? [{ key: 'jumpers', label: 'Jumper settings' }] : []), { key: 'record', label: 'Record' }, { key: 'history', label: 'History' }, { key: 'compliance', label: 'Compliance' }, { key: 'notes', label: 'Notes' }, { key: 'text', label: 'Settings file' }, { key: 'files', label: 'Files and records' }, { key: 'manual', label: 'Manual' }]} />
      {section === 'settings' && (template
        /* #168: the template's view of the device — functions, inputs, settings by function — when the model has one */
        ? <>
            {/* #192: a draft based on another request's draft — its drift and re-base sit first, being what the engineer must act on */}
            {/* #231 (the owner, 2026-09-23): once the settings are loaded on the relay they are not edited — the package's state says so */}
            {r.GridState === 'Outstanding' && settingsLocked && <Status>These settings have been loaded on the relay. They are not changed in this request; finish it, or raise a new change to alter them.</Status>}
            {r.GridState === 'Outstanding' && !!r.BasedOnRevisionRowId && <BasisPanel r={r} revision={revision} editable={!settingsLocked && can('ConfigurationFile.Modify')} />}
            <DeviceSettings r={r} revision={revision} filedText={textQ.data?.text ?? null} editable={r.GridState === 'Outstanding' && !settingsLocked && can('ConfigurationFile.Modify')} />
          </>
        : <Panel title={parsed.length ? `Settings · ${parsed.length} parsed from the ${s(r.FileKind)} file` : r.FileKind === 'NativeSettings' ? 'Settings · the native (vendor) file is stored as is; no reader exists for it yet (#113)' : 'Settings · no parsed settings; the text as filed is the record'}>
            {parsed.length > 0 ? <DataGrid rows={parsed} columns={PARSED_COLS} rowKey={(x) => s(x.SettingCode) + '|' + s(x.GroupNumber)} /> : <Status>No settings template for this model yet; the text as filed is the record.</Status>}
          </Panel>)}
      {/* #200 (owner, 2026-09-19): the CTs and PTs on a tab of their own; #205 (owner, 2026-09-20): only the transformers that feed
          the protection — the relay's ratio settings went back to the book; #206: the legacy declared-ratio section is retired
          (its strings became the scheme's transformers by the migration rule) and the tab adds, connects and removes sources */}
      {/* #216 (the owner, 2026-09-21): the relay's JUMPER SETTINGS — the jumper positions its manual names — a tab beside Settings and
          Analog inputs; recorded on the device, not this revision; changed under the change request; never in the settings file */}
      {section === 'jumpers' && !!r.TemplateDefinitionEntityId && <AssetCharacteristics assetEntityId={s(r.DeviceEntityId)} definitionEntityId={s(r.TemplateDefinitionEntityId)} groups={['Hardware']} title="Jumper settings"
        editable={r.GridState === 'Outstanding' && can('Asset.Modify')} workRequestEntityId={s(r.WorkRequestEntityId) || undefined}
        note="The jumpers on this relay. They are the same on every record of it, are changed here under the change request, and are not part of the settings file. Hover a name for the manual's words." />}
      {section === 'analog' && <AnalogInputs r={r} revision={revision} canEditAssets={can('Asset.Modify')} canEditScheme={can('Scheme.Modify')} />}
      {/* #188: the relay, its placement and scheme, and the dates and state — a tab, not the top of every view. The owner,
          2026-09-18: the three panels "take up too much room and should really just be another tab"; "Where" renamed */}
      {section === 'record' && (
        <>
      <div className="grid gap-3 lg:grid-cols-3">
        <Panel title="Relay"><Facts cols={1} pairs={[['Device', legacyFree(r.DeviceName)], ['Model', <span><a className="text-sky-300 underline" href={screenPath('DEVICE_TEMPLATE', s(r.ModelId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('DEVICE_TEMPLATE', s(r.ModelId))) }} title="This model's template">{s(r.ModelCode)}</a>{r.ModelName ? ' — ' + s(r.ModelName) : ''}</span>], ['Manufacturer', s(r.ManufacturerName)], ['Technology', s(r.Technology)], ['Software version', s(r.FirmwareVersion)], ['Serial number', s(r.SerialNumber)], ['Voltage', s(r.VoltageClassCode)], ['Functions', s(r.Functions || r.PositionName)],
          /* #187: what the sheet is drawn from — the owner could not tell whether the relay "had a template applied" */
          ['Template', r.TemplateKey ? <span><a className="text-sky-300 underline" href={screenPath('DEVICE_TEMPLATE', s(r.ModelId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('DEVICE_TEMPLATE', s(r.ModelId))) }}>{s(r.TemplateKey)} v{s(r.TemplateVersion)}</a> <span className="text-slate-500">through the model</span></span> : <span className="text-slate-500">no template for this model yet</span>]]} /></Panel>
        <Panel title="Placement and scheme"><Facts cols={1} pairs={[['Location', <NodeLink id={s(r.BuildingNodeEntityId)} name={s(r.BuildingName)} />],
          ['Scheme', r.SchemeEntityId ? <a className="text-sky-300 underline" href={screenPath('SCHEME', s(r.SchemeEntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('SCHEME', s(r.SchemeEntityId))) }}>{s(r.SchemeName)}</a> : s(r.SchemeName)],
          ['Protects', r.SchemeEntityId ? <ProtectedAssetList schemeEntityId={s(r.SchemeEntityId)} /> : <span className="text-slate-500">—</span>], ['Equipment', s(r.PanelName)], ['Position', s(r.PositionName)],
          /* #187: placed and FLOC are two facts — a relay can be installed at a position that has no tag yet */
          ['Placed', r.PositionNodeEntityId
            ? <span>Installed at <NodeLink id={s(r.PositionNodeEntityId)} name={s(r.PositionName)} />{r.PanelName ? <>, {s(r.PanelName)}</> : null}{r.PlacedFrom ? ` since ${fmtDate(r.PlacedFrom)}` : ''}</span>
            : <span className="text-slate-500">not placed — no position holds this device</span>],
          ['FLOC', r.Floc ? <code className="rounded bg-slate-800 px-1 font-mono text-xs text-slate-200">{s(r.Floc)}</code> : <FlocMissing r={r} />]]} /></Panel>
        <Panel title="Dates and state"><Facts cols={1} pairs={[['Calculated', fmtWhen(r.CalculatedAt) + (r.CalculatedByDisplayName ? ' by ' + r.CalculatedByDisplayName : '')], ['Verified', fmtWhen(r.VerifiedAt)], ['In service', r.InServiceFrom ? fmtWhen(r.InServiceFrom) + (r.InServiceTo ? ' – ' + fmtWhen(r.InServiceTo) : ' – now') : 'not in service'], ['Change request', legacyFree(r.WorkRequestTitle)], ['Action type', s(r.WorkTypeName) || s(r.WorkTypeKey)], ['Lifecycle', s(r.LifecycleState) || '—'], ['Revision', `${s(r.RevisionLabel)} (${s(r.RevisionStatus).toLowerCase()})`],
          /* #191: a draft copied from another request's open draft */
          ['Based on', r.BasedOnWorkRequestEntityId
            ? <span><a className="text-sky-300 underline" href={screenPath('WORK_ITEM', s(r.BasedOnWorkRequestEntityId))} onClick={(e) => { e.preventDefault(); navigate(screenPath('WORK_ITEM', s(r.BasedOnWorkRequestEntityId))) }}>{legacyFree(r.BasedOnWorkRequestTitle)}</a>
                <span className="text-slate-500">{r.BasedOnGridState === 'Outstanding' ? ' — still outstanding; this revision cannot go in service before it' : ` — ${s(r.BasedOnGridState).toLowerCase()}`}</span></span>
            : '—']]} /></Panel>
      </div>
        </>
      )}
      {/* #194: the Classification tab is gone (its eight legacy fields dropped as untrusted); the legacy instrument-transformer
          characteristics moved to the Analog inputs tab in #200 and were retired in #206 */}
      {/* #171: what the device is, what it inherits from the station and the protected asset, its obligations and the evaluator's working */}
      {section === 'compliance' && <ComplianceTab r={r} />}
      {section === 'notes' && <Notes r={r} revision={revision} />}
      {/* #225 (the owner, 2026-09-22): the three forms of the same settings sat on two tabs and read as duplicates —
          "what is the significance between Text as filed and Files and records? It seems that they are showing the same
          data in a slightly different way". They are together now: what came in, how the relay lists it, what we would write. */}
      {section === 'text' && (
        <>
        {template && <RelayListingAndFile template={template} parsed={parsed} revision={revision} filedText={textQ.data?.text ?? null} bare />}
        <Panel title="The file as filed">
          <h3 className="mt-1 text-xs font-semibold uppercase tracking-wide text-slate-400">{textQ.data ? textQ.data.name : 'file'}</h3>
          <pre className="mt-1 max-h-[32rem] overflow-auto rounded border border-slate-800 bg-slate-950 p-2 text-xs whitespace-pre-wrap">{textQ.isPending ? 'loading…' : textQ.isError ? 'The settings text could not be read: ' + (textQ.error as Error).message : textQ.data ? textQ.data.text : 'No settings file is filed for this revision.'}</pre>
        </Panel>
        </>
      )}
      {section === 'history' && <HistoryPanel r={r} revisions={revisionsQ.data ?? []} current={revision} />}   {/* #220 */}
      {section === 'files' && (
        <>
          {/* #225: the settings file, in every form, is on the Settings file tab; this tab is the documents */}
          <FilesPanel r={r} revision={revision} />
        </>)}
      {section === 'manual' && <ManualPanel templateDefinitionEntityId={s(r.TemplateDefinitionEntityId) || null} modelName={s(r.ModelName)} />}   {/* #216 */}
      {section === 'rationale' && hasRationaleTab && <RationalePanel revision={id} editable={s(r.GridState) === 'Outstanding' && !settingsLocked} />}   {/* #219, #222 */}
    </div>
  )
}

const PARSED_COLS: Column<Row>[] = [
  { key: 'SettingCode', label: 'Setting' }, { key: 'SettingName', label: 'Name' }, { key: 'GroupNumber', label: 'Group' }, { key: 'DisplayValue', label: 'Value' }, { key: 'UnitCode', label: 'Unit' },
  { key: 'MinValue', label: 'Min' }, { key: 'MaxValue', label: 'Max' }, { key: 'RangeCheck', label: 'Range' }, { key: 'RangeCheckNote', label: 'Note' },
]

/** The instrument-transformer fields (the columnless legacy CT/PT fields, characteristics by the owner's ruling of 2026-09-15;
 * the eight classification fields left in #194 — untrusted): the schema's definitions by display group; a migrated record's
 * values read from its summary until the values are migrated; a draft revision's values saved directly
 * (document.CharacteristicValue_Add/_Revise, audited). */
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

/** #220 (the owner, 2026-09-22): the device's whole history in one place — every revision with the change that made it, who asked for it and
 * when, the dates it was calculated and verified, its time in service, and the rationale it holds. A change the migration brought in is
 * marked legacy and shows the record's own dates, not the import's. Replaces Compare (a diff between revisions was ruled of no use). */
function HistoryPanel({ r, revisions, current }: { r: Row; revisions: Row[]; current: string }) {
  const navigate = useNavigate()
  const ids = useMemo(() => [...new Set(revisions.map((x) => s(x.WorkRequestEntityId)).filter(Boolean))], [revisions])
  const reqQ = useQuery({ queryKey: ['history', 'requests', ids.join(',')], enabled: ids.length > 0, staleTime: 60_000, queryFn: async () => {
    const out: Record<string, Row> = {}
    for (const id of ids) { const row = (await view('work', 'vChangeRequestStatus', { WorkRequestEntityId: id }, { take: 1 })).rows[0]; if (row) out[id] = row }
    return out
  } })
  const ratQ = useQuery({ queryKey: ['history', 'rationale', revisions.map((x) => s(x.RevisionRowId)).join(',')], enabled: revisions.length > 0, staleTime: 60_000, queryFn: async () => {
    const out: Record<string, Row> = {}
    for (const x of revisions) {
      const link = (await view('document', 'vRevisionLink', { SubjectKind: 'DocumentRevision', SubjectEntityId: s(x.RevisionRowId), LinkKind: 'About' }, { take: 5 })).rows[0]
      if (!link) continue
      const f = (await view('document', 'vFile', { RevisionRowId: s(link.RevisionRowId) }, { take: 10 })).rows.filter((y) => /\.docx?$/i.test(s(y.FileName))).pop()
      if (f) out[s(x.RevisionRowId)] = f
    }
    return out
  } })
  const rows = [...revisions].sort((a, b) => Number(b.RevisionLabel) - Number(a.RevisionLabel))
  const isLegacy = (x: Row) => /^CR \d+/.test(s(x.WorkRequestTitle))
  return (
    <Panel title={`History · ${legacyFree(r.DeviceName)} · ${rows.length} revision(s)`}>
      <DataGrid rows={rows} rowKey={(x) => s(x.RevisionRowId)} columns={[
        { key: 'RevisionLabel', label: 'Rev', render: (x) => <span>{s(x.RevisionLabel)}{s(x.RevisionRowId) === current ? ' (this one)' : ''}</span> },
        { key: 'GridState', label: 'State', render: (x) => <Pill tone={stateTone(x.GridState)}>{s(x.GridState)}</Pill> },
        { key: 'InServiceFrom', label: 'In service', render: (x) => <span>{x.InServiceFrom ? fmtDate(x.InServiceFrom) : '—'}{x.InServiceTo ? ` to ${fmtDate(x.InServiceTo)}` : x.InServiceFrom ? ' to now' : ''}</span> },
        { key: 'WorkRequestTitle', label: 'Change request', render: (x) => (x.WorkRequestEntityId
          ? <button type="button" className="text-sky-300 underline" onClick={() => navigate(screenPath('WORK_ITEM', s(x.WorkRequestEntityId)))}>{legacyFree(x.WorkRequestTitle)}{isLegacy(x) ? ' · legacy' : ''}</button>
          : <span className="text-slate-500">—</span>) },
        { key: 'RequestedBy', label: 'Requested by', render: (x) => { const q = reqQ.data?.[s(x.WorkRequestEntityId)]; return <span>{s(q?.RequestedByDisplayName) || (isLegacy(x) ? s(q?.Description).replace(/^Requested by /, '') : '') || '—'}</span> } },
        { key: 'RequestedAt', label: 'Requested', render: (x) => { const q = reqQ.data?.[s(x.WorkRequestEntityId)]; return <span>{isLegacy(x) ? 'legacy record' : q?.RequestedAt ? fmtDate(q.RequestedAt) : '—'}</span> } },
        { key: 'CalculatedAt', label: 'Calculated', render: (x) => <span>{x.CalculatedAt ? fmtDate(x.CalculatedAt) : '—'}</span> },
        { key: 'VerifiedAt', label: 'Verified', render: (x) => <span>{x.VerifiedAt ? fmtDate(x.VerifiedAt) : '—'}</span> },
        { key: 'rationale', label: 'Rationale', render: (x) => { const f = ratQ.data?.[s(x.RevisionRowId)]; return f
          ? <button type="button" className="text-sky-300 underline" onClick={() => void openFile(s(f.RowId), s(f.FileName), s(f.MimeType))}>{s(f.FileName)}</button>
          : <span className="text-slate-500">{ratQ.isPending ? '…' : 'none'}</span> } },
      ]} emptyText="No revision of this relay is on record." />
      <Status>Each row is one revision of this relay's settings: the change that made it, who asked for it, when it was calculated and verified, and its time in service. A change marked legacy came from the old program's records. The rationale opens in Word.</Status>
    </Panel>
  )
}

/** The files and records: this revision's files, then every record of the change with its evidence files (a name opens the file — every open is a logged read, #144). */
function FilesPanel({ r, revision }: { r: Row; revision: string }) {
  const q = useQuery({ queryKey: ['recordFiles', revision, s(r.WorkRequestEntityId)], staleTime: 60_000, queryFn: async () => {
    const rows: Row[] = []
    // #217: the documents About this revision — a legacy rationale as filed (frozen at this revision) — first
    for (const l of (await view('document', 'vRevisionLink', { SubjectKind: 'DocumentRevision', SubjectEntityId: revision, LinkKind: 'About' }, { take: 20 })).rows) {
      const rev = (await view('document', 'vRevision', { RowId: s(l.RevisionRowId) }, { take: 1 })).rows[0]
      const doc = rev ? (await view('document', 'vDocument', { EntityId: s(rev.DocumentEntityId) }, { take: 1 })).rows[0] : null
      const cls = doc ? (await view('config', 'vDefinition', { EntityId: s(doc.DocumentClassDefinitionEntityId) }, { take: 1 })).rows[0] : null
      const what = s(cls?.DefinitionKey) === 'Rationale' ? (doc?.MigrationRunId ? 'Rationale (legacy, as filed)' : 'Rationale') : s(cls?.Name) || 'document'
      for (const f of (await view('document', 'vFile', { RevisionRowId: s(l.RevisionRowId) }, { take: 10 })).rows)
        rows.push({ what, kind: f.FileRole, name: f.FileName, mime: f.MimeType, size: f.SizeBytes, sha: f.Sha256, when: f.CreatedAt, fileRowId: f.RowId, note: s(doc?.Description) })
    }
    // #220: the revision's own settings file is on the Settings tab (the file the platform writes) and the Text as filed tab, not here
    if (r.WorkRequestEntityId) {
      for (const rec of (await view('record', 'vRecord', { WorkRequestEntityId: s(r.WorkRequestEntityId) }, { take: 200 })).rows) {
        const links = (await view('document', 'vRevisionLink', { SubjectKind: 'Record', SubjectEntityId: s(rec.EntityId) }, { take: 50 })).rows
        if (rec.RecordKindCode === 'ConfigurationFileRevision') continue   // #220: the migrated record's detail is on the Record tab
        if (!links.length) { rows.push({ what: rec.RecordKindCode, kind: rec.OverallResult ?? '', name: legacyFree(rec.Summary), when: rec.OccurredAt }); continue }
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
  const [fileErr, setFileErr] = useState('')
  const hasRationale = rows.some((x) => s(x.what).startsWith('Rationale'))
  // #217: the importer's note on a rationale (where it was filed, why it sits on this revision) follows the path in the document's description
  const noteOf = (d: unknown) => { const i = s(d).indexOf('; '); return i >= 0 ? s(d).slice(i + 2) : '' }
  const trackQ = useViewAll('work', 'vChangeRequestStatus', { WorkRequestEntityId: s(r.WorkRequestEntityId) }, undefined, !!r.WorkRequestEntityId && !q.isPending && !hasRationale)
  const docTrack = s(trackQ.data?.[0]?.DocumentationStatus)
  return (
    <div id="files-panel"><Panel title={`Files and records · ${q.isPending ? '…' : rows.length}`}>
      {!q.isPending && !hasRationale && docTrack === 'NA' && <Status>No rationale was written for this change in the old program (its documentation track reads NA).</Status>}
      {!q.isPending && !hasRationale && docTrack && docTrack !== 'NA' && <Status>No rationale document is held for this revision. The old program's documentation track reads {docTrack}; the document folder we have covers stations E to W only.</Status>}
      <DataGrid rows={rows} rowKey={(x, ) => s(x.fileRowId) || s(x.what) + s(x.name) + s(x.when)} columns={[{ key: 'what', label: 'Record' }, { key: 'kind', label: 'Kind' },
        { key: 'name', label: 'File / summary', render: (x) => (<>{x.fileRowId ? <><button type="button" className="text-sky-300 underline" onClick={() => void openFile(s(x.fileRowId), s(x.name), s(x.mime)).catch((e) => setFileErr(e instanceof Error ? e.message : String(e)))}>{s(x.name)}</button>{/^application\/(msword|vnd\.openxmlformats)/i.test(s(x.mime)) && <button type="button" className="ml-2 text-xs text-slate-400 underline" title="Save the file instead of opening it in Word" onClick={() => void downloadFile(s(x.fileRowId), s(x.name)).catch((e) => setFileErr(e instanceof Error ? e.message : String(e)))}>save</button>}</> : s(x.name)}{noteOf(x.note) && <span className="ml-2 text-xs text-slate-400">{noteOf(x.note)}</span>}</>) },
        { key: 'mime', label: 'Type' }, { key: 'size', label: 'Bytes' }, { key: 'sha', label: 'SHA-256', render: (x) => (x.sha ? s(x.sha).slice(0, 12) + '…' : '') }, { key: 'when', label: 'When', render: (x) => fmtWhen(x.when) }]} emptyText={q.isPending ? 'Loading…' : 'No files.'} />
      {fileErr && <Status bad>{fileErr}</Status>}
      <Status>Click a file name to open it. A Word document opens in Word (the browser asks once); “save” keeps a copy instead. A rationale from the old program stays as it was filed; a new change gets its rationale from the Rationale tab.</Status>
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
  const nodeTypeName = useNodeTypeName()
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
    <span className="text-slate-400">no tag yet — no code on {missing.map((n, i) => <span key={s(n.EntityId)}>{i > 0 ? (i === missing.length - 1 ? ' and ' : ', ') : ''}<NodeLink id={s(n.EntityId)} name={`${s(n.Name)} (${nodeTypeName(n.NodeTypeCode).toLowerCase()})`} /></span>)}; open one to enter it</span>
  )
}
