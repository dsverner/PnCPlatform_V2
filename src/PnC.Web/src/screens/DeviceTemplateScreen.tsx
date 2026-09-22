// #184 (2026-09-18): one device type's template — <MODEL>_Template. The owner: a template is one per device type, one
// level below a scheme, and it bundles everything true of the model itself. Nothing here is per model in code: every
// panel draws from what is bound to the model in the database, so a template for another relay draws the same way.
//
//   Settings        FIRST — the model's settings template by the manual's own groups, none hidden (#183) — DeviceSettings.tsx
//   then, collapsed until wanted (#186, the owner: "the important, user facing stuff, at the top of the page and only show
//   the documentation when the user needs them"):
//   Template facts  the CharacteristicSchema.AssetTemplate definition bound to this model, its rows the model-level facts
//   What it can do  scheme.vFunctionCapability, numbers as numbers and the rest as words (#181, #182)
//
// #185: no compliance here. The owner: "compliance is really a function of it's own, outside of the template. That is
// PRC-023 will be compulsory, no matter what physical device we are implementing". The standards and the rules live
// under the Compliance menu for every device type; what binds a particular relay is on that relay's own record.
// Reached from the Templates menu (DEVICE_TEMPLATES lists config.vAssetTemplate) and from the model on a settings record.
import { useNavigate } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { s, view, viewAll } from '@/lib/api'
import { useViewAll } from '@/lib/hooks'
import { type RecordParams, type Screen } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status } from '@/components/ui/ui'
import { useTemplate, SettingsByFunction } from './DeviceSettings'
import { bit } from './PrimaryAssetScreen'
import { ManualPanel } from '@/components/ManualPanel'

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
  // #185: the template's Effective version for this model, through config.vAssetTemplate (Effective only, so a
  // binding an older version left behind is never read — v1's rows had shown beside v2's facts on DEV)
  const factsQ = useQuery({ queryKey: ['assetTemplate', modelId], enabled: !!modelId, staleTime: 60_000, queryFn: async () => {
    const tmplRow = (await view('config', 'vAssetTemplate', { ModelId: modelId }, { take: 5 })).rows[0]
    if (!tmplRow) return null
    return { def: tmplRow, rows: await viewAll('config', 'vCharacteristicDefinition', { DefinitionVersionRowId: s(tmplRow.DefinitionVersionRowId) }, 'DisplayOrder') }
  } })

  if (modelQ.isPending) return <Status>Loading…</Status>
  if (!model) return <Status bad>No relay model was found at this address.</Status>
  const nameOf = new Map((names.data ?? []).map((a) => [s(a.AnsiCode), s(a.Name)]))
  const isNum = new Map((names.data ?? []).map((a) => [s(a.AnsiCode), bit(a.IsDeviceNumber)]))

  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center gap-2">
        <h1 className="text-xl font-semibold text-slate-100">{templateKey}</h1>
        <Pill tone="accent">{code}</Pill>
        <span className="text-sm text-slate-400">{s(model.ModelName)}</span>
        <div className="ml-auto"><Button onClick={() => navigate(-1)}>Close</Button></div>
      </header>
      <Status>One template per device type, one level below a scheme. What is shown here is true of every {code}. Which standards apply is under Compliance. What binds one relay is on that relay's own record.</Status>


      {/* #186: the settings first — the owner: "the important, user facing stuff, at the top of the page and only show the
          documentation when the user needs them" */}
      <Panel title="Settings — by the manual's own groups, none hidden">
        {tmpl.isPending && <Status>…</Status>}
        {!tmpl.isPending && !tmpl.data && <Status>No settings list is loaded for this model yet. An administrator builds it from the manufacturer's manual.</Status>}
        {tmpl.data && <SettingsByFunction template={tmpl.data} parsed={[]} parseStatus="template" parseError="" revision="" filedText={null} />}
      </Panel>

      {/* #216: the manual, kept with the template — in the page, or its own tab */}
      {factsQ.data !== undefined && <ManualPanel templateDefinitionEntityId={factsQ.data ? s(factsQ.data.def.DefinitionEntityId) : null} modelName={code} />}

      {/* #186: the documentation, closed until wanted */}
      <details className="rounded border border-slate-800">
        <summary className="cursor-pointer select-none px-3 py-2 text-xs font-semibold uppercase tracking-wider text-slate-400 hover:text-slate-200">About this template — its facts and what the relay can do</summary>
        <div className="p-3">
        <div className="grid gap-3 lg:grid-cols-2">
          <Panel title="Template facts">
            {factsQ.isPending && <Status>…</Status>}
            {!factsQ.isPending && !factsQ.data && <Status>No facts are recorded for this model yet. An administrator builds them from the manufacturer's manual.</Status>}
            {factsQ.data && <Facts cols={1} pairs={factsQ.data.rows.map((r) => [s(r.Name), <span className="text-slate-300">{s(r.Description)}</span>] as [string, React.ReactNode])} />}
          </Panel>
          <Panel title={`What it can do · ${caps.isPending ? '…' : (caps.data ?? []).length}`}>
            {!caps.isPending && !(caps.data ?? []).length && <Status>No element list has been recorded for this model. An administrator builds it from the manufacturer's manual.</Status>}
            <ul className="grid grid-cols-1 gap-x-4 gap-y-1 text-sm md:grid-cols-2">
              {(caps.data ?? []).map((c) => { const k = s(c.AnsiCode); return (
                <li key={k} className="text-slate-200">{isNum.get(k) ? <><span className="font-mono">{k}</span> {nameOf.get(k) ?? ''}</> : (nameOf.get(k) || k)}
                  <span className="ml-2 text-xs text-slate-500">{s(c.Source).toLowerCase()}</span></li>) })}
            </ul>
            {/* #182: ten of the functions carry a C37.2 device number; the rest keep the manual's own names */}
            <div className="mt-2"><Status>Ten carry a C37.2 device number. The rest are named in the manual's own words. Ticked per position when a relay is placed.</Status></div>
          </Panel>
        </div>
        </div>
      </details>
    </div>
  )
}
