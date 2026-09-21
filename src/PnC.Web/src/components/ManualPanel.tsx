// #216 (2026-09-21): a device model's instruction manual, kept with its asset template — a document of class
// InstructionManual whose revision is linked About the template definition (tools/load_manual.py). The owner: "a copy of
// the manual kept with the template and accessible for review in a tab or possibly separate window ... the field staff
// work on a single monitor." So: the PDF in the page (a frame over a blob the page fetched, the browser's own viewer),
// with "Open in its own tab" for a second screen. Readable at any scope (security.fHasPermission, #216).
import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { s, view, type Row } from '@/lib/api'
import { fetchFileBlob, openFileInTab } from '@/lib/files'
import { Panel, Button, Status } from '@/components/ui/ui'

export interface ModelManual { fileRowId: string; name: string; sizeBytes: number; title: string }

/** The manual linked About a template definition: the newest Issued revision's PDF, if any. */
export function useModelManual(templateDefinitionEntityId: string | null | undefined) {
  return useQuery({ queryKey: ['modelManual', templateDefinitionEntityId], enabled: !!templateDefinitionEntityId, staleTime: 10 * 60_000, queryFn: async (): Promise<ModelManual | null> => {
    const links = (await view('document', 'vRevisionLink', { SubjectKind: 'Definition', SubjectEntityId: templateDefinitionEntityId!, LinkKind: 'About' }, { take: 20 })).rows
    for (const l of links) {
      const files = (await view('document', 'vFile', { RevisionRowId: s(l.RevisionRowId) }, { take: 10 })).rows.filter((f: Row) => /^application\/pdf/i.test(s(f.MimeType)))
      if (!files.length) continue
      const rev = (await view('document', 'vRevision', { RowId: s(l.RevisionRowId) }, { take: 1 })).rows[0]
      const doc = rev ? (await view('document', 'vDocument', { EntityId: s(rev.DocumentEntityId) }, { take: 1 })).rows[0] : null
      return { fileRowId: s(files[0].RowId), name: s(files[0].FileName), sizeBytes: Number(files[0].SizeBytes ?? 0), title: s(doc?.Title) || s(files[0].FileName) }
    }
    return null
  } })
}

export function ManualPanel({ templateDefinitionEntityId, modelName }: { templateDefinitionEntityId: string | null | undefined; modelName?: string }) {
  const q = useModelManual(templateDefinitionEntityId)
  const m = q.data ?? null
  const [url, setUrl] = useState<string | null>(null); const [err, setErr] = useState<string | null>(null); const [busy, setBusy] = useState(false)
  useEffect(() => {
    let alive = true; let made: string | null = null
    setUrl(null); setErr(null)
    if (m) {
      setBusy(true)
      fetchFileBlob(m.fileRowId).then((b) => { if (!alive) return; made = URL.createObjectURL(b); setUrl(made) }).catch((e) => { if (alive) setErr(e instanceof Error ? e.message : String(e)) }).finally(() => { if (alive) setBusy(false) })
    }
    return () => { alive = false; if (made) URL.revokeObjectURL(made) }
  }, [m?.fileRowId])   // eslint-disable-line react-hooks/exhaustive-deps
  const mb = m ? (m.sizeBytes / 1048576).toFixed(1) + ' MB' : ''
  return (
    <Panel title={m ? `Manual · ${m.title}` : 'Manual'} actions={m ? <Button onClick={() => void openFileInTab(m.fileRowId).catch((e) => setErr(String(e)))}>Open in its own tab</Button> : undefined}>
      {!templateDefinitionEntityId && <Status>{modelName ? `${modelName} has no device template yet, so no manual is kept for it.` : 'No device template, so no manual.'}</Status>}
      {!!templateDefinitionEntityId && q.isPending && <Status>Looking for the manual…</Status>}
      {!!templateDefinitionEntityId && !q.isPending && !m && <Status>No manual is loaded for this template on this environment. An administrator loads it from the manufacturer's PDF (tools/load_manual.py).</Status>}
      {m && <div className="mb-2 text-xs text-slate-500">{m.name} · {mb} · every open is a logged read.</div>}
      {err && <Status bad>The manual could not be fetched: {err}</Status>}
      {m && busy && !url && <Status>Fetching {mb}…</Status>}
      {url && <iframe title={m?.title ?? 'Manual'} src={url} className="h-[78vh] w-full rounded border border-slate-800 bg-white" />}
    </Panel>
  )
}
