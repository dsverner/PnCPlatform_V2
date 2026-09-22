// The one route for every defined screen (#165): /s/:key[/:id]. The definition names the kind; the kind is the component.
import { useParams } from 'react-router'
import { useScreens, type Screen, type SettingsBookParams, type ListParams, type WorkItemParams, type StepParams, type RecordParams } from '@/lib/screens'
import { Status } from '@/components/ui/ui'
import SettingsBookScreen from '@/screens/SettingsBookScreen'
import ListScreen from '@/screens/ListScreen'
import WorkItemScreen from '@/screens/WorkItemScreen'
import StepScreen from '@/screens/StepScreen'
import RecordScreen from '@/screens/RecordScreen'
import SchemeScreen from '@/screens/SchemeScreen'
import PrimaryAssetScreen from '@/screens/PrimaryAssetScreen'
import LocationScreen from '@/screens/LocationScreen'
import DeviceTemplateScreen from '@/screens/DeviceTemplateScreen'
import InstrumentTransformerScreen from '@/screens/InstrumentTransformerScreen'
import LocationsScreen from '@/screens/LocationsScreen'
import ReferenceDataScreen from '@/screens/ReferenceDataScreen'
import ComplianceEvaluationScreen from '@/screens/ComplianceEvaluationScreen'

export default function ScreenPage() {
  const { key = '', id } = useParams()
  const q = useScreens()
  if (q.isPending) return <Status>Loading the screen…</Status>
  if (q.isError) return <Status bad>The screens could not be loaded: {(q.error as Error).message}</Status>
  const screen = q.data.find((x) => x.key === key)
  if (!screen) return <Status bad>There is no screen here, or you may not open it.</Status>
  return <ScreenBody screen={screen} id={id} />
}

function ScreenBody({ screen, id }: { screen: Screen; id?: string }) {
  switch (screen.screenKind) {
    case 'settingsBook': return <SettingsBookScreen screen={screen} params={screen.params as SettingsBookParams} />
    // #173: the locations index is plain code — the generic list cannot join a station to the buildings inside it
    case 'list': return screen.key === 'LOCATIONS' ? <LocationsScreen />
      : (screen.params as { view?: string }).view === 'ref.vVoltageClass' ? <ReferenceDataScreen screen={screen} params={screen.params as ListParams} id={id} />   // #210: the reference lists, kept from their own page
      : (screen.params as { view?: string }).view === 'compliance.vEvaluationQueue' ? <ComplianceEvaluationScreen screen={screen} />   // #214: how compliance keeps itself evaluated
      : <ListScreen screen={screen} params={screen.params as ListParams} />
    case 'workItem': return <WorkItemScreen screen={screen} params={screen.params as WorkItemParams} id={id} />
    case 'step': return <StepScreen screen={screen} params={screen.params as StepParams} id={id} />
    case 'record': {
      // #170: the record kind names its view; the view names the plain-React component (a one-off screen each, the #167 rule)
      const rp = screen.params as RecordParams
      if (rp.view === 'scheme.vScheme') return <SchemeScreen screen={screen} params={rp} id={id} />
      if (rp.view === 'asset.vPrimaryAsset') return <PrimaryAssetScreen screen={screen} params={rp} id={id} />
      if (rp.view === 'location.vNode') return <LocationScreen screen={screen} params={rp} id={id} />  // #173: any node of the location tree
      if (rp.view === 'ref.vModel') return <DeviceTemplateScreen screen={screen} params={rp} id={id} />  // #184: a device type's template
      if (rp.view === 'asset.vInstrumentTransformer') return <InstrumentTransformerScreen screen={screen} params={rp} id={id} />  // #201: a CT, VT … as equipment
      return <RecordScreen screen={screen} params={rp} id={id} />
    }
    // the screen kind, the key and the id are ours; the person is told what to do (#221)
    default: return <Status bad>This screen cannot be shown here. Ask an administrator to check how it is set up.</Status>
  }
}
