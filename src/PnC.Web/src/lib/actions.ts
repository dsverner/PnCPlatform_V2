// The calls behind the settings book's commands, ported from pnc.js: the settings text of a revision, raising a work
// request and starting its workflow, the return-to-service step calls behind Set Verified Date. Each is the platform's
// own call; the API refuses in its own words and the screen shows them. Nothing here knows a rule.
import { view, getText, postJson, proc, type Row } from './api'

export interface SettingsText { name: string; mime: string; text: string }
/** The settings file filed for a revision: the text file first, else the source, else the first. */
export async function settingsText(revisionRowId: string): Promise<SettingsText | null> {
  const files = (await view('document', 'vFile', { RevisionRowId: revisionRowId }, { take: 50 })).rows
  if (!files.length) return null
  const f = files.find((x) => /^text\//i.test(String(x.MimeType || ''))) || files.find((x) => x.FileRole === 'Source') || files[0]
  return { name: String(f.FileName), mime: String(f.MimeType), text: await getText('/api/v1/files/' + f.RowId) }
}

export interface WorkTypeOption { versionRowId: string; key: string; name: string; workflowKey?: string }
/** The effective work types a request may be raised under (Program.WorkType definitions with an Effective version), each
 * with the workflow its payload binds (#131) — the raise starts that workflow, so a new work type needs no screen change. */
export async function workTypes(): Promise<WorkTypeOption[]> {
  const [types, versions] = await Promise.all([
    view('config', 'vDefinition', { DefinitionKind: 'Program.WorkType' }, { take: 500 }),
    view('config', 'vDefinitionVersion', { Status: 'Effective' }, { take: 500 }),
  ])
  const out: WorkTypeOption[] = []
  for (const t of types.rows) {
    const v = versions.rows.find((x) => String(x.DefinitionEntityId).toLowerCase() === String(t.EntityId).toLowerCase()); if (!v) continue
    let workflowKey: string | undefined
    try { workflowKey = JSON.parse(String(v.PayloadText || '{}')).workflow || undefined } catch { /* a work type with no payload binds no workflow */ }
    out.push({ versionRowId: String(v.RowId), key: String(t.DefinitionKey), name: String(t.Name || ''), workflowKey })
  }
  return out
}

/** Raise a work request and start the settings-change workflow on it; returns the request's entity id. */
export async function raiseAndStart(o: { workTypeVersionRowId: string; title: string; scopeKind: 'Asset' | 'Node'; scopeEntityId: string; workflowKey?: string }): Promise<string> {
  const wr = await proc('work', 'WorkRequest_Add', { WorkTypeDefinitionVersionRowId: o.workTypeVersionRowId, Title: o.title, ScopeKind: o.scopeKind, ScopeEntityId: o.scopeEntityId })
  const wf = await postJson<{ workflowInstanceEntityId: string }>('/api/v1/process/workflows/start', { workflowKey: o.workflowKey ?? 'SETTINGS_CHANGE_REQUEST', subjectKind: 'WorkRequest', subjectEntityId: wr.EntityId })
  await postJson(`/api/v1/process/workflow-instances/${wf.workflowInstanceEntityId}/transitions`, { name: 'Start' })
  return String(wr.EntityId)
}

/** The return-to-service step calls (#114 witnessed commit, #115 field capture check-in). */
export const step = {
  claim: (id: string) => postJson<Row>(`/api/v1/process/step-instances/${id}/claim`, {}),
  witness: (id: string) => postJson<Row>(`/api/v1/process/step-instances/${id}/witness`, {}),
  checkin: (id: string, capturedBy: string, capturedAt: string) => postJson<Row>(`/api/v1/process/step-instances/${id}/checkin`, { outcome: 'Done', capturedBy, capturedAt }),
  commit: (id: string) => postJson<Row>(`/api/v1/process/step-instances/${id}/commit`, { outcome: 'Done' }),
}
