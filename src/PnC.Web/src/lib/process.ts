// The process engine as the screens see it (docs/design/API.md §8b; ProcessEndpoints.cs): a procedure instance's block
// tree, a step instance with its definition node (#165), the workflow document behind a stage bar, and the calls a
// person makes on a step or a workflow. Every rule stays in the engine; the API refuses in its own words.
import { getJson, postJson, view, type Row } from './api'

export interface BlockNode {
  blockInstanceEntityId: string; parent: string | null; path: string; kind: 'sequence' | 'step' | 'choice' | 'parallel' | 'branch' | 'foreach' | 'repeat' | 'call' | 'hold'
  iterationKey: string | null; pass: number; memberSubjectKind: string | null; memberSubjectEntityId: string | null
  state: string; outcome: string | null; startedAt: string | null; completedAt: string | null; title: string | null
  step: { stepInstanceEntityId: string; stepId: string; state: string; outcome: string | null; committedAt: string | null; heldReason: string | null; role: string | null; dueAt: string | null; dueBasis: string } | null
}
export interface ProcedureInstance {
  procedureInstanceEntityId: string; versionRowId: string; key: string; subjectKind: string; subjectEntityId: string; workRequestEntityId: string | null; workflowInstanceEntityId: string | null
  state: string; outcome: string | null; produced: Record<string, string>; readySteps: { stepEntityId: string; stepId: string; stepState: string; member: string | null }[]; blocks: BlockNode[]
}
export const procedureInstance = (id: string) => getJson<ProcedureInstance>(`/api/v1/process/procedure-instances/${id}`)
export const evaluate = (id: string) => postJson<{ changes: number; completed: boolean; notes: string[] }>(`/api/v1/process/procedure-instances/${id}/evaluate`, {})
export const releaseHold = (blockId: string, reason: string) => postJson(`/api/v1/process/block-instances/${blockId}/release-hold`, { reason })

export interface CaptureSpec { type: 'num' | 'text' | 'bool' | 'date' | 'dur' | 'ref' | 'set' | 'file'; unit?: string; base?: string; refKind?: string; allowed?: string[]; required?: boolean; validate?: unknown }
export interface StepDefinition {
  title: string; instruction?: string; role: string; roleCode?: string; requires?: unknown
  capture?: Record<string, CaptureSpec>; outcomes: string[]; evidence?: { required?: boolean; kinds?: string[]; min?: number }
  signoff?: { action?: string; witness?: boolean }; deviation?: { allow?: string[]; findingCategory?: string }; due?: unknown
  record?: { kind: string; template?: string }; produces?: { kind: string; as: string }; advances?: { workflow: string; transition: string; onOutcome?: string }; branchOutcome?: Record<string, string>; precondition: boolean
}
export interface StepInstance {
  stepInstanceEntityId: string; procedureInstanceEntityId: string; procedureKey: string; procedureVersionRowId: string; workRequestEntityId: string | null; workflowInstanceEntityId: string | null
  subjectKind: string; subjectEntityId: string; blockPath: string; stepId: string; state: string; outcome: string | null; heldReason: string | null
  memberSubjectKind: string | null; memberSubjectEntityId: string | null
  assignedRoleCode: string | null; claimedByActorId: string | null; claimedByDisplayName: string | null; claimedAt: string | null; claimExpiresAt: string | null; isClaimant: boolean
  witnessedByActorId: string | null; witnessedByDisplayName: string | null; committedAt: string | null; committedByActorId: string | null; committedRecordEntityId: string | null
  capturedAt: string | null; captureSource: string | null; draftModifiedAt: string | null; draft: Record<string, unknown> | null; dueAt: string | null; dueBasis: string
  definition: StepDefinition
  /** #232: the claimant's person, and an override another person has approved for their sign-off on this run (unused, unexpired) */
  claimedByPersonEntityId: string | null
  overrideApproval: { OverrideApprovalId: number; ExpiresAt: string; ApprovedByDisplayName: string | null } | null
}
/** #232: a segregation override approved by the approver, from their own session — never a name typed by the person acting */
export const approveOverride = (body: { subjectKind: string; subjectEntityId: string; action: string; forPersonEntityId: string; reason: string }) =>
  postJson<{ overrideApprovalId: number; expiresAt: string }>('/api/v1/process/override-approvals', body)
export const withdrawOverride = (id: number) => postJson(`/api/v1/process/override-approvals/${id}/withdraw`, {})
export const stepInstance = (id: string) => getJson<StepInstance>(`/api/v1/process/step-instances/${id}`)
export interface Evidence { name: string; mimeType: string; kind: string; contentBase64: string }
export interface CommitResult { stepInstanceEntityId: string; outcome: string; recordEntityId: string | null; producedEntityId: string | null; branchOutcome: string | null; advanced: string | null; deferred: boolean; instance: { changes: number; completed: boolean; notes: string[] } }
export const stepCall = {
  claim: (id: string) => postJson(`/api/v1/process/step-instances/${id}/claim`, {}),
  release: (id: string) => postJson(`/api/v1/process/step-instances/${id}/release`, {}),
  takeover: (id: string, reason: string) => postJson(`/api/v1/process/step-instances/${id}/takeover`, { reason }),
  witness: (id: string) => postJson(`/api/v1/process/step-instances/${id}/witness`, {}),
  draft: (id: string, draft: Record<string, unknown>) => postJson(`/api/v1/process/step-instances/${id}/draft`, { draft }),
  commit: (id: string, body: { outcome: string; capture?: Record<string, unknown>; evidence?: Evidence[]; overrideReason?: string }) => postJson<CommitResult>(`/api/v1/process/step-instances/${id}/commit`, body),
  checkin: (id: string, body: { outcome: string; capture?: Record<string, unknown>; evidence?: Evidence[]; capturedBy: string; capturedAt: string }) => postJson<CommitResult>(`/api/v1/process/step-instances/${id}/checkin`, body),
}

export interface WorkflowDocument { key: string; name?: string; states: { code: string; name: string; initial?: boolean; terminal?: boolean; cancellation?: boolean; roles?: string[] }[]; transitions: { from: string; to: string; name: string; roles?: string[]; requiresReason?: boolean; signoff?: string }[] }
/** The workflow document pinned by an instance, through the definitions read (Definition.Read). */
export async function workflowDocumentOf(workflowInstanceEntityId: string): Promise<{ instance: Row; document: WorkflowDocument } | null> {
  const inst = (await view('process', 'vWorkflowInstance', { EntityId: workflowInstanceEntityId }, { take: 1 })).rows[0]
  if (!inst) return null
  const d = await getJson<{ document: WorkflowDocument }>(`/api/v1/definitions/documents/${inst.WorkflowDefinitionVersionRowId}`)
  return { instance: inst, document: d.document }
}
export const transition = (workflowInstanceEntityId: string, name: string, reason?: string) =>
  postJson<{ toState: string }>(`/api/v1/process/workflow-instances/${workflowInstanceEntityId}/transitions`, reason ? { name, reason } : { name })

/** A file as the commit body carries it. */
export function fileToEvidence(f: File, kind: string): Promise<Evidence> {
  return new Promise((resolve, reject) => {
    const r = new FileReader()
    r.onload = () => { const s = String(r.result); resolve({ name: f.name, mimeType: f.type || 'application/octet-stream', kind, contentBase64: s.slice(s.indexOf(',') + 1) }) }
    r.onerror = () => reject(r.error); r.readAsDataURL(f)
  })
}
