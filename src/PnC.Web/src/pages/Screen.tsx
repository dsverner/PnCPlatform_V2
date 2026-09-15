// The one route for every defined screen (#165): /s/:key[/:id]. The definition names the kind; the kind is the component.
import { useParams } from 'react-router'
import { useScreens, type Screen, type SettingsBookParams, type ListParams } from '@/lib/screens'
import { Status } from '@/components/ui/ui'
import SettingsBookScreen from '@/screens/SettingsBookScreen'
import ListScreen from '@/screens/ListScreen'

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
    default: return <Status bad>The screen kind “{screen.screenKind}” is not built yet (screen {screen.key}{id ? ', id ' + id : ''}).</Status>
  }
}
