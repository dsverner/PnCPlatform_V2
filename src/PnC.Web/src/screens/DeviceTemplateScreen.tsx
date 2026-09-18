// #184 (2026-09-18): one device type's template — <MODEL>_Template. The owner: a template is one per device type, one
// level below a scheme, and it bundles everything true of the model itself. Nothing here is per model in code: every
// panel draws from what is bound to the model in the database, so a template for another relay draws the same way.
//
//   Settings        the model's settings template by the manual's own groups, none hidden (#183) — DeviceSettings.tsx
//   What it can do  scheme.vFunctionCapability, numbers as numbers and the rest as words (#181, #182)
//   Template facts  the CharacteristicSchema.AssetTemplate definition bound to this model (config.vDefinitionAppliesTo,
//                   dimension Model), its rows the model-level facts nothing else holds
//   PRC-023         the settings the loadability calculation reads (device.settings.* facts of the seeded formulas) and the
//                   rules that can attach; the calculation itself runs per device (#171)
//   NPCC A-10 / D4  the Directory 4 criteria as reading material, attaching when the protected bus is declared BPS
//
// Compliance is CALCULATED from study values on the primary elements — the CIP-002 rating, the A-10 declaration, the
// PRC-023 listing and ratings — never switched on for a device by an admin (the owner, 2026-09-18). This screen says what
// can attach and why; a relay's own Compliance tab says what does.
import { useNavigate } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { s, view, viewAll } from '@/lib/api'
import { useViewAll } from '@/lib/hooks'
import { type RecordParams, type Screen } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status } from '@/components/ui/ui'
import { useTemplate, SettingsByFunction } from './DeviceSettings'
import { bit } from './PrimaryAssetScreen'

/** The five settings the PRC-023 loadability formulas read (tools/compliance_rules.py): named there as device.settings.<code>. */
const PRC023_SETTINGS = ['Z3%', 'R1', 'X1', 'MTA', '50H']

