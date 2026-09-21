// #216 (2026-09-21): a stored file, fetched with the platform's identity (the DEV identity is a header, which a plain link
// cannot carry — RequestUserMiddleware reads X-PnC-Dev-User and nothing else), held as a blob the page can show in a
// frame or open in its own tab. The API serves a PDF or a text inline (FileEndpoints, #216); every open is a logged read.
import { devUser, postJson } from '@/lib/api'

export async function fetchFileBlob(fileRowId: string): Promise<Blob> {
  const h: Record<string, string> = {}
  const u = devUser(); if (u) h['X-PnC-Dev-User'] = u
  const r = await fetch('/api/v1/files/' + fileRowId, { headers: h, credentials: 'same-origin' })
  if (!r.ok) { const d = await r.json().catch(() => null); throw new Error((d && d.detail) || r.statusText) }
  return r.blob()
}

/** The file in its own browser tab (the browser's own viewer for a PDF). */
export async function openFileInTab(fileRowId: string): Promise<void> {
  const blob = await fetchFileBlob(fileRowId)
  const url = URL.createObjectURL(blob)
  window.open(url, '_blank', 'noopener')
  setTimeout(() => URL.revokeObjectURL(url), 60_000)
}

/** The file saved by the browser under its own name (a Word document, a settings file): a plain link cannot carry the
 * identity and lands on 401 on DEV (#217 follow-up), so the bytes are fetched with it and handed to the browser's download. */
export async function downloadFile(fileRowId: string, fileName: string): Promise<void> {
  const blob = await fetchFileBlob(fileRowId)
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a'); a.href = url; a.download = fileName || 'file'; a.rel = 'noopener'
  document.body.appendChild(a); a.click(); a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 60_000)
}

/** A PDF or a text opens in its own tab (the browser shows it); anything else is saved. */
export function openOrDownload(fileRowId: string, fileName: string, mime: string): Promise<void> {
  const inline = /^application\/pdf|^text\//i.test(mime || '')
  return inline ? openFileInTab(fileRowId) : downloadFile(fileRowId, fileName)
}

// #218: a Word document opens in Word itself. Word fetches the document from a URL through the Office URI scheme
// (ms-word:ofv|u|<url>) with its own HTTP client, so the URL is a short-lived link the API issues for this file and this user
// (POST files/{id}/link; the token and the file name in the path — Word requests nothing without a document extension and drops
// a query string). The browser asks once whether to open Word. Where the file is not an Office document, or Word is not there,
// the saved download stands.
export interface FileLink { url: string; absoluteUrl: string; expiresAt: string; fileName: string; mimeType: string; officeUrl: string | null }
export const requestFileLink = (fileRowId: string) => postJson<FileLink>('/api/v1/files/' + fileRowId + '/link')

/** Open the file the way its kind wants: a PDF or a text in its own tab, an Office document in its application, anything else saved. */
export async function openFile(fileRowId: string, fileName: string, mime: string): Promise<'tab' | 'office' | 'saved'> {
  if (/^application\/pdf|^text\//i.test(mime || '')) { await openFileInTab(fileRowId); return 'tab' }
  const link = await requestFileLink(fileRowId)
  if (link.officeUrl) { window.location.assign(link.officeUrl); return 'office' }
  await downloadFile(fileRowId, fileName); return 'saved'
}
