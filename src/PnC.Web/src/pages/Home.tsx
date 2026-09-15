// The shell's home: the platform's health, the signed-in person and their grants, and — in DEV only — the act-as sign-in
// the plain pages also use (decision #85).
import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useHealth, useMe } from '@/lib/hooks'
import { devUser, setDevUser } from '@/lib/api'
import { Panel, Facts, Button, inputClass, Status } from '@/components/ui/ui'

export default function HomePage() {
  const healthQ = useHealth(); const meQ = useMe(); const qc = useQueryClient()
  const [upn, setUpn] = useState(devUser() ?? '')
  const isDev = healthQ.data?.environment === 'DEV'
  return (
    <div className="grid gap-4 md:grid-cols-2">
      <Panel title="Platform">
        {healthQ.data ? <Facts cols={1} pairs={[['Environment', healthQ.data.environment], ['Release', healthQ.data.release], ['Database', healthQ.data.database], ['Catalogue loaded', new Date(healthQ.data.catalogLoadedAt).toLocaleString()]]} />
          : <Status bad={healthQ.isError}>{healthQ.isError ? 'The API did not answer.' : '…'}</Status>}
      </Panel>
      <Panel title="You">
        {meQ.data ? <Facts cols={1} pairs={[['Person', meQ.data.person.displayName], ['Account', meQ.data.user.userPrincipalName], ['Permissions', String(meQ.data.permissions.length)]]} />
          : <Status bad={meQ.isError}>{meQ.isError ? 'Not signed in.' : '…'}</Status>}
        {isDev && (
          <form className="mt-3 flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); setDevUser(upn.trim() || null); qc.invalidateQueries({ queryKey: ['me'] }); qc.invalidateQueries({ queryKey: ['view'] }) }}>
            <label className="flex flex-col gap-1 text-xs text-slate-400">DEV sign-in (act as)
              <input className={inputClass} list="dev-upns" value={upn} onChange={(e) => setUpn(e.target.value)} placeholder="user@pnc.local" autoComplete="off" />
            </label>
            <datalist id="dev-upns"><option value="smoke.admin@pnc.local">Administrator</option><option value="smoke.approver@pnc.local">Administrator (second)</option><option value="smoke.hydro@pnc.local">PCEngineer, Generation · Hydro</option><option value="smoke.readonly@pnc.local">ReadOnly</option></datalist>
            <Button type="submit" kind="primary">Sign in</Button>
          </form>
        )}
      </Panel>
    </div>
  )
}
