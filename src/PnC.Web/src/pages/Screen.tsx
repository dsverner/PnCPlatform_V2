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
import StationScreen from '@/screens/StationScreen'

export default function ScreenPage() {
  const { key = '', id } = useParams()
  const q = useScreens()
  if (q.isPending) return <Status>Loading the screen…</Status>
  if (q.isError) return <Status bad>The screens could not be read: {(q.error as Error).message}</Status>
  const screen = q.data.find((x) => x.key === key)
  if (!screen) return <Status bad>No screen named {key} is defined for you.</Status>
  return <ScreenBody screen={screen} id={id} />
}

function ScreenBody({ screen, id }: { screen: Screen; id?: string }) {
  switch (screen.screenKind) {
    case 'settingsBook': return <SettingsBookScreen screen={screen} params={screen.params as SettingsBookParams} />
    case 'list': return <ListScreen screen={screen} params={screen.params as ListParams} />
    case 'workItem': return <WorkItemScreen screen={screen} params={screen.params as WorkItemParams} id={id} />
    case 'step': return <StepScreen screen={screen} params={screen.params as StepParams} id={id} />
    case 'record': {
      // #170: the record kind names its view; the view names the plain-React component (a one-off screen each, the #167 rule)
      const rp = screen.params as RecordParams
      if (rp.view === 'scheme.vScheme') return <SchemeScreen screen={screen} params={rp} id={id} />
      if (rp.view === 'asset.vPrimaryAsset') return <PrimaryAssetScreen screen={screen} params={rp} id={id} />
      if (rp.view === 'location.vNode') return <StationScreen screen={screen} params={rp} id={id} />   // #171: the station page
      return <RecordScreen screen={screen} params={rp} id={id} />
    }
    default: return <Status bad>The screen kind “{screen.screenKind}” is not built yet (screen {screen.key}{id ? ', id ' + id : ''}).</Status>
  }
}
