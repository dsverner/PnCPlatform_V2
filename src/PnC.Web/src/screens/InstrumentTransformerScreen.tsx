// #201 (2026-09-19): an instrument transformer as equipment in its own right — the vision §4.3 (auxiliary equipment
// first-class in Phase 1: "a relay setting is expressed against the instrument transformers that feed it") and §10.1
// (CTs and PTs/VTs are Hybrid: one foot at primary voltage). The owner, 2026-09-19: "Instrument transformers should be first
// class devices in their own right with testing (saturation curves, ratio and polarity etc.)."
// What the page shows: what it is and where it is, its nameplate (the CT_Template / VT_Template characteristics, editable),
// the schemes it feeds as CT or VT source (and a way to add one), and its tests — which are #202's. Plain React (#167);
// the INSTRUMENT_TRANSFORMER definition names asset.vInstrumentTransformer and this component reads it.
import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router'
import { ApiError, fmtDate, proc, s, type Row } from '@/lib/api'
import { useCan, useViewAll } from '@/lib/hooks'
import { type RecordParams, type Screen, screenPath } from '@/lib/screens'
import { Panel, Pill, Button, Facts, Status, inputClass } from '@/components/ui/ui'
import { AssetCharacteristics } from '@/components/CharacteristicsPanel'
import { NodeLink } from './PrimaryAssetScreen'

/** The asset types this page and the location page treat as instrument transformers (the set asset.vInstrumentTransformer lists). */
export const INSTRUMENT_TRANSFORMER_TYPES = ['CT', 'VT', 'CT_AUX', 'VT_AUX', 'COUPLING_CAPACITOR_VT', 'CCPD', 'METERING_UNIT']
/** Which source role an instrument transformer plays in a scheme: current types feed as CT source, voltage types as VT source. */
export const sourceRoleFor = (assetTypeCode: string) => (['CT', 'CT_AUX', 'METERING_UNIT'].includes(assetTypeCode) ? 'CtSource' : 'VtSource')