export default function DeviceTemplateScreen({ params: p, id }: { screen: Screen; params: RecordParams; id?: string }) {
  const navigate = useNavigate()
  const modelId = id ?? ''
  const modelQ = useViewAll('ref', 'vModel', { [p.key]: modelId }, undefined, !!modelId)
  const model = modelQ.data?.[0]
  const code = s(model?.ModelCode)
  const templateKey = code.replace(/[^A-Za-z0-9]/g, '') + '_Template'
  const tmpl = useTemplate(modelId || null)
  const caps = useViewAll('scheme', 'vFunctionCapability', { ModelId: modelId }, 'AnsiCode', !!modelId)
  const names = useViewAll('ref', 'vAnsiFunction', {}, 'AnsiCode')
  // the AssetTemplate bound to this model: applies-to row → its definition version → the version's characteristic rows
  const factsQ = useQuery({ queryKey: ['assetTemplate', modelId], enabled: !!modelId, staleTime: 60_000, queryFn: async () => {
    const binds = (await view('config', 'vDefinitionAppliesTo', { DimensionCode: 'Model', ValueEntityId: modelId }, { take: 20 })).rows
    for (const b of binds) {
      const ver = (await view('config', 'vDefinitionVersion', { RowId: s(b.DefinitionVersionRowId) }, { take: 1 })).rows[0]
      if (!ver) continue
      const def = (await view('config', 'vDefinition', { EntityId: s(ver.DefinitionEntityId) }, { take: 1 })).rows[0]
      if (def && s(def.DefinitionKind) === 'CharacteristicSchema.AssetTemplate')
        return { def, rows: await viewAll('config', 'vCharacteristicDefinition', { DefinitionVersionRowId: s(ver.RowId) }, 'DisplayOrder') }
    }
    return null
  } })
  const rulesQ = useViewAll('compliance', 'vObligationRule', {}, 'DefinitionKey')
  const d4 = useQuery({ queryKey: ['npccD4'], staleTime: 60_000, queryFn: async () => {
    const sv = (await view('compliance', 'vStandardVersion', { StandardCode: 'NPCC-D4' }, { take: 5 })).rows[0]
    return sv ? await viewAll('compliance', 'vRequirement', { StandardVersionRowId: s(sv.RowId) }, 'RequirementNumber') : []
  } })

  if (modelQ.isPending) return <Status>Loading…</Status>
  if (!model) return <Status bad>No model with that id.</Status>
  const nameOf = new Map((names.data ?? []).map((a) => [s(a.AnsiCode), s(a.Name)]))
  const isNum = new Map((names.data ?? []).map((a) => [s(a.AnsiCode), bit(a.IsDeviceNumber)]))
  const prcRules = (rulesQ.data ?? []).filter((r) => s(r.DefinitionKey).startsWith('prc023'))
  const npccRule = (rulesQ.data ?? []).find((r) => s(r.DefinitionKey) === 'npcc_d4')
  const settingRows = tmpl.data?.rows ?? []
  const prcInputs = PRC023_SETTINGS.map((c) => ({ code: c, row: settingRows.find((r) => s(r.SettingCode) === c) }))

  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center gap-2">
        <h1 className="text-xl font-semibold text-slate-100">{templateKey}</h1>
        <Pill tone="accent">{code}</Pill>
        <span className="text-sm text-slate-400">{s(model.ModelName)}</span>
        <div className="ml-auto"><Button onClick={() => navigate(-1)}>Close</Button></div>
      </header>
      <Status>One template per device type, one level below a scheme. What is shown here is true of every {code}; what a particular relay does, and which obligations bind it, is on that relay's own record.</Status>

      <div className="grid gap-3 lg:grid-cols-2">
        <Panel title="Template facts">
          {factsQ.isPending && <Status>…</Status>}
          {!factsQ.isPending && !factsQ.data && <Status>No template definition is bound to this model yet. An administrator seeds one ({templateKey}) from the manufacturer's manual.</Status>}
          {factsQ.data && <Facts cols={1} pairs={factsQ.data.rows.map((r) => [s(r.Name), <span className="text-slate-300">{s(r.Description)}</span>] as [string, React.ReactNode])} />}
        </Panel>
        <Panel title={`What it can do · ${caps.isPending ? '…' : (caps.data ?? []).length}`}>
          {!caps.isPending && !(caps.data ?? []).length && <Status>No element list has been recorded for this model. An administrator builds it from the manufacturer's manual.</Status>}
          <ul className="grid grid-cols-1 gap-x-4 gap-y-1 text-sm md:grid-cols-2">
            {(caps.data ?? []).map((c) => { const k = s(c.AnsiCode); return (
              <li key={k} className="text-slate-200">{isNum.get(k) ? <><span className="font-mono">{k}</span> {nameOf.get(k) ?? ''}</> : (nameOf.get(k) || k)}
                <span className="ml-2 text-xs text-slate-500">{s(c.Source).toLowerCase()}</span></li>) })}
          </ul>
          <div className="mt-2"><Status>Ten carry a C37.2 device number; the rest are named in the manual's own words (#182). Ticked per position when a relay is placed.</Status></div>
        </Panel>
      </div>

      <div className="grid gap-3 lg:grid-cols-2">
        <Panel title="PRC-023 — transmission relay loadability">
          <Status>Calculated from this relay's settings and the protected line's ratings and terminal voltage (#171). It attaches when the line is 200 kV and above or on the Planning Authority's list, and the criterion the settings satisfy decides which requirement binds.</Status>
          <div className="mt-2 text-xs uppercase tracking-wide text-slate-500">The settings the calculation reads</div>
          <ul className="mt-1 text-sm">
            {prcInputs.map(({ code: c, row }) => (
              <li key={c} className="flex gap-2"><span className="w-14 font-mono text-slate-200">{c}</span>
                <span className="text-slate-300">{row ? s(row.Name) : <span className="text-amber-300">not in this model's settings template</span>}</span>
                {row && <span className="text-xs text-slate-500">{s(row.Category)}</span>}</li>))}
          </ul>
          <div className="mt-2 text-xs uppercase tracking-wide text-slate-500">The rules that can attach</div>
          <ul className="mt-1 text-sm">
            {prcRules.map((r) => <li key={s(r.DefinitionKey)} className="text-slate-300"><span className="text-slate-200">{s(r.Name)}</span><span className="ml-2 font-mono text-xs text-slate-500">{s(r.ScopeText)}</span></li>)}
          </ul>
        </Panel>
        <Panel title={`NPCC A-10 / Directory 4 — protection design criteria · ${d4.isPending ? '…' : (d4.data ?? []).length}`}>
          <Status>No effect on settings, a large effect on the physical design of the protection. Attaches when the bus this relay protects is declared BPS by the A-10 study; the criteria are then reading material on the relay's Compliance tab, with the evidence — the design and its TFSP submittal — held outside the platform.</Status>
          {npccRule && <div className="mt-1 font-mono text-xs text-slate-500">{s(npccRule.ScopeText)}</div>}
          {!d4.isPending && !(d4.data ?? []).length && <Status bad>Directory 4 is not seeded on this database.</Status>}
          <ul className="mt-2 max-h-80 space-y-1 overflow-auto text-sm">
            {(d4.data ?? []).map((r) => (
              <li key={s(r.RequirementNumber)}>
                <span className="font-mono text-slate-200">{s(r.RequirementNumber)}</span> <span className="text-slate-200">{s(r.Title)}</span>
                <div className="text-xs text-slate-400">{s(r.Summary)}</div>
              </li>))}
          </ul>
        </Panel>
      </div>

      <Panel title="Settings — by the manual's own groups, none hidden">
        {tmpl.isPending && <Status>…</Status>}
        {!tmpl.isPending && !tmpl.data && <Status>No settings template is bound to this model.</Status>}
        {tmpl.data && <SettingsByFunction template={tmpl.data} parsed={[]} parseStatus="template" parseError="" revision="" filedText={null} />}
      </Panel>
    </div>
  )
}