export default function InstrumentTransformerScreen({ params: p, id }: { screen: Screen; params: RecordParams; id?: string }) {
  const navigate = useNavigate(); const can = useCan()
  const rowQ = useViewAll('asset', 'vInstrumentTransformer', { [p.key]: id ?? '' }, undefined, !!id)
  const r = rowQ.data?.[0]
  const typeQ = useViewAll('ref', 'vAssetType', { AssetTypeCode: s(r?.AssetTypeCode) }, undefined, !!r)
  if (!id) return <Status bad>No instrument transformer in the address.</Status>
  if (rowQ.isPending) return <Status>Loading the instrument transformer…</Status>
  if (!r) return <Status bad>No instrument transformer with that id is readable by you.</Status>
  const editable = can('Asset.Modify')
  const template = s(typeQ.data?.[0]?.DefaultTemplateDefinitionEntityId)
  return (
    <div className="space-y-3">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2"><h1 className="text-lg font-semibold text-slate-100">{s(r.Name)}</h1><Pill tone="accent">{s(r.AssetTypeName)}</Pill><Pill tone={r.Status === 'InService' ? 'good' : 'neutral'}>{s(r.Status)}</Pill></div>
        <div className="flex gap-2"><Button onClick={() => navigate(-1)}>Close</Button></div>
      </header>
      <div className="grid gap-3 lg:grid-cols-2">
        <Panel title="Equipment">
          <Facts cols={1} pairs={[['Type', <span>{s(r.AssetTypeName)} <span className="text-xs text-slate-500">{s(r.AssetClassCode)} — {r.AssetClassCode === 'Hybrid' ? 'one foot at primary voltage' : 'on the secondary circuit'}</span></span>],
            ['Serial number', s(r.SerialNumber) || '—'], ['Model', s(r.ModelCode) || '—'],
            ['Placed at', r.NodeEntityId ? <span><NodeLink id={s(r.NodeEntityId)} name={s(r.NodeName)} /> <span className="text-xs text-slate-500">{s(r.NodeTypeCode)} · {s(r.PlacementKind)}</span></span> : <span className="text-slate-500">not placed — nothing says where this transformer is</span>],
            ['Station', r.StationNodeEntityId ? <NodeLink id={s(r.StationNodeEntityId)} name={s(r.StationName)} /> : '—'],
            ['Commissioned', r.CommissionedAt ? fmtDate(r.CommissionedAt) : '—'], ['Notes', s(r.Notes) || '—']]} />
          <Status>Placed at a bay, an equipment position, a yard or a panel from that location's page. The ratio a relay setting is checked against is the nameplate's <em>Ratio in use</em>.</Status>
        </Panel>
        <Feeds r={r} editable={can('Scheme.Modify')} />
      </div>
      <AssetCharacteristics assetEntityId={s(r.EntityId)} definitionEntityId={template} editable={editable}
        emptyNote={typeQ.isPending ? 'Loading the type…' : `The type ${s(r.AssetTypeCode)} names no nameplate template yet.`} />
      <Panel title="Tests">
        <Status>Ratio, polarity and excitation (saturation) curve tests are the next increment (#202): a test plan per kind, recorded against this transformer with its readings, so the relay's commissioning package can cite them. Nothing is recorded here yet.</Status>
      </Panel>
    </div>
  )
}

/** The schemes this transformer feeds, with its role, and a way to add one: the schemes at its station, the role its type implies. */
function Feeds({ r, editable }: { r: Row; editable: boolean }) {
  const qc = useQueryClient(); const navigate = useNavigate()
  const asset = s(r.EntityId)
  const feedsQ = useViewAll('scheme', 'vSchemeSource', { AssetEntityId: asset }, undefined, !!asset)
  const schemesQ = useViewAll('scheme', 'vSchemeStation', { StationNodeEntityId: s(r.StationNodeEntityId) }, 'SchemeName', !!r.StationNodeEntityId && editable)
  const [scheme, setScheme] = useState(''); const [busy, setBusy] = useState(false); const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null)
  const role = sourceRoleFor(s(r.AssetTypeCode))
  const rows = feedsQ.data ?? []
  const add = async () => {
    if (!scheme) return
    setBusy(true); setMsg(null)
    try {
      await proc('scheme', 'AddSchemeMember', { SchemeEntityId: scheme, MemberKind: 'Asset', MemberEntityId: asset, MemberRoleCode: role, IsInService: true })
      setMsg({ text: `${s(r.Name)} now feeds ${s((schemesQ.data ?? []).find((x) => s(x.SchemeEntityId) === scheme)?.SchemeName)} as ${role === 'CtSource' ? 'CT source' : 'VT source'}.` })
      setScheme(''); qc.invalidateQueries({ queryKey: ['view', 'scheme'] }); qc.invalidateQueries({ queryKey: ['view', 'asset'] })
    } catch (e) { setMsg({ text: e instanceof ApiError ? e.message : String(e), bad: true }) } finally { setBusy(false) }
  }
  return (
    <Panel title={`Feeds · ${feedsQ.isPending ? '…' : rows.length}`}>
      {!feedsQ.isPending && !rows.length && <Status>No scheme names this transformer as a source yet. A relay's CTR or PTR can only be checked once it does.</Status>}
      {rows.length > 0 && (
        <ul className="space-y-1 text-sm">
          {rows.map((x) => <li key={s(x.MemberEntityId)}><SchemeName id={s(x.SchemeEntityId)} onOpen={() => navigate(screenPath('SCHEME', s(x.SchemeEntityId)))} /> <span className="text-xs text-slate-500">{x.MemberRoleCode === 'CtSource' ? 'CT source' : 'VT source'}{x.IsInService === false ? ' · not in service' : ''}{x.RatioInUse ? ` · ${s(x.RatioInUse)}${x.Ratio != null ? ` = ${s(x.Ratio)}` : ' (ratio not read)'}` : ''}</span></li>)}
        </ul>)}
      {editable && !!r.StationNodeEntityId && (
        <div className="mt-2 flex flex-wrap items-end gap-2 border-t border-slate-800 pt-2 text-sm">
          <label className="flex flex-col gap-1 text-xs text-slate-400">Feed a scheme at {s(r.StationName)} as {role === 'CtSource' ? 'CT source' : 'VT source'}
            <select className={`${inputClass} w-72`} value={scheme} disabled={busy} onChange={(e) => setScheme(e.target.value)}>
              <option value="">{schemesQ.isPending ? '…' : 'choose a scheme'}</option>
              {(schemesQ.data ?? []).map((x) => <option key={s(x.SchemeEntityId)} value={s(x.SchemeEntityId)}>{s(x.SchemeName)}</option>)}
            </select></label>
          <Button kind="primary" disabled={busy || !scheme} onClick={() => void add()}>Add as source</Button>
        </div>)}
      {editable && !r.StationNodeEntityId && <Status>Place the transformer first; the schemes offered are its station's.</Status>}
      {msg && <Status bad={msg.bad}>{msg.text}</Status>}
    </Panel>
  )
}

function SchemeName({ id, onOpen }: { id: string; onOpen: () => void }) {
  const q = useViewAll('scheme', 'vScheme', { EntityId: id }, undefined, !!id)
  const name = s(q.data?.[0]?.Name) || id.slice(0, 8)
  return <a className="text-sky-300 underline" href={screenPath('SCHEME', id)} onClick={(e) => { e.preventDefault(); onOpen() }}>{name}</a>
}
